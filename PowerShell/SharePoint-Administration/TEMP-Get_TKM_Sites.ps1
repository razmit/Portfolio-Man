Connect-PnPOnline -Url "https://companynet-admin.sharepoint.com/" -clientId CLIENT_ID -Interactive

# TEST PARAMETERS - Modify these
$targetGroupName = "Talent Knowledge Management"  # Replace with exact group name
$maxSitesToTest = 5  # Only process first 5 site collections

# Get limited set of site collections for testing
$allSiteCollections = Get-PnPTenantSite | Select-Object Url -First $maxSitesToTest

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "POC TEST RUN" -ForegroundColor Yellow
Write-Host "Target Group: $targetGroupName" -ForegroundColor Yellow
Write-Host "Testing first $maxSitesToTest site collections" -ForegroundColor Yellow
Write-Host "========================================`n" -ForegroundColor Cyan

$results = @()
$currentSite = 0

foreach ($siteCollection in $allSiteCollections) {
    $currentSite++
    Write-Host "[$currentSite/$maxSitesToTest] Processing: $($siteCollection.Url)" -ForegroundColor Cyan
    
    try {
        # Connect to site collection root
        Connect-PnPOnline -Url $siteCollection.Url -Interactive
        
        # Check root site's Owners group
        $ownersGroup = Get-PnPGroup -AssociatedOwnerGroup -ErrorAction SilentlyContinue
        
        if ($ownersGroup) {
            Write-Host "  Owners group: $($ownersGroup.Title)" -ForegroundColor Gray
            $members = Get-PnPGroupMember -Group $ownersGroup
            
            # Display all members for verification
            Write-Host "  Members in Owners group:" -ForegroundColor Gray
            foreach ($member in $members) {
                Write-Host "    - $($member.Title)" -ForegroundColor Gray
            }
            
            # Check if target Entra group is in the Owners group
            if ($members | Where-Object { $_.Title -eq $targetGroupName }) {
                $web = Get-PnPWeb
                $results += [PSCustomObject]@{
                    SiteName        = $web.Title
                    SiteUrl         = $web.Url
                    SiteType        = "Site Collection"
                    OwnersGroupName = $ownersGroup.Title
                }
                Write-Host "  ✓ TARGET GROUP FOUND in root site!" -ForegroundColor Green
            }
            else {
                Write-Host "  ✗ Target group not found in root site" -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "  No associated Owners group found" -ForegroundColor Yellow
        }
        
        # Get subsites (limit to first 3 per site collection for testing)
        $subsites = Get-PnPSubWeb -Recurse
        $subsiteCount = $subsites.Count
        
        Write-Host "  Found $subsiteCount subsites" -ForegroundColor Gray
        
        $testedSubsites = 0
        foreach ($subsite in $subsites) {
            $testedSubsites++
            if ($testedSubsites -gt 3) {
                Write-Host "  (Skipping remaining subsites for POC)" -ForegroundColor Yellow
                break
            }
            
            Write-Host "  [$testedSubsites] Checking subsite: $($subsite.Title)" -ForegroundColor Gray
            
            # Connect to each subsite
            Connect-PnPOnline -Url $subsite.Url -Interactive
            
            $subOwnersGroup = Get-PnPGroup -AssociatedOwnerGroup -ErrorAction SilentlyContinue
            
            if ($subOwnersGroup) {
                Write-Host "    Owners group: $($subOwnersGroup.Title)" -ForegroundColor DarkGray
                $subMembers = Get-PnPGroupMember -Group $subOwnersGroup
                
                if ($subMembers | Where-Object { $_.Title -eq $targetGroupName }) {
                    $results += [PSCustomObject]@{
                        SiteName        = $subsite.Title
                        SiteUrl         = $subsite.Url
                        SiteType        = "Subsite"
                        OwnersGroupName = $subOwnersGroup.Title
                    }
                    Write-Host "    ✓ TARGET GROUP FOUND!" -ForegroundColor Green
                }
                else {
                    Write-Host "    ✗ Target group not found" -ForegroundColor DarkGray
                }
            }
            else {
                Write-Host "    No associated Owners group" -ForegroundColor DarkGray
            }
        }
        
        Write-Host ""  # Blank line between sites
        
    }
    catch {
        Write-Host "  ✗ Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Display results
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "POC TEST RESULTS" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan

if ($results.Count -gt 0) {
    Write-Host "Found $($results.Count) sites with target group:`n" -ForegroundColor Green
    $results | Format-Table -AutoSize
    
    # Save to CSV
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $outputPath = "C:\Temp\POC_Sites_With_TargetGroup_$timestamp.csv"
    $results | Export-Csv -Path $outputPath -NoTypeInformation
    Write-Host "`nResults saved to: $outputPath" -ForegroundColor Green
}
else {
    Write-Host "No sites found with target group in this sample." -ForegroundColor Yellow
    Write-Host "This could mean:" -ForegroundColor Yellow
    Write-Host "  1. The group name is incorrect (check spelling/case)" -ForegroundColor Yellow
    Write-Host "  2. The group doesn't exist in the first $maxSitesToTest site collections tested" -ForegroundColor Yellow
    Write-Host "  3. Try testing more sites or a different subset" -ForegroundColor Yellow
}

Write-Host "`n========================================" -ForegroundColor Cyan