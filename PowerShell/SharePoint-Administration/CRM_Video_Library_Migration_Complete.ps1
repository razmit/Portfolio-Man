# ============================================
# CRM Video Library Migration - Complete Solution
# ============================================
# This script:
# 1. Moves video files from Video content type folders to library root
# 2. Preserves Resource Type metadata from the folders
# 3. Handles naming collisions intelligently
# 4. Cleans up empty folders after migration
# ============================================

param(
    [string]$SiteUrl = "https://companynet.sharepoint.com/sites/in_CRMResourceCenter",
    [string]$ClientId = "CLIENT_ID",
    [string]$LibraryName = "CRM Video Library",
    [switch]$WhatIf = $false  # Use -WhatIf to preview without making changes
)

# Connect to SharePoint
Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "=== CRM VIDEO LIBRARY MIGRATION ===" -ForegroundColor Cyan
Write-Host "============================================`n" -ForegroundColor Cyan

if ($WhatIf) {
    Write-Host "⚠️  RUNNING IN PREVIEW MODE (WhatIf)" -ForegroundColor Yellow
    Write-Host "   No changes will be made`n" -ForegroundColor Yellow
}

Write-Host "Connecting to SharePoint..." -ForegroundColor Yellow
Write-Host "  Site: $SiteUrl" -ForegroundColor Gray
Write-Host "  Library: $LibraryName`n" -ForegroundColor Gray

