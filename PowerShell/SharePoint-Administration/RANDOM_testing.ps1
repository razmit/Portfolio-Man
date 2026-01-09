Connect-PnPOnline -Url https://companynet.sharepoint.com/sites/Resources/IMC/CRMResourceCenter -clientId CLIENT_ID -interactive

$destLibrary = "CRM Video Library"
$sourceLibrary = "CRM Simulation Library"

Write-Host "=== STEP 3: COPYING RESOURCE TYPE DATA ===" -ForegroundColor Cyan

# Get source library (same site, so no need to reconnect)
Write-Host "`nGetting source library: $sourceLibrary" -ForegroundColor Yellow

try {
    $sourceList = Get-PnPList -Identity $sourceLibrary
    $sourceLibraryUrl = $sourceList.RootFolder.ServerRelativeUrl
    
    Write-Host "✓ Connected to source library" -ForegroundColor Green
    Write-Host "  Path: $sourceLibraryUrl" -ForegroundColor Gray
    
}
catch {
    Write-Host "✗ Could not find source library!" -ForegroundColor Red
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "`nMake sure the library name is exactly correct." -ForegroundColor Yellow
    Write-Host "Available libraries on this site:" -ForegroundColor Cyan
    
    Get-PnPList | Where-Object { $_.BaseTemplate -eq 101 } | ForEach-Object {
        Write-Host "  - $($_.Title)" -ForegroundColor White
    }
    
    exit
}

# Get all items from source
Write-Host "`nRetrieving items from source library..." -ForegroundColor Yellow
$sourceItems = Get-PnPListItem -List $sourceList -PageSize 5000 -Fields "FileLeafRef", "Resource_x0020_Type", "FSObjType", "FileDirRef"

Write-Host "Retrieved $($sourceItems.Count) items from source" -ForegroundColor Cyan

# Filter to folders at library root (Video content type folders)
$sourceFolders = $sourceItems | Where-Object {
    $_.FieldValues.FSObjType -eq 1 -and
    $_.FieldValues.FileDirRef -eq $sourceLibraryUrl -and
    $_.FieldValues.Resource_x0020_Type
}

Write-Host "Found $($sourceFolders.Count) folders with Resource Type at library root" -ForegroundColor Cyan

if ($sourceFolders.Count -eq 0) {
    Write-Host "`n⚠️  No folders with Resource Type found!" -ForegroundColor Red
    Write-Host "This might mean:" -ForegroundColor Yellow
    Write-Host "  - Resource Type field has different internal name in source"
    Write-Host "  - Folders don't have Resource Type values"
    Write-Host "  - Looking at wrong path" -ForegroundColor Yellow
    
    Write-Host "`nLet me check what fields are available..." -ForegroundColor Cyan
    $sampleFolder = $sourceItems | Where-Object { $_.FieldValues.FSObjType -eq 1 } | Select-Object -First 1
    
    if ($sampleFolder) {
        Write-Host "`nSample folder: $($sampleFolder.FieldValues.FileLeafRef)" -ForegroundColor Yellow
        Write-Host "Available fields:" -ForegroundColor Gray
        $sampleFolder.FieldValues.Keys | Where-Object { $_ -like "*Resource*" -or $_ -like "*Type*" } | ForEach-Object {
            Write-Host "  - $_" -ForegroundColor White
        }
    }
    
    exit
}

# Create a mapping: FolderName → ResourceType
$folderToResourceType = @{}

Write-Host "`nBuilding folder → Resource Type mapping..." -ForegroundColor Yellow

foreach ($folder in $sourceFolders) {
    $folderName = $folder.FieldValues.FileLeafRef
    $resourceType = $folder.FieldValues.Resource_x0020_Type
    
    $folderToResourceType[$folderName] = $resourceType
    Write-Host "  $folderName → $resourceType" -ForegroundColor Gray
}

Write-Host "`n✓ Mapping created with $($folderToResourceType.Count) entries" -ForegroundColor Green

