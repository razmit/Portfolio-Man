<#
.SYNOPSIS
    Bulk-sets SharePoint Online site permissions to "Read", preserving any principal
    that currently holds "Full Control".

.DESCRIPTION
    Connects to a SharePoint Online site and walks every securable object that has
    broken inheritance (unique permissions): the site itself, all visible
    lists/libraries, and — when -IncludeItems is specified — every individual list
    item and file as well.

    For each unique-permission object, every role assignment is evaluated:
      • Principals whose role includes "Full Control" are left completely untouched.
      • Principals with only "Limited Access" are skipped (SharePoint manages this
        automatically; it cannot be cleanly removed without breaking child permissions).
      • All other principals are changed to the built-in "Read" permission level.

    Objects that still inherit permissions are not touched directly — changes at
    their parent (web or list) cascade down automatically.

    Designed for site decommissioning: locks down the site for regular users while
    allowing owners (Full Control) to continue their wind-down activities.

.PARAMETER SiteUrl
    The URL of the SharePoint Online site to process.

.PARAMETER IncludeItems
    When specified, processes permissions on individual list items and files in
    addition to the site and list/library level.

.PARAMETER WhatIf
    Simulates all changes without applying them. Use this to preview what would
    change before running for real.

.PARAMETER LogPath
    Optional path for a plain-text log file. If not specified, output is
    console-only.

.PARAMETER ClientId
    Azure AD App Registration Client ID used for interactive authentication.
    Defaults to the tenant app ID used across this script family.

.EXAMPLE
    .\Set-SiteReadPermissions.ps1 -SiteUrl "https://contoso.sharepoint.com/sites/SITE_NAME"

    Processes the site and all lists/libraries. No item-level processing.

.EXAMPLE
    .\Set-SiteReadPermissions.ps1 -SiteUrl "https://contoso.sharepoint.com/sites/SITE_NAME" -IncludeItems -WhatIf

    Preview (no changes applied) of a full site + item-level sweep.

.EXAMPLE
    .\Set-SiteReadPermissions.ps1 -SiteUrl "https://contoso.sharepoint.com/sites/SITE_NAME" -IncludeItems -LogPath "C:\Logs\permissions_change.txt"

    Full sweep with a log file written alongside the console output.

.NOTES
    Requires : PnP.PowerShell module
                 Install-Module PnP.PowerShell -Scope CurrentUser
    Author   : Claude
    Date     : 2026-03-05
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$SiteUrl,

    [switch]$IncludeItems,

    [switch]$WhatIf,

    [string]$LogPath,

    [string]$ClientId = "CLIENT_ID"
)

# ── Module check ──────────────────────────────────────────────────────────────
if (-not (Get-Module -ListAvailable -Name PnP.PowerShell)) {
    Write-Error "PnP.PowerShell module is not installed. Run: Install-Module PnP.PowerShell -Scope CurrentUser"
    exit 1
}
Import-Module PnP.PowerShell -ErrorAction Stop

# ── Script-scope counters ─────────────────────────────────────────────────────
$script:ChangesApplied   = 0   # Principals successfully set to Read
$script:FullControlKept  = 0   # Principals skipped due to Full Control
$script:AlreadyRead      = 0   # Principals that already had only Read
$script:ObjectsProcessed = 0   # Securable objects with unique permissions found
$script:Errors           = @()

# ── Logging helper ────────────────────────────────────────────────────────────
function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,

        [ValidateSet("Info","Success","Warning","Error","Action","Preserve","Verbose")]
        [string]$Level = "Info"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine   = "[$timestamp] $Message"

    $color = switch ($Level) {
        "Success"  { "Green"    }
        "Warning"  { "Yellow"   }
        "Error"    { "Red"      }
        "Action"   { "Cyan"     }
        "Preserve" { "Magenta"  }
        "Verbose"  { "DarkGray" }
        default    { "White"    }
    }

    Write-Host $logLine -ForegroundColor $color

    if ($LogPath) {
        Add-Content -Path $LogPath -Value $logLine -ErrorAction SilentlyContinue
    }
}

