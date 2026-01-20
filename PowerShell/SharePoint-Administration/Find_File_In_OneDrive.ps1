# Configuration
$userEmail = "jane.doe@companynet.com"
$searchTerm = "Private Company Workstreams"  # Partial match
$tenant = "companynet"

# Build OneDrive URL
$username = $userEmail.Replace("@", "_").Replace(".", "_")
$oneDriveUrl = "https://companynet-my.sharepoint.com/personal/XXXXX_company_old_rsm_net"

Write-Host "=== Comprehensive OneDrive Search ===" -ForegroundColor Cyan
Write-Host "User: $userEmail"
Write-Host "Searching for: *$searchTerm*"
Write-Host ""

# Connect
Connect-PnPOnline -Url $oneDriveUrl -clientId CLIENT_ID -interactive

# ===== STEP 1: Search ALL Lists/Libraries =====
Write-Host "[1] Discovering all lists and libraries..." -ForegroundColor Yellow

$allLists = Get-PnPList | Where-Object { 
    $_.Hidden -eq $false -and 
    $_.BaseType -eq "DocumentLibrary" 
}

Write-Host "Found $($allLists.Count) document libraries to search:"
$allLists | ForEach-Object { Write-Host "  - $($_.Title)" -ForegroundColor Gray }

# ===== STEP 2: Search Each Library =====
Write-Host "`n[2] Searching all libraries for '*$searchTerm*'..." -ForegroundColor Yellow

$allFoundFiles = @()

foreach ($list in $allLists) {
    Write-Host "  Searching: $($list.Title)..." -ForegroundColor Gray
    
    try {
        # Get all items from this library
        $items = Get-PnPListItem -List $list.Title -PageSize 5000
        
        # Search for matching files (wildcard)
        $matches = $items | Where-Object { 
            $_["FileLeafRef"] -like "*$searchTerm*" -or
            $_["Title"] -like "*$searchTerm*"
        }
        
        if ($matches) {
            foreach ($match in $matches) {
                $allFoundFiles += [PSCustomObject]@{
                    FileName   = $match["FileLeafRef"]
                    Title      = $match["Title"]
                    Library    = $list.Title
                    FullPath   = $match["FileRef"]
                    Modified   = $match["Modified"]
                    ModifiedBy = $match["Editor"].LookupValue
                    FileSize   = if ($match["File_x0020_Size"]) { 
                        "$([math]::Round($match['File_x0020_Size'] / 1KB, 2)) KB" 
                    }
                    else { "N/A" }
                    ItemId     = $match.Id
                    Url        = "$oneDriveUrl$($match['FileRef'])"
                }
            }
        }
    }
    catch {
        Write-Host "    ⚠ Could not search $($list.Title): $_" -ForegroundColor Yellow
    }
}

# ===== STEP 3: Display Results =====
if ($allFoundFiles.Count -gt 0) {
    Write-Host "`n✓ Found $($allFoundFiles.Count) matching file(s):" -ForegroundColor Green
    
    $allFoundFiles | Format-Table -AutoSize FileName, Library, Modified, FileSize
    
    Write-Host "`nDetailed results:"
    $allFoundFiles | ForEach-Object {
        Write-Host "`n  File: $($_.FileName)" -ForegroundColor Cyan
        Write-Host "  Location: $($_.Library)"
        Write-Host "  Full Path: $($_.FullPath)"
        Write-Host "  Modified: $($_.Modified) by $($_.ModifiedBy)"
        Write-Host "  Size: $($_.FileSize)"
        Write-Host "  URL: $($_.Url)"
    }
    
    # Export results
    $exportPath = "C:\temp\OneDrive_Search_Results_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    $allFoundFiles | Export-Csv -Path $exportPath -NoTypeInformation
    Write-Host "`n✓ Results exported to: $exportPath" -ForegroundColor Green
    
}
else {
    Write-Host "`n✗ No files found matching '*$searchTerm*' in active files" -ForegroundColor Red
}

# ===== STEP 4: Search Recycle Bins =====
Write-Host "`n[3] Searching first-stage recycle bin..." -ForegroundColor Yellow

