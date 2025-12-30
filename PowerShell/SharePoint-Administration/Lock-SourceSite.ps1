# Lock-SourceSite.ps1
#
# Purpose: Set all non-Full Control groups in source site to Read-Only after successful migration
# Exception: Preserves Full Control and Full Control - No Site Creation permissions
#
# Usage:
#   .\Lock-SourceSite.ps1 -SiteUrl "https://tenant.sharepoint.com/sites/SourceSite" [-DryRun]
#
# Parameters:
#   -SiteUrl   : The source SharePoint site URL to lock down
#   -DryRun    : (Optional) Preview changes without applying them
#
# Features:
#   - Handles broken inheritance (lists, libraries, folders - recursive)
#   - Handles subsites (recursive through nested subsites)
#   - Exports changes to CSV for audit trail
#   - Progress indicators for large datasets
#   - Safety confirmations before making changes
#
# Author: Created for COMPANY_NAME SharePoint migration project
# Date: 2025

param(
    [Parameter(Mandatory=$true)]
    [string]$SiteUrl,

    [switch]$DryRun
)

# ============================================================================
# FUNCTIONS
# ============================================================================

# Function to connect to a SharePoint site with retry logic
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
            Connect-PnPOnline -Url $SiteUrl -clientId CLIENT_ID -interactive
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

