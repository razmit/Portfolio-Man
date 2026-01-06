# ============================================================================
# Flatten Site Permissions Script
# ============================================================================
# Purpose: Reset inheritance on all libraries, folders, and files in a SharePoint site
#          EXCEPT for specified libraries that should keep their unique permissions
#
# Date: December 2025
# ============================================================================

# Function to connect to the requested site and retry if it failed
function Connect-IndicatedSite {
    param (
        [string]$SiteUrl
    )

    $failCounter = 1
    $maxRetries = 3
    $connected = $false

    do {
        try {
            $SiteUrl = $SiteUrl.TrimStart()
            Write-Host "Connecting to the site... (Attempt $failCounter of $maxRetries)" -ForegroundColor Yellow
            Connect-PnPOnline -Url $SiteUrl -ClientId CLIENT_ID -Interactive
            Write-Host "Connection successful!" -ForegroundColor Green
            $connected = $true
            break
        }
        catch {
            if ($_.Exception.Message -notlike "*parse near offset*" -and $_.Exception.Message -notlike "*ASCII digit*") {
                Write-Host "Connection attempt $failCounter failed: $($_.Exception.Message)" -ForegroundColor Red
            } else {
                Write-Host "Connection attempt $failCounter failed (authentication flow issue - retrying...)" -ForegroundColor Red
            }
            $failCounter++

            if ($failCounter -le $maxRetries) {
                Write-Host "Retrying in 2 seconds..." -ForegroundColor Yellow
                Start-Sleep -Seconds 2
            }
        }
    } while ($failCounter -le $maxRetries -and -not $connected)

    if (-not $connected) {
        Write-Host "All connection attempts failed. Unable to connect to $SiteUrl" -ForegroundColor Red
        return $false
    }

    return $true
}

