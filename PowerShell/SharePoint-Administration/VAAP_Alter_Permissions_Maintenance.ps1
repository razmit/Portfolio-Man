# VAAP_Alter_Permissions_Maintenance.ps1
#
# Purpose: Temporarily set list permissions to Read-Only for maintenance, with ability to restore
# Exception: Preserves any groups/users with "Full Control" permission levels
#
# Usage:
#   Lock Mode:    .\VAAP_Alter_Permissions_Maintenance.ps1 [-DryRun]
#   Restore Mode: .\VAAP_Alter_Permissions_Maintenance.ps1 -Restore [-DryRun]
#
# Parameters:
#   -Restore : Restore permissions from the latest backup CSV
#   -DryRun  : Preview changes without applying them
#
# Output:
#   - CSV backup files in: %USERPROFILE%\Downloads\VAAP-Permissions\
#
# Features:
#   - Modifies permissions on specific VAAP lists (hardcoded GUIDs)
#   - Backs up original permissions before modification
#   - Restores permissions from latest backup CSV
#   - Preserves all Full Control permission assignments
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

# Target site URL
$Global:SiteUrl = "https://companynet.sharepoint.com/sites/solutions/vaap"

# Target list GUIDs (the 5 VAAP lists that require maintenance)
$Global:TargetListGuids = @(
    "8531C4BA-6AD0-4369-8F72-038A90585E11",
    "ACA202CE-BB34-4BC2-A91C-40BE0B04BBC0",
    "E055289A-9C09-4DC2-A546-6E2C9B87AFF2",
    "EDB1FB42-3E67-480D-813E-BE4B95DE7A53",
    "CEE3B8A5-E9E4-49A0-A346-62E195984783",
    "28CAD9EC-394F-4B43-8CC0-735D43BC47BB"
)

# Dynamic path to VAAP-Permissions folder
$Global:VaapFolder = Join-Path $env:USERPROFILE "Downloads\VAAP-Permissions"

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
            Write-Host "Connecting to site... (Attempt $failCounter of $maxRetries)" -ForegroundColor Yellow
            Connect-PnPOnline -Url $SiteUrl -clientId CLIENT_ID -interactive
            Write-Host "✓ Connection successful!" -ForegroundColor Green
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
        Write-Host "✗ All connection attempts failed for $SiteUrl" -ForegroundColor Red
        return $false
    }

    return $true
}

# Get list by GUID with error handling
function Get-TargetList {
    param (
        [string]$ListGuid
    )

    try {
        $list = Get-PnPList -Identity $ListGuid -Includes Title,RoleAssignments,HasUniqueRoleAssignments -ErrorAction Stop
        Write-Host "  ✓ Found list: $($list.Title) (GUID: $ListGuid)" -ForegroundColor Green
        return $list
    }
    catch {
        Write-Host "  ✗ Failed to retrieve list with GUID: $ListGuid" -ForegroundColor Red
        Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor DarkRed
        return $null
    }
}

