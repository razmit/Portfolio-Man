# Configuration
$siteUrl = "https://companynet.sharepoint.com/sites/in_CRMResourceCenter"
Connect-PnPOnline -Url $siteUrl -clientId CLIENT_ID -interactive

$libraryName = "CRM Resource Library"
$oldColumnInternalName = "Focus_x0020_Area0"  # Old list column
$newColumnInternalName = "Focus_x0020_area"   # Site column (currently "CRM Resource Type")

Write-Host "=== Data Migration from List Column to Site Column ===" -ForegroundColor Cyan

# ===== STEP 1: Get Columns =====
$oldColumn = Get-PnPField -List $libraryName | Where-Object { $_.InternalName -eq $oldColumnInternalName }
$siteColumnInLibrary = Get-PnPField -List $libraryName | Where-Object { $_.InternalName -eq $newColumnInternalName }

Write-Host "`n[1] Column Information:"
Write-Host "  Source: '$($oldColumn.Title)' (list column)"
Write-Host "  Target: '$($siteColumnInLibrary.Title)' (site column)"

# ===== STEP 2: Analyze Mismatches =====
Write-Host "`n[2] Analyzing data differences..."

$items = Get-PnPListItem -List $libraryName -PageSize 5000

$analysis = @{
    Total       = $items.Count
    OldHasValue = 0
    NewHasValue = 0
    BothEmpty   = 0
    Matching    = 0
    OldOnly     = 0      # Old has value, new is empty
    NewOnly     = 0      # New has value, old is empty
    Different   = 0    # Both have values but different
}

$mismatches = @()

foreach ($item in $items) {
    $oldValue = $item[$oldColumnInternalName]
    $newValue = $item[$newColumnInternalName]
    
    $oldHasValue = ($oldValue -ne $null -and $oldValue -ne "")
    $newHasValue = ($newValue -ne $null -and $newValue -ne "")
    
    if ($oldHasValue) { $analysis.OldHasValue++ }
    if ($newHasValue) { $analysis.NewHasValue++ }
    
    if (-not $oldHasValue -and -not $newHasValue) {
        $analysis.BothEmpty++
    }
    elseif ($oldValue -eq $newValue) {
        $analysis.Matching++
    }
    elseif ($oldHasValue -and -not $newHasValue) {
        $analysis.OldOnly++
        $mismatches += [PSCustomObject]@{
            ItemId   = $item.Id
            FileName = $item["FileLeafRef"]
            OldValue = $oldValue
            NewValue = "(empty)"
            Action   = "Copy old → new"
        }
    }
    elseif (-not $oldHasValue -and $newHasValue) {
        $analysis.NewOnly++
        $mismatches += [PSCustomObject]@{
            ItemId   = $item.Id
            FileName = $item["FileLeafRef"]
            OldValue = "(empty)"
            NewValue = $newValue
            Action   = "Keep new (or manual review)"
        }
    }
    else {
        $analysis.Different++
        $mismatches += [PSCustomObject]@{
            ItemId   = $item.Id
            FileName = $item["FileLeafRef"]
            OldValue = $oldValue
            NewValue = $newValue
            Action   = "CONFLICT - needs review"
        }
    }
}

Write-Host "`nAnalysis Results:"
Write-Host "  Total items: $($analysis.Total)"
Write-Host "  Both empty: $($analysis.BothEmpty)"
Write-Host "  Matching values: $($analysis.Matching)" -ForegroundColor Green
Write-Host "  Old has value, new empty: $($analysis.OldOnly)" -ForegroundColor Yellow
Write-Host "  New has value, old empty: $($analysis.NewOnly)" -ForegroundColor Cyan
Write-Host "  Both have DIFFERENT values: $($analysis.Different)" -ForegroundColor Red

# ===== STEP 3: Export Mismatches =====
if ($mismatches.Count -gt 0) {
    $mismatchPath = "C:\temp\FocusArea_Mismatches_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    $mismatches | Export-Csv -Path $mismatchPath -NoTypeInformation
    Write-Host "`n⚠ Found $($mismatches.Count) mismatches"
    Write-Host "  Exported to: $mismatchPath"
    
    Write-Host "`nFirst 10 mismatches:"
    $mismatches | Select-Object -First 10 | Format-Table -AutoSize
}

# ===== STEP 4: Migration Strategy =====
Write-Host "`n[3] Migration Strategy:"

if ($analysis.Different -gt 0) {
    Write-Host "⚠ CONFLICT: Both columns have different values for some items" -ForegroundColor Red
    Write-Host "  Manual review required before proceeding."
    Write-Host "  Options:"
    Write-Host "    1. Always use old column value (overwrite new)"
    Write-Host "    2. Keep new column value where it differs"
    Write-Host "    3. Manual review each conflict"
    
    $strategy = Read-Host "`nChoose strategy (1/2/3)"
}
else {
    Write-Host "✓ No conflicts - safe to migrate" -ForegroundColor Green
    $strategy = "1"  # Default: copy from old
}