# ── Apply Read to a single principal on a securable object ────────────────────
#
# Centralises all the skip-logic and the three Set-PnP*Permission call sites.
# Uses splatting to keep the User/Group axis DRY.
#
function Set-PrincipalToRead {
    param(
        [string]   $PrincipalTitle,
        [string]   $PrincipalLogin,
        [int]      $PrincipalType,      # CSOM PrincipalType integer
        [string[]] $CurrentRoles,
        [ValidateSet("Site","List","Item")]
        [string]   $ObjectType,
        [string]   $ListIdentity = $null,
        [int]      $ItemId       = $null,
        [string]   $ObjectDesc   = ""
    )

    # ── Skip: Limited Access is system-managed and cannot be directly removed
    #    without breaking permissions on child items that granted it.
    if ($CurrentRoles.Count -eq 1 -and $CurrentRoles[0] -eq "Limited Access") {
        Write-Log "    [SKIP] $PrincipalTitle — Limited Access only (system-managed)" -Level Verbose
        return
    }

    # ── Skip: any assignment whose roles include "Full Control" — matched as a
    #    substring so that custom levels like "Full Control - no site creation"
    #    are caught alongside the built-in "Full Control" level.
    if ($CurrentRoles | Where-Object { $_ -like "*Full Control*" }) {
        Write-Log "    [PRESERVE] $PrincipalTitle — Full Control kept intact (roles: $($CurrentRoles -join ', '))" -Level Preserve
        $script:FullControlKept++
        return
    }

    # ── Skip: already Read-only — nothing to change
    if ($CurrentRoles.Count -eq 1 -and $CurrentRoles[0] -eq "Read") {
        Write-Log "    [SKIP] $PrincipalTitle — already Read only" -Level Verbose
        $script:AlreadyRead++
        return
    }

    $whatIfTag = if ($WhatIf) { " [WHATIF]" } else { "" }
    Write-Log "    [SET READ]$whatIfTag $PrincipalTitle (was: $($CurrentRoles -join ', '))" -Level Action

    if ($WhatIf) { return }

    # PrincipalType 8 = SharePointGroup → use -Group <Title>
    # All others (1=User, 4=SecurityGroup)  → use -User <LoginName>
    $isSpGroup     = ($PrincipalType -eq 8)
    $principalArgs = if ($isSpGroup) { @{ Group = $PrincipalTitle } } else { @{ User = $PrincipalLogin } }

    # Roles to remove = everything the principal currently holds except Read
    # (if they already have Read we still want to keep it, just strip the rest)
    $rolesToRemove = @($CurrentRoles | Where-Object { $_ -ne "Read" })

    try {
        switch ($ObjectType) {
            "Site" {
                if ($rolesToRemove.Count -gt 0) {
                    Set-PnPWebPermission @principalArgs -AddRole "Read" -RemoveRole $rolesToRemove -ErrorAction Stop
                } else {
                    Set-PnPWebPermission @principalArgs -AddRole "Read" -ErrorAction Stop
                }
            }
            "List" {
                if ($rolesToRemove.Count -gt 0) {
                    Set-PnPListPermission -Identity $ListIdentity @principalArgs -AddRole "Read" -RemoveRole $rolesToRemove -ErrorAction Stop
                } else {
                    Set-PnPListPermission -Identity $ListIdentity @principalArgs -AddRole "Read" -ErrorAction Stop
                }
            }
            "Item" {
                if ($rolesToRemove.Count -gt 0) {
                    Set-PnPListItemPermission -List $ListIdentity -Identity $ItemId @principalArgs -AddRole "Read" -RemoveRole $rolesToRemove -ErrorAction Stop
                } else {
                    Set-PnPListItemPermission -List $ListIdentity -Identity $ItemId @principalArgs -AddRole "Read" -ErrorAction Stop
                }
            }
        }
        $script:ChangesApplied++
    }
    catch {
        $errMsg = $_.Exception.Message
        Write-Log "    [ERROR] Could not update '$PrincipalTitle' on '$ObjectDesc': $errMsg" -Level Error
        $script:Errors += [PSCustomObject]@{
            Object    = $ObjectDesc
            Principal = $PrincipalTitle
            Error     = $errMsg
        }
    }
}

