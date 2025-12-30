Connect-pnpOnline -Url https://companynet.sharepoint.com/sites/IWS_TDMInternal/TDMArchives -clientId CLIENT_ID -interactive

$libraryName = "Course Document Sets"

# Logging just in case
$logFile = "C:\Temp\DocSetMove_Log.txt"
"Starting doc set move process - $(Get-Date)" | Out-File -FilePath $logFile 

# Get the library
$library = Get-PnPList -Identity $libraryName

Write-Host "======================================" -ForegroundColor Yellow
Write-Host "Doc Set Move Process Starting" -ForegroundColor Yellow
Write-Host "======================================" -ForegroundColor Yellow

# Retrieve ALL doc sets with Last Offered FY values (handling pagination)
Write-Host "`nRetrieving all doc sets with Last Offered FY values..." -ForegroundColor Cyan
$AllItems = Get-PnPListItem -List $LibraryName -PageSize 2000

Write-Host "Retrieved $($AllItems.Count) total items" -ForegroundColor Green

# Filter for items with FY values
Write-Host "Filtering for items with Last Offered FY values..." -ForegroundColor Cyan
$DocSetsWithFY = $AllItems | Where-Object { 
    $_.FieldValues.LastOfferedFY -ne $null -and 
    $_.FieldValues.LastOfferedFY -match '^FY\d{2}$'
}

Write-Host "Found $($DocSetsWithFY.Count) doc sets with FY values" -ForegroundColor Green
"Total doc sets with FY values: $($DocSetsWithFY.Count) - $(Get-Date)" | Out-File $LogFile -Append

# Counter for progress
$Counter = 0
$SuccessCount = 0
$ErrorCount = 0
$SkippedCount = 0
$AlreadyInPlaceCount = 0

Write-Host "`n======================================" -ForegroundColor Yellow
Write-Host "Beginning Move Operations" -ForegroundColor Yellow
Write-Host "======================================`n" -ForegroundColor Yellow

# Calculate estimated time
$EstimatedMinutes = [math]::Ceiling($DocSetsWithFY.Count / 100 * 5 / 60)
Write-Host "Estimated time: ~$EstimatedMinutes minutes (assuming no throttling)" -ForegroundColor Gray
Write-Host "Processing $($DocSetsWithFY.Count) doc sets...`n" -ForegroundColor Gray

foreach ($DocSet in $DocSetsWithFY) {
    $Counter++
    
    # Get the fiscal year value
    $FiscalYear = $DocSet["LastOfferedFY"]
    
    # Skip if no fiscal year or doesn't match pattern
    if ([string]::IsNullOrEmpty($FiscalYear) -or $FiscalYear -notmatch '^FY\d{2}$') {
        Write-Host "[$Counter/$($DocSetsWithFY.Count)] Skipping: $($DocSet['FileLeafRef']) - Invalid or missing FY value" -ForegroundColor Gray
        $SkippedCount++
        continue
    }
    
    try {
        # Get current file path
        $CurrentPath = $DocSet["FileRef"]
        $FileName = $DocSet["FileLeafRef"]
        
        # Build target folder path
        $TargetFolderPath = "$($Library.RootFolder.ServerRelativeUrl)/$FiscalYear"
        $NewPath = "$TargetFolderPath/$FileName"
        
        # Check if already in the correct folder
        if ($CurrentPath -like "*/$FiscalYear/*" -or $CurrentPath -eq $NewPath) {
            Write-Host "[$Counter/$($DocSetsWithFY.Count)] Already in correct location: $FileName ($FiscalYear)" -ForegroundColor DarkGreen
            $AlreadyInPlaceCount++
            continue
        }
        
        # Move the doc set
        Write-Host "[$Counter/$($DocSetsWithFY.Count)] Moving: $FileName to $FiscalYear folder..." -ForegroundColor Cyan
        Move-PnPFile -SourceUrl $CurrentPath -TargetUrl $NewPath -Force
        
        Write-Host "[$Counter/$($DocSetsWithFY.Count)] SUCCESS: Moved $FileName to $FiscalYear" -ForegroundColor Green
        "SUCCESS: $FileName moved to $FiscalYear - $(Get-Date)" | Out-File $LogFile -Append
        $SuccessCount++
        
        # Progress milestone reporting
        if ($Counter % 500 -eq 0) {
            $PercentComplete = [math]::Round(($Counter / $DocSetsWithFY.Count) * 100, 1)
            Write-Host "`n  === MILESTONE: $Counter/$($DocSetsWithFY.Count) processed ($PercentComplete%) ===" -ForegroundColor Magenta
            Write-Host "  Moved: $SuccessCount | Already in place: $AlreadyInPlaceCount | Errors: $ErrorCount`n" -ForegroundColor Magenta
        }
        
        # Throttle protection - pause every 100 items
        if ($Counter % 100 -eq 0) {
            Write-Host "  [Throttle Protection] Pausing for 5 seconds..." -ForegroundColor Yellow
            Start-Sleep -Seconds 5
        }
        
    }
    catch {
        Write-Host "[$Counter/$($DocSetsWithFY.Count)] ERROR: Failed to move $FileName - $($_.Exception.Message)" -ForegroundColor Red
        "ERROR: $FileName to $FiscalYear - $($_.Exception.Message) - $(Get-Date)" | Out-File $LogFile -Append
        $ErrorCount++
        
        # If we hit throttling errors, pause longer
        if ($_.Exception.Message -like "*throttled*" -or $_.Exception.Message -like "*429*") {
            Write-Host "  [THROTTLING DETECTED] Pausing for 60 seconds..." -ForegroundColor Red
            Start-Sleep -Seconds 60
        }
        # If file already exists at destination
        elseif ($_.Exception.Message -like "*already exists*") {
            Write-Host "  Note: File already exists at destination" -ForegroundColor Yellow
        }
    }
}

Write-Host "`n======================================" -ForegroundColor Yellow
Write-Host "FULL Process Complete!" -ForegroundColor Yellow
Write-Host "======================================" -ForegroundColor Yellow
Write-Host "Total Processed: $Counter" -ForegroundColor Cyan
Write-Host "Successfully Moved: $SuccessCount" -ForegroundColor Green
Write-Host "Already in Correct Location: $AlreadyInPlaceCount" -ForegroundColor DarkGreen
Write-Host "Errors: $ErrorCount" -ForegroundColor Red
Write-Host "Skipped (invalid FY): $SkippedCount" -ForegroundColor Gray
Write-Host "`nLog file: $LogFile" -ForegroundColor Cyan
Write-Host "======================================`n" -ForegroundColor Yellow

# Summary to log
"FULL process completed - $(Get-Date)" | Out-File $LogFile -Append
"Total Processed: $Counter" | Out-File $LogFile -Append
"Successfully Moved: $SuccessCount" | Out-File $LogFile -Append
"Already in Place: $AlreadyInPlaceCount" | Out-File $LogFile -Append
"Errors: $ErrorCount" | Out-File $LogFile -Append
"Skipped: $SkippedCount" | Out-File $LogFile -Append