# ===== STEP 5: Execute Migration =====
Write-Host "`n[4] Executing migration..."

$confirm = Read-Host "Proceed with data migration? (Y/N)"

if ($confirm -ne "Y") {
    Write-Host "Migration cancelled." -ForegroundColor Yellow
    exit
}

$list = Get-PnPList -Identity $libraryName
$ctx = Get-PnPContext

$migratedCount = 0
$skippedCount = 0
$conflictCount = 0

foreach ($item in $items) {
    $oldValue = $item[$oldColumnInternalName]
    $newValue = $item[$newColumnInternalName]
    
    $oldHasValue = ($oldValue -ne $null -and $oldValue -ne "")
    $newHasValue = ($newValue -ne $null -and $newValue -ne "")
    
    try {
        $shouldUpdate = $false
        
        if ($strategy -eq "1") {
            # Always copy from old if old has value
            if ($oldHasValue) {
                $shouldUpdate = $true
                $valueToSet = $oldValue
            }
        }
        elseif ($strategy -eq "2") {
            # Only copy from old if new is empty
            if ($oldHasValue -and -not $newHasValue) {
                $shouldUpdate = $true
                $valueToSet = $oldValue
            }
        }
        elseif ($strategy -eq "3") {
            # Manual review - skip conflicts
            if ($oldHasValue -and $newHasValue -and $oldValue -ne $newValue) {
                $conflictCount++
                continue
            }
            elseif ($oldHasValue) {
                $shouldUpdate = $true
                $valueToSet = $oldValue
            }
        }
        
        if ($shouldUpdate) {
            $item[$newColumnInternalName] = $valueToSet
            $item.SystemUpdate()  # Preserves Modified/ModifiedBy
            $ctx.ExecuteQuery()
            $migratedCount++
            
            if ($migratedCount % 50 -eq 0) {
                Write-Host "  Migrated $migratedCount items..." -ForegroundColor Gray
            }
        }
        else {
            $skippedCount++
        }
    }
    catch {
        Write-Host "  ✗ Error on item $($item.Id): $_" -ForegroundColor Red
    }
}

Write-Host "`n✓ Migration complete!"
Write-Host "  Migrated: $migratedCount items"
Write-Host "  Skipped: $skippedCount items"
if ($conflictCount -gt 0) {
    Write-Host "  Conflicts (not migrated): $conflictCount items" -ForegroundColor Yellow
}

# ===== STEP 6: Verification =====
Write-Host "`n[5] Verifying migration..."

$verifyItems = Get-PnPListItem -List $libraryName -PageSize 10

$stillMismatched = 0
$verifyItems | ForEach-Object {
    $oldVal = $_[$oldColumnInternalName]
    $newVal = $_[$newColumnInternalName]
    
    if ($oldVal -and $newVal -and $oldVal -ne $newVal) {
        $stillMismatched++
    }
}

if ($stillMismatched -eq 0) {
    Write-Host "✓ Verification passed - no remaining mismatches in sample" -ForegroundColor Green
}
else {
    Write-Host "⚠ Still found $stillMismatched mismatches in sample" -ForegroundColor Yellow
}

# ===== STEP 7: Cleanup (Optional) =====
Write-Host "`n[6] Cleanup old column?"
Write-Host "⚠ This will DELETE the old 'Focus Area' list column" -ForegroundColor Red
$deleteConfirm = Read-Host "Type 'DELETE' to remove old column, or press Enter to skip"

if ($deleteConfirm -eq "DELETE") {
    try {
        Remove-PnPField -List $libraryName -Identity $oldColumn.Id -Force
        Write-Host "✓ Deleted old 'Focus Area' column" -ForegroundColor Green
    }
    catch {
        Write-Host "✗ Error deleting column: $_" -ForegroundColor Red
        exit
    }
}
else {
    Write-Host "⊘ Skipped column deletion" -ForegroundColor Yellow
    Write-Host "  You can delete manually later from Library Settings"
}

# ===== STEP 8: Rename to Match Site Column =====
if ($deleteConfirm -eq "DELETE") {
    Write-Host "`n[7] Renaming column to match site column..."
    
    try {
        Set-PnPField -List $libraryName -Identity $siteColumnInLibrary.Id -Values @{Title = "Focus area" }
        Write-Host "✓ Renamed to 'Focus area'" -ForegroundColor Green
        Write-Host "`n✓✓ COMPLETE! Column is now synced with site column definition." -ForegroundColor Green
    }
    catch {
        Write-Host "✗ Error renaming: $_" -ForegroundColor Red
    }
}

Write-Host "`n=== Migration Complete ===" -ForegroundColor Cyan
