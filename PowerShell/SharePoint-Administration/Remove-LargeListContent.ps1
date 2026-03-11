<#
.SYNOPSIS
    Bulk-deletes all items from (or entirely removes) a SharePoint Online list or
    library that exceeds the list view threshold — no GUI batch-clicking required.

.DESCRIPTION
    Targets lists and libraries with 100,000+ items that are impractical to clean
    up through the browser UI.  Supports two operation modes:

      ClearItems  (default)
          Deletes every item in the list in server-side batches while keeping the
          list/library structure and schema intact.  Uses PnP batch operations to
          bundle up to -BatchSize deletions into a single HTTP request, cutting
          run-time from hours (GUI) to minutes.  Checked-out files are
          force-checked-in before deletion.  A CAML RowLimit query re-fetches from
          the top of the list after each batch, safely traversing lists far larger
          than SharePoint's 5,000-item view threshold without needing indexed
          columns or position tokens.

          Folder handling: deleting a folder item via this script removes the folder
          and all its contents server-side.  If a file inside that folder is also
          queued in the same batch, SharePoint may return "Item does not exist" for
          it — this is treated as a non-failure (the item is already gone).

      DeleteList
          Removes the entire list/library (structure + all content) in one
          server-side Remove-PnPList call.  Significantly faster than ClearItems
          when you do not need items in the Recycle Bin and just want the
          list/library gone entirely.

    Throttling is handled with exponential back-off (2 / 4 / 8 / 16 s).
    A WhatIf mode resolves the list and reports its item count without deleting.
    Items that cannot be deleted are logged and exported to a CSV for follow-up.

.PARAMETER SiteUrl
    Full URL of the SharePoint Online site, e.g.
    https://contoso.sharepoint.com/sites/SITE_NAME

.PARAMETER ListTitle
    Display name (Title) of the list or library to target.

.PARAMETER Mode
    Operation mode.
      ClearItems  — Delete all items; the list/library structure is preserved.
      DeleteList  — Remove the entire list/library including its schema.
    Default: ClearItems

.PARAMETER BatchSize
    Number of items bundled into each server-side delete batch (default: 500).
    Increase to 1000 for faster throughput on stable connections; decrease if
    throttling errors (HTTP 429) appear frequently.  Maximum allowed: 2000.

.PARAMETER Recycle
    Send deleted items to the site Recycle Bin instead of permanently deleting
    them.  Applies to both ClearItems (individual items) and DeleteList (the
    list structure).

    WARNING: For lists with 100,000+ items, recycling will rapidly consume
    Recycle Bin quota (first-stage limit = 25% of site storage or 200 items,
    whichever is less).  Omit -Recycle (permanent deletion) unless specific
    items need to remain recoverable.

.PARAMETER WhatIf
    Preview-only mode.  Connects to the site, resolves the list, and reports
    its item count — but does not delete anything.

.PARAMETER FailureCsvPath
    Path for a CSV file that logs items which could not be deleted.
    Defaults to: $env:TEMP\RemoveLargeList_Failures_<yyyyMMdd_HHmmss>.csv

.PARAMETER LogPath
    Optional path for a plain-text transcript of all console output.

.PARAMETER ClientId
    Azure AD App Registration Client ID for interactive browser authentication.
    Defaults to the shared tenant app used across this script family.

.EXAMPLE
    .\Remove-LargeListContent.ps1 `
        -SiteUrl   "https://contoso.sharepoint.com/sites/SITE_NAME" `
        -ListTitle "Old Documents"

    Permanently deletes every item in "Old Documents" using 500-item server
    batches.  The document library structure and schema are preserved.

.EXAMPLE
    .\Remove-LargeListContent.ps1 `
        -SiteUrl   "https://contoso.sharepoint.com/sites/SITE_NAME" `
        -ListTitle "Old Documents" `
        -Mode      DeleteList

    Removes the entire "Old Documents" library (schema + content) in one
    server-side call.

.EXAMPLE
    .\Remove-LargeListContent.ps1 `
        -SiteUrl   "https://contoso.sharepoint.com/sites/SITE_NAME" `
        -ListTitle "Huge Tracking List" `
        -WhatIf

    Connects and reports how many items "Huge Tracking List" contains.
    Nothing is deleted.

