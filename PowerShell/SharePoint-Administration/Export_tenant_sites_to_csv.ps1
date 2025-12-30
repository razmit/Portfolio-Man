try {
    # Connect to the tenant admin

    Connect-SPOService -Url https://companynet-admin.sharepoint.com/ 

    # Get the current date in dd-MM-yyyy format
    $currentDateTime = Get-Date -Format "dd-MM-yyyy"

    # Create the name of the new CSV file that will contain ALL of the site collections in the tenant. Appends the date in which it was created
    $exportPath = "C:\Users\E095713\Downloads\SiteCollection-Reports\SiteCollections-TenantWide-" + $currentDateTime + ".csv"

    Get-SPOSite -Limit All | Export-Csv -Path $exportPath -NoTypeInformation
    
    return @{Success = $true; $Message = "Connection and export successful!"}
}
catch {
    Write-Host "Connection failed: "$_.Exception.Message -ForegroundColor Red
    return @{Success = $false; Message = $_.Exception.Message}
}
##### MY BELOVED BARRA DE PROGRESO NOOOOOOOOOOOOOO #####

# # Get all sites first
# $sites = Get-SPOSite -Limit All
# $total = $sites.Count
# $j = 0

# $exportList = @()

# foreach ($site in $sites) {
#     $j++
#     Write-Progress -Activity "Exporting sites" -Status "Processing $($site.Url)" -PercentComplete (($j / $total) * 100)
        
#     $exportList += $site
# }
    
# # Once they're all in the $exportList, we can put them in a CSV
    
# $exportList | Export-Csv -Path $exportPath -NoTypeInformation

# Backup way