$recycleItems = Get-PnPRecycleBinItem
$foundRecycle = $recycleItems | Where-Object { 
    $_.LeafName -like "*$searchTerm*" -or
    $_.Title -like "*$searchTerm*"
}

if ($foundRecycle) {
    Write-Host "✓ Found $($foundRecycle.Count) matching item(s) in recycle bin:" -ForegroundColor Green
    
    $foundRecycle | ForEach-Object {
        Write-Host "`n  File: $($_.LeafName)" -ForegroundColor Cyan
        Write-Host "  Deleted: $($_.DeletedDate)"
        Write-Host "  Deleted by: $($_.DeletedByEmail)"
        Write-Host "  Original location: $($_.DirName)"
        Write-Host "  Item ID: $($_.Id)"
    }
    
    # Offer to restore
    Write-Host ""
    $restore = Read-Host "Restore file(s) from recycle bin? (Y/N)"
    if ($restore -eq "Y") {
        foreach ($item in $foundRecycle) {
            Restore-PnPRecycleBinItem -Identity $item.Id -Force
            Write-Host "✓ Restored: $($item.LeafName)" -ForegroundColor Green
        }
    }
}
else {
    Write-Host "✗ Not found in first-stage recycle bin" -ForegroundColor Red
}

Write-Host "`n[4] Searching second-stage recycle bin..." -ForegroundColor Yellow

$secondStage = Get-PnPRecycleBinItem -SecondStage
$foundSecond = $secondStage | Where-Object { 
    $_.LeafName -like "*$searchTerm*" -or
    $_.Title -like "*$searchTerm*"
}

if ($foundSecond) {
    Write-Host "✓ Found $($foundSecond.Count) matching item(s) in second-stage recycle bin:" -ForegroundColor Green
    
    $foundSecond | ForEach-Object {
        Write-Host "`n  File: $($_.LeafName)" -ForegroundColor Cyan
        Write-Host "  Deleted: $($_.DeletedDate)"
        Write-Host "  Original location: $($_.DirName)"
    }
}
else {
    Write-Host "✗ Not found in second-stage recycle bin" -ForegroundColor Red
}

# ===== STEP 5: Alternative Searches =====
if ($allFoundFiles.Count -eq 0 -and !$foundRecycle -and !$foundSecond) {
    Write-Host "`n[5] Trying alternative search methods..." -ForegroundColor Yellow
    
    # Try searching with different variations
    $variations = @(
        $searchTerm,
        $searchTerm.Replace(" ", "_"),
        $searchTerm.Replace(" ", "-"),
        $searchTerm.Replace(" ", "")
    )
    
    Write-Host "  Trying filename variations:"
    foreach ($variation in $variations) {
        Write-Host "    - *$variation*" -ForegroundColor Gray
        
        $items = Get-PnPListItem -List "Documents" -PageSize 5000
        $matches = $items | Where-Object { 
            $_["FileLeafRef"] -like "*$variation*"
        }
        
        if ($matches) {
            Write-Host "    ✓ Found matches with variation '$variation'" -ForegroundColor Green
            $matches | ForEach-Object {
                Write-Host "      File: $($_['FileLeafRef'])"
            }
        }
    }
}

Write-Host "`n=== Search Complete ===" -ForegroundColor Cyan

# Summary
Write-Host "`nSummary:"
Write-Host "  Active files found: $($allFoundFiles.Count)"
Write-Host "  Recycle bin (stage 1): $(if ($foundRecycle) { $foundRecycle.Count } else { 0 })"
Write-Host "  Recycle bin (stage 2): $(if ($foundSecond) { $foundSecond.Count } else { 0 })"

if ($allFoundFiles.Count -eq 0 -and !$foundRecycle -and !$foundSecond) {
    Write-Host "`n⚠ File not found in OneDrive or recycle bins" -ForegroundColor Yellow
    Write-Host "`nNext steps to try:"
    Write-Host "  1. Check if file is in a SharePoint site or Teams (not OneDrive)"
    Write-Host "  2. Check user's local OneDrive sync folder on their computer"
    Write-Host "  3. Search user's email for file as attachment"
    Write-Host "  4. Check with user if file was renamed or moved to different location"
    Write-Host "  5. If you have access, check Purview compliance center for retention holds"
}