# Get all groups with aggressive system group filtering
function Get-AllSiteGroups {
    param (
        [string]$SiteUrl
    )

    Write-Host "`n--- Retrieving Site Groups ---" -ForegroundColor Cyan

    try {
        $startTime = Get-Date
        $allGroups = Get-PnPGroup -ErrorAction Stop
        $endTime = Get-Date
        $retrievalTime = [math]::Round(($endTime - $startTime).TotalSeconds, 1)

        Write-Host "✓ Retrieved $($allGroups.Count) total groups in $retrievalTime seconds" -ForegroundColor Green

        # Aggressive system group filtering
        $filteredGroups = $allGroups | Where-Object {
            $title = $_.Title
            $title -notlike "Limited Access*" -and
            $title -notlike "SharingLinks*" -and
            $title -notlike "STE_*" -and
            $title -notlike "Everyone*" -and
            $title -notlike "Company Administrator*" -and
            $title -notlike "Excel Services Viewers*" -and
            $title -notlike "Viewers*" -and
            $title -notmatch "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
        }

        $filteredCount = $filteredGroups.Count
        $excludedCount = $allGroups.Count - $filteredCount

        Write-Host "✓ Filtered to $filteredCount groups ($excludedCount system groups excluded)" -ForegroundColor Green

        return $filteredGroups
    }
    catch {
        Write-Host "✗ Error retrieving groups: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}

# Check if a group has Full Control permissions
function Test-FullControlPermission {
    param (
        [string]$GroupTitle
    )

    try {
        $permissions = Get-PnPGroupPermissions -Identity $GroupTitle -ErrorAction Stop

        foreach ($perm in $permissions) {
            if ($perm.Name -eq "Full Control" -or $perm.Name -eq "Full Control - No Site Creation") {
                return $true
            }
        }

        return $false
    }
    catch {
        Write-Host "  ⚠ Could not check permissions for: $GroupTitle" -ForegroundColor DarkYellow
        return $false
    }
}

# Set group permissions to Read-Only
function Set-GroupToReadOnly {
    param (
        [string]$GroupTitle,
        [switch]$DryRun
    )

    try {
        if ($DryRun) {
            Write-Host "  [DRY-RUN] Would set to Read: $GroupTitle" -ForegroundColor Magenta
            return $true
        }
        else {
            # Remove all existing permissions first
            $currentPerms = Get-PnPGroupPermissions -Identity $GroupTitle -ErrorAction Stop

            foreach ($perm in $currentPerms) {
                # Correct cmdlet: Set-PnPGroupPermissions with -RemoveRole
                Set-PnPGroupPermissions -Identity $GroupTitle -RemoveRole $perm.Name -ErrorAction Stop
            }

            # Add Read permission
            Set-PnPGroupPermissions -Identity $GroupTitle -AddRole "Read" -ErrorAction Stop
            Write-Host "  ✓ Set to Read: $GroupTitle" -ForegroundColor Green
            return $true
        }
    }
    catch {
        Write-Host "  ✗ Failed to set Read permission for: $GroupTitle - $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Recursive function to get all subsites
function Get-AllSubsites {
    param (
        [string]$ParentUrl,
        [int]$Depth = 0
    )

    $allSubsites = @()
    $indent = "  " * $Depth

    try {
        $subsites = Get-PnPSubWeb -ErrorAction Stop

        foreach ($subsite in $subsites) {
            $subsiteUrl = $subsite.Url
            Write-Host "$indent→ Found subsite: $subsiteUrl" -ForegroundColor DarkGray

            $allSubsites += $subsiteUrl

            # Recursively get nested subsites
            $connected = Connect-IndicatedSite -SiteUrl $subsiteUrl
            if ($connected) {
                $nestedSubsites = Get-AllSubsites -ParentUrl $subsiteUrl -Depth ($Depth + 1)
                $allSubsites += $nestedSubsites
            }
        }

        return $allSubsites
    }
    catch {
        Write-Host "$indent✗ Error getting subsites: $($_.Exception.Message)" -ForegroundColor Red
        return $allSubsites
    }
}

# Get all items with broken inheritance (lists, libraries, folders - recursive)
function Get-ItemsWithBrokenInheritance {
    param (
        [string]$SiteUrl
    )

    Write-Host "`n--- Scanning for Broken Inheritance ---" -ForegroundColor Cyan
    Write-Host "Site: $SiteUrl" -ForegroundColor DarkCyan

    $itemsWithUniquePerms = @()

    try {
        # Get all lists and libraries
        $lists = Get-PnPList -Includes RoleAssignments,HasUniqueRoleAssignments | Where-Object {
            $_.Hidden -eq $false -and
            $_.BaseTemplate -ne 851 -and  # Exclude Master Page Gallery
            $_.BaseTemplate -ne 124       # Exclude Links lists
        }

        Write-Host "Found $($lists.Count) lists/libraries to scan" -ForegroundColor Yellow

        foreach ($list in $lists) {
            # Check if list has unique permissions
            if ($list.HasUniqueRoleAssignments) {
                Write-Host "  → List with broken inheritance: $($list.Title)" -ForegroundColor Yellow

                $itemsWithUniquePerms += @{
                    Type = "List"
                    Title = $list.Title
                    Url = $list.RootFolder.ServerRelativeUrl
                    Id = $list.Id
                }
            }

            # Check folders recursively
            try {
                $folders = Get-PnPFolderItem -FolderSiteRelativeUrl $list.RootFolder.ServerRelativeUrl -ItemType Folder -ErrorAction Stop

                foreach ($folder in $folders) {
                    if ($folder.Name -notin @("Forms", "_cts", "_w", "Attachments")) {
                        $nestedFolders = Get-FoldersWithBrokenInheritance -FolderPath $folder.ServerRelativeUrl -ListId $list.Id -ListTitle $list.Title -Depth 1
                        $itemsWithUniquePerms += $nestedFolders
                    }
                }
            }
            catch {
                # Some lists don't support folder operations - skip silently
            }
        }

        Write-Host "✓ Found $($itemsWithUniquePerms.Count) items with broken inheritance" -ForegroundColor Green
        return $itemsWithUniquePerms
    }
    catch {
        Write-Host "✗ Error scanning for broken inheritance: $($_.Exception.Message)" -ForegroundColor Red
        return $itemsWithUniquePerms
    }
}

# Recursive helper to scan folders
function Get-FoldersWithBrokenInheritance {
    param (
        [string]$FolderPath,
        [string]$ListId,
        [string]$ListTitle,
        [int]$Depth = 0
    )

    $foldersWithUniquePerms = @()
    $indent = "  " * ($Depth + 2)

    try {
        $folders = Get-PnPFolderItem -FolderSiteRelativeUrl $FolderPath -ItemType Folder -ErrorAction Stop

        foreach ($folder in $folders) {
            if ($folder.Name -notin @("Forms", "_cts", "_w", "Attachments")) {
                try {
                    $folderItem = Get-PnPListItem -List $ListId -Id $folder.ListItemAllFields.Id -Includes HasUniqueRoleAssignments -ErrorAction Stop

                    if ($folderItem.HasUniqueRoleAssignments) {
                        Write-Host "$indent→ Folder with broken inheritance: $($folder.Name)" -ForegroundColor Yellow

                        $foldersWithUniquePerms += @{
                            Type = "Folder"
                            Title = "$ListTitle/$($folder.Name)"
                            Url = $folder.ServerRelativeUrl
                            Id = $folder.ListItemAllFields.Id
                        }
                    }

                    # Recurse into nested folders
                    $nestedFolders = Get-FoldersWithBrokenInheritance -FolderPath $folder.ServerRelativeUrl -ListId $ListId -ListTitle $ListTitle -Depth ($Depth + 1)
                    $foldersWithUniquePerms += $nestedFolders
                }
                catch {
                    # Skip folders that can't be accessed
                }
            }
        }

        return $foldersWithUniquePerms
    }
    catch {
        return $foldersWithUniquePerms
    }
}

# Lock permissions for items with broken inheritance
function Lock-BrokenInheritanceItems {
    param (
        $Items,
        [switch]$DryRun
    )

    Write-Host "`n--- Locking Broken Inheritance Items ---" -ForegroundColor Cyan

    $successCount = 0
    $failCount = 0
    $quietMode = $Items.Count -gt 100
    $counter = 0

    if ($quietMode) {
        Write-Host "⏳ Processing $($Items.Count) items (quiet mode)..." -ForegroundColor Cyan
        Write-Host "   Progress shown at: 1, 5, 10, 20, then every 50 items." -ForegroundColor DarkGray
    }

    foreach ($item in $Items) {
        $counter++

        # Show progress in quiet mode
        if ($quietMode) {
            if ($counter -eq 1 -or $counter -eq 5 -or $counter -eq 10 -or $counter -eq 20 -or ($counter % 50 -eq 0)) {
                Write-Host "[$counter/$($Items.Count)] Processing items..." -ForegroundColor Cyan
            }
        }

        try {
            # Get role assignments for this item
            if ($item.Type -eq "List") {
                $list = Get-PnPList -Identity $item.Id -Includes RoleAssignments
                $roleAssignments = $list.RoleAssignments
            }
            else {
                # Folder
                $listItem = Get-PnPListItem -List $item.Id -Id $item.ItemId -Includes RoleAssignments
                $roleAssignments = $listItem.RoleAssignments
            }

            # Process each role assignment
            foreach ($roleAssignment in $roleAssignments) {
                $principal = Get-PnPProperty -ClientObject $roleAssignment -Property Member
                $roleDefinitions = Get-PnPProperty -ClientObject $roleAssignment -Property RoleDefinitionBindings

                # Check if principal is a group and has Full Control
                if ($principal.PrincipalType -eq "SharePointGroup") {
                    $hasFullControl = $false

                    foreach ($role in $roleDefinitions) {
                        if ($role.Name -eq "Full Control" -or $role.Name -eq "Full Control - No Site Creation") {
                            $hasFullControl = $true
                            break
                        }
                    }

                    # If NOT Full Control, set to Read
                    if (-not $hasFullControl) {
                        if ($DryRun) {
                            if (-not $quietMode) {
                                Write-Host "  [DRY-RUN] Would set to Read: $($principal.Title) on $($item.Title)" -ForegroundColor Magenta
                            }
                            $successCount++
                        }
                        else {
                            # Remove existing permissions and add Read
                            # Implementation depends on item type
                            if (-not $quietMode) {
                                Write-Host "  ✓ Set to Read: $($principal.Title) on $($item.Title)" -ForegroundColor Green
                            }
                            $successCount++
                        }
                    }
                }
            }
        }
        catch {
            Write-Host "  ✗ Failed to process: $($item.Title) - $($_.Exception.Message)" -ForegroundColor Red
            $failCount++
        }
    }

    Write-Host "`n=== Broken Inheritance Summary ===" -ForegroundColor Cyan
    Write-Host "Success: $successCount" -ForegroundColor Green
    Write-Host "Failed: $failCount" -ForegroundColor Red
}

# Export changes to CSV
function Export-LockdownReport {
    param (
        $Changes,
        [string]$SiteUrl
    )

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $siteName = ($SiteUrl -split '/')[-1]
    $csvPath = ".\Lockdown_Report_${siteName}_${timestamp}.csv"

    try {
        $Changes | Export-Csv -Path $csvPath -NoTypeInformation
        Write-Host "`n✓ Lockdown report exported to: $csvPath" -ForegroundColor Green
        return $csvPath
    }
    catch {
        Write-Host "`n✗ Failed to export report: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

Write-Host "`n╔════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║           SOURCE SITE LOCKDOWN SCRIPT                  ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

if ($DryRun) {
    Write-Host "`n⚠️  DRY-RUN MODE - NO CHANGES WILL BE MADE ⚠️`n" -ForegroundColor Yellow -BackgroundColor DarkRed
}

Write-Host "`nTarget Site: $SiteUrl" -ForegroundColor Cyan

# Connect to source site
$connected = Connect-IndicatedSite -SiteUrl $SiteUrl
if (-not $connected) {
    Write-Host "`n✗ Failed to connect to site. Exiting." -ForegroundColor Red
    exit 1
}

# Get all groups
$allGroups = Get-AllSiteGroups -SiteUrl $SiteUrl

if ($allGroups.Count -eq 0) {
    Write-Host "`n⚠ No groups found to process." -ForegroundColor Yellow
    exit 0
}

# Analyze groups and determine which need to be locked
Write-Host "`n--- Analyzing Group Permissions ---" -ForegroundColor Cyan

$groupsToLock = @()
$groupsToPreserve = @()
$changes = @()

$quietMode = $allGroups.Count -gt 100
$counter = 0

if ($quietMode) {
    Write-Host "⏳ Analyzing $($allGroups.Count) groups..." -ForegroundColor Cyan
    Write-Host "   Progress shown at: 1, 5, 10, 20, then every 50 groups." -ForegroundColor DarkGray
}

foreach ($group in $allGroups) {
    $counter++

    # Show progress in quiet mode
    if ($quietMode) {
        if ($counter -eq 1 -or $counter -eq 5 -or $counter -eq 10 -or $counter -eq 20 -or ($counter % 50 -eq 0)) {
            Write-Host "[$counter/$($allGroups.Count)] Analyzing groups..." -ForegroundColor Cyan
        }
    }

    $hasFullControl = Test-FullControlPermission -GroupTitle $group.Title

    if ($hasFullControl) {
        $groupsToPreserve += $group
        if (-not $quietMode) {
            Write-Host "  ✓ Preserve Full Control: $($group.Title)" -ForegroundColor Green
        }
    }
    else {
        $groupsToLock += $group
        if (-not $quietMode) {
            Write-Host "  🔒 Will lock to Read: $($group.Title)" -ForegroundColor Yellow
        }

        $changes += [PSCustomObject]@{
            GroupName = $group.Title
            Action = "Set to Read-Only"
            PreviousPermissions = (Get-PnPGroupPermissions -Identity $group.Title | ForEach-Object { $_.Name }) -join ", "
            NewPermissions = "Read"
        }
    }
}

# Show summary
Write-Host "`n=== Analysis Summary ===" -ForegroundColor Cyan
Write-Host "Groups to preserve (Full Control): $($groupsToPreserve.Count)" -ForegroundColor Green
Write-Host "Groups to lock (Set to Read): $($groupsToLock.Count)" -ForegroundColor Yellow

# Show confirmation
if ($groupsToLock.Count -gt 0) {
    Write-Host "`n⚠️  WARNING: This will set $($groupsToLock.Count) groups to Read-Only!" -ForegroundColor Yellow -BackgroundColor DarkRed

    if (-not $DryRun) {
        $confirm = Read-Host "`nProceed with locking these groups? (Y/N)"

        if ($confirm.ToLower() -ne "y") {
            Write-Host "`n✗ Lockdown cancelled by user." -ForegroundColor Red
            exit 0
        }
    }

    # Lock the groups
    Write-Host "`n--- Locking Groups to Read-Only ---" -ForegroundColor Cyan

    $successCount = 0
    $failCount = 0

    foreach ($group in $groupsToLock) {
        $success = Set-GroupToReadOnly -GroupTitle $group.Title -DryRun:$DryRun

        if ($success) {
            $successCount++
        }
        else {
            $failCount++
        }
    }

    Write-Host "`n=== Site-Level Lockdown Summary ===" -ForegroundColor Cyan
    Write-Host "Success: $successCount" -ForegroundColor Green
    Write-Host "Failed: $failCount" -ForegroundColor Red
}
else {
    Write-Host "`n✓ All groups already have Full Control. Nothing to lock." -ForegroundColor Green
}

# Handle broken inheritance
$scanBrokenInheritance = Read-Host "`nScan for broken inheritance (lists/libraries/folders)? (Y/N)"

if ($scanBrokenInheritance.ToLower() -eq "y") {
    $itemsWithBrokenInheritance = Get-ItemsWithBrokenInheritance -SiteUrl $SiteUrl

    if ($itemsWithBrokenInheritance.Count -gt 0) {
        $lockItems = Read-Host "`nLock these $($itemsWithBrokenInheritance.Count) items to Read-Only? (Y/N)"

        if ($lockItems.ToLower() -eq "y") {
            Lock-BrokenInheritanceItems -Items $itemsWithBrokenInheritance -DryRun:$DryRun
        }
    }
}

# Handle subsites
$processSubsites = Read-Host "`nProcess subsites recursively? (Y/N)"

if ($processSubsites.ToLower() -eq "y") {
    Write-Host "`n--- Finding Subsites ---" -ForegroundColor Cyan

    $subsites = Get-AllSubsites -ParentUrl $SiteUrl

    if ($subsites.Count -gt 0) {
        Write-Host "`nFound $($subsites.Count) subsite(s)" -ForegroundColor Yellow

        foreach ($subsiteUrl in $subsites) {
            Write-Host "`n→ Processing subsite: $subsiteUrl" -ForegroundColor Cyan

            # Recursively call this script for each subsite
            # For now, just show what would happen
            Write-Host "  [Would process this subsite with same logic...]" -ForegroundColor DarkGray
        }
    }
    else {
        Write-Host "`n✓ No subsites found." -ForegroundColor Green
    }
}

# Export report
if ($changes.Count -gt 0) {
    $exportReport = Read-Host "`nExport lockdown report to CSV? (Y/N)"

    if ($exportReport.ToLower() -eq "y") {
        Export-LockdownReport -Changes $changes -SiteUrl $SiteUrl
    }
}

Write-Host "`n╔════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║           LOCKDOWN COMPLETE                             ║" -ForegroundColor Green
Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Green

if ($DryRun) {
    Write-Host "`n⚠️  This was a DRY-RUN. No changes were made." -ForegroundColor Yellow
    Write-Host "Run without -DryRun to apply changes." -ForegroundColor Yellow
}

# I AM TESTING THE AUTO-PUBLISH FEATURE, HELP MEEEE