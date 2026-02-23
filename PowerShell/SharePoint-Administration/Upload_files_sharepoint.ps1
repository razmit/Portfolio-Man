# Site to where the file is going to be uploaded

$url = "https://companynet.sharepoint.com/sites/SITE_NAME" 

# Standard connection command 
Connect-PnPOnline -Url $url -clientId CLIENT_ID -interactive

# File to be uploaded
$filePath = "C:\Users\LOCAL_USER\Downloads\SiteCollection-Reports\SiteCollections-TenantWide-25-08-2025.csv"

# Upload the file

Add-PnPFile -Folder "Machine Litanies/Test-Automation" -Path $filePath