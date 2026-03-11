<#
.SYNOPSIS
    Finds all SharePoint sites and subsites where a specified Entra ID group is a member
    of the site's Associated Owners group.

.DESCRIPTION
    Connects to SharePoint Online via the Admin Center, enumerates every site collection
    and all of their subsites (recursively), and checks whether the target Entra ID group
    appears as a member of each site's Associated Owners group.

    Results are written to the console in real time and exported to a CSV file.

.PARAMETER AdminUrl
    Your SharePoint Admin Center URL.
    Example: "https://companynet-admin.sharepoint.com"

.PARAMETER EntraGroupName
    Display name of the Entra ID (Azure AD) group to search for.
    Default: "Talent Knowledge Management"

.PARAMETER OutputCsvPath
    Path for the output CSV file.
    Default: .\EntraGroup_OwnerSites_<timestamp>.csv

.PARAMETER ClientId
    Azure AD app registration Client ID used for interactive PnP authentication.
    Default: the shared app registration already used in this repo.

.EXAMPLE
    .\Find-EntraGroupOwnerSites.ps1 -AdminUrl "https://companynet-admin.sharepoint.com"

.EXAMPLE
    .\Find-EntraGroupOwnerSites.ps1 -AdminUrl "https://companynet-admin.sharepoint.com" `
        -EntraGroupName "Talent Knowledge Management" `
        -OutputCsvPath "C:\Reports\TKM_OwnerSites.csv"

.NOTES
    Requires: PnP.PowerShell module (Install-Module PnP.PowerShell -Scope CurrentUser)
    Author:   Claude
    Date:     2026-03-09
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$AdminUrl,

    [Parameter(Mandatory = $false)]
    [string]$EntraGroupName = "Talent Knowledge Management",

    [Parameter(Mandatory = $false)]
    [string]$OutputCsvPath = ".\EntraGroup_OwnerSites_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv",

    [Parameter(Mandatory = $false)]
    [string]$ClientId = "CLIENT_ID"
)

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------

if (-not (Get-Module -ListAvailable -Name PnP.PowerShell)) {
    Write-Error "PnP.PowerShell is not installed. Run: Install-Module PnP.PowerShell -Scope CurrentUser"
    exit 1
}

Import-Module PnP.PowerShell -ErrorAction Stop

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Returns $true if $EntraGroupName is a member of the web's Associated Owners group.
# Expects an active PnP connection to the web's site collection.
function Test-EntraGroupInOwnersGroup {
    param(
        [Microsoft.SharePoint.Client.Web]$Web,
        [string]$GroupName
    )

    # Make sure AssociatedOwnerGroup is loaded
    try {
        Get-PnPProperty -ClientObject $Web -Property AssociatedOwnerGroup -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Verbose "  Could not load AssociatedOwnerGroup for $($Web.Url): $($_.Exception.Message)"
        return $false
    }

    if ($null -eq $Web.AssociatedOwnerGroup -or $Web.AssociatedOwnerGroup.ServerObjectIsNull) {
        return $false
    }

    try {
        $members = Get-PnPGroupMember -Group $Web.AssociatedOwnerGroup -ErrorAction Stop
    }
    catch {
        Write-Verbose "  Could not enumerate Owners group members for $($Web.Url): $($_.Exception.Message)"
        return $false
    }

    # Match by Title (display name) — this is the Entra group's display name as SharePoint sees it.
    # Also do a case-insensitive substring check on LoginName as a safety net, since some tenants
    # surface the group slightly differently.
    foreach ($member in $members) {
        if ($member.Title -ieq $GroupName) {
            return $true
        }
        # LoginName for Entra security groups:  c:0t.c|tenant|<objectId>
        # LoginName for M365 groups:            c:0o.c|federateddirectoryclaimprovider|<objectId>
        # Both have the display name embedded nowhere in LoginName, so Title is the right field.
        # Belt-and-suspenders: also catch if the group name appears in the login name (rare edge case).
        if ($member.LoginName -ilike "*$GroupName*") {
            return $true
        }
    }

    return $false
}

# ---------------------------------------------------------------------------
# Script-level tracking
# ---------------------------------------------------------------------------

$script:Results     = [System.Collections.Generic.List[PSCustomObject]]::new()
$script:Errors      = [System.Collections.Generic.List[PSCustomObject]]::new()
$script:SitesTotal  = 0
$script:SitesHits   = 0

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " Entra Group Owner-Site Finder" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " Target group : $EntraGroupName" -ForegroundColor White
Write-Host " Admin URL    : $AdminUrl" -ForegroundColor White
Write-Host " Output CSV   : $OutputCsvPath" -ForegroundColor White
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

# Step 1 — Connect to Admin Center and pull every site collection
Write-Host "[1/3] Connecting to SharePoint Admin Center..." -ForegroundColor Yellow
try {
    Connect-PnPOnline -Url $AdminUrl -ClientId $ClientId -Interactive -ErrorAction Stop
    Write-Host "      Connected." -ForegroundColor Green
}
catch {
    Write-Error "Failed to connect to Admin Center: $($_.Exception.Message)"
    exit 1
}

