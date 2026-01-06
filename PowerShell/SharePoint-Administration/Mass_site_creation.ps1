# ============================================================================
# Mass create SharePoint sites based on a predefined list
# ============================================================================
# Purpose: Mass create SharePoint sites based on a predefined list so I don't have to create 30 sites manually
#
# Date: January 2026
# ============================================================================

Connect-PnPOnline -Url https://companynet.sharepoint.com/sites/IWS_ORM_PCAOB_Inspections -clientId CLIENT_ID -interactive

# We load the file containing the sites to be created
$pathToFile = "C:\Users\E095713\Downloads\PCAOB_Mapping.xlsx"

# Get the data from the Excel file
$excelData = Import-Excel -Path $pathToFile -WorksheetName "Sheet1"

$excelData | Select-Object 'Source', 'New URL of child site' -First 5 | Format-Table -AutoSize

# Example: Accessing specific cell values for the source site
$targetRow = 0
$sourceTargetColumn = "Source"

# Example: Accessing specific cell values for the new site URL
$newSiteTargetColumn = "New URL of child site"

# Get the source site URL
$sourceCellValue = $excelData[$targetRow].$sourceTargetColumn

# Check if there's a value for the new site URL
$newSiteCellValue = $excelData[$targetRow].$newSiteTargetColumn

if ($null -eq $sourceCellValue) {
    Write-Host "Cell at Source row $targetRow, column '$sourceTargetColumn' is null or does not exist." -ForegroundColor Red
}
else {
    Write-Host "Value at row $targetRow, column '$sourceTargetColumn': $sourceCellValue" -ForegroundColor Green
    
    if ($null -eq $newSiteCellValue) {
        Write-Host "Cell at New URL of child site row $targetRow, column '$newSiteTargetColumn' is also null or does not exist." -ForegroundColor Yellow
    }
    else {
        Write-Host "Value at row $targetRow, column '$newSiteTargetColumn': $newSiteCellValue" -ForegroundColor Cyan
    }
}


# # Subsite naming for the 12- series
# for ($i = 0; $i -lt $array.Count; $i++) {
#     <# Action that will repeat until the condition is met #>
# }