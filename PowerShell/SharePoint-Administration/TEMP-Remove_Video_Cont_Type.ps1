Connect-PnPOnline -Url https://companynet.sharepoint.com/sites/in_CRMResourceCenter -clientId CLIENT_ID -interactive

$libraryName = "CRM video library"

Write-Host "=== FLATTENING VIDEO STRUCTURE ===" -ForegroundColor Cyan
Write-Host "Getting library information..." -ForegroundColor Yellow

$list = Get-PnPList -Identity $libraryName
$libraryUrl = $list.RootFolder.ServerRelativeUrl

Write-Host "Library path: $libraryUrl`n" -ForegroundColor Gray

# Get ALL items in the library
Write-Host "Retrieving all items from library..." -ForegroundColor Yellow
$allItems = Get-PnPListItem -List $list -PageSize 5000 -Fields "FileLeafRef", "FileRef", "FSObjType", "FileDirRef"

Write-Host "Total items: $($allItems.Count)`n" -ForegroundColor Cyan

# Find root-level folders (Video content type folders)
$rootFolders = $allItems | Where-Object { 
    $_.FieldValues.FSObjType -eq 1 -and 
    $_.FieldValues.FileDirRef -eq $libraryUrl
}

Write-Host "Found $($rootFolders.Count) video folders at library root`n" -ForegroundColor Cyan

$movedFiles = @()
$errors = @()
$foldersProcessed = 0

