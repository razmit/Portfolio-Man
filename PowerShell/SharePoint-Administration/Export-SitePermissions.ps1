# Export-SitePermissions.ps1
#
# Purpose: Audit and export SharePoint site permissions - groups, members, and permission levels.
#          Supports optional subsite traversal and group filtering by name and/or permission level.
#
# Usage:
#   .\Export-SitePermissions.ps1 -SiteUrl "https://tenant.sharepoint.com/sites/SITE_NAME"
#   .\Export-SitePermissions.ps1 -SiteUrl "..." -IncludeSubsites
#   .\Export-SitePermissions.ps1 -SiteUrl "..." -GroupNameFilter "Project", "Team"
#   .\Export-SitePermissions.ps1 -SiteUrl "..." -PermissionLevelFilter "Full Control", "Edit"
#   .\Export-SitePermissions.ps1 -SiteUrl "..." -IncludeSubsites -GroupNameFilter "Project" -PermissionLevelFilter "Contribute"
#
# Parameters:
#   -SiteUrl               (Required) URL of the root SharePoint site to audit.
#   -IncludeSubsites       (Switch)   Also process all subsites found under the given site.
#   -GroupNameFilter       (Optional) Whitelist of name fragments. Only groups whose Title contains at least one of the provided strings are exported (case-insensitive).
#   -PermissionLevelFilter (Optional) Whitelist of permission level names. Only groups that have at least one matching permission level are exported (case-insensitive).
#
# Output:
#   - CSV file with all matching group details (one row per group, SiteUrl column included)
#   - Console summary grouped by permission level

param(
    [Parameter(Mandatory=$true)]
    [string]$SiteUrl,

    [switch]$IncludeSubsites,

    [string[]]$GroupNameFilter,

    [string[]]$PermissionLevelFilter
)

# PnP OAuth Client ID
$ClientId = "CLIENT_ID"

# ============================================================================
# HEADER
# ============================================================================

Write-Host "`n╔════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║         QUICK PERMISSIONS AUDIT & EXPORT               ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

Write-Host "`nTarget Site : $SiteUrl" -ForegroundColor Cyan
Write-Host "Subsites    : $(if ($IncludeSubsites) { 'Included' } else { 'Root site only' })" -ForegroundColor Cyan

if ($GroupNameFilter -and $GroupNameFilter.Count -gt 0) {
    Write-Host "Name filter : $($GroupNameFilter -join ' | ')" -ForegroundColor DarkYellow
}
if ($PermissionLevelFilter -and $PermissionLevelFilter.Count -gt 0) {
    Write-Host "Perm filter : $($PermissionLevelFilter -join ' | ')" -ForegroundColor DarkYellow
}

Write-Host "Mode        : Extract Only (No Migration)`n" -ForegroundColor Yellow

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Test-GroupNameMatch {
    param([string]$GroupTitle, [string[]]$Filters)
    if (-not $Filters -or $Filters.Count -eq 0) { return $true }
    foreach ($f in $Filters) {
        if ($GroupTitle -ilike "*$f*") { return $true }
    }
    return $false
}

function Test-PermissionMatch {
    param([string]$PermissionLevels, [string[]]$Filters)
    if (-not $Filters -or $Filters.Count -eq 0) { return $true }
    foreach ($f in $Filters) {
        if ($PermissionLevels -ilike "*$f*") { return $true }
    }
    return $false
}

