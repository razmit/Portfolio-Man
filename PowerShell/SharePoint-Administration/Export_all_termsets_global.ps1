# Script to export ALL term sets from the tenant's global term store to a CSV file

# Connect to a site in the tenant with PnP PowerShell
Connect-PnPOnline -Url https://companynet.sharepoint.com/sites/firm/csr/foundation -clientId CLIENT_ID -interactive

# Get the taxonomy session
$taxonomySession = Get-PnPTaxonomySession

# Get the term store
$termStore = $taxonomySession | Select-Object -ExpandProperty TermStores | Select-Object -First 1

$termStore = Get-PnPProperty -ClientObject $termStore -Property Groups

$report = @()

# Lopp through each group in the term store
foreach ($group in $termStore) {
    
    $groupName = $group.Name
    
    Write-Host "Processing Group: $($group.Name)" -ForegroundColor Cyan
    
    # Load term sets for this group
    $group = Get-PnPProperty -ClientObject $group -Property TermSets
    
    Write-Host "Current group: $($group.Name) has $($group.Count) term sets." -ForegroundColor Green
    
    # Loop through each term set in the group
    foreach ($termSet in $group) {
        
        $termSetName = $termSet.Name
        
        Write-Host "Current set is: $($termSet.Name)" -ForegroundColor Magenta
        
        Write-Host "  Processing Term Set: $($termSet.Name)" -ForegroundColor Yellow
        
        # Load terms for this term set
        $termSet = Get-PnPProperty -ClientObject $termSet -Property Terms
        
        # Loop through each term in the term set
        foreach ($term in $termSet) {
            
            $report += [PSCustomObject]@{
                'Term Group'     = $groupName.ToString()
                'Term Set'       = $termSetName.ToString()
                'Term Name'      = $term.Name.ToString()
                'Term ID'        = $term.Id.ToString()
                'Is Deprecated'  = $term.IsDeprecated
            }
        }
        
        # Add the report item to the report array
        $report += $reportItem
    }
}

# Export the report to a CSV file
$exportPath = "C:\Users\E095713\Downloads\TermStore-Reports\AllTermSets-" + (Get-Date -Format "dd-MM-yyyy") + ".csv"
$report | Export-Csv -Path $exportPath -NoTypeInformation

Write-Host "Export completed! File saved to $exportPath" -ForegroundColor Green
Write-Host "Total Terms Exported: $($report.Count)" -ForegroundColor Green