# Step 4: Get destination library and update files
Write-Host "`n=== STEP 4: UPDATING VIDEO FILES ===" -ForegroundColor Cyan

Connect-PnPOnline -Url https://companynet.sharepoint.com/sites/in_CRMResourceCenter -clientId CLIENT_ID -interactive

$destList = Get-PnPList -Identity $destLibrary
$destLibraryUrl = $destList.RootFolder.ServerRelativeUrl

Write-Host "Getting video files from destination library..." -ForegroundColor Yellow
$destItems = Get-PnPListItem -List $destList -PageSize 5000 -Fields "FileLeafRef", "FSObjType", "FileDirRef"

# Filter to video files at library root
$videoFiles = $destItems | Where-Object {
    $_.FieldValues.FSObjType -eq 0 -and
    $_.FieldValues.FileDirRef -eq $destLibraryUrl -and
    $_.FieldValues.FileLeafRef -match '\.(mp4|mov|avi|wmv|webm|m4v)$'
}

Write-Host "Found $($videoFiles.Count) video files in destination library`n" -ForegroundColor Cyan

$updated = 0
$notFound = 0
$notFoundFiles = @()

foreach ($videoFile in $videoFiles) {
    $videoFileName = $videoFile.FieldValues.FileLeafRef
    
    # Remove extension to match folder name
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($videoFileName)
    
    # Handle duplicates with suffix " - [name]"
    $alternateBaseName = $null
    if ($baseName -match '^(.+) - (.+)$') {
        # For "Account - Account Creation", try both parts
        $firstPart = $matches[1]
        $secondPart = $matches[2]
        
        # Try second part first (more likely to be the original name)
        if ($folderToResourceType.ContainsKey($secondPart)) {
            $alternateBaseName = $secondPart
        }
        elseif ($folderToResourceType.ContainsKey($firstPart)) {
            $alternateBaseName = $firstPart
        }
    }
    
    # Look up Resource Type from folder mapping
    $resourceType = $null
    
    if ($folderToResourceType.ContainsKey($baseName)) {
        $resourceType = $folderToResourceType[$baseName]
        Write-Host "✓ $videoFileName → $resourceType" -ForegroundColor Green
    }
    elseif ($alternateBaseName) {
        $resourceType = $folderToResourceType[$alternateBaseName]
        Write-Host "✓ $videoFileName → $resourceType (via alternate: $alternateBaseName)" -ForegroundColor Cyan
    }
    else {
        Write-Host "⚠️  $videoFileName → No matching folder found" -ForegroundColor Yellow
        $notFound++
        $notFoundFiles += $videoFileName
        continue
    }
    
    # Update the file
    try {
        Set-PnPListItem -List $destList -Identity $videoFile.Id -Values @{"Resource_x0020_Type" = $resourceType } -UpdateType SystemUpdate
        $updated++
    }
    catch {
        Write-Host "  ✗ Failed to update: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`n=== SUMMARY ===" -ForegroundColor Green
Write-Host "Total video files: $($videoFiles.Count)" -ForegroundColor White
Write-Host "Successfully updated: $updated" -ForegroundColor Green
Write-Host "No matching source folder: $notFound" -ForegroundColor $(if ($notFound -gt 0) { "Yellow" }else { "Green" })

if ($notFound -gt 0) {
    Write-Host "`nFiles without matches:" -ForegroundColor Yellow
    $notFoundFiles | ForEach-Object {
        Write-Host "  - $_" -ForegroundColor Gray
    }
    
    Write-Host "`nThese files might be:" -ForegroundColor Yellow
    Write-Host "  - New files added after migration"
    Write-Host "  - Files with mismatched names"
    Write-Host "  - Duplicates that need manual review"
}

Write-Host "`n✓ COMPLETE: Resource Type data copied from source to destination" -ForegroundColor Cyan
Write-Host "Modified By fields preserved (SystemUpdate used)" -ForegroundColor Cyan