Write-Host "[2/3] Enumerating all site collections (excluding personal/OneDrive sites)..." -ForegroundColor Yellow
try {
    # Filter=IsHubSite doesn't help us; grab everything and exclude OneDrive (/personal/)
    $allSites = Get-PnPTenantSite -ErrorAction Stop |
                Where-Object { $_.Url -notlike "*/personal/SITE_NAME" }
    Write-Host "      Found $($allSites.Count) site collections." -ForegroundColor Green
}
catch {
    Write-Error "Failed to enumerate site collections: $($_.Exception.Message)"
    Disconnect-PnPOnline -ErrorAction SilentlyContinue
    exit 1
}

Disconnect-PnPOnline -ErrorAction SilentlyContinue

# Step 3 — Walk each site collection
Write-Host "[3/3] Scanning sites and subsites for group membership..." -ForegroundColor Yellow
Write-Host ""

$siteIndex = 0
foreach ($site in $allSites) {
    $siteIndex++
    $siteUrl  = $site.Url
    $siteName = if ($site.Title) { $site.Title } else { $siteUrl }

    Write-Progress -Activity "Scanning site collections" `
                   -Status "[$siteIndex/$($allSites.Count)] $siteName" `
                   -PercentComplete (($siteIndex / $allSites.Count) * 100)

    Write-Host "[$siteIndex/$($allSites.Count)] $siteName" -ForegroundColor Cyan
    Write-Host "  $siteUrl" -ForegroundColor DarkGray

    try {
        Connect-PnPOnline -Url $siteUrl -ClientId $ClientId -Interactive -ErrorAction Stop

        # Collect the root web plus every subsite in one call
        $webs = Get-PnPSubWeb -Recurse -IncludeRootWeb -ErrorAction Stop

        foreach ($web in $webs) {

            # Load the properties we need
            try {
                Get-PnPProperty -ClientObject $web -Property Title, Url, AssociatedOwnerGroup -ErrorAction SilentlyContinue | Out-Null
            }
            catch { <# non-fatal; proceed with whatever loaded #> }

            $isRoot    = ($web.Url.TrimEnd('/') -ieq $siteUrl.TrimEnd('/'))
            $webLabel  = if ($isRoot) { "(root)" } else { $web.Url.Replace($siteUrl, "").TrimStart('/') }

            $found = Test-EntraGroupInOwnersGroup -Web $web -GroupName $EntraGroupName

            if ($found) {
                $script:SitesHits++
                Write-Host "  [MATCH] $($web.Title)  ($webLabel)" -ForegroundColor Green

                $script:Results.Add([PSCustomObject]@{
                    SiteCollectionName = $siteName
                    SiteCollectionUrl  = $siteUrl
                    WebTitle           = $web.Title
                    WebUrl             = $web.Url
                    IsRootSite         = $isRoot
                    EntraGroupFound    = $EntraGroupName
                    OwnersGroupName    = if ($web.AssociatedOwnerGroup -and -not $web.AssociatedOwnerGroup.ServerObjectIsNull) {
                                             $web.AssociatedOwnerGroup.Title
                                         } else { "N/A" }
                })
            }
            else {
                Write-Verbose "  [ -- ]  $($web.Title)  ($webLabel)"
            }

            $script:SitesTotal++
        }

        Disconnect-PnPOnline -ErrorAction SilentlyContinue
    }
    catch {
        Write-Warning "  Error processing $siteUrl : $($_.Exception.Message)"
        $script:Errors.Add([PSCustomObject]@{
            SiteUrl = $siteUrl
            Error   = $_.Exception.Message
        })
        Disconnect-PnPOnline -ErrorAction SilentlyContinue
    }
}

Write-Progress -Activity "Scanning site collections" -Completed

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " RESULTS" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

if ($script:Results.Count -gt 0) {
    Write-Host ""
    Write-Host "Sites / subsites where '$EntraGroupName' is in the Owners group:" -ForegroundColor Green
    Write-Host ""

    $script:Results | Format-Table -AutoSize -Property WebTitle, WebUrl, IsRootSite, OwnersGroupName

    $script:Results | Export-Csv -Path $OutputCsvPath -NoTypeInformation -Encoding UTF8
    Write-Host "CSV exported to: $OutputCsvPath" -ForegroundColor Green
}
else {
    Write-Host "No sites found where '$EntraGroupName' is in the Owners group." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " SUMMARY" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  Site collections scanned : $($allSites.Count)" -ForegroundColor White
Write-Host "  Total webs checked       : $script:SitesTotal" -ForegroundColor White
Write-Host "  Matching webs found      : $script:SitesHits" -ForegroundColor $(if ($script:SitesHits -gt 0) { "Green" } else { "Yellow" })
Write-Host "  Errors encountered       : $($script:Errors.Count)" -ForegroundColor $(if ($script:Errors.Count -gt 0) { "Red" } else { "Green" })

if ($script:Errors.Count -gt 0) {
    Write-Host ""
    Write-Host "Errors:" -ForegroundColor Red
    foreach ($err in $script:Errors) {
        Write-Host "  - $($err.SiteUrl)" -ForegroundColor Red
        Write-Host "    $($err.Error)" -ForegroundColor DarkRed
    }
}

Write-Host ""
Write-Host "Done." -ForegroundColor Cyan
Write-Host ""