# Get the latest backup CSV file
function Get-LatestBackupCsv {
    try {
        $csvFiles = Get-ChildItem -Path $Global:VaapFolder -Filter "VAAP_PermissionsBackup_*.csv" |
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

# Check if a role assignment has Full Control permissions
function Test-HasFullControl {
    param (
        $RoleDefinitions
    )

    foreach ($role in $RoleDefinitions) {
        if ($role.Name -like "*Full Control*") {
            return $true
        }
    }
    return $false
}

# Process list permissions in Lock mode
function Invoke-LockList {
    param (
        [string]$ListGuid,
        [switch]$DryRun
    )

    $backupEntries = @()
    $lockedCount = 0
    $preservedCount = 0
    $failCount = 0

    # Get the list
    $list = Get-TargetList -ListGuid $ListGuid
    if (-not $list) {
        Write-Host "  ✗ Skipping list due to retrieval failure`n" -ForegroundColor Red
        return $backupEntries
    }

    # Check if list has unique permissions
    if (-not $list.HasUniqueRoleAssignments) {
        Write-Host "  ⚠ Warning: List '$($list.Title)' inherits permissions from parent" -ForegroundColor Yellow
        Write-Host "    This script only works on lists with broken inheritance" -ForegroundColor Yellow
        return $backupEntries
    }

    Write-Host "`n  --- Analyzing List Permissions ---" -ForegroundColor Cyan
    Write-Host "  List: $($list.Title)" -ForegroundColor DarkCyan

    # Get all role assignments
    $roleAssignments = $list.RoleAssignments

    if ($roleAssignments.Count -eq 0) {
        Write-Host "  ⚠ No role assignments found on this list" -ForegroundColor Yellow
        return $backupEntries
    }

    Write-Host "  Found $($roleAssignments.Count) role assignment(s)" -ForegroundColor DarkGray

    # Process each role assignment
    foreach ($roleAssignment in $roleAssignments) {
        try {
            # Get the principal (group or user)
            $principal = Get-PnPProperty -ClientObject $roleAssignment -Property Member -ErrorAction Stop
            $roleDefinitions = Get-PnPProperty -ClientObject $roleAssignment -Property RoleDefinitionBindings -ErrorAction Stop

            $principalTitle = $principal.Title
            $principalType = $principal.PrincipalType.ToString()
            $principalId = $principal.Id

            # Get permission level names
            $permissionLevels = ($roleDefinitions | ForEach-Object { $_.Name }) -join ","

            # Check if has Full Control
            $hasFullControl = Test-HasFullControl -RoleDefinitions $roleDefinitions

            if ($hasFullControl) {
                Write-Host "    ✓ Preserve Full Control: $principalTitle ($permissionLevels)" -ForegroundColor Green
                $preservedCount++
            }
            else {
                # Backup current permissions
                $backupEntries += [PSCustomObject]@{
                    ListGuid         = $ListGuid
                    ListTitle        = $list.Title
                    PrincipalType    = $principalType
                    PrincipalTitle   = $principalTitle
                    PrincipalId      = $principalId
                    PermissionLevels = $permissionLevels
                }

                if ($DryRun) {
                    Write-Host "    [DRY-RUN] Would set to Read: $principalTitle (Current: $permissionLevels)" -ForegroundColor Magenta
                    $lockedCount++
                }
                else {
                    # Remove existing permission levels
                    foreach ($role in $roleDefinitions) {
                        Set-PnPListPermission -Identity $ListGuid -User $principalTitle -RemoveRole $role.Name -ErrorAction Stop
                    }

                    # Add Read permission
                    Set-PnPListPermission -Identity $ListGuid -User $principalTitle -AddRole "Read" -ErrorAction Stop
                    Write-Host "    ✓ Set to Read: $principalTitle (Was: $permissionLevels)" -ForegroundColor Green
                    $lockedCount++
                }
            }
        }
        catch {
            Write-Host "    ✗ Failed to process: $principalTitle - $($_.Exception.Message)" -ForegroundColor Red
            $failCount++
        }
    }

    Write-Host "`n  Summary for '$($list.Title)':" -ForegroundColor Cyan
    Write-Host "    Locked to Read: $lockedCount" -ForegroundColor Yellow
    Write-Host "    Preserved: $preservedCount" -ForegroundColor Green
    Write-Host "    Failed: $failCount" -ForegroundColor $(if ($failCount -gt 0) { "Red" } else { "DarkGray" })

    return $backupEntries
}

# Main Lock mode function
function Invoke-LockMode {
    param (
        [switch]$DryRun
    )

    Write-Host "`n--- Starting Lock Mode ---" -ForegroundColor Cyan
    Write-Host "Target Site: $Global:SiteUrl" -ForegroundColor Yellow
    Write-Host "Lists to process: $($Global:TargetListGuids.Count)" -ForegroundColor Yellow

    $allBackupEntries = @()
    $totalLocked = 0
    $totalPreserved = 0

    foreach ($listGuid in $Global:TargetListGuids) {
        Write-Host "`n→ Processing list: $listGuid" -ForegroundColor Cyan

        $backupEntries = Invoke-LockList -ListGuid $listGuid -DryRun:$DryRun
        $allBackupEntries += $backupEntries
    }

    # Export backup CSV
    if ($allBackupEntries.Count -gt 0) {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $csvPath = Join-Path $Global:VaapFolder "VAAP_PermissionsBackup_$timestamp.csv"

        try {
            $allBackupEntries | Export-Csv -Path $csvPath -NoTypeInformation
            Write-Host "`n✓ Backup exported to: $csvPath" -ForegroundColor Green
            Write-Host "  Total entries backed up: $($allBackupEntries.Count)" -ForegroundColor DarkGray
        }
        catch {
            Write-Host "`n✗ Failed to export backup CSV: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    else {
        Write-Host "`n⚠ No permissions were modified (nothing to backup)" -ForegroundColor Yellow
    }

    # Final summary
    Write-Host "`n╔════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║              LOCK MODE COMPLETE                         ║" -ForegroundColor Green
    Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Green

    if ($DryRun) {
        Write-Host "`n⚠️  This was a DRY-RUN. No changes were made." -ForegroundColor Yellow
        Write-Host "Run without -DryRun to apply changes." -ForegroundColor Yellow
    }
}

# Restore permissions from CSV
function Invoke-RestoreMode {
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

        # Group by list
        $listGroups = $backup | Group-Object -Property ListGuid

        Write-Host "`n=== Lists in Backup ===" -ForegroundColor Cyan
        foreach ($listGroup in $listGroups) {
            $listTitle = ($listGroup.Group | Select-Object -First 1).ListTitle
            Write-Host "  • $listTitle - $($listGroup.Count) permission(s)" -ForegroundColor DarkGray
        }

        Write-Host "`n--- Starting Restoration ---`n" -ForegroundColor Cyan

        $totalSuccess = 0
        $totalFailed = 0

        foreach ($listGroup in $listGroups) {
            $listGuid = $listGroup.Name
            $listTitle = ($listGroup.Group | Select-Object -First 1).ListTitle

            Write-Host "→ Processing list: $listTitle (GUID: $listGuid)" -ForegroundColor Cyan

            # Get the list
            $list = Get-TargetList -ListGuid $listGuid
            if (-not $list) {
                Write-Host "  ✗ Skipping list due to retrieval failure" -ForegroundColor Red
                $totalFailed += $listGroup.Count
                continue
            }

            # Restore each permission
            foreach ($item in $listGroup.Group) {
                try {
                    $principalTitle = $item.PrincipalTitle
                    $permissionLevels = $item.PermissionLevels -split ","

                    if ($DryRun) {
                        Write-Host "    [DRY-RUN] Would restore: $principalTitle -> $($item.PermissionLevels)" -ForegroundColor Magenta
                        $totalSuccess++
                    }
                    else {
                        # Get current permissions for this principal
                        $currentRoles = @()
                        try {
                            $roleAssignment = $list.RoleAssignments | Where-Object {
                                $member = Get-PnPProperty -ClientObject $_ -Property Member
                                $member.Title -eq $principalTitle
                            } | Select-Object -First 1

                            if ($roleAssignment) {
                                $roleDefinitions = Get-PnPProperty -ClientObject $roleAssignment -Property RoleDefinitionBindings
                                $currentRoles = $roleDefinitions | ForEach-Object { $_.Name }
                            }
                        }
                        catch {
                            # Principal might not have any roles currently
                        }

                        # Remove current permissions
                        foreach ($role in $currentRoles) {
                            Set-PnPListPermission -Identity $listGuid -User $principalTitle -RemoveRole $role -ErrorAction Stop
                        }

                        # Add back original permissions
                        foreach ($permission in $permissionLevels) {
                            if ($permission.Trim() -ne "") {
                                Set-PnPListPermission -Identity $listGuid -User $principalTitle -AddRole $permission.Trim() -ErrorAction Stop
                            }
                        }

                        Write-Host "    ✓ Restored: $principalTitle -> $($item.PermissionLevels)" -ForegroundColor Green
                        $totalSuccess++
                    }
                }
                catch {
                    Write-Host "    ✗ Failed to restore: $($item.PrincipalTitle) - $($_.Exception.Message)" -ForegroundColor Red
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

# ============================================================================
# MAIN EXECUTION
# ============================================================================

Write-Host "`n╔════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     VAAP LIST PERMISSIONS MAINTENANCE SCRIPT            ║" -ForegroundColor Cyan
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

# Connect to site
Write-Host "`nConnecting to: $Global:SiteUrl" -ForegroundColor Cyan
$connected = Connect-IndicatedSite -SiteUrl $Global:SiteUrl
if (-not $connected) {
    Write-Host "`n✗ Failed to connect to site. Exiting." -ForegroundColor Red
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
        $confirm = Read-Host "`n⚠️  WARNING: This will restore list permissions from the backup. Proceed? (Y/N)"
        if ($confirm.ToLower() -ne "y") {
            Write-Host "`n✗ Restoration cancelled by user." -ForegroundColor Red
            exit 0
        }
    }

    # Restore permissions
    Invoke-RestoreMode -CsvPath $csvPath -DryRun:$DryRun

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

    # Confirm lock
    if (-not $DryRun) {
        $confirm = Read-Host "`n⚠️  WARNING: This will set non-Full Control permissions to Read-Only on $($Global:TargetListGuids.Count) list(s). Proceed? (Y/N)"
        if ($confirm.ToLower() -ne "y") {
            Write-Host "`n✗ Lock operation cancelled by user." -ForegroundColor Red
            exit 0
        }
    }

    # Lock lists
    Invoke-LockMode -DryRun:$DryRun
}

Write-Host ""