# Processes one site (already connected). Returns an array of PSCustomObjects.
function Get-SiteGroupData {
    param([string]$Url)

    Write-Host "`n  Retrieving groups from: $Url" -ForegroundColor Yellow

    # Fetch associated-group metadata once for the entire site
    $web = Get-PnPWeb -Includes AssociatedOwnerGroup, AssociatedMemberGroup, AssociatedVisitorGroup `
                      -ErrorAction SilentlyContinue

    $startTime = Get-Date
    $allGroups  = Get-PnPGroup -ErrorAction Stop
    $elapsed    = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)
    Write-Host "  ✓ Retrieved $($allGroups.Count) groups in $elapsed seconds" -ForegroundColor Green

    # Remove well-known system/noise groups
    $candidates = $allGroups | Where-Object {
        $t = $_.Title
        $t -notlike "Limited Access*"       -and
        $t -notlike "SharingLinks*"         -and
        $t -notlike "STE_*"                 -and
        $t -notlike "Everyone*"             -and
        $t -notlike "Company Administrator*"-and
        $t -notlike "Excel Services Viewers*" -and
        $t -notlike "Viewers*"              -and
        $t -notmatch "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
    }

    $systemExcluded = $allGroups.Count - $candidates.Count
    Write-Host "  ✓ After system-group exclusion: $($candidates.Count) groups ($systemExcluded excluded)" `
               -ForegroundColor Green

    # Apply name filter (cheap — no extra API calls)
    if ($GroupNameFilter -and $GroupNameFilter.Count -gt 0) {
        $before     = $candidates.Count
        $candidates = $candidates | Where-Object { Test-GroupNameMatch -GroupTitle $_.Title -Filters $GroupNameFilter }
        Write-Host "  ✓ After name filter: $($candidates.Count) groups ($($before - $candidates.Count) excluded)" `
                   -ForegroundColor DarkYellow
    }

    if ($candidates.Count -eq 0) {
        Write-Host "  ⚠ No groups to export for this site." -ForegroundColor Yellow
        return @()
    }

    # Gather details
    Write-Host "`n  Gathering group details..." -ForegroundColor Yellow

    $siteData   = @()
    $counter    = 0
    $total      = $candidates.Count
    $permSkipped = 0

    foreach ($group in $candidates) {
        $counter++

        if ($counter % 10 -eq 0 -or $counter -eq 1) {
            Write-Host "  [$counter/$total] $($group.Title)" -ForegroundColor Cyan
        }

        try {
            # --- Permission levels first (enables early-exit before member fetch) ---
            $permissions     = Get-PnPGroupPermissions -Identity $group.Title -ErrorAction SilentlyContinue
            $permissionLevels = if ($permissions) {
                ($permissions | ForEach-Object { $_.Name }) -join "; "
            } else {
                "No permissions"
            }

            # Apply permission filter before the more expensive member call
            if ($PermissionLevelFilter -and $PermissionLevelFilter.Count -gt 0) {
                if (-not (Test-PermissionMatch -PermissionLevels $permissionLevels -Filters $PermissionLevelFilter)) {
                    $permSkipped++
                    continue
                }
            }

            # --- Members (only fetched when the group passed all filters) ---
            $members      = Get-PnPGroupMember -Identity $group.Title -ErrorAction SilentlyContinue
            $memberNames  = if ($members) { ($members | ForEach-Object { $_.Title }) -join "; " } else { "No members" }
            $memberCount  = if ($members) { $members.Count } else { 0 }

            # Associated-group classification
            $isAssociated  = "No"
            $associatedType = ""
            if ($web.AssociatedOwnerGroup.Title   -eq $group.Title) { $isAssociated = "Yes"; $associatedType = "Owner"   }
            elseif ($web.AssociatedMemberGroup.Title  -eq $group.Title) { $isAssociated = "Yes"; $associatedType = "Member"  }
            elseif ($web.AssociatedVisitorGroup.Title -eq $group.Title) { $isAssociated = "Yes"; $associatedType = "Visitor" }

            $siteData += [PSCustomObject]@{
                SiteUrl          = $Url
                GroupName        = $group.Title
                MemberCount      = $memberCount
                Members          = $memberNames
                PermissionLevels = $permissionLevels
                Owner            = if ($group.OwnerTitle) { $group.OwnerTitle } else { "Not specified" }
                Description      = if ($group.Description) { $group.Description } else { "" }
                IsAssociatedGroup = $isAssociated
                AssociatedType   = $associatedType
                GroupID          = $group.Id
            }
        }
        catch {
            Write-Host "  ⚠ Error processing $($group.Title): $($_.Exception.Message)" -ForegroundColor DarkYellow

            $siteData += [PSCustomObject]@{
                SiteUrl          = $Url
                GroupName        = $group.Title
                MemberCount      = "Error"
                Members          = "Error retrieving data"
                PermissionLevels = "Error"
                Owner            = "Error"
                Description      = "Error"
                IsAssociatedGroup = "Unknown"
                AssociatedType   = ""
                GroupID          = $group.Id
            }
        }
    }

    if ($permSkipped -gt 0) {
        Write-Host "  ✓ After permission filter: $($siteData.Count) groups ($permSkipped excluded)" `
                   -ForegroundColor DarkYellow
    }

    return $siteData
}

# ============================================================================
# CONNECT TO ROOT SITE
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
# DISCOVER SITES TO PROCESS
# ============================================================================

$sitesToProcess = [System.Collections.Generic.List[string]]::new()
$sitesToProcess.Add($SiteUrl)

if ($IncludeSubsites) {
    Write-Host "`nDiscovering subsites..." -ForegroundColor Yellow
    try {
        $subsites = Get-PnPSubWebs -Recurse -ErrorAction SilentlyContinue
        if ($subsites -and $subsites.Count -gt 0) {
            foreach ($sub in $subsites) { $sitesToProcess.Add($sub.Url) }
            Write-Host "✓ Found $($subsites.Count) subsite(s) — will process $($sitesToProcess.Count) site(s) total" `
                       -ForegroundColor Green
        } else {
            Write-Host "  No subsites found under $SiteUrl." -ForegroundColor DarkGray
        }
    }
    catch {
        Write-Host "⚠ Could not retrieve subsites: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }
}

# ============================================================================
# PROCESS EACH SITE
# ============================================================================

$allGroupData = @()

foreach ($site in $sitesToProcess) {
    # Reconnect for each site so PnP context is correct.
    # The OAuth token is cached after the first interactive login — no repeated prompts.
    if ($site -ne $SiteUrl) {
        try {
            Connect-PnPOnline -Url $site -ClientId $ClientId -Interactive
        }
        catch {
            Write-Host "`n✗ Could not connect to $site — skipping. ($($_.Exception.Message))" -ForegroundColor Red
            continue
        }
    }

    $allGroupData += Get-SiteGroupData -Url $site
}

# ============================================================================
# EXPORT TO CSV
# ============================================================================

if ($allGroupData.Count -eq 0) {
    Write-Host "`n⚠ No groups matched the specified filters. Nothing to export." -ForegroundColor Yellow
    exit 0
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$siteName  = ($SiteUrl -split '/')[-1]
$scope     = if ($IncludeSubsites) { "WithSubsites" } else { "RootOnly" }
$csvPath   = ".\PermissionsAudit_${siteName}_${scope}_${timestamp}.csv"

try {
    $allGroupData | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
    Write-Host "`n✓ Exported $($allGroupData.Count) group(s) to: $csvPath" -ForegroundColor Green
}
catch {
    Write-Host "`n✗ Export failed: $($_.Exception.Message)" -ForegroundColor Red
}

# ============================================================================
# CONSOLE SUMMARY
# ============================================================================

Write-Host "`n╔════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                  QUICK REFERENCE                       ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

$groupsByPermission = $allGroupData | Group-Object -Property PermissionLevels | Sort-Object Count -Descending

foreach ($permGroup in $groupsByPermission) {
    Write-Host "`n[$($permGroup.Name)]" -ForegroundColor Yellow -BackgroundColor DarkGray

    foreach ($group in $permGroup.Group) {
        $assocLabel  = if ($group.IsAssociatedGroup -eq "Yes") { " [ASSOCIATED: $($group.AssociatedType)]" } else { "" }
        $memberInfo  = if ($group.MemberCount -eq "Error") { "Error" } else { "$($group.MemberCount) members" }
        $siteLabel   = if ($sitesToProcess.Count -gt 1) { "  Site: $($group.SiteUrl)" } else { "" }

        Write-Host "  • $($group.GroupName)$assocLabel" -ForegroundColor Cyan
        if ($siteLabel) { Write-Host "    $siteLabel" -ForegroundColor DarkGray }
        Write-Host "    └─ $memberInfo | Owner: $($group.Owner)" -ForegroundColor DarkGray
    }
}

$totalMembers    = ($allGroupData | Where-Object { $_.MemberCount -ne "Error" } |
                    ForEach-Object { [int]$_.MemberCount } | Measure-Object -Sum).Sum
$associatedCount = ($allGroupData | Where-Object { $_.IsAssociatedGroup -eq "Yes" }).Count
$regularCount    = $allGroupData.Count - $associatedCount
$sitesProcessed  = ($allGroupData | Select-Object -ExpandProperty SiteUrl -Unique).Count

Write-Host "`n═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "SUMMARY" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "Sites processed:      $sitesProcessed" -ForegroundColor White
Write-Host "Total Groups:         $($allGroupData.Count)" -ForegroundColor White
Write-Host "  - Associated:       $associatedCount" -ForegroundColor Green
Write-Host "  - Regular:          $regularCount" -ForegroundColor Yellow
Write-Host "Total Members:        $totalMembers" -ForegroundColor White
Write-Host "CSV Export:           $csvPath" -ForegroundColor White
Write-Host "═══════════════════════════════════════════════════════`n" -ForegroundColor Cyan

Write-Host "✓ Audit complete! Open the CSV to see all details." -ForegroundColor Green
Write-Host "  You can now use this data to manually recreate groups in destination sites.`n" -ForegroundColor DarkGray