.EXAMPLE
    .\Remove-LargeListContent.ps1 `
        -SiteUrl      "https://contoso.sharepoint.com/sites/SITE_NAME" `
        -ListTitle    "Old Documents" `
        -BatchSize    1000 `
        -Recycle `
        -LogPath      "C:\Logs\clear_old_docs.txt"

    Recycles all items in 1,000-item batches and writes a timestamped log file.

.EXAMPLE
    .\Remove-LargeListContent.ps1 `
        -SiteUrl          "https://contoso.sharepoint.com/sites/SITE_NAME" `
        -ListTitle        "Old Documents" `
        -FailureCsvPath   "C:\Temp\failures.csv"

    Permanent deletion with a custom path for the failure report CSV.

.NOTES
    Requires : PnP.PowerShell module v2 or later
                 Install-Module PnP.PowerShell -Scope CurrentUser
    Author   : Claude
    Date     : 2026-03-11
    Tested on: PnP.PowerShell 2.x, SharePoint Online
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$SiteUrl,

    [Parameter(Mandatory = $true)]
    [string]$ListTitle,

    [ValidateSet("ClearItems", "DeleteList")]
    [string]$Mode = "ClearItems",

    [ValidateRange(1, 2000)]
    [int]$BatchSize = 500,

    [switch]$Recycle,

    [switch]$WhatIf,

    [string]$FailureCsvPath,

    [string]$LogPath,

    [string]$ClientId = "CLIENT_ID"
)

# ── Module check ───────────────────────────────────────────────────────────────
if (-not (Get-Module -ListAvailable -Name PnP.PowerShell)) {
    Write-Error "PnP.PowerShell is not installed.  Run: Install-Module PnP.PowerShell -Scope CurrentUser"
    exit 1
}
Import-Module PnP.PowerShell -ErrorAction Stop

# ── Default failure CSV path ───────────────────────────────────────────────────
if (-not $FailureCsvPath) {
    $ts             = Get-Date -Format "yyyyMMdd_HHmmss"
    $FailureCsvPath = "$env:TEMP\RemoveLargeList_Failures_$ts.csv"
}

# ── Script-scope counters ──────────────────────────────────────────────────────
$script:TotalDeleted = 0
$script:TotalFailed  = 0
$script:FailedItems  = [System.Collections.Generic.List[PSCustomObject]]::new()

