# Source site
$sourceSite = "https://companynet.sharepoint.com/sites/Resources/IMC/CRMResourceCenter"

# Target site
$targetSite = "https://companynet.sharepoint.com/sites/in_CRMResourceCenter"

# Connect to the source site
connect-pnpOnline -Url $sourceSite -clientId CLIENT_ID -interactive

$list = Get-PnPList -Identity "CRM Resource Library"
$oldView = Get-PnPView -List $list -Identity "ESS"

# Capture view properties
$viewFields = $oldView.ViewFields
$viewQuery = $oldView.ViewQuery
$viewRowLimit = $oldView.RowLimit

Write-Host "ViewFields: $viewFields" -ForegroundColor Gray
Write-Host "ViewQuery: $viewQuery" -ForegroundColor Gray
Write-Host "RowLimit: $viewRowLimit" -ForegroundColor Gray

# Connect to the target site
connect-pnpOnline -Url $targetSite -clientId CLIENT_ID -interactive

# Remove the broken view
Remove-PnPView -List $list -Identity "ESS" -Force
Write-Host "Removed old ESS view from target site." -ForegroundColor Green

# Recreate the view in the target site
Add-PnPView -List $list -Title "ESS" -Fields $viewFields -Query $viewQuery -RowLimit $viewRowLimit -SetAsDefault
Write-Host "Recreated ESS view in target site." -ForegroundColor Green