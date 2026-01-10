# ============================================
# CRM Video Library Migration - Complete Solution
# ============================================
# This script migrates video files from a Classic library to a Modern library:
# 1. Reads Resource Type metadata from SOURCE library folders
# 2. Moves videos from folders to root in DESTINATION library
# 3. Applies correct Resource Type metadata using source mapping
# 4. Handles naming collisions intelligently
# 5. Cleans up empty folders after migration
# ============================================

param(
    [string]$SourceSiteUrl = "https://companynet.sharepoint.com/sites/Resources/IMC/CRMResourceCenter/",
    [string]$SourceLibraryName = "CRM Simulation Library",
    [string]$DestinationSiteUrl = "https://companynet.sharepoint.com/sites/in_CRMResourceCenter",
    [string]$DestinationLibraryName = "CRM Video Library",
    [string]$ClientId = "CLIENT_ID",
    [switch]$WhatIf = $false  # Use -WhatIf to preview without making changes
)

# ============================================
# PHASE 1: READ SOURCE LIBRARY METADATA
# ============================================

Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "=== CRM VIDEO LIBRARY MIGRATION ===" -ForegroundColor Cyan
Write-Host "============================================`n" -ForegroundColor Cyan

if ($WhatIf) {
    Write-Host "⚠️  RUNNING IN PREVIEW MODE (WhatIf)" -ForegroundColor Yellow
    Write-Host "   No changes will be made`n" -ForegroundColor Yellow
}

Write-Host "PHASE 1: Reading Resource Type metadata from SOURCE library" -ForegroundColor Cyan
Write-Host "------------------------------------------------------------`n" -ForegroundColor Cyan

Write-Host "Connecting to SOURCE library..." -ForegroundColor Yellow
Write-Host "  Site: $SourceSiteUrl" -ForegroundColor Gray
Write-Host "  Library: $SourceLibraryName`n" -ForegroundColor Gray

try {
    Connect-PnPOnline -Url $SourceSiteUrl -ClientId $ClientId -Interactive
    Write-Host "✓ Connected to source library`n" -ForegroundColor Green
}
catch {
    Write-Host "✗ Connection failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "`nTroubleshooting tips:" -ForegroundColor Yellow
    Write-Host "  - Verify the source site URL is correct" -ForegroundColor White
    Write-Host "  - Ensure you have access to the source site" -ForegroundColor White
    Write-Host "  - Check if the library name is correct`n" -ForegroundColor White
    exit 1
}

# Get source library
Write-Host "Getting source library information..." -ForegroundColor Yellow
try {
    $sourceList = Get-PnPList -Identity $SourceLibraryName -ErrorAction Stop
    $sourceLibraryUrl = $sourceList.RootFolder.ServerRelativeUrl
    Write-Host "✓ Library path: $sourceLibraryUrl`n" -ForegroundColor Green
}
catch {
    Write-Host "✗ Could not find library '$SourceLibraryName'" -ForegroundColor Red
    Write-Host "`nAvailable libraries:" -ForegroundColor Yellow
    Get-PnPList | Where-Object { $_.BaseTemplate -eq 101 } | ForEach-Object {
        Write-Host "  - $($_.Title)" -ForegroundColor Gray
    }
    exit 1
}

# Read all folders and their Resource Type values
Write-Host "Reading folders and Resource Type values..." -ForegroundColor Yellow
$sourceItems = Get-PnPListItem -List $sourceList -PageSize 5000 -Fields "FileLeafRef", "FileRef", "FSObjType", "FileDirRef", "Resource_x0020_Type"

# Find all root-level folders (Video folders)
$sourceFolders = $sourceItems | Where-Object {
    $_.FieldValues.FSObjType -eq 1 -and
    $_.FieldValues.FileDirRef -eq $sourceLibraryUrl
}

Write-Host "✓ Found $($sourceFolders.Count) video folders in source library`n" -ForegroundColor Green

# Build mapping: FolderName → Resource Type
$resourceTypeMapping = @{}
$mappingStats = @{
    WithResourceType = 0
    WithoutResourceType = 0
    Duplicates = 0
}

Write-Host "Building Resource Type mapping..." -ForegroundColor Yellow