# ── Walk all role assignments on one securable object ─────────────────────────
#
# Loads HasUniqueRoleAssignments first; if the object inherits permissions it is
# skipped entirely (the change on the parent will cascade down to it).
# Otherwise all role assignments are loaded in two batched CSOM round-trips and
# each principal is passed to Set-PrincipalToRead.
#
function Invoke-PermissionsChange {
    param(
        [Parameter(Mandatory=$true)]
        $ClientObject,

        [Parameter(Mandatory=$true)]
        [ValidateSet("Site","List","Item")]
        [string]$ObjectType,

        [Parameter(Mandatory=$true)]
        [string]$Description,

        [string]$ListIdentity = $null,
        [int]   $ItemId       = $null
    )

    # ── Check broken inheritance
    $hasUnique = Get-PnPProperty -ClientObject $ClientObject -Property HasUniqueRoleAssignments -ErrorAction Stop

    if (-not $hasUnique) {
        Write-Log "  [INHERITED] $Description — inherits from parent, skipping" -Level Verbose
        return
    }

    Write-Log "  [UNIQUE] $Description" -Level Info
    $script:ObjectsProcessed++

    # ── Load RoleAssignments collection
    $ctx = Get-PnPContext
    $ctx.Load($ClientObject.RoleAssignments)
    $ctx.ExecuteQuery()

    # ── Batch-load Member + RoleDefinitionBindings for every assignment
    foreach ($ra in $ClientObject.RoleAssignments) {
        $ctx.Load($ra.Member)
        $ctx.Load($ra.RoleDefinitionBindings)
    }
    $ctx.ExecuteQuery()

    # ── Batch-load role definition names (Name property on each RoleDefinition)
    foreach ($ra in $ClientObject.RoleAssignments) {
        foreach ($rd in $ra.RoleDefinitionBindings) {
            $ctx.Load($rd)
        }
    }
    $ctx.ExecuteQuery()

    # ── Materialise all assignment data into plain PowerShell objects NOW,
    #    before touching any permissions.  Set-PnP*Permission calls ExecuteQuery()
    #    internally, which invalidates the loaded state of the CSOM collection;
    #    if we were still iterating it we'd get "collection not initialised" errors.
    $assignments = foreach ($ra in $ClientObject.RoleAssignments) {
        [PSCustomObject]@{
            Title         = $ra.Member.Title
            LoginName     = $ra.Member.LoginName
            PrincipalType = [int]$ra.Member.PrincipalType
            RoleNames     = @($ra.RoleDefinitionBindings | ForEach-Object { $_.Name })
        }
    }

    # ── Apply changes — no CSOM collections in flight at this point
    foreach ($assignment in $assignments) {
        Set-PrincipalToRead `
            -PrincipalTitle $assignment.Title `
            -PrincipalLogin $assignment.LoginName `
            -PrincipalType  $assignment.PrincipalType `
            -CurrentRoles   $assignment.RoleNames `
            -ObjectType     $ObjectType `
            -ListIdentity   $ListIdentity `
            -ItemId         $ItemId `
            -ObjectDesc     $Description
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Main execution
# ═══════════════════════════════════════════════════════════════════════════════
try {
    $modeTag = if ($WhatIf) { " [WHATIF — no changes will be applied]" } else { "" }

    Write-Log ""
    Write-Log "═══════════════════════════════════════════════════════════════" -Level Info
    Write-Log " Set-SiteReadPermissions$modeTag"                               -Level Info
    Write-Log " Site  : $SiteUrl"                                              -Level Info
    Write-Log " Scope : Site + Lists$(if ($IncludeItems) { ' + Items/Files' })" -Level Info
    Write-Log "═══════════════════════════════════════════════════════════════" -Level Info
    Write-Log ""

    if ($LogPath) {
        $null = New-Item -ItemType File -Path $LogPath -Force
        Add-Content -Path $LogPath -Value "Set-SiteReadPermissions  |  $(Get-Date)"
        Add-Content -Path $LogPath -Value "Site: $SiteUrl  |  IncludeItems: $IncludeItems  |  WhatIf: $WhatIf"
        Add-Content -Path $LogPath -Value ("=" * 80)
        Write-Log "Logging to: $LogPath" -Level Info
    }

    # ── Connect ───────────────────────────────────────────────────────────────
    Write-Log "Connecting to $SiteUrl ..." -Level Info
    Connect-PnPOnline -Url $SiteUrl -ClientId $ClientId -Interactive -ErrorAction Stop
    Write-Log "Connected." -Level Success

    # ── 1. Site (web) level ───────────────────────────────────────────────────
    Write-Log ""
    Write-Log "── SITE LEVEL ──────────────────────────────────────────────────" -Level Info

    $web = Get-PnPWeb
    Invoke-PermissionsChange -ClientObject $web -ObjectType "Site" -Description $SiteUrl

    # ── 2. Lists and libraries ────────────────────────────────────────────────
    Write-Log ""
    Write-Log "── LISTS & LIBRARIES ───────────────────────────────────────────" -Level Info

    # Hidden lists (appdata, appfiles, style library, etc.) are excluded;
    # they're infrastructure and shouldn't be touched by a permissions sweep.
    $lists = Get-PnPList | Where-Object { -not $_.Hidden }
    Write-Log "Found $($lists.Count) visible list(s)/librar(ies)." -Level Info

    $listIdx = 0
    foreach ($list in $lists) {
        $listIdx++
        $listTitle = $list.Title

        Write-Progress -Activity "Processing lists" `
            -Status "[$listIdx / $($lists.Count)] $listTitle" `
            -PercentComplete (($listIdx / $lists.Count) * 100)

        try {
            Invoke-PermissionsChange `
                -ClientObject $list `
                -ObjectType   "List" `
                -Description  "List: $listTitle" `
                -ListIdentity $listTitle
        }
        catch {
            $errMsg = $_.Exception.Message
            Write-Log "  [ERROR] Failed processing list '$listTitle': $errMsg" -Level Error
            $script:Errors += [PSCustomObject]@{
                Object    = "List: $listTitle"
                Principal = "(list-level)"
                Error     = $errMsg
            }
        }

        # ── 3. Items / files (optional) ───────────────────────────────────────
        if (-not $IncludeItems) { continue }

        Write-Log "  Scanning '$listTitle' for items with broken inheritance..." -Level Info

        try {
            # Retrieve all items; only ID is needed at this stage.
            # PageSize 200 keeps individual requests well within throttle limits.
            $items = Get-PnPListItem -List $listTitle -PageSize 200 -Fields "ID" -ErrorAction Stop

            $itemIdx    = 0
            $uniqueHits = 0

            foreach ($item in $items) {
                $itemIdx++

                Write-Progress -Activity "Scanning items in '$listTitle'" `
                    -Status "Item $itemIdx / $($items.Count)" `
                    -PercentComplete (($itemIdx / [Math]::Max($items.Count, 1)) * 100)

                try {
                    # Load the flag first — avoids a full role-assignment round-trip
                    # for items that still inherit from the list.
                    $itemHasUnique = Get-PnPProperty -ClientObject $item -Property HasUniqueRoleAssignments -ErrorAction Stop

                    if (-not $itemHasUnique) { continue }

                    $uniqueHits++
                    Invoke-PermissionsChange `
                        -ClientObject $item `
                        -ObjectType   "Item" `
                        -Description  "Item $($item.Id) in '$listTitle'" `
                        -ListIdentity $listTitle `
                        -ItemId       $item.Id
                }
                catch {
                    $errMsg = $_.Exception.Message
                    Write-Log "  [ERROR] Item $($item.Id) in '$listTitle': $errMsg" -Level Error
                    $script:Errors += [PSCustomObject]@{
                        Object    = "Item $($item.Id) in $listTitle"
                        Principal = "(item-level)"
                        Error     = $errMsg
                    }
                }
            }

            Write-Progress -Activity "Scanning items in '$listTitle'" -Completed
            Write-Log "  '$listTitle': scanned $itemIdx item(s), $uniqueHits had unique permissions." -Level Info
        }
        catch {
            $errMsg = $_.Exception.Message
            Write-Log "  [ERROR] Could not retrieve items from '$listTitle': $errMsg" -Level Error
            $script:Errors += [PSCustomObject]@{
                Object    = "Items in: $listTitle"
                Principal = "(retrieval)"
                Error     = $errMsg
            }
        }
    }

    Write-Progress -Activity "Processing lists" -Completed

    # ── Summary ───────────────────────────────────────────────────────────────
    Write-Log ""
    Write-Log "═══════════════════════════════════════════════════════════════" -Level Info
    Write-Log " SUMMARY$(if ($WhatIf) { ' [WHATIF — no actual changes were made]' })"        -Level Info
    Write-Log "═══════════════════════════════════════════════════════════════" -Level Info
    Write-Log " Unique-permission objects found : $script:ObjectsProcessed"    -Level Info
    Write-Log " Principals set to Read          : $script:ChangesApplied"      -Level $(if ($script:ChangesApplied  -gt 0) { "Action"   } else { "Info" })
    Write-Log " Full Control preserved          : $script:FullControlKept"     -Level $(if ($script:FullControlKept -gt 0) { "Preserve" } else { "Info" })
    Write-Log " Already Read-only (no change)   : $script:AlreadyRead"         -Level Verbose
    Write-Log " Errors                          : $($script:Errors.Count)"     -Level $(if ($script:Errors.Count   -gt 0) { "Error"    } else { "Info" })
    Write-Log "═══════════════════════════════════════════════════════════════" -Level Info

    if ($script:Errors.Count -gt 0) {
        Write-Log ""
        Write-Log "Errors encountered:" -Level Error
        foreach ($err in $script:Errors) {
            Write-Log "  [$($err.Object)] $($err.Principal): $($err.Error)" -Level Error
        }
    }

    Write-Log ""
    Write-Log "Done." -Level Success
}
catch {
    Write-Log "FATAL: $($_.Exception.Message)" -Level Error
    Write-Log $_.ScriptStackTrace -Level Error
    exit 1
}
finally {
    if (Get-PnPConnection -ErrorAction SilentlyContinue) {
        Disconnect-PnPOnline
    }
}