# Function to get all items with broken inheritance
function Get-ItemsWithBrokenInheritance {
    param (
        [string]$SiteUrl
    )

    Write-Host "`n╔════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║     SCANNING FOR ITEMS WITH BROKEN INHERITANCE         ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

    $itemsWithBrokenInheritance = @()

    try {
        # Get all lists and libraries
        $lists = Get-PnPList -Includes HasUniqueRoleAssignments, RootFolder, Hidden | Where-Object {
            $_.Hidden -eq $false -and
            $_.BaseTemplate -ne 100 -and  # Avoid generic lists
            $_.BaseTemplate -ne 119       # Avoid web page libraries
        }

        Write-Host "Found $($lists.Count) lists/libraries to scan" -ForegroundColor Yellow
        $listCounter = 0

        foreach ($list in $lists) {
            $listCounter++
            $percentComplete = [math]::Round(($listCounter / $lists.Count) * 100, 2)
            Write-Progress -Activity "Scanning lists and libraries" -Status "Processing: $($list.Title) ($listCounter of $($lists.Count))" -PercentComplete $percentComplete

            try {
                # Check if the list itself has broken inheritance
                $listItem = Get-PnPList -Identity $list.Id -Includes HasUniqueRoleAssignments

                if ($listItem.HasUniqueRoleAssignments) {
                    Write-Host "  [LIST] $($list.Title) - Has unique permissions" -ForegroundColor Yellow
                    $itemsWithBrokenInheritance += [PSCustomObject]@{
                        Type = "List/Library"
                        Title = $list.Title
                        Url = $list.RootFolder.ServerRelativeUrl
                        ListId = $list.Id
                        ItemId = $null
                        HasUniquePermissions = $true
                    }
                }

                # Get all folders in the list (recursively)
                Write-Host "  Scanning folders in: $($list.Title)" -ForegroundColor Gray
                $folders = Get-PnPFolderItem -FolderSiteRelativeUrl $list.RootFolder.ServerRelativeUrl -ItemType Folder -Recursive -ErrorAction SilentlyContinue

                foreach ($folder in $folders) {
                    try {
                        # Get folder item with permissions info
                        $folderItem = Get-PnPListItem -List $list.Id -Id $folder.ListItemAllFields.Id -Includes HasUniqueRoleAssignments -ErrorAction Stop

                        if ($folderItem.HasUniqueRoleAssignments) {
                            Write-Host "    [FOLDER] $($folder.Name) - Has unique permissions" -ForegroundColor Yellow
                            $itemsWithBrokenInheritance += [PSCustomObject]@{
                                Type = "Folder"
                                Title = $folder.Name
                                Url = $folder.ServerRelativeUrl
                                ListId = $list.Id
                                ItemId = $folderItem.Id
                                HasUniquePermissions = $true
                            }
                        }
                    }
                    catch {
                        Write-Host "    Warning: Could not check permissions for folder: $($folder.Name)" -ForegroundColor DarkYellow
                    }
                }

                # Get all files in the list
                Write-Host "  Scanning files in: $($list.Title)" -ForegroundColor Gray
                $items = Get-PnPListItem -List $list.Id -PageSize 2000 -Fields ID, FileRef, FileLeafRef, HasUniqueRoleAssignments, FSObjType

                $fileItems = $items | Where-Object { $_["FSObjType"] -eq 0 }  # 0 = File, 1 = Folder

                foreach ($item in $fileItems) {
                    try {
                        # Get item with permissions info
                        $itemWithPerms = Get-PnPListItem -List $list.Id -Id $item.Id -Includes HasUniqueRoleAssignments -ErrorAction Stop

                        if ($itemWithPerms.HasUniqueRoleAssignments) {
                            $fileName = $item["FileLeafRef"]
                            Write-Host "    [FILE] $fileName - Has unique permissions" -ForegroundColor Yellow
                            $itemsWithBrokenInheritance += [PSCustomObject]@{
                                Type = "File"
                                Title = $fileName
                                Url = $item["FileRef"]
                                ListId = $list.Id
                                ItemId = $item.Id
                                HasUniquePermissions = $true
                            }
                        }
                    }
                    catch {
                        Write-Host "    Warning: Could not check permissions for item ID: $($item.Id)" -ForegroundColor DarkYellow
                    }
                }
            }
            catch {
                Write-Host "  Error processing list: $($list.Title) - $($_.Exception.Message)" -ForegroundColor Red
            }
        }

        Write-Progress -Activity "Scanning lists and libraries" -Completed

    }
    catch {
        Write-Host "Error during scan: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }

    return $itemsWithBrokenInheritance
}

# Function to export permissions data to CSV
function Export-PermissionsToCSV {
    param (
        [array]$Items,
        [string]$OutputPath
    )

    Write-Host "`nExporting permissions data to CSV..." -ForegroundColor Cyan

    try {
        $Items | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
        Write-Host "Export successful: $OutputPath" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "Error exporting to CSV: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Function to get detailed permissions for an item (for backup)
function Get-ItemPermissions {
    param (
        [string]$ListId,
        [int]$ItemId,
        [string]$ItemType
    )

    $permissions = @()

    try {
        if ($ItemType -eq "List/Library") {
            $roleAssignments = Get-PnPProperty -ClientObject (Get-PnPList -Identity $ListId) -Property RoleAssignments
            $context = Get-PnPContext

            foreach ($roleAssignment in $roleAssignments) {
                $context.Load($roleAssignment.Member)
                $context.Load($roleAssignment.RoleDefinitionBindings)
                $context.ExecuteQuery()

                $permissions += [PSCustomObject]@{
                    PrincipalName = $roleAssignment.Member.Title
                    PrincipalType = $roleAssignment.Member.PrincipalType
                    Roles = ($roleAssignment.RoleDefinitionBindings | ForEach-Object { $_.Name }) -join "; "
                }
            }
        }
        else {
            $item = Get-PnPListItem -List $ListId -Id $ItemId
            $roleAssignments = Get-PnPProperty -ClientObject $item -Property RoleAssignments
            $context = Get-PnPContext

            foreach ($roleAssignment in $roleAssignments) {
                $context.Load($roleAssignment.Member)
                $context.Load($roleAssignment.RoleDefinitionBindings)
                $context.ExecuteQuery()

                $permissions += [PSCustomObject]@{
                    PrincipalName = $roleAssignment.Member.Title
                    PrincipalType = $roleAssignment.Member.PrincipalType
                    Roles = ($roleAssignment.RoleDefinitionBindings | ForEach-Object { $_.Name }) -join "; "
                }
            }
        }
    }
    catch {
        Write-Host "Warning: Could not retrieve permissions - $($_.Exception.Message)" -ForegroundColor DarkYellow
    }

    return $permissions
}

# Function to export detailed permissions backup
function Export-DetailedPermissionsBackup {
    param (
        [array]$Items,
        [string]$OutputPath
    )

    Write-Host "`n╔════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║        CREATING DETAILED PERMISSIONS BACKUP            ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

    $detailedBackup = @()
    $counter = 0

    foreach ($item in $Items) {
        $counter++
        $percentComplete = [math]::Round(($counter / $Items.Count) * 100, 2)
        Write-Progress -Activity "Backing up permissions" -Status "Processing: $($item.Title) ($counter of $($Items.Count))" -PercentComplete $percentComplete

        Write-Host "Backing up: [$($item.Type)] $($item.Title)" -ForegroundColor Gray

        $permissions = Get-ItemPermissions -ListId $item.ListId -ItemId $item.ItemId -ItemType $item.Type

        foreach ($perm in $permissions) {
            $detailedBackup += [PSCustomObject]@{
                Type = $item.Type
                Title = $item.Title
                Url = $item.Url
                ListId = $item.ListId
                ItemId = $item.ItemId
                PrincipalName = $perm.PrincipalName
                PrincipalType = $perm.PrincipalType
                Roles = $perm.Roles
                BackupDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            }
        }
    }

    Write-Progress -Activity "Backing up permissions" -Completed

    try {
        $detailedBackup | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
        Write-Host "`nDetailed backup successful: $OutputPath" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "Error creating detailed backup: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Function to reset inheritance on items
function Reset-ItemInheritance {
    param (
        [array]$Items,
        [array]$ExcludedLibraries,
        [switch]$DryRun
    )

    if ($DryRun) {
        Write-Host "`n╔════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
        Write-Host "║          DRY-RUN MODE - NO CHANGES WILL BE MADE        ║" -ForegroundColor Magenta
        Write-Host "╚════════════════════════════════════════════════════════╝`n" -ForegroundColor Magenta
    }
    else {
        Write-Host "`n╔════════════════════════════════════════════════════════╗" -ForegroundColor Green
        Write-Host "║            RESETTING INHERITANCE - LIVE MODE           ║" -ForegroundColor Green
        Write-Host "╚════════════════════════════════════════════════════════╝`n" -ForegroundColor Green
    }

    $resetCount = 0
    $skippedCount = 0
    $errorCount = 0
    $counter = 0

    $resetLog = @()

    foreach ($item in $Items) {
        $counter++
        $percentComplete = [math]::Round(($counter / $Items.Count) * 100, 2)
        Write-Progress -Activity "Processing items" -Status "Processing: $($item.Title) ($counter of $($Items.Count))" -PercentComplete $percentComplete

        # Check if this item is in an excluded library
        $shouldSkip = $false

        if ($item.Type -eq "List/Library" -and $ExcludedLibraries -contains $item.Title) {
            $shouldSkip = $true
            Write-Host "[$($item.Type)] $($item.Title) - SKIPPED (Excluded library)" -ForegroundColor Yellow
        }
        elseif ($item.Type -ne "List/Library") {
            # For folders and files, check if they belong to an excluded library
            foreach ($excludedLib in $ExcludedLibraries) {
                if ($item.Url -like "*/$excludedLib/*" -or $item.Url -like "*/$excludedLib") {
                    $shouldSkip = $true
                    Write-Host "[$($item.Type)] $($item.Title) - SKIPPED (In excluded library: $excludedLib)" -ForegroundColor Yellow
                    break
                }
            }
        }

        if ($shouldSkip) {
            $skippedCount++
            $resetLog += [PSCustomObject]@{
                Type = $item.Type
                Title = $item.Title
                Url = $item.Url
                Action = "Skipped"
                Reason = "In excluded library"
                Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            }
            continue
        }

        # Reset inheritance
        try {
            if (-not $DryRun) {
                if ($item.Type -eq "List/Library") {
                    Set-PnPList -Identity $item.ListId -ResetRoleInheritance
                    Write-Host "[$($item.Type)] $($item.Title) - INHERITANCE RESET" -ForegroundColor Green
                }
                else {
                    # For folders and files
                    Set-PnPListItemPermission -List $item.ListId -Identity $item.ItemId -InheritPermissions
                    Write-Host "[$($item.Type)] $($item.Title) - INHERITANCE RESET" -ForegroundColor Green
                }

                $resetLog += [PSCustomObject]@{
                    Type = $item.Type
                    Title = $item.Title
                    Url = $item.Url
                    Action = "Reset"
                    Reason = "Inheritance restored"
                    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                }

                $resetCount++
            }
            else {
                Write-Host "[$($item.Type)] $($item.Title) - WOULD RESET INHERITANCE" -ForegroundColor Cyan
                $resetLog += [PSCustomObject]@{
                    Type = $item.Type
                    Title = $item.Title
                    Url = $item.Url
                    Action = "Would Reset"
                    Reason = "Dry-run mode"
                    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                }
                $resetCount++
            }
        }
        catch {
            Write-Host "[$($item.Type)] $($item.Title) - ERROR: $($_.Exception.Message)" -ForegroundColor Red
            $resetLog += [PSCustomObject]@{
                Type = $item.Type
                Title = $item.Title
                Url = $item.Url
                Action = "Error"
                Reason = $_.Exception.Message
                Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            }
            $errorCount++
        }
    }

    Write-Progress -Activity "Processing items" -Completed

    # Summary
    Write-Host "`n╔════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                    OPERATION SUMMARY                   ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host "Total items processed: $($Items.Count)" -ForegroundColor White
    Write-Host "Items reset: $resetCount" -ForegroundColor Green
    Write-Host "Items skipped: $skippedCount" -ForegroundColor Yellow
    Write-Host "Errors: $errorCount" -ForegroundColor Red

    return $resetLog
}

# Main script execution
function Start-PermissionFlattening {
    Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                                                              ║" -ForegroundColor Cyan
    Write-Host "║        SharePoint Site Permissions Flattening Script        ║" -ForegroundColor Cyan
    Write-Host "║                                                              ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    # Get site URL
    $siteUrl = Read-Host "Enter the SharePoint site URL"

    if ([string]::IsNullOrWhiteSpace($siteUrl)) {
        Write-Host "Site URL cannot be empty. Exiting." -ForegroundColor Red
        return
    }

    # Connect to site
    $connected = Connect-IndicatedSite -SiteUrl $siteUrl
    if (-not $connected) {
        Write-Host "Failed to connect to site. Exiting." -ForegroundColor Red
        return
    }

    # Get excluded libraries
    Write-Host "`nEnter library names to EXCLUDE from flattening (keep their unique permissions)" -ForegroundColor Yellow
    Write-Host "Separate multiple libraries with commas (e.g., 'Library1, Library2, Library3')" -ForegroundColor Yellow
    Write-Host "Press Enter without typing anything if you want to flatten EVERYTHING" -ForegroundColor Yellow
    $excludedInput = Read-Host "Excluded libraries"

    $excludedLibraries = @()
    if (-not [string]::IsNullOrWhiteSpace($excludedInput)) {
        $excludedLibraries = $excludedInput.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
        Write-Host "`nExcluded libraries:" -ForegroundColor Cyan
        foreach ($lib in $excludedLibraries) {
            Write-Host "  - $lib" -ForegroundColor Cyan
        }
    }
    else {
        Write-Host "`nNo libraries excluded - ALL items will be flattened" -ForegroundColor Yellow
    }

    # Scan for items with broken inheritance
    $itemsWithBrokenInheritance = Get-ItemsWithBrokenInheritance -SiteUrl $siteUrl

    if ($itemsWithBrokenInheritance.Count -eq 0) {
        Write-Host "`nNo items with broken inheritance found. Nothing to flatten!" -ForegroundColor Green
        return
    }

    Write-Host "`n╔════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                    SCAN RESULTS                        ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host "Total items with broken inheritance: $($itemsWithBrokenInheritance.Count)" -ForegroundColor Yellow
    Write-Host "  Lists/Libraries: $(($itemsWithBrokenInheritance | Where-Object { $_.Type -eq 'List/Library' }).Count)" -ForegroundColor White
    Write-Host "  Folders: $(($itemsWithBrokenInheritance | Where-Object { $_.Type -eq 'Folder' }).Count)" -ForegroundColor White
    Write-Host "  Files: $(($itemsWithBrokenInheritance | Where-Object { $_.Type -eq 'File' }).Count)" -ForegroundColor White

    # Create output directory
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $outputDir = Join-Path $PSScriptRoot "PermissionFlattening_$timestamp"
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    Write-Host "`nOutput directory: $outputDir" -ForegroundColor Cyan

    # Export scan results
    $scanResultsPath = Join-Path $outputDir "01_ScanResults.csv"
    Export-PermissionsToCSV -Items $itemsWithBrokenInheritance -OutputPath $scanResultsPath

    # Create detailed permissions backup
    $backupPath = Join-Path $outputDir "02_PermissionsBackup.csv"
    Export-DetailedPermissionsBackup -Items $itemsWithBrokenInheritance -OutputPath $backupPath

    # Dry-run mode
    Write-Host "`n╔════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
    Write-Host "║                  DRY-RUN PREVIEW                       ║" -ForegroundColor Magenta
    Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Magenta
    Write-Host "Running in dry-run mode to show what would be changed..." -ForegroundColor Yellow

    $dryRunLog = Reset-ItemInheritance -Items $itemsWithBrokenInheritance -ExcludedLibraries $excludedLibraries -DryRun

    $dryRunPath = Join-Path $outputDir "03_DryRun_Preview.csv"
    $dryRunLog | Export-Csv -Path $dryRunPath -NoTypeInformation -Encoding UTF8
    Write-Host "Dry-run preview saved: $dryRunPath" -ForegroundColor Cyan

    # Ask for confirmation
    Write-Host "`n╔════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "║                     CONFIRMATION                       ║" -ForegroundColor Yellow
    Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
    Write-Host "Do you want to proceed with resetting inheritance?" -ForegroundColor Yellow
    Write-Host "This will reset permissions on $($dryRunLog | Where-Object { $_.Action -eq 'Would Reset' }).Count items" -ForegroundColor Yellow
    Write-Host "Type 'YES' to proceed, or anything else to cancel" -ForegroundColor Yellow
    $confirmation = Read-Host "Proceed"

    if ($confirmation -ne "YES") {
        Write-Host "`nOperation cancelled by user. No changes were made." -ForegroundColor Yellow
        Write-Host "All reports have been saved to: $outputDir" -ForegroundColor Cyan
        return
    }

    # Execute the reset
    Write-Host "`nProceeding with live execution..." -ForegroundColor Green
    $executionLog = Reset-ItemInheritance -Items $itemsWithBrokenInheritance -ExcludedLibraries $excludedLibraries

    $executionLogPath = Join-Path $outputDir "04_Execution_Log.csv"
    $executionLog | Export-Csv -Path $executionLogPath -NoTypeInformation -Encoding UTF8
    Write-Host "`nExecution log saved: $executionLogPath" -ForegroundColor Cyan

    Write-Host "`n╔════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║                  OPERATION COMPLETE                    ║" -ForegroundColor Green
    Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host "All reports saved to: $outputDir" -ForegroundColor Cyan
    Write-Host "`nGenerated files:" -ForegroundColor White
    Write-Host "  1. Scan Results: 01_ScanResults.csv" -ForegroundColor White
    Write-Host "  2. Permissions Backup: 02_PermissionsBackup.csv" -ForegroundColor White
    Write-Host "  3. Dry-run Preview: 03_DryRun_Preview.csv" -ForegroundColor White
    Write-Host "  4. Execution Log: 04_Execution_Log.csv" -ForegroundColor White
}

# Run the script
Start-PermissionFlattening
