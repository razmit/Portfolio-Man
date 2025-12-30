Import-Module -Name ImportExcel
$excelPath = "C:\Users\E095713\Downloads\Whitelist-Teamdocs.xlsx"
$allSites = Import-Excel -Path $excelPath

# The domain to whitelist
$domainToAdd = "resecon.com"

$sites = $allSites

Write-Host "Processing $($sites.Count) sites from Excel..." -ForegroundColor Cyan

Connect-PnPOnline -Url "https://rsmcanadacom-admin.sharepoint.com" -clientId CLIENT_ID -interactive

foreach ($site in $sites) {
    $rawUrl = $site.'TDLink'
    
    # Clean the URL - extract only up to /td_XXXXXXX
    if ($rawUrl -match "(https://[^/]+/teams/td_\d+)") {
        $siteUrl = $matches[1]
        # Write-Host "`nCleaned URL: $rawUrl" -ForegroundColor Gray
        # Write-Host "         to: $siteUrl" -ForegroundColor Cyan
    }
    else {
        Write-Host "`n✗ Could not parse URL pattern from: $rawUrl" -ForegroundColor Red
        continue
    }
    
    try {
        Write-Host "Processing: $siteUrl" -ForegroundColor Cyan
        
        # Get current site settings
        $currentSite = Get-PnPTenantSite -Url $siteUrl
        $currentDomains = $currentSite.SharingAllowedDomainList
        $currentSharingCapability = $currentSite.SharingCapability
        
        Write-Host "Current sharing capability: $currentSharingCapability" -ForegroundColor Gray
        Write-Host "Current allowed domains: $currentDomains" -ForegroundColor Gray
        
        # Build the updated domain list 
        if ($currentDomains -and $currentDomains.Trim() -ne "") {
            # Check if domain already exists
            if ($currentDomains -notlike "*$domainToAdd*") {
                # Add comma and space, then the new domain
                $updatedDomains = "$currentDomains, $domainToAdd"
            }
            else {
                $updatedDomains = $currentDomains
                Write-Host "Domain already exists, skipping..." -ForegroundColor Yellow
            }
        }
        else {
            $updatedDomains = $domainToAdd
        }
        
        Write-Host "Updated domains will be: $updatedDomains" -ForegroundColor Gray
        
        # Set sharing capability to "ExternalUserSharingOnly"
        # And set domain restriction to AllowList
        Set-PnPTenantSite -Url $siteUrl `
            -SharingCapability ExternalUserSharingOnly `
            -SharingAllowedDomainList $updatedDomains `
            -SharingDomainRestrictionMode AllowList
        
        Write-Host "✓ Added $domainToAdd to $siteUrl and enabled external sharing" -ForegroundColor Green
    }
    catch {
        Write-Host "✗ Failed for $siteUrl : $($_.Exception.Message)" -ForegroundColor Red
    }
}