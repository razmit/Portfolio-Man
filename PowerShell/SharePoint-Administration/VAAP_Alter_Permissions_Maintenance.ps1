# VAAP_Alter_Permissions_Maintenance.ps1
#
# Purpose: Temporarily set site permissions to Read-Only for maintenance, with ability to restore
# Exception: Preserves any groups with "Full Control" in their permission levels
#
# Usage:
#   Lock Mode:    .\VAAP_Alter_Permissions_Maintenance.ps1 [-DryRun]
#   Restore Mode: .\VAAP_Alter_Permissions_Maintenance.ps1 -Restore [-DryRun]
#
# Parameters:
#   -Restore : Restore permissions from the latest backup CSV
#   -DryRun  : Preview changes without applying them
#
# Input:
#   - SiteUrls.txt: Text file with one site URL per line (in VAAP-Permissions folder)
#
# Output:
#   - CSV backup files in: %USERPROFILE%\Downloads\VAAP-Permissions\
#
# Features:
#   - Processes multiple sites from a text file
#   - Backs up original permissions before modification
#   - Restores permissions from latest backup CSV
#   - Preserves all Full Control permission groups
#   - Progress indicators and detailed logging
#   - Safety confirmations before making changes
#
# Author: Created for COMPANY_NAME SharePoint maintenance operations
# Date: 2025

param(
    [switch]$Restore,
    [switch]$DryRun
)

# ============================================================================
# GLOBAL VARIABLES
# ============================================================================

# Dynamic path to VAAP-Permissions folder
$Global:VaapFolder = Join-Path $env:USERPROFILE "Downloads\VAAP-Permissions"
$Global:SiteUrlsFile = Join-Path $Global:VaapFolder "SiteUrls.txt"

# ============================================================================
# FUNCTIONS
# ============================================================================

# Initialize VAAP-Permissions folder structure
function Initialize-VaapFolder {
    try {
        if (-not (Test-Path $Global:VaapFolder)) {
            New-Item -Path $Global:VaapFolder -ItemType Directory -Force | Out-Null
            Write-Host "✓ Created VAAP-Permissions folder: $Global:VaapFolder" -ForegroundColor Green
        }
        else {
            Write-Host "✓ Using VAAP-Permissions folder: $Global:VaapFolder" -ForegroundColor Green
        }
        return $true
    }
    catch {
        Write-Host "✗ Failed to initialize VAAP-Permissions folder: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

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
            Write-Host "  Connecting to site... (Attempt $failCounter of $maxRetries)" -ForegroundColor Yellow
            Connect-PnPOnline -Url $SiteUrl -clientId CLIENT_ID -interactive
            Write-Host "  ✓ Connection successful!" -ForegroundColor Green
            $connected = $true
            break
        }
        catch {
            if ($_.Exception.Message -notlike "*parse near offset*" -and $_.Exception.Message -notlike "*ASCII digit*") {
                Write-Host "  Connection attempt $failCounter failed: $($_.Exception.Message)" -ForegroundColor Red
            } else {
                Write-Host "  Connection attempt $failCounter failed (authentication flow issue - retrying...)" -ForegroundColor Red
            }
            $failCounter++

            if ($failCounter -le $maxRetries) {
                Write-Host "  Retrying in 2 seconds..." -ForegroundColor Yellow
                Start-Sleep -Seconds 2
            }
        }
    } while ($failCounter -le $maxRetries -and -not $connected)

    if (-not $connected) {
        Write-Host "  ✗ All connection attempts failed for $SiteUrl" -ForegroundColor Red
        return $false
    }

    return $true
}

# Get all groups with aggressive system group filtering
function Get-AllSiteGroups {
    param (
        [string]$SiteUrl
    )

    try {
        $startTime = Get-Date
        $allGroups = Get-PnPGroup -ErrorAction Stop
        $endTime = Get-Date
        $retrievalTime = [math]::Round(($endTime - $startTime).TotalSeconds, 1)

        Write-Host "  ✓ Retrieved $($allGroups.Count) total groups in $retrievalTime seconds" -ForegroundColor Green

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

        Write-Host "  ✓ Filtered to $filteredCount groups ($excludedCount system groups excluded)" -ForegroundColor Green

        return $filteredGroups
    }
    catch {
        Write-Host "  ✗ Error retrieving groups: $($_.Exception.Message)" -ForegroundColor Red
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
            if ($perm.Name -like "*Full Control*") {
                return $true
            }
        }

        return $false
    }
    catch {
        Write-Host "    ⚠ Could not check permissions for: $GroupTitle" -ForegroundColor DarkYellow
        return $false
    }
}

