Connect-PnPOnline -Url "https://companynet-admin.sharepoint.com/sites/Teams/NatLPD/SourceContent/" -clientId CLIENT_ID -Interactive 

$libraryName = "YourLibraryName"
$list = Get-PnPList -Identity $libraryName

# Get all Document Sets (ContentTypeId starts with 0x0120D520)
Write-Host "Finding all Document Sets..." -ForegroundColor Cyan

$allItems = Get-PnPListItem -List $list -PageSize 5000 -Fields "ContentTypeId", "FileLeafRef", "CheckoutUser"

$docSets = $allItems | Where-Object { 
    $_.FieldValues.ContentTypeId -like "0x0120D520*"
}

Write-Host "Found $($docSets.Count) Document Sets to delete" -ForegroundColor Yellow
Write-Host "`nStarting deletion process..." -ForegroundColor Cyan

# Process in batches of 50 (smaller batches = more reliable)
$batchSize = 50
$totalDeleted = 0
$totalFailed = 0
$failedItems = @()

for ($i = 0; $i -lt $docSets.Count; $i += $batchSize) {
    $batch = $docSets[$i..[Math]::Min($i + $batchSize - 1, $docSets.Count - 1)]
    
    Write-Host "`nProcessing batch $([Math]::Floor($i/$batchSize) + 1) (Items $($i+1) to $($i + $batch.Count))..." -ForegroundColor Cyan
    
    foreach ($item in $batch) {
        try {
            $itemId = $item.Id
            $fileName = $item.FieldValues.FileLeafRef
            
            # Check if item is checked out
            if ($item.FieldValues.CheckoutUser) {
                Write-Host "  Checking in: $fileName (ID: $itemId)" -ForegroundColor Yellow
                
                # Force check-in using the File object
                $file = Get-PnPFile -Url $item.FieldValues.FileRef -AsListItem
                $fileObj = $file.File
                Invoke-PnPQuery
                
                # Undo checkout
                $fileObj.UndoCheckOut()
                Invoke-PnPQuery
            }
            
            # Delete the item with recycle option
            Remove-PnPListItem -List $list -Identity $itemId -Recycle -Force
            
            Write-Host "  ✓ Deleted: $fileName (ID: $itemId)" -ForegroundColor Green
            $totalDeleted++
            
        }
        catch {
            Write-Host "  ✗ Failed: $fileName (ID: $itemId) - $($_.Exception.Message)" -ForegroundColor Red
            $totalFailed++
            
            $failedItems += [PSCustomObject]@{
                ItemID   = $itemId
                FileName = $fileName
                Error    = $_.Exception.Message
            }
        }
    }
    
    # Small delay between batches to avoid throttling
    Start-Sleep -Seconds 2
}

# Summary
Write-Host "`n==================== SUMMARY ====================" -ForegroundColor Cyan
Write-Host "Total Document Sets: $($docSets.Count)" -ForegroundColor White
Write-Host "Successfully deleted: $totalDeleted" -ForegroundColor Green
Write-Host "Failed: $totalFailed" -ForegroundColor Red

if ($failedItems.Count -gt 0) {
    Write-Host "`nFailed items exported to C:\Temp\FailedDeletions.csv" -ForegroundColor Yellow
    $failedItems | Export-Csv "C:\Temp\FailedDeletions.csv" -NoTypeInformation
}