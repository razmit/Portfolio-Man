# Export-SitePermissions.ps1
#
# Purpose: Quick audit of site permissions - Extract group names, members, and permissions
# NO migration - just data collection for manual setup
#
# Usage:
#   .\Export-SitePermissions.ps1 -SiteUrl "https://tenant.sharepoint.com/sites/YourSite"
#
# Output:
#   - CSV file with all group details
#   - Console summary for quick reference
#
# Perfect for: Getting info to manually recreate groups in destination sites

param(
    [Parameter(Mandatory=$true)]
    [string]$SiteUrl
)

# PnP OAuth Client ID
$ClientId = "CLIENT_ID"

Write-Host "`n╔════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║         QUICK PERMISSIONS AUDIT & EXPORT               ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

Write-Host "`nTarget Site: $SiteUrl" -ForegroundColor Cyan
Write-Host "Mode: Extract Only (No Migration)`n" -ForegroundColor Yellow

# ============================================================================
# CONNECT
# ============================================================================

Write-Host "Connecting to site..." -ForegroundColor Yellow

try {
    Connect-PnPOnline -Url $SiteUrl -ClientId $ClientId -Interactive
    Write-Host "✓ Connection successful!" -ForegroundColor Green
}
catch {
    Write-Host "✗ Connection failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# ============================================================================
# GET ALL GROUPS
# ============================================================================

Write-Host "`nRetrieving groups..." -ForegroundColor Yellow

$startTime = Get-Date
$allGroups = Get-PnPGroup -ErrorAction Stop
$endTime = Get-Date
$retrievalTime = [math]::Round(($endTime - $startTime).TotalSeconds, 1)

Write-Host "✓ Retrieved $($allGroups.Count) groups in $retrievalTime seconds" -ForegroundColor Green

# Filter out system groups
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

$excludedCount = $allGroups.Count - $filteredGroups.Count
Write-Host "✓ Filtered to $($filteredGroups.Count) groups ($excludedCount system groups excluded)" -ForegroundColor Green

if ($filteredGroups.Count -eq 0) {
    Write-Host "`n⚠ No groups found to export." -ForegroundColor Yellow
    exit 0
}

# ============================================================================
# GET DETAILS FOR EACH GROUP
# ============================================================================

Write-Host "`nGathering group details..." -ForegroundColor Yellow

$groupData = @()
$counter = 0
$totalGroups = $filteredGroups.Count

foreach ($group in $filteredGroups) {
    $counter++

    # Show progress every 10 groups
    if ($counter % 10 -eq 0 -or $counter -eq 1) {
        Write-Host "[$counter/$totalGroups] Processing: $($group.Title)" -ForegroundColor Cyan
    }

    try {
        # Get members
        $members = Get-PnPGroupMember -Identity $group.Title -ErrorAction SilentlyContinue
        $memberNames = if ($members) {
            ($members | ForEach-Object { $_.Title }) -join "; "
        } else {
            "No members"
        }
        $memberCount = if ($members) { $members.Count } else { 0 }

        # Get permissions
        $permissions = Get-PnPGroupPermissions -Identity $group.Title -ErrorAction SilentlyContinue
        $permissionLevels = if ($permissions) {
            ($permissions | ForEach-Object { $_.Name }) -join "; "
        } else {
            "No permissions"
        }

        # Get owner
        $ownerTitle = if ($group.OwnerTitle) { $group.OwnerTitle } else { "Not specified" }

        # Determine if associated group
        $web = Get-PnPWeb -Includes AssociatedOwnerGroup,AssociatedMemberGroup,AssociatedVisitorGroup -ErrorAction SilentlyContinue
        $isAssociated = "No"
        $associatedType = ""

        if ($web.AssociatedOwnerGroup.Title -eq $group.Title) {
            $isAssociated = "Yes"
            $associatedType = "Owner"
        }
        elseif ($web.AssociatedMemberGroup.Title -eq $group.Title) {
            $isAssociated = "Yes"
            $associatedType = "Member"
        }
        elseif ($web.AssociatedVisitorGroup.Title -eq $group.Title) {
            $isAssociated = "Yes"
            $associatedType = "Visitor"
        }

        # Add to export data
        $groupData += [PSCustomObject]@{
            GroupName = $group.Title
            MemberCount = $memberCount
            Members = $memberNames
            PermissionLevels = $permissionLevels
            Owner = $ownerTitle
            Description = if ($group.Description) { $group.Description } else { "" }
            IsAssociatedGroup = $isAssociated
            AssociatedType = $associatedType
            GroupID = $group.Id
        }
    }
    catch {
        Write-Host "  ⚠ Error processing $($group.Title): $($_.Exception.Message)" -ForegroundColor DarkYellow

        # Add minimal data even on error
        $groupData += [PSCustomObject]@{
            GroupName = $group.Title
            MemberCount = "Error"
            Members = "Error retrieving data"
            PermissionLevels = "Error"
            Owner = "Error"
            Description = "Error"
            IsAssociatedGroup = "Unknown"
            AssociatedType = ""
            GroupID = $group.Id
        }
    }
}

Write-Host "✓ Gathered details for $($groupData.Count) groups" -ForegroundColor Green

# ============================================================================
# EXPORT TO CSV
# ============================================================================

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$siteName = ($SiteUrl -split '/')[-1]
$csvPath = ".\PermissionsAudit_${siteName}_${timestamp}.csv"

try {
    $groupData | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
    Write-Host "`n✓ Exported to: $csvPath" -ForegroundColor Green
}
catch {
    Write-Host "`n✗ Export failed: $($_.Exception.Message)" -ForegroundColor Red
}

# ============================================================================
# CONSOLE SUMMARY
# ============================================================================

Write-Host "`n╔════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                  QUICK REFERENCE                        ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

# Show groups sorted by permission level
$groupsByPermission = $groupData | Group-Object -Property PermissionLevels | Sort-Object Count -Descending

foreach ($permGroup in $groupsByPermission) {
    Write-Host "`n[$($permGroup.Name)]" -ForegroundColor Yellow -BackgroundColor DarkGray

    foreach ($group in $permGroup.Group) {
        $associatedIndicator = if ($group.IsAssociatedGroup -eq "Yes") { " [ASSOCIATED: $($group.AssociatedType)]" } else { "" }
        $memberInfo = if ($group.MemberCount -eq "Error") { "Error" } else { "$($group.MemberCount) members" }

        Write-Host "  • $($group.GroupName)$associatedIndicator" -ForegroundColor Cyan
        Write-Host "    └─ $memberInfo | Owner: $($group.Owner)" -ForegroundColor DarkGray
    }
}

# Summary statistics
$totalMembers = ($groupData | Where-Object { $_.MemberCount -ne "Error" } | ForEach-Object { [int]$_.MemberCount } | Measure-Object -Sum).Sum
$associatedCount = ($groupData | Where-Object { $_.IsAssociatedGroup -eq "Yes" }).Count
$regularCount = $groupData.Count - $associatedCount

Write-Host "`n═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "SUMMARY" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "Total Groups:         $($groupData.Count)" -ForegroundColor White
Write-Host "  - Associated:       $associatedCount" -ForegroundColor Green
Write-Host "  - Regular:          $regularCount" -ForegroundColor Yellow
Write-Host "Total Members:        $totalMembers" -ForegroundColor White
Write-Host "CSV Export:           $csvPath" -ForegroundColor White
Write-Host "═══════════════════════════════════════════════════════`n" -ForegroundColor Cyan

Write-Host "✓ Audit complete! Open the CSV to see all details." -ForegroundColor Green
Write-Host "  You can now use this data to manually recreate groups in destination sites.`n" -ForegroundColor DarkGray