foreach ($videoFolder in $rootFolders) {
    $folderPath = $videoFolder.FieldValues.FileRef
    $folderName = $videoFolder.FieldValues.FileLeafRef
    
    $foldersProcessed++
    Write-Host "[$foldersProcessed/$($rootFolders.Count)] Processing: $folderName" -ForegroundColor Cyan
    
    # Find video FILES directly in this folder (not in subfolders)
    $filesInFolder = $allItems | Where-Object {
        $_.FieldValues.FSObjType -eq 0 -and # Files only (0 = file, 1 = folder)
        $_.FieldValues.FileDirRef -eq $folderPath -and
        $_.FieldValues.FileLeafRef -match '\.(mp4|mov|avi|wmv|webm|m4v)$'  # Video files only
    }
    
    if ($filesInFolder.Count -eq 0) {
        Write-Host "  ⚠️  No video files found" -ForegroundColor Yellow
        
        $errors += [PSCustomObject]@{
            Folder = $folderName
            Path   = $folderPath
            Issue  = "No video files found"
        }
        continue
    }
    
    Write-Host "  Found $($filesInFolder.Count) video file(s)" -ForegroundColor Green
    
    foreach ($fileItem in $filesInFolder) {
        $fileName = $fileItem.FieldValues.FileLeafRef
        $sourceUrl = $fileItem.FieldValues.FileRef
        
        Write-Host "    Video: $fileName" -ForegroundColor White
        
        # Check for naming collision at library root
        $targetFileName = $fileName
        $targetUrl = "$libraryUrl/$targetFileName"
        
        $collision = $allItems | Where-Object {
            $_.FieldValues.FileRef -eq $targetUrl -and
            $_.FieldValues.FSObjType -eq 0
        }
        
        if ($collision) {
            # Append folder name to avoid collision
            $nameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
            $extension = [System.IO.Path]::GetExtension($fileName)
            $targetFileName = "$nameWithoutExt - $folderName$extension"
            $targetUrl = "$libraryUrl/$targetFileName"
            Write-Host "      ⚠️  Name collision, renaming to: $targetFileName" -ForegroundColor Yellow
        }
        
        Write-Host "      Moving to library root..." -ForegroundColor Gray
        
        try {
            # Move the video file
            Move-PnPFile -SourceUrl $sourceUrl -TargetUrl $targetUrl -Force
            
            Write-Host "      ✓ Moved successfully" -ForegroundColor Green
            
            $movedFiles += [PSCustomObject]@{
                OriginalFolder   = $folderName
                OriginalFileName = $fileName
                NewFileName      = $targetFileName
                NewPath          = $targetUrl
            }
            
        }
        catch {
            Write-Host "      ✗ Move failed: $($_.Exception.Message)" -ForegroundColor Red
            
            $errors += [PSCustomObject]@{
                Folder = $folderName
                Path   = $folderPath
                Issue  = "Move failed: $($_.Exception.Message)"
            }
        }
    }
    
    # After moving video, delete the entire folder structure
    Write-Host "  Removing folder structure (including subfolders)..." -ForegroundColor Yellow
    
    try {
        # Get the folder as a list item and delete it
        $folderItem = Get-PnPListItem -List $list -Id $videoFolder.Id
        $folderItem.DeleteObject()
        Invoke-PnPQuery
        
        Write-Host "  ✓ Folder removed`n" -ForegroundColor Green
        
    }
    catch {
        Write-Host "  ⚠️  Could not remove folder: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "     (You may need to delete manually)`n" -ForegroundColor Gray
    }
}

Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "=== MIGRATION COMPLETE ===" -ForegroundColor Green
Write-Host "============================================`n" -ForegroundColor Cyan

Write-Host "Video folders processed: $foldersProcessed" -ForegroundColor White
Write-Host "Videos successfully moved: $($movedFiles.Count)" -ForegroundColor Green
Write-Host "Errors: $($errors.Count)" -ForegroundColor $(if ($errors.Count -gt 0) { 'Red' }else { 'Green' })

if ($movedFiles.Count -gt 0) {
    Write-Host "`n--- Moved Files Summary ---" -ForegroundColor Cyan
    $movedFiles | Select-Object -First 10 | ForEach-Object {
        Write-Host "  ✓ $($_.OriginalFileName) → $($_.NewFileName)" -ForegroundColor Green
    }
    
    if ($movedFiles.Count -gt 10) {
        Write-Host "  ... and $($movedFiles.Count - 10) more" -ForegroundColor Gray
    }
    
    $movedFiles | Export-Csv "C:\Temp\MovedVideoFiles.csv" -NoTypeInformation
    Write-Host "`nFull list exported to C:\Temp\MovedVideoFiles.csv" -ForegroundColor Cyan
}

if ($errors.Count -gt 0) {
    Write-Host "`n--- Errors ---" -ForegroundColor Red
    $errors | Format-Table -AutoSize
    $errors | Export-Csv "C:\Temp\VideoMigrationErrors.csv" -NoTypeInformation
    Write-Host "Errors exported to C:\Temp\VideoMigrationErrors.csv" -ForegroundColor Cyan
}

Write-Host "`nNext steps:" -ForegroundColor Yellow
Write-Host "1. Verify videos are at library root in browser" -ForegroundColor White
Write-Host "2. Test 'Replace' functionality on a video file" -ForegroundColor White
Write-Host "3. Remove Video content type (run cleanup script)" -ForegroundColor White

### DELETE VIDEO CONTENT TYPE ###

# $libraryName = "CRM video library"

# Write-Host "=== CHANGING EXISTING VIDEO FILES TO DOCUMENT CONTENT TYPE ===" -ForegroundColor Cyan

# $list = Get-PnPList -Identity $libraryName
# $libraryUrl = $list.RootFolder.ServerRelativeUrl

# Write-Host "Library path: $libraryUrl`n" -ForegroundColor Gray

# # Get all items in the library
# Write-Host "Retrieving all items..." -ForegroundColor Yellow
# $allItems = Get-PnPListItem -List $list -PageSize 5000 -Fields "FileLeafRef", "ContentType", "FSObjType", "FileDirRef"

# # Filter to video files at library root
# $videoFiles = $allItems | Where-Object {
#     $_.FieldValues.FSObjType -eq 0 -and # Files only (not folders)
#     $_.FieldValues.FileDirRef -eq $libraryUrl -and # At library root only
#     $_.FieldValues.FileLeafRef -match '\.(mp4|mov|avi|wmv|webm|m4v)$'  # Video files only
# }

# Write-Host "Found $($videoFiles.Count) video files at library root`n" -ForegroundColor Yellow

# $updated = 0
# $alreadyDocument = 0
# $failed = 0

# foreach ($videoFile in $videoFiles) {
#     $fileName = $videoFile.FieldValues.FileLeafRef
#     $currentContentType = $videoFile.FieldValues.ContentType
    
#     # Check current content type
#     if ($currentContentType -and $currentContentType.Name -eq "Document") {
#         Write-Host "✓ $fileName (already Document)" -ForegroundColor Gray
#         $alreadyDocument++
#         continue
#     }
    
#     Write-Host "Updating: $fileName" -ForegroundColor Cyan
#     if ($currentContentType) {
#         Write-Host "  Current type: $($currentContentType.Name)" -ForegroundColor Gray
#     }
#     else {
#         Write-Host "  Current type: (none)" -ForegroundColor Gray
#     }
    
#     try {
#         # Set content type to Document
#         Set-PnPListItem -List $list -Identity $videoFile.Id -ContentType "Document" -UpdateType SystemUpdate
#         Write-Host "  ✓ Changed to Document" -ForegroundColor Green
#         $updated++
        
#     }
#     catch {
#         Write-Host "  ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
#         $failed++
#     }
# }

# Write-Host "`n=== SUMMARY ===" -ForegroundColor Green
# Write-Host "Total video files: $($videoFiles.Count)" -ForegroundColor White
# Write-Host "Already Document: $alreadyDocument" -ForegroundColor Gray
# Write-Host "Successfully updated: $updated" -ForegroundColor Green
# Write-Host "Failed: $failed" -ForegroundColor $(if ($failed -gt 0) { "Red" }else { "Green" })

# if ($updated -gt 0) {
#     Write-Host "`n✓ All video files now have Document content type" -ForegroundColor Cyan
#     Write-Host "This ensures consistent behavior and prevents issues" -ForegroundColor Cyan
# }

# Write-Host "`n=== COMPLETE ===" -ForegroundColor Green



##### Remove Video content type from New menu #####

# $libraryName = "CRM video library"

# Write-Host "=== REMOVING VIDEO CONTENT TYPE FROM NEW MENU ===" -ForegroundColor Cyan

# # Get the list and load content types
# $list = Get-PnPList -Identity $libraryName
# $ctx = Get-PnPContext

# $ctx.Load($list)
# $ctx.Load($list.ContentTypes)
# $ctx.Load($list.RootFolder)
# $ctx.ExecuteQuery()

# Write-Host "`nCurrent content types in library:" -ForegroundColor Yellow
# foreach ($ct in $list.ContentTypes) {
#     Write-Host "  - $($ct.Name)" -ForegroundColor Gray
# }

# # Get the Document content type
# $docCT = $list.ContentTypes | Where-Object { $_.Name -eq "Document" }

# if ($docCT) {
#     Write-Host "`nSetting Document as the only available content type for uploads..." -ForegroundColor Yellow
    
#     # Set Document as the only content type in the "New" menu
#     # This removes Video (and any others) from the upload dropdown
#     $list.RootFolder.UniqueContentTypeOrder = @($docCT)
#     $list.RootFolder.Update()
#     $ctx.ExecuteQuery()
    
#     Write-Host "✓ Video content type removed from 'New' menu" -ForegroundColor Green
#     Write-Host "✓ Document set as default content type" -ForegroundColor Green
#     Write-Host "`nUsers can now only upload files as 'Document' type" -ForegroundColor Cyan
#     Write-Host "This prevents accidental recreation of Video folder structures" -ForegroundColor Cyan
    
# }
# else {
#     Write-Host "`n⚠️  Document content type not found!" -ForegroundColor Red
#     Write-Host "Adding Document content type first..." -ForegroundColor Yellow
    
#     Add-PnPContentTypeToList -List $libraryName -ContentType "Document" -DefaultContentType
    
#     Write-Host "✓ Document content type added" -ForegroundColor Green
#     Write-Host "Please run this script again to set it as default" -ForegroundColor Yellow
# }

# Write-Host "`n=== COMPLETE ===" -ForegroundColor Green


#################

# $oldLibraryName = "CRM video library"
# $newLibraryName = "Video Library - Clean"

# Write-Host "=== COPYING VIDEOS TO NEW LIBRARY ===" -ForegroundColor Cyan

# $oldList = Get-PnPList -Identity $oldLibraryName
# $oldLibraryUrl = $oldList.RootFolder.ServerRelativeUrl

# # Get all video files from old library (at root level)
# $allItems = Get-PnPListItem -List $oldList -PageSize 5000 -Fields "FileLeafRef", "FileRef", "FSObjType", "FileDirRef"

# $videoFiles = $allItems | Where-Object {
#     $_.FieldValues.FSObjType -eq 0 -and
#     $_.FieldValues.FileDirRef -eq $oldLibraryUrl -and
#     $_.FieldValues.FileLeafRef -match '\.(mp4|mov|avi|wmv|webm|m4v)$'
# }

# Write-Host "Found $($videoFiles.Count) video files to copy`n" -ForegroundColor Yellow

# $copied = 0

# foreach ($videoFile in $videoFiles) {
#     $sourceUrl = $videoFile.FieldValues.FileRef
#     $fileName = $videoFile.FieldValues.FileLeafRef
#     $targetUrl = "/sites/in_CRMResourceCenter/VideoLibraryClean/$fileName"
    
#     Write-Host "Copying: $fileName" -ForegroundColor Cyan
    
#     try {
#         Copy-PnPFile -SourceUrl $sourceUrl -TargetUrl $targetUrl -Force
#         Write-Host "  ✓ Copied" -ForegroundColor Green
#         $copied++
#     }
#     catch {
#         Write-Host "  ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
#     }
# }

# Write-Host "`n=== COPY COMPLETE ===" -ForegroundColor Green
# Write-Host "Videos copied: $copied out of $($videoFiles.Count)" -ForegroundColor Cyan

# Write-Host "`nNext steps:" -ForegroundColor Yellow
# Write-Host "1. Test Replace function in new library"
# Write-Host "2. If it works, notify users of new library location"
# Write-Host "3. Archive or delete old library"