foreach ($folder in $sourceFolders) {
    $folderName = $folder.FieldValues.FileLeafRef
    $resourceType = $folder.FieldValues.Resource_x0020_Type

    if ($resourceType) {
        if ($resourceTypeMapping.ContainsKey($folderName)) {
            Write-Host "  ⚠️  Duplicate folder name: $folderName" -ForegroundColor Yellow
            $mappingStats.Duplicates++
        }
        else {
            $resourceTypeMapping[$folderName] = $resourceType
            $mappingStats.WithResourceType++
        }
    }
    else {
        Write-Host "  ⚠️  No Resource Type: $folderName" -ForegroundColor Yellow
        $mappingStats.WithoutResourceType++
    }
}

Write-Host "`nMapping Summary:" -ForegroundColor Cyan
Write-Host "  Folders with Resource Type: $($mappingStats.WithResourceType)" -ForegroundColor Green
Write-Host "  Folders without Resource Type: $($mappingStats.WithoutResourceType)" -ForegroundColor $(if ($mappingStats.WithoutResourceType -gt 0) { 'Yellow' } else { 'Gray' })
Write-Host "  Duplicate folder names: $($mappingStats.Duplicates)" -ForegroundColor $(if ($mappingStats.Duplicates -gt 0) { 'Yellow' } else { 'Gray' })

if ($resourceTypeMapping.Count -eq 0) {
    Write-Host "`n✗ No Resource Type data found in source library!" -ForegroundColor Red
    Write-Host "  Cannot proceed with migration.`n" -ForegroundColor Red
    exit 1
}

# Show sample mapping
Write-Host "`nSample mappings (first 5):" -ForegroundColor Cyan
$resourceTypeMapping.GetEnumerator() | Select-Object -First 5 | ForEach-Object {
    Write-Host "  $($_.Key) → $($_.Value)" -ForegroundColor Gray
}

# Export mapping to CSV for reference
$mappingExportPath = "C:\Temp\CRM_ResourceType_Mapping_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
$resourceTypeMapping.GetEnumerator() | ForEach-Object {
    [PSCustomObject]@{
        FolderName = $_.Key
        ResourceType = $_.Value
    }
} | Export-Csv $mappingExportPath -NoTypeInformation

Write-Host "`n✓ Mapping exported to: $mappingExportPath" -ForegroundColor Green

# ============================================
# PHASE 2: MIGRATE DESTINATION LIBRARY
# ============================================

Write-Host "`n`n============================================" -ForegroundColor Cyan
Write-Host "PHASE 2: Migrating DESTINATION library" -ForegroundColor Cyan
Write-Host "------------------------------------------------------------`n" -ForegroundColor Cyan

Write-Host "Connecting to DESTINATION library..." -ForegroundColor Yellow
Write-Host "  Site: $DestinationSiteUrl" -ForegroundColor Gray
Write-Host "  Library: $DestinationLibraryName`n" -ForegroundColor Gray

