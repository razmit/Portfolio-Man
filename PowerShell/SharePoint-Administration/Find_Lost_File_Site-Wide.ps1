connect-pnpOnline -Url https://companynet.sharepoint.com/sites/in_ORM -clientId CLIENT_ID -interactive

# The file's name
$fileName = "Business Continuity"

# Get all document libraries in the site
$lists = Get-PnPList | Where-Object { $_.BaseTemplate -eq 101 } # 101 is the template ID for document libraries

# Matches found counter
$matchesFound = 0

$matchesList = @()

Write-Host "Searching for file '$fileName' across all document libraries..." -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan

foreach ($list in $lists) {
    
    Write-Host "Searching in library: $($list.Title)" -ForegroundColor Yellow
    
    # Search for the file in this library
    $items = Get-PnPListItem -List $list -PageSize 500
    
    foreach ($item in $items) {
        
        if($item.FileSystemObjectType -eq "File" -and $item.FieldValues.FileLeafRef -like "*$fileName*") {
            Write-Host "Found something!" -ForegroundColor Green
            # Write-Host "Library: $($list.Title)" -ForegroundColor Green
            # Write-Host "File URL: $($item.FieldValues.FileRef)" -ForegroundColor Green
            $matchesFound++
            $matchesList += [PSCustomObject]@{
                Fullname = $item.FieldValues.FileLeafRef;
                Library = $list.Title;
                FileUrl = $item.FieldValues.FileRef;
                ModifiedOn = $item.FieldValues.Modified
            }
        }
    }
}

write-Host "Search completed!" -ForegroundColor Cyan

if ($matchesFound -eq 0) {
    Write-Host "No files found containing the name '$fileName'." -ForegroundColor Red
} else {
    Write-Host "There were $($matchesList.Count) matches found." -ForegroundColor Green
    foreach($match in $matchesList) {
        write-Host "======================================" -ForegroundColor Cyan
        Write-Host "File's Full Name: $($match.Fullname)" -ForegroundColor Green
        Write-Host "Found in library: $($match.Library)" -ForegroundColor Green
        Write-Host "File URL: $($match.FileUrl)" -ForegroundColor Green
        Write-Host "Modified On: $($match.ModifiedOn)" -ForegroundColor Green
        Write-Host "======================================" -ForegroundColor Cyan
    }
}
