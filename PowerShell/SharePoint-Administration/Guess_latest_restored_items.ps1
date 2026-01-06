Connect-PnPOnline -Url https://companynet.sharepoint.com/sites/DDSAppDevandIntegration -clientId CLIENT_ID -interactive

$restoreDate = Get-Date "2026-01-05"
$modifiedAfter = $restoreDate.Date
$modifiedBefore = $restoreDate.AddDays(1).Date

Write-Host "=== FOLDERS MODIFIED ON JAN 5, 2026 ===" -ForegroundColor Cyan

$lists = Get-PnPList | Where-Object { $_.Hidden -eq $false -and $_.BaseTemplate -eq 101 }

$folderList = @()

foreach ($list in $lists) {
    $items = Get-PnPListItem -List $list -PageSize 5000 -Fields "FileLeafRef", "Modified", "FSObjType", "FileDirRef"
    
    $folders = $items | Where-Object {
        $_.FieldValues.Modified -ge $modifiedAfter -and 
        $_.FieldValues.Modified -lt $modifiedBefore -and
        $_.FieldValues.FSObjType -eq 1
    }
    
    foreach ($folder in $folders) {
        $folderList += [PSCustomObject]@{
            Library    = $list.Title
            FolderName = $folder.FieldValues.FileLeafRef
            Location   = $folder.FieldValues.FileDirRef
            FullPath   = $folder.FieldValues.FileDirRef + "/" + $folder.FieldValues.FileLeafRef
        }
    }
}

Write-Host "`nFound $($folderList.Count) folders:" -ForegroundColor Yellow
$folderList | Sort-Object Library, Location, FolderName | 
Format-Table Library, FolderName, Location -AutoSize