try {
    Connect-PnPOnline -Url $DestinationSiteUrl -ClientId $ClientId -Interactive
    Write-Host "✓ Connected to destination library`n" -ForegroundColor Green
}
catch {
    Write-Host "✗ Connection failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Get destination library
Write-Host "Getting destination library information..." -ForegroundColor Yellow
try {
    $destList = Get-PnPList -Identity $DestinationLibraryName -ErrorAction Stop
    $destLibraryUrl = $destList.RootFolder.ServerRelativeUrl
    Write-Host "✓ Library path: $destLibraryUrl`n" -ForegroundColor Green
}
catch {
    Write-Host "✗ Could not find library '$DestinationLibraryName'" -ForegroundColor Red
    Write-Host "`nAvailable libraries:" -ForegroundColor Yellow
    Get-PnPList | Where-Object { $_.BaseTemplate -eq 101 } | ForEach-Object {
        Write-Host "  - $($_.Title)" -ForegroundColor Gray
    }
    exit 1
}

# Check if Resource Type field exists, create if needed
Write-Host "Checking Resource Type field..." -ForegroundColor Yellow

try {
    $resourceTypeField = Get-PnPField -List $destList -Identity "Resource_x0020_Type" -ErrorAction Stop
    Write-Host "✓ Resource Type field exists: $($resourceTypeField.Title)" -ForegroundColor Green
    Write-Host "  Internal name: $($resourceTypeField.InternalName)" -ForegroundColor Gray
    Write-Host "  Type: $($resourceTypeField.TypeAsString)`n" -ForegroundColor Gray
}
catch {
    Write-Host "⚠️  Resource Type field does not exist" -ForegroundColor Yellow
    Write-Host "  Creating new Choice field..." -ForegroundColor Yellow

    if (-not $WhatIf) {
        try {
            # Create the Resource Type field as Choice
            $choices = @("User Guides", "Simulations", "Role-based", "Trainings")

            Add-PnPField -List $destList -DisplayName "Resource Type" -InternalName "Resource_x0020_Type" -Type Choice -Choices $choices -AddToDefaultView

            Write-Host "✓ Resource Type field created successfully`n" -ForegroundColor Green
        }
        catch {
            Write-Host "✗ Failed to create field: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "`nYou may need to create this field manually:" -ForegroundColor Yellow
            Write-Host "  Field name: Resource Type" -ForegroundColor White
            Write-Host "  Internal name: Resource_x0020_Type" -ForegroundColor White
            Write-Host "  Type: Choice" -ForegroundColor White
            Write-Host "  Choices: User Guides, Simulations, Role-based, Trainings`n" -ForegroundColor White

            $continue = Read-Host "Continue anyway? (y/n)"
            if ($continue -ne 'y') {
                exit 1
            }
        }
    }
    else {
        Write-Host "  [WhatIf] Would create Resource Type field with choices:" -ForegroundColor Gray
        Write-Host "    - User Guides" -ForegroundColor Gray
        Write-Host "    - Simulations" -ForegroundColor Gray
        Write-Host "    - Role-based" -ForegroundColor Gray
        Write-Host "    - Trainings`n" -ForegroundColor Gray
    }
}

# Get all items from destination library
Write-Host "Retrieving all items from destination library..." -ForegroundColor Yellow
$destItems = Get-PnPListItem -List $destList -PageSize 5000 -Fields "FileLeafRef", "FileRef", "FSObjType", "FileDirRef", "Resource_x0020_Type"
Write-Host "✓ Retrieved $($destItems.Count) total items`n" -ForegroundColor Green

# Find root-level folders in destination
$destFolders = $destItems | Where-Object {
    $_.FieldValues.FSObjType -eq 1 -and
    $_.FieldValues.FileDirRef -eq $destLibraryUrl
}

Write-Host "Found $($destFolders.Count) folders to process`n" -ForegroundColor Cyan

# Statistics tracking
$stats = @{
    FoldersProcessed = 0
    VideosMoved = 0
    VideosUpdated = 0
    VideosSkipped = 0
    FoldersDeleted = 0
    MappingFound = 0
    MappingNotFound = 0
    Errors = 0
}

$movedFiles = @()
$errors = @()

# ============================================
# PHASE 3: PROCESS FOLDERS AND MOVE VIDEOS
# ============================================

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "PHASE 3: Processing folders and moving videos" -ForegroundColor Cyan
Write-Host "============================================`n" -ForegroundColor Cyan

foreach ($folder in $destFolders) {
    $folderPath = $folder.FieldValues.FileRef
    $folderName = $folder.FieldValues.FileLeafRef

    $stats.FoldersProcessed++

    Write-Host "[$($stats.FoldersProcessed)/$($destFolders.Count)] Folder: $folderName" -ForegroundColor Cyan

    # Look up Resource Type from source mapping
    $mappedResourceType = $resourceTypeMapping[$folderName]

    if ($mappedResourceType) {
        Write-Host "  ✓ Resource Type (from source): $mappedResourceType" -ForegroundColor Green
        $stats.MappingFound++
    }
    else {
        Write-Host "  ⚠️  No Resource Type mapping found for this folder" -ForegroundColor Yellow
        $stats.MappingNotFound++

        $errors += [PSCustomObject]@{
            Folder = $folderName
            Issue = "No Resource Type mapping found in source library"
            Action = "Manual review needed"
        }
    }

    # Find video files in this folder (including subfolders)
    $filesInFolder = $destItems | Where-Object {
        $_.FieldValues.FSObjType -eq 0 -and
        $_.FieldValues.FileRef -like "$folderPath/*" -and
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
        $targetUrl = "$destLibraryUrl/$targetFileName"

        $existingFile = $destItems | Where-Object {
            $_.FieldValues.FileRef -eq $targetUrl -and
            $_.FieldValues.FSObjType -eq 0
        }

        if ($existingFile -and $existingFile.Id -ne $fileItem.Id) {
            # Different file with same name exists - rename needed
            $nameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
            $extension = [System.IO.Path]::GetExtension($fileName)
            $targetFileName = "$nameWithoutExt - $folderName$extension"
            $targetUrl = "$destLibraryUrl/$targetFileName"

            Write-Host "      ⚠️  Name collision - renaming to: $targetFileName" -ForegroundColor Yellow
        }
        elseif ($existingFile -and $existingFile.Id -eq $fileItem.Id) {
            Write-Host "      ✓ Already at library root (skipping move)" -ForegroundColor Gray
            $stats.VideosSkipped++

            # Still update metadata if missing and we have a mapping
            if ($mappedResourceType -and -not $existingFile.FieldValues.Resource_x0020_Type) {
                Write-Host "      → Updating Resource Type..." -ForegroundColor Yellow

                if (-not $WhatIf) {
                    try {
                        Set-PnPListItem -List $destList -Identity $existingFile.Id -Values @{
                            "Resource_x0020_Type" = $mappedResourceType
                        } -UpdateType SystemUpdate

                        Write-Host "      ✓ Resource Type updated to: $mappedResourceType" -ForegroundColor Green
                        $stats.VideosUpdated++
                    }
                    catch {
                        Write-Host "      ✗ Failed to update: $($_.Exception.Message)" -ForegroundColor Red
                        $stats.Errors++
                    }
                }
                else {
                    Write-Host "      [WhatIf] Would set Resource Type to: $mappedResourceType" -ForegroundColor Gray
                }
            }
            continue
        }

        # Move the file
        Write-Host "      → Moving to library root..." -ForegroundColor Gray

        if (-not $WhatIf) {
            try {
                Move-PnPFile -SourceUrl $sourceUrl -TargetUrl $targetUrl -Force -ErrorAction Stop
                Write-Host "      ✓ Moved successfully" -ForegroundColor Green
                $stats.VideosMoved++

                # Update Resource Type if we have a mapping
                if ($mappedResourceType) {
                    Write-Host "      → Setting Resource Type: $mappedResourceType" -ForegroundColor Gray

                    try {
                        # Brief pause to ensure file is indexed
                        Start-Sleep -Milliseconds 500
                        $movedFile = Get-PnPFile -Url $targetUrl -AsListItem

                        Set-PnPListItem -List $destList -Identity $movedFile.Id -Values @{
                            "Resource_x0020_Type" = $mappedResourceType
                        } -UpdateType SystemUpdate

                        Write-Host "      ✓ Resource Type set" -ForegroundColor Green
                        $stats.VideosUpdated++
                    }
                    catch {
                        Write-Host "      ⚠️  Move succeeded but Resource Type update failed" -ForegroundColor Yellow
                        Write-Host "         Error: $($_.Exception.Message)" -ForegroundColor Gray

                        $errors += [PSCustomObject]@{
                            Folder = $folderName
                            File = $fileName
                            Issue = "Resource Type update failed: $($_.Exception.Message)"
                            Action = "Manual update needed"
                        }
                        $stats.Errors++
                    }
                }

                $movedFiles += [PSCustomObject]@{
                    OriginalFolder = $folderName
                    OriginalFileName = $fileName
                    NewFileName = $targetFileName
                    ResourceType = $mappedResourceType
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
            if ($mappedResourceType) {
                Write-Host "      [WhatIf] Would set Resource Type: $mappedResourceType" -ForegroundColor Gray
            }
        }
    }

    # Delete the folder after processing (if not in WhatIf mode)
    if ($filesInFolder.Count -gt 0 -and -not $WhatIf) {
        Write-Host "`n  → Checking if folder is empty..." -ForegroundColor Yellow

        try {
            # Check if folder is empty (all videos moved out)
            $remainingItems = Get-PnPFolderItem -FolderSiteRelativeUrl $folder.FieldValues.FileRef.Replace($destLibraryUrl + "/", "") -ErrorAction Stop

            if ($remainingItems.Count -eq 0) {
                Write-Host "  → Deleting empty folder..." -ForegroundColor Yellow

                $folderItem = Get-PnPListItem -List $destList -Id $folder.Id
                $folderItem.DeleteObject()
                Invoke-PnPQuery

                Write-Host "  ✓ Folder deleted`n" -ForegroundColor Green
                $stats.FoldersDeleted++
            }
            else {
                Write-Host "  ⚠️  Folder still contains $($remainingItems.Count) item(s)" -ForegroundColor Yellow
                Write-Host "     (May contain subfolders - you may need to delete manually)`n" -ForegroundColor Gray
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
Write-Host "  Resource Type mappings found: $($stats.MappingFound)" -ForegroundColor $(if ($stats.MappingFound -gt 0) { 'Green' } else { 'Gray' })
Write-Host "  Resource Type mappings NOT found: $($stats.MappingNotFound)" -ForegroundColor $(if ($stats.MappingNotFound -gt 0) { 'Yellow' } else { 'Gray' })
Write-Host "  Videos moved: $($stats.VideosMoved)" -ForegroundColor $(if ($stats.VideosMoved -gt 0) { 'Green' } else { 'Gray' })
Write-Host "  Videos updated (metadata): $($stats.VideosUpdated)" -ForegroundColor $(if ($stats.VideosUpdated -gt 0) { 'Green' } else { 'Gray' })
Write-Host "  Videos skipped (already at root): $($stats.VideosSkipped)" -ForegroundColor Gray
Write-Host "  Folders deleted: $($stats.FoldersDeleted)" -ForegroundColor $(if ($stats.FoldersDeleted -gt 0) { 'Green' } else { 'Gray' })
Write-Host "  Errors: $($stats.Errors)" -ForegroundColor $(if ($stats.Errors -gt 0) { 'Red' } else { 'Green' })

# Export moved files report
if ($movedFiles.Count -gt 0 -and -not $WhatIf) {
    Write-Host "`n--- Moved Files (first 10) ---" -ForegroundColor Cyan

    $movedFiles | Select-Object -First 10 | ForEach-Object {
        Write-Host "  ✓ [$($_.OriginalFolder)] $($_.OriginalFileName)" -ForegroundColor Green
        if ($_.ResourceType) {
            Write-Host "    → Resource Type: $($_.ResourceType)" -ForegroundColor Gray
        }
    }

    if ($movedFiles.Count -gt 10) {
        Write-Host "  ... and $($movedFiles.Count - 10) more" -ForegroundColor Gray
    }

    $reportPath = "C:\Temp\CRM_Video_Migration_Report_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    $movedFiles | Export-Csv $reportPath -NoTypeInformation
    Write-Host "`n✓ Full migration report: $reportPath" -ForegroundColor Cyan
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
Write-Host "  1. Review the mapping CSV to verify Resource Types" -ForegroundColor White
Write-Host "  2. Check videos at library root in browser" -ForegroundColor White
Write-Host "  3. Verify Resource Type column values are correct" -ForegroundColor White
Write-Host "  4. Test video playback and Replace functionality" -ForegroundColor White

if ($destFolders.Count -gt 0 -and $stats.FoldersDeleted -lt $destFolders.Count) {
    Write-Host "  5. Review and manually delete any remaining folders" -ForegroundColor White
}

if ($stats.MappingNotFound -gt 0) {
    Write-Host "`n⚠️  WARNING: $($stats.MappingNotFound) folder(s) had no Resource Type mapping" -ForegroundColor Yellow
    Write-Host "   Review the errors CSV and update these manually" -ForegroundColor Yellow
}

if ($WhatIf) {
    Write-Host "`n⚠️  THIS WAS A PREVIEW - NO CHANGES WERE MADE" -ForegroundColor Yellow
    Write-Host "   Run without -WhatIf to execute the migration" -ForegroundColor Yellow
}

Write-Host "`n✓ Migration script completed" -ForegroundColor Green
Write-Host "============================================`n" -ForegroundColor Cyan