# Read site URLs from text file
function Get-SiteUrlsFromFile {
    try {
        if (-not (Test-Path $Global:SiteUrlsFile)) {
            Write-Host "✗ SiteUrls.txt not found at: $Global:SiteUrlsFile" -ForegroundColor Red
            Write-Host "  Please create this file with one site URL per line." -ForegroundColor Yellow
            return $null
        }

        $urls = Get-Content $Global:SiteUrlsFile | Where-Object {
            $_.Trim() -ne "" -and -not $_.StartsWith("#")
        }

        if ($urls.Count -eq 0) {
            Write-Host "✗ SiteUrls.txt is empty or contains only comments." -ForegroundColor Red
            return $null
        }

        Write-Host "✓ Found $($urls.Count) site URL(s) in SiteUrls.txt" -ForegroundColor Green
        return $urls
    }
    catch {
        Write-Host "✗ Error reading SiteUrls.txt: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

# Get the latest backup CSV file
function Get-LatestBackupCsv {
    try {
        $csvFiles = Get-ChildItem -Path $Global:VaapFolder -Filter "PermissionsBackup_*.csv" |
                    Sort-Object LastWriteTime -Descending

        if ($csvFiles.Count -eq 0) {
            Write-Host "✗ No backup CSV files found in: $Global:VaapFolder" -ForegroundColor Red
            return $null
        }

        $latestCsv = $csvFiles[0]
        Write-Host "✓ Found latest backup: $($latestCsv.Name)" -ForegroundColor Green
        Write-Host "  Created: $($latestCsv.LastWriteTime)" -ForegroundColor DarkGray

        return $latestCsv.FullName
    }
    catch {
        Write-Host "✗ Error finding backup CSV: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

# Set group permissions to Read-Only and return backup info
function Set-GroupToReadOnly {
    param (
        [string]$GroupTitle,
        [string]$SiteUrl,
        [switch]$DryRun
    )

    try {
        # Get current permissions for backup
        $currentPerms = Get-PnPGroupPermissions -Identity $GroupTitle -ErrorAction Stop
        $permissionsString = ($currentPerms | ForEach-Object { $_.Name }) -join ","

        if ($DryRun) {
            Write-Host "    [DRY-RUN] Would set to Read: $GroupTitle" -ForegroundColor Magenta
        }
        else {
            # Remove all existing permissions first
            foreach ($perm in $currentPerms) {
                Set-PnPGroupPermissions -Identity $GroupTitle -RemoveRole $perm.Name -ErrorAction Stop
            }

            # Add Read permission
            Set-PnPGroupPermissions -Identity $GroupTitle -AddRole "Read" -ErrorAction Stop
            Write-Host "    ✓ Set to Read: $GroupTitle" -ForegroundColor Green
        }

        # Return backup object
        return [PSCustomObject]@{
            SiteUrl     = $SiteUrl
            GroupName   = $GroupTitle
            Permissions = $permissionsString
        }
    }
    catch {
        Write-Host "    ✗ Failed to set Read permission for: $GroupTitle - $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

# Restore permissions from CSV
function Restore-PermissionsFromCsv {
    param (
        [string]$CsvPath,
        [switch]$DryRun
    )

    try {
        $backup = Import-Csv $CsvPath -ErrorAction Stop

        if ($backup.Count -eq 0) {
            Write-Host "✗ Backup CSV is empty." -ForegroundColor Red
            return
        }

        Write-Host "✓ Loaded $($backup.Count) permission entries from backup" -ForegroundColor Green

        # Group by site URL
        $siteGroups = $backup | Group-Object -Property SiteUrl

        Write-Host "`n=== Sites in Backup ===" -ForegroundColor Cyan
        foreach ($siteGroup in $siteGroups) {
            Write-Host "  • $($siteGroup.Name) - $($siteGroup.Count) groups" -ForegroundColor DarkGray
        }

        Write-Host "`n--- Starting Restoration ---`n" -ForegroundColor Cyan

        $totalSuccess = 0
        $totalFailed = 0

        foreach ($siteGroup in $siteGroups) {
            $siteUrl = $siteGroup.Name
            Write-Host "→ Processing site: $siteUrl" -ForegroundColor Cyan

            # Connect to site
            $connected = Connect-IndicatedSite -SiteUrl $siteUrl
            if (-not $connected) {
                Write-Host "  ✗ Skipping site due to connection failure" -ForegroundColor Red
                $totalFailed += $siteGroup.Count
                continue
            }

            # Restore each group's permissions
            foreach ($item in $siteGroup.Group) {
                try {
                    $groupName = $item.GroupName
                    $permissions = $item.Permissions -split ","

                    if ($DryRun) {
                        Write-Host "    [DRY-RUN] Would restore: $groupName -> $($item.Permissions)" -ForegroundColor Magenta
                        $totalSuccess++
                    }
                    else {
                        # Remove current permissions (likely just Read)
                        $currentPerms = Get-PnPGroupPermissions -Identity $groupName -ErrorAction Stop
                        foreach ($perm in $currentPerms) {
                            Set-PnPGroupPermissions -Identity $groupName -RemoveRole $perm.Name -ErrorAction Stop
                        }

                        # Add back original permissions
                        foreach ($permission in $permissions) {
                            if ($permission.Trim() -ne "") {
                                Set-PnPGroupPermissions -Identity $groupName -AddRole $permission.Trim() -ErrorAction Stop
                            }
                        }

                        Write-Host "    ✓ Restored: $groupName -> $($item.Permissions)" -ForegroundColor Green
                        $totalSuccess++
                    }
                }
                catch {
                    Write-Host "    ✗ Failed to restore: $($item.GroupName) - $($_.Exception.Message)" -ForegroundColor Red
                    $totalFailed++
                }
            }

            Write-Host ""
        }

        Write-Host "`n=== Restoration Summary ===" -ForegroundColor Cyan
        Write-Host "Successfully restored: $totalSuccess" -ForegroundColor Green
        Write-Host "Failed: $totalFailed" -ForegroundColor Red
    }
    catch {
        Write-Host "✗ Error during restoration: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Process sites in Lock mode
function Invoke-LockMode {
    param (
        [array]$SiteUrls,
        [switch]$DryRun
    )

    Write-Host "`n--- Starting Lock Mode ---" -ForegroundColor Cyan
    Write-Host "Sites to process: $($SiteUrls.Count)" -ForegroundColor Yellow

    $allBackupEntries = @()
    $totalGroupsLocked = 0
    $totalGroupsPreserved = 0
    $totalFailures = 0

    foreach ($siteUrl in $SiteUrls) {
        Write-Host "`n→ Processing site: $siteUrl" -ForegroundColor Cyan

        # Connect to site
        $connected = Connect-IndicatedSite -SiteUrl $siteUrl
        if (-not $connected) {
            Write-Host "  ✗ Skipping site due to connection failure`n" -ForegroundColor Red
            continue
        }

        # Get all groups
        $allGroups = Get-AllSiteGroups -SiteUrl $siteUrl

        if ($allGroups.Count -eq 0) {
            Write-Host "  ⚠ No groups found to process`n" -ForegroundColor Yellow
            continue
        }

        Write-Host "`n  --- Analyzing Group Permissions ---" -ForegroundColor Cyan

        $groupsToLock = @()
        $groupsToPreserve = @()

        foreach ($group in $allGroups) {
            $hasFullControl = Test-FullControlPermission -GroupTitle $group.Title

            if ($hasFullControl) {
                $groupsToPreserve += $group
                Write-Host "    ✓ Preserve Full Control: $($group.Title)" -ForegroundColor Green
                $totalGroupsPreserved++
            }
            else {
                $groupsToLock += $group
                Write-Host "    🔒 Will lock to Read: $($group.Title)" -ForegroundColor Yellow
            }
        }

        # Lock groups
        if ($groupsToLock.Count -gt 0) {
            Write-Host "`n  --- Locking $($groupsToLock.Count) Group(s) ---" -ForegroundColor Cyan

            foreach ($group in $groupsToLock) {
                $backupEntry = Set-GroupToReadOnly -GroupTitle $group.Title -SiteUrl $siteUrl -DryRun:$DryRun

                if ($null -ne $backupEntry) {
                    $allBackupEntries += $backupEntry
                    $totalGroupsLocked++
                }
                else {
                    $totalFailures++
                }
            }
        }
        else {
            Write-Host "`n  ✓ All groups already have Full Control. Nothing to lock." -ForegroundColor Green
        }

        Write-Host ""
    }

    # Export backup CSV
    if ($allBackupEntries.Count -gt 0) {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $csvPath = Join-Path $Global:VaapFolder "PermissionsBackup_$timestamp.csv"

        try {
            $allBackupEntries | Export-Csv -Path $csvPath -NoTypeInformation
            Write-Host "`n✓ Backup exported to: $csvPath" -ForegroundColor Green
        }
        catch {
            Write-Host "`n✗ Failed to export backup CSV: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    # Final summary
    Write-Host "`n╔════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║              LOCK MODE COMPLETE                         ║" -ForegroundColor Green
    Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host "`nGroups locked to Read-Only: $totalGroupsLocked" -ForegroundColor Yellow
    Write-Host "Groups preserved (Full Control): $totalGroupsPreserved" -ForegroundColor Green
    Write-Host "Failures: $totalFailures" -ForegroundColor Red

    if ($DryRun) {
        Write-Host "`n⚠️  This was a DRY-RUN. No changes were made." -ForegroundColor Yellow
        Write-Host "Run without -DryRun to apply changes." -ForegroundColor Yellow
    }
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

Write-Host "`n╔════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     VAAP PERMISSIONS MAINTENANCE SCRIPT                 ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

if ($DryRun) {
    Write-Host "`n⚠️  DRY-RUN MODE - NO CHANGES WILL BE MADE ⚠️`n" -ForegroundColor Yellow -BackgroundColor DarkRed
}

# Initialize folder structure
$folderReady = Initialize-VaapFolder
if (-not $folderReady) {
    Write-Host "`n✗ Cannot proceed without VAAP-Permissions folder. Exiting." -ForegroundColor Red
    exit 1
}

# RESTORE MODE
if ($Restore) {
    Write-Host "`n=== RESTORE MODE ===" -ForegroundColor Yellow

    # Get latest backup CSV
    $csvPath = Get-LatestBackupCsv
    if (-not $csvPath) {
        Write-Host "`n✗ Cannot proceed without backup CSV. Exiting." -ForegroundColor Red
        exit 1
    }

    # Confirm restoration
    if (-not $DryRun) {
        $confirm = Read-Host "`n⚠️  WARNING: This will restore permissions from the backup. Proceed? (Y/N)"
        if ($confirm.ToLower() -ne "y") {
            Write-Host "`n✗ Restoration cancelled by user." -ForegroundColor Red
            exit 0
        }
    }

    # Restore permissions
    Restore-PermissionsFromCsv -CsvPath $csvPath -DryRun:$DryRun

    Write-Host "`n╔════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║           RESTORATION COMPLETE                          ║" -ForegroundColor Green
    Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Green

    if ($DryRun) {
        Write-Host "`n⚠️  This was a DRY-RUN. No changes were made." -ForegroundColor Yellow
    }
}
# LOCK MODE
else {
    Write-Host "`n=== LOCK MODE ===" -ForegroundColor Yellow

    # Read site URLs from file
    $siteUrls = Get-SiteUrlsFromFile
    if (-not $siteUrls) {
        Write-Host "`n✗ Cannot proceed without site URLs. Exiting." -ForegroundColor Red
        exit 1
    }

    # Display sites
    Write-Host "`nSites to lock:" -ForegroundColor Cyan
    foreach ($url in $siteUrls) {
        Write-Host "  • $url" -ForegroundColor DarkGray
    }

    # Confirm lock
    if (-not $DryRun) {
        $confirm = Read-Host "`n⚠️  WARNING: This will set non-Full Control groups to Read-Only. Proceed? (Y/N)"
        if ($confirm.ToLower() -ne "y") {
            Write-Host "`n✗ Lock operation cancelled by user." -ForegroundColor Red
            exit 0
        }
    }

    # Lock sites
    Invoke-LockMode -SiteUrls $siteUrls -DryRun:$DryRun
}

Write-Host ""