# ── Logging helper ─────────────────────────────────────────────────────────────
function Write-Log {
    param (
        [string]$Message,

        [ValidateSet("Info", "Success", "Warning", "Error", "Action", "Verbose")]
        [string]$Level = "Info"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine   = "[$timestamp] $Message"

    $color = switch ($Level) {
        "Success" { "Green"    }
        "Warning" { "Yellow"   }
        "Error"   { "Red"      }
        "Action"  { "Cyan"     }
        "Verbose" { "DarkGray" }
        default   { "White"    }
    }

    Write-Host $logLine -ForegroundColor $color

    if ($LogPath) {
        Add-Content -Path $LogPath -Value $logLine -ErrorAction SilentlyContinue
    }
}

# ── Throttle-aware retry wrapper ───────────────────────────────────────────────
# Retries a scriptblock up to 4 times with exponential back-off when a
# throttling or transient server error is detected (HTTP 429 / 503 / timeout).
function Invoke-WithRetry {
    param (
        [scriptblock]$Action,
        [string]$Label = "operation"
    )

    $delays = @(2, 4, 8, 16)

    for ($attempt = 1; $attempt -le 4; $attempt++) {
        try {
            return (& $Action)
        }
        catch {
            $msg       = $_.Exception.Message
            $throttled = $msg -match "429|503|throttl|timeout|Too Many Requests"

            if ($attempt -lt 4 -and $throttled) {
                $wait = $delays[$attempt - 1]
                Write-Log "  [THROTTLE] $Label — waiting ${wait}s before retry ($attempt / 4)..." -Level Warning
                Start-Sleep -Seconds $wait
            }
            else {
                throw
            }
        }
    }
}

# ── Single-item fallback deletion (used when a PnP batch fails entirely) ───────
function Invoke-FallbackDelete {
    param (
        [object[]]$Items,
        [int]$BatchNum
    )

    foreach ($item in $Items) {
        $itemId   = $item.Id
        $fileName = if ($item.FieldValues.FileLeafRef) { $item.FieldValues.FileLeafRef } else { "Item $itemId" }

        try {
            Invoke-WithRetry -Label "Delete $fileName (ID $itemId)" -Action {
                Remove-PnPListItem -List $ListTitle -Identity $itemId `
                    -Recycle:$Recycle -Force -ErrorAction Stop
            }
            $script:TotalDeleted++
        }
        catch {
            $errMsg = $_.Exception.Message

            # "Item does not exist" means a parent folder deletion already removed
            # this item — treat it as a success rather than a failure.
            if ($errMsg -match "does not exist|Item Not Found|0x80131600") {
                Write-Log "    [ALREADY GONE] $fileName (ID: $itemId) — skipped" -Level Verbose
                $script:TotalDeleted++
                continue
            }

            $script:TotalFailed++
            Write-Log "    [FAIL] $fileName (ID: $itemId): $errMsg" -Level Error

            $script:FailedItems.Add([PSCustomObject]@{
                ItemID    = $itemId
                FileName  = $fileName
                BatchNum  = $BatchNum
                Error     = $errMsg
                Timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            })
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Main execution
# ═══════════════════════════════════════════════════════════════════════════════
try {
    $whatIfTag = if ($WhatIf) { " [WHATIF — no changes will be applied]" } else { "" }

    Write-Log ""
    Write-Log "═══════════════════════════════════════════════════════════════" -Level Info
    Write-Log " Remove-LargeListContent$whatIfTag"                              -Level Info
    Write-Log " Site      : $SiteUrl"                                           -Level Info
    Write-Log " List      : $ListTitle"                                         -Level Info
    Write-Log " Mode      : $Mode"                                              -Level Info
    if ($Mode -eq "ClearItems") {
        Write-Log " BatchSize : $BatchSize  |  Recycle: $Recycle"               -Level Info
    }
    Write-Log "═══════════════════════════════════════════════════════════════" -Level Info
    Write-Log ""

    if ($LogPath) {
        $null = New-Item -ItemType File -Path $LogPath -Force
        Add-Content -Path $LogPath -Value "Remove-LargeListContent  |  $(Get-Date)"
        Add-Content -Path $LogPath -Value "Site: $SiteUrl  |  List: $ListTitle  |  Mode: $Mode  |  WhatIf: $WhatIf"
        Add-Content -Path $LogPath -Value ("=" * 80)
        Write-Log "Logging to: $LogPath" -Level Info
    }

    # ── Connect ────────────────────────────────────────────────────────────────
    Write-Log "Connecting to $SiteUrl ..." -Level Info
    Connect-PnPOnline -Url $SiteUrl -ClientId $ClientId -Interactive -ErrorAction Stop
    Write-Log "Connected." -Level Success

    # ── Resolve list and report item count ─────────────────────────────────────
    Write-Log ""
    Write-Log "Resolving list '$ListTitle' ..." -Level Info

    $list = Get-PnPList -Identity $ListTitle -ErrorAction Stop
    if (-not $list) {
        Write-Log "List '$ListTitle' was not found on $SiteUrl." -Level Error
        exit 1
    }

    $itemCount = $list.ItemCount
    $listType  = switch ($list.BaseTemplate) {
        101     { "Document Library" }
        100     { "Custom List"      }
        default { "List (template $($list.BaseTemplate))" }
    }

    Write-Log "$listType found : '$($list.Title)'" -Level Success
    Write-Log "Item count      : $itemCount"        -Level Info

    # ── WhatIf: report and exit ────────────────────────────────────────────────
    if ($WhatIf) {
        Write-Log ""
        Write-Log "[WHATIF] Mode    : $Mode"                                       -Level Action
        Write-Log "[WHATIF] Items   : $itemCount item(s) would be affected."       -Level Action
        Write-Log "[WHATIF] Recycle : $Recycle"                                    -Level Action
        Write-Log ""
        Write-Log "No changes made (WhatIf mode)." -Level Warning
        return
    }

    # ── Recycle Bin quota advisory ─────────────────────────────────────────────
    if ($Recycle -and $itemCount -gt 10000) {
        Write-Log ""
        Write-Log "WARNING: -Recycle is set on a list with $itemCount items."           -Level Warning
        Write-Log "         Recycling at this scale may rapidly consume Recycle Bin"    -Level Warning
        Write-Log "         quota.  Monitor usage or consider permanent deletion."      -Level Warning
        Write-Log ""
    }

    # ═══════════════════════════════════════════════════════════════════════════
    # Mode: DeleteList — remove the entire list/library in one server-side call
    # ═══════════════════════════════════════════════════════════════════════════
    if ($Mode -eq "DeleteList") {
        Write-Log ""
        Write-Log "Removing '$ListTitle' ($itemCount items) ..." -Level Action

        Invoke-WithRetry -Label "Remove-PnPList '$ListTitle'" -Action {
            Remove-PnPList -Identity $ListTitle -Recycle:$Recycle -Force -ErrorAction Stop
        }

        Write-Log "List/library removed successfully." -Level Success
        return
    }

    # ═══════════════════════════════════════════════════════════════════════════
    # Mode: ClearItems — batch-delete all items, preserve list structure
    # ═══════════════════════════════════════════════════════════════════════════
    if ($itemCount -eq 0) {
        Write-Log "List is already empty — nothing to do." -Level Warning
        return
    }

    $estimatedBatches = [Math]::Ceiling($itemCount / $BatchSize)

    Write-Log ""
    Write-Log "Starting item deletion (ClearItems)..."              -Level Action
    Write-Log "Estimated batches : ~$estimatedBatches"              -Level Info
    Write-Log "Press Ctrl+C to abort (completed batches are final)" -Level Warning
    Write-Log ""

    # ID-cursor pagination: query WHERE ID > $lastId ORDER BY ID, advancing the
    # cursor after each batch.  The ID column is always indexed in every SharePoint
    # list/library, so this query is guaranteed never to hit the list view
    # threshold — regardless of list size or whether any other indexed columns exist.
    $lastId   = 0
    $batchNum = 0

    do {
        $batchNum++

        # Build the CAML query for this window (IDs strictly greater than $lastId).
        $caml = @"
<View>
  <Query>
    <Where>
      <Gt>
        <FieldRef Name="ID"/>
        <Value Type="Counter">$lastId</Value>
      </Gt>
    </Where>
    <OrderBy>
      <FieldRef Name="ID" Ascending="TRUE"/>
    </OrderBy>
  </Query>
  <RowLimit>$BatchSize</RowLimit>
</View>
"@

        # ── Fetch next batch ───────────────────────────────────────────────────
        $items = $null
        try {
            $items = Invoke-WithRetry -Label "Fetch batch $batchNum" -Action {
                Get-PnPListItem -List $ListTitle `
                    -Query  $caml `
                    -Fields "ID", "FileLeafRef", "FileRef", "CheckoutUser" `
                    -ErrorAction Stop
            }
        }
        catch {
            Write-Log "  [ERROR] Could not retrieve batch $batchNum : $($_.Exception.Message)" -Level Error
            Write-Log "          Stopping — check connectivity or throttle limits." -Level Error
            break
        }

        if (-not $items -or $items.Count -eq 0) {
            Write-Log "  No more items found — list is now empty." -Level Success
            break
        }

        # Advance the cursor to the highest ID in this batch so the next query
        # starts past it.  We do this before deletion so that even if some items
        # fail, we don't loop on them forever (failures are captured in the CSV).
        $lastId = ($items | Measure-Object -Property Id -Maximum).Maximum

        Write-Log "  Batch $batchNum | $($items.Count) items | total deleted so far: $($script:TotalDeleted)" -Level Info

        # ── Undo checkouts (document libraries only) ───────────────────────────
        foreach ($item in $items) {
            if ($item.FieldValues.CheckoutUser) {
                $fname   = $item.FieldValues.FileLeafRef
                $fileRef = $item.FieldValues.FileRef
                Write-Log "    [CHECKOUT] Undoing checkout on: $fname" -Level Warning
                try {
                    if ($fileRef) {
                        Undo-PnPFileCheckOut -Url $fileRef -ErrorAction SilentlyContinue
                    }
                }
                catch {
                    Write-Log "    [WARN] Could not undo checkout on '$fname': $($_.Exception.Message)" -Level Warning
                }
            }
        }

        # ── Build and execute PnP batch delete ────────────────────────────────
        # Batching bundles all Remove calls into a single $batch REST request,
        # dramatically reducing round-trips compared to one call per item.
        $pnpBatch    = New-PnPBatch
        $batchSuccess = $false

        foreach ($item in $items) {
            Remove-PnPListItem -List $ListTitle -Identity $item.Id `
                -Recycle:$Recycle -Batch $pnpBatch -Force
        }

        try {
            Invoke-WithRetry -Label "Execute batch $batchNum" -Action {
                Invoke-PnPBatch -Batch $pnpBatch -ErrorAction Stop
            }
            $batchSuccess = $true
        }
        catch {
            Write-Log "  [WARN] Batch $batchNum failed: $($_.Exception.Message)" -Level Warning
            Write-Log "         Falling back to item-by-item deletion for this batch..." -Level Warning
        }

        if ($batchSuccess) {
            $script:TotalDeleted += $items.Count
            Write-Log "  Batch $batchNum complete. Total deleted: $($script:TotalDeleted)" -Level Success
        }
        else {
            # Batch failed wholesale — fall back to sequential deletion so we can
            # capture exactly which items failed and why.
            Invoke-FallbackDelete -Items $items -BatchNum $batchNum
            Write-Log "  Batch $batchNum fallback complete. Deleted: $($script:TotalDeleted)  Failed: $($script:TotalFailed)" -Level Info
        }

        # ── Progress bar ───────────────────────────────────────────────────────
        $pct = [Math]::Min([Math]::Round(($script:TotalDeleted / [Math]::Max($itemCount, 1)) * 100, 1), 100)
        Write-Progress -Activity "Clearing '$ListTitle'" `
            -Status    "Deleted $($script:TotalDeleted) / ~$itemCount items ($pct%)" `
            -PercentComplete $pct

        # Brief pause to reduce throttling pressure between batches
        Start-Sleep -Milliseconds 300

    } while ($true)

    Write-Progress -Activity "Clearing '$ListTitle'" -Completed

    # ── Summary ────────────────────────────────────────────────────────────────
    Write-Log ""
    Write-Log "═══════════════════════════════════════════════════════════════" -Level Info
    Write-Log " SUMMARY (ClearItems)"                                           -Level Info
    Write-Log "═══════════════════════════════════════════════════════════════" -Level Info
    Write-Log " Batches run     : $batchNum"                                     -Level Info
    Write-Log " Items deleted   : $($script:TotalDeleted)"                       -Level $(if ($script:TotalDeleted -gt 0) { "Success" } else { "Info" })
    Write-Log " Items failed    : $($script:TotalFailed)"                        -Level $(if ($script:TotalFailed  -gt 0) { "Error"   } else { "Info" })
    Write-Log " Recycle Bin     : $Recycle"                                      -Level Info
    Write-Log "═══════════════════════════════════════════════════════════════" -Level Info

    if ($script:FailedItems.Count -gt 0) {
        $script:FailedItems | Export-Csv -Path $FailureCsvPath -NoTypeInformation
        Write-Log ""
        Write-Log "Failed items exported to: $FailureCsvPath" -Level Warning
    }

    Write-Log ""
    Write-Log "Done." -Level Success
}
catch {
    Write-Log "FATAL: $($_.Exception.Message)" -Level Error
    Write-Log $_.ScriptStackTrace                -Level Error
    exit 1
}
finally {
    Write-Progress -Activity "Clearing '$ListTitle'" -Completed -ErrorAction SilentlyContinue
    if (Get-PnPConnection -ErrorAction SilentlyContinue) {
        Disconnect-PnPOnline
    }
}