try {
    Connect-PnPOnline -Url $SiteUrl -ClientId $ClientId -Interactive
    Write-Host "✓ Connected successfully`n" -ForegroundColor Green
}
catch {
    Write-Host "✗ Connection failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Get library information
Write-Host "Getting library information..." -ForegroundColor Yellow
$list = Get-PnPList -Identity $LibraryName
$libraryUrl = $list.RootFolder.ServerRelativeUrl
Write-Host "✓ Library path: $libraryUrl`n" -ForegroundColor Green

# Retrieve all items
Write-Host "Retrieving all items from library..." -ForegroundColor Yellow
$allItems = Get-PnPListItem -List $list -PageSize 5000 -Fields "FileLeafRef", "FileRef", "FSObjType", "FileDirRef", "Resource_x0020_Type"
Write-Host "✓ Retrieved $($allItems.Count) total items`n" -ForegroundColor Green

# Find root-level folders (Video content type folders)
$rootFolders = $allItems | Where-Object {
    $_.FieldValues.FSObjType -eq 1 -and
    $_.FieldValues.FileDirRef -eq $libraryUrl
}

Write-Host "Found $($rootFolders.Count) folders at library root`n" -ForegroundColor Cyan

# Check if Resource Type field exists
Write-Host "Verifying Resource Type field..." -ForegroundColor Yellow
try {
    $resourceTypeField = Get-PnPField -List $list -Identity "Resource_x0020_Type" -ErrorAction Stop
    Write-Host "✓ Resource Type field found: $($resourceTypeField.Title)`n" -ForegroundColor Green
}
catch {
    Write-Host "⚠️  Resource Type field not found!" -ForegroundColor Red
    Write-Host "   Looking for alternative field names..." -ForegroundColor Yellow

    $fields = Get-PnPField -List $list | Where-Object { $_.Title -like "*Resource*" -or $_.Title -like "*Type*" }
    if ($fields) {
        Write-Host "`n   Found these similar fields:" -ForegroundColor Cyan
        $fields | ForEach-Object {
            Write-Host "     - $($_.Title) (Internal: $($_.InternalName))" -ForegroundColor Gray
        }
    }

    Write-Host "`n   The script will continue, but Resource Type data may not be preserved." -ForegroundColor Yellow
    Write-Host "   Press Enter to continue or Ctrl+C to exit..." -ForegroundColor Yellow
    Read-Host
}

# Statistics tracking
$stats = @{
    FoldersProcessed = 0
    VideosMoved = 0
    VideosUpdated = 0
    VideosSkipped = 0
    FoldersDeleted = 0
    Errors = 0
}

$movedFiles = @()
$errors = @()
$skippedFiles = @()

# Process each folder
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "=== PROCESSING VIDEO FOLDERS ===" -ForegroundColor Cyan
Write-Host "============================================`n" -ForegroundColor Cyan

foreach ($folder in $rootFolders) {
    $folderPath = $folder.FieldValues.FileRef
    $folderName = $folder.FieldValues.FileLeafRef
    $resourceType = $folder.FieldValues.Resource_x0020_Type

    $stats.FoldersProcessed++

    Write-Host "[$($stats.FoldersProcessed)/$($rootFolders.Count)] Folder: $folderName" -ForegroundColor Cyan

    if ($resourceType) {
        Write-Host "  Resource Type: $resourceType" -ForegroundColor Green
    }
    else {
        Write-Host "  ⚠️  No Resource Type found on folder" -ForegroundColor Yellow
    }

    # Find video files in this folder
    $filesInFolder = $allItems | Where-Object {
        $_.FieldValues.FSObjType -eq 0 -and
        $_.FieldValues.FileDirRef -eq $folderPath -and
        $_.FieldValues.FileLeafRef -match '\.(mp4|mov|avi|wmv|webm|m4v|flv|mkv)$'
    }

    if ($filesInFolder.Count -eq 0) {
        Write-Host "  ⚠️  No video files found in this folder" -ForegroundColor Yellow

        $errors += [PSCustomObject]@{
            Folder = $folderName
            Issue = "No video files found"
            Action = "Skipped"
        }

        Write-Host ""
        continue
    }

    Write-Host "  Found $($filesInFolder.Count) video file(s)" -ForegroundColor White

    # Process each video file
    foreach ($fileItem in $filesInFolder) {
        $fileName = $fileItem.FieldValues.FileLeafRef
        $sourceUrl = $fileItem.FieldValues.FileRef

        Write-Host "`n    Video: $fileName" -ForegroundColor White

        # Check if file already exists at library root
        $targetFileName = $fileName
        $targetUrl = "$libraryUrl/$targetFileName"

        $existingFile = $allItems | Where-Object {
            $_.FieldValues.FileRef -eq $targetUrl -and
            $_.FieldValues.FSObjType -eq 0
        }

        if ($existingFile) {
            # File already exists at root - check if it's the same file or a duplicate
            if ($existingFile.Id -eq $fileItem.Id) {
                Write-Host "      ✓ Already at library root (skipping)" -ForegroundColor Gray
                $stats.VideosSkipped++

                # Still update metadata if missing
                if ($resourceType -and -not $existingFile.FieldValues.Resource_x0020_Type) {
                    Write-Host "      → Updating missing Resource Type..." -ForegroundColor Yellow

                    if (-not $WhatIf) {
                        try {
                            Set-PnPListItem -List $list -Identity $existingFile.Id -Values @{
                                "Resource_x0020_Type" = $resourceType
                            } -UpdateType SystemUpdate

                            Write-Host "      ✓ Resource Type updated" -ForegroundColor Green
                            $stats.VideosUpdated++
                        }
                        catch {
                            Write-Host "      ✗ Failed to update: $($_.Exception.Message)" -ForegroundColor Red
                        }
                    }
                    else {
                        Write-Host "      [WhatIf] Would update Resource Type to: $resourceType" -ForegroundColor Gray
                    }
                }

                continue
            }
            else {
                # Different file with same name - need to rename
                $nameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
                $extension = [System.IO.Path]::GetExtension($fileName)

                # Check if filename already includes folder name (from previous migration attempts)
                if ($nameWithoutExt -match "^(.+)\s+-\s+(.+)$") {
                    # Already has a suffix, just use original name
                    $targetFileName = $fileName
                }
                else {
                    # Add folder name as suffix
                    $targetFileName = "$nameWithoutExt - $folderName$extension"
                }

                $targetUrl = "$libraryUrl/$targetFileName"
                Write-Host "      ⚠️  Name collision detected" -ForegroundColor Yellow
                Write-Host "      → Renaming to: $targetFileName" -ForegroundColor Yellow
            }
        }

        # Move the file
        Write-Host "      → Moving to library root..." -ForegroundColor Gray

        if (-not $WhatIf) {
            try {
                Move-PnPFile -SourceUrl $sourceUrl -TargetUrl $targetUrl -Force -ErrorAction Stop
                Write-Host "      ✓ Moved successfully" -ForegroundColor Green
                $stats.VideosMoved++

                # Update Resource Type metadata
                if ($resourceType) {
                    Write-Host "      → Setting Resource Type: $resourceType" -ForegroundColor Gray

                    try {
                        # Get the moved file's new ID
                        Start-Sleep -Milliseconds 500  # Brief pause to ensure file is indexed
                        $movedFile = Get-PnPFile -Url $targetUrl -AsListItem

                        Set-PnPListItem -List $list -Identity $movedFile.Id -Values @{
                            "Resource_x0020_Type" = $resourceType
                        } -UpdateType SystemUpdate

                        Write-Host "      ✓ Resource Type set" -ForegroundColor Green
                        $stats.VideosUpdated++
                    }
                    catch {
                        Write-Host "      ⚠️  Could not set Resource Type: $($_.Exception.Message)" -ForegroundColor Yellow

                        $errors += [PSCustomObject]@{
                            Folder = $folderName
                            File = $fileName
                            Issue = "Move succeeded but Resource Type update failed: $($_.Exception.Message)"
                            Action = "Manual review needed"
                        }
                    }
                }

                $movedFiles += [PSCustomObject]@{
                    OriginalFolder = $folderName
                    OriginalFileName = $fileName
                    NewFileName = $targetFileName
                    ResourceType = $resourceType
                    NewPath = $targetUrl
                }
            }
            catch {
                Write-Host "      ✗ Move failed: $($_.Exception.Message)" -ForegroundColor Red
                $stats.Errors++

                $errors += [PSCustomObject]@{
                    Folder = $folderName
                    File = $fileName
                    Issue = "Move failed: $($_.Exception.Message)"
                    Action = "Retry needed"
                }
            }
        }
        else {
            Write-Host "      [WhatIf] Would move to: $targetUrl" -ForegroundColor Gray
            if ($resourceType) {
                Write-Host "      [WhatIf] Would set Resource Type: $resourceType" -ForegroundColor Gray
            }
        }
    }

    # Delete the folder after processing (if not in WhatIf mode)
    if ($filesInFolder.Count -gt 0 -and -not $WhatIf) {
        Write-Host "`n  → Removing empty folder..." -ForegroundColor Yellow

        try {
            # Refresh folder to check if it's empty
            $folderCheck = Get-PnPFolderItem -FolderSiteRelativeUrl $folder.FieldValues.FileRef.Replace($libraryUrl + "/", "")

            if ($folderCheck.Count -eq 0) {
                $folderItem = Get-PnPListItem -List $list -Id $folder.Id
                $folderItem.DeleteObject()
                Invoke-PnPQuery

                Write-Host "  ✓ Folder deleted`n" -ForegroundColor Green
                $stats.FoldersDeleted++
            }
            else {
                Write-Host "  ⚠️  Folder still contains items, not deleted" -ForegroundColor Yellow
                Write-Host "     (May contain subfolders or other files)`n" -ForegroundColor Gray
            }
        }
        catch {
            Write-Host "  ⚠️  Could not delete folder: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host "     (You may need to delete manually)`n" -ForegroundColor Gray
        }
    }
    elseif ($WhatIf) {
        Write-Host "`n  [WhatIf] Would delete folder: $folderName`n" -ForegroundColor Gray
    }
    else {
        Write-Host ""
    }
}

# ============================================
# SUMMARY AND REPORTING
# ============================================

Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "=== MIGRATION COMPLETE ===" -ForegroundColor Green
Write-Host "============================================`n" -ForegroundColor Cyan

Write-Host "Summary:" -ForegroundColor White
Write-Host "  Folders processed: $($stats.FoldersProcessed)" -ForegroundColor White
Write-Host "  Videos moved: $($stats.VideosMoved)" -ForegroundColor $(if ($stats.VideosMoved -gt 0) { 'Green' } else { 'Gray' })
Write-Host "  Videos updated (metadata): $($stats.VideosUpdated)" -ForegroundColor $(if ($stats.VideosUpdated -gt 0) { 'Green' } else { 'Gray' })
Write-Host "  Videos skipped (already at root): $($stats.VideosSkipped)" -ForegroundColor Gray
Write-Host "  Folders deleted: $($stats.FoldersDeleted)" -ForegroundColor $(if ($stats.FoldersDeleted -gt 0) { 'Green' } else { 'Gray' })
Write-Host "  Errors: $($stats.Errors)" -ForegroundColor $(if ($stats.Errors -gt 0) { 'Red' } else { 'Green' })

# Export moved files report
if ($movedFiles.Count -gt 0 -and -not $WhatIf) {
    Write-Host "`n--- Moved Files ---" -ForegroundColor Cyan

    $movedFiles | Select-Object -First 5 | ForEach-Object {
        Write-Host "  ✓ [$($_.OriginalFolder)] $($_.OriginalFileName)" -ForegroundColor Green
        if ($_.ResourceType) {
            Write-Host "    → Resource Type: $($_.ResourceType)" -ForegroundColor Gray
        }
    }

    if ($movedFiles.Count -gt 5) {
        Write-Host "  ... and $($movedFiles.Count - 5) more" -ForegroundColor Gray
    }

    $reportPath = "C:\Temp\CRM_Video_Migration_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    $movedFiles | Export-Csv $reportPath -NoTypeInformation
    Write-Host "`n✓ Full report exported to: $reportPath" -ForegroundColor Cyan
}

# Show errors if any
if ($errors.Count -gt 0) {
    Write-Host "`n--- Errors and Warnings ---" -ForegroundColor Red
    $errors | Format-Table -AutoSize

    if (-not $WhatIf) {
        $errorPath = "C:\Temp\CRM_Video_Migration_Errors_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
        $errors | Export-Csv $errorPath -NoTypeInformation
        Write-Host "✓ Errors exported to: $errorPath" -ForegroundColor Cyan
    }
}

# Next steps
Write-Host "`nNext Steps:" -ForegroundColor Yellow
Write-Host "  1. Verify videos are at library root in browser" -ForegroundColor White
Write-Host "  2. Verify Resource Type metadata is preserved" -ForegroundColor White
Write-Host "  3. Test video playback and Replace functionality" -ForegroundColor White

if ($rootFolders.Count -gt 0 -and $stats.FoldersDeleted -lt $rootFolders.Count) {
    Write-Host "  4. Review and manually delete any remaining folders" -ForegroundColor White
}

if ($WhatIf) {
    Write-Host "`n⚠️  THIS WAS A PREVIEW - NO CHANGES WERE MADE" -ForegroundColor Yellow
    Write-Host "   Run without -WhatIf to execute the migration" -ForegroundColor Yellow
}

Write-Host "`n✓ Migration script completed" -ForegroundColor Green
