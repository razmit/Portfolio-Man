# ========================================
# Mass Add People to SharePoint Permission Groups
# ========================================
# This script adds users to SharePoint site permission groups
# Input: Excel file OR manual entry
# Output: Summary of additions with success/failure status
# ========================================

Import-Module -Name ImportExcel

# ========================================
# Configuration
# ========================================
$clientId = "CLIENT_ID"
$tenantUrl = "https://companynet.sharepoint.com"

# Define target groups (can be modified as needed)
$targetGroups = @("National Tax PMO Owners", "Tax Services Project Owners")

# Initialize result tracking
$results = @()
$totalAttempts = 0
$successfulAdds = 0
$skippedUsers = 0
$failedAdds = 0

# ========================================
# Functions
# ========================================

function Show-Menu {
    Clear-Host
    $menu = @'

+----------------------------------------------------------+
|                                                          |
|     Mass Add People to SharePoint Permission Groups     |
|                                                          |
+----------------------------------------------------------+
|                                                          |
|  [1] Import from Excel file                             |
|  [2] Manual entry (Terminal)                            |
|  [Exit] Quit the script                                 |
|                                                          |
+----------------------------------------------------------+

'@
    Write-Host $menu -ForegroundColor Cyan
}

function Get-ExcelData {
    Write-Host "`nExcel Import Mode" -ForegroundColor Cyan
    Write-Host "=================" -ForegroundColor Cyan

    $excelPath = Read-Host "`nEnter the full path to your Excel file"

    if (-not (Test-Path $excelPath)) {
        Write-Host "✗ File not found: $excelPath" -ForegroundColor Red
        return $null
    }

    try {
        # Open Excel package to access hyperlinks
        $excelPackage = Open-ExcelPackage -Path $excelPath

        # Debug: Show worksheet information
        Write-Host "`nWorkbook Information:" -ForegroundColor Cyan
        Write-Host "  Total worksheets: $($excelPackage.Workbook.Worksheets.Count)" -ForegroundColor Gray

        for ($i = 0; $i -lt $excelPackage.Workbook.Worksheets.Count; $i++) {
            $ws = $excelPackage.Workbook.Worksheets[$i]
            $wsName = $ws.Name
            $wsDim = if ($ws.Dimension) { "$($ws.Dimension.Rows) rows x $($ws.Dimension.Columns) cols" } else { "No dimensions (empty)" }
            Write-Host "  [$i] '$wsName' - $wsDim" -ForegroundColor Gray
        }

        # Try to find the worksheet with data
        $worksheet = $null
        $worksheetIndex = 0

        # First, try to find a worksheet named similar to the table
        foreach ($ws in $excelPackage.Workbook.Worksheets) {
            if ($ws.Dimension -ne $null -and $ws.Dimension.Rows -gt 0) {
                $worksheet = $ws
                Write-Host "`nUsing worksheet: '$($ws.Name)'" -ForegroundColor Green
                break
            }
            $worksheetIndex++
        }

        if ($null -eq $worksheet) {
            Write-Host "`n✗ No worksheet with data found in the Excel file" -ForegroundColor Red
            Close-ExcelPackage $excelPackage -NoSave
            return $null
        }

        # Get header row to find column indices
        $headers = @{}
        $columnCount = if ($worksheet.Dimension) { $worksheet.Dimension.Columns } else { 0 }
        $rowCount = if ($worksheet.Dimension) { $worksheet.Dimension.Rows } else { 0 }

        Write-Host "  Dimensions: $rowCount rows x $columnCount columns" -ForegroundColor Gray
        Write-Host "`nDetecting columns..." -ForegroundColor Gray
        for ($col = 1; $col -le $columnCount; $col++) {
            $headerValue = $worksheet.Cells[1, $col].Value
            if ($headerValue) {
                # Trim spaces for cleaner matching
                $cleanHeader = $headerValue.ToString().Trim()
                $headers[$cleanHeader] = $col
                Write-Host "  Column $col : '$cleanHeader'" -ForegroundColor Gray
            }
        }

        Write-Host "`nFound $($headers.Count) column(s)" -ForegroundColor Gray
        Write-Host ""

        # Find required columns (case-insensitive)
        $siteUrlCol = $null
        $newUsersCol = $null

        foreach ($key in $headers.Keys) {
            if ($key -match "^Site\s*URL$" -or $key -eq "Site URL") {
                $siteUrlCol = $headers[$key]
                Write-Host "✓ Found Site URL column: $key" -ForegroundColor Green
            }
            if ($key -match "^New\s*Users?$" -or $key -eq "New Users" -or $key -eq "New User") {
                $newUsersCol = $headers[$key]
                Write-Host "✓ Found New Users column: $key" -ForegroundColor Green
            }
        }

        # Validate required columns were found
        if ($null -eq $newUsersCol) {
            Write-Host "`n✗ Excel file must contain a 'New Users' or 'New User' column" -ForegroundColor Red
            Close-ExcelPackage $excelPackage -NoSave
            return $null
        }

        if ($null -eq $siteUrlCol) {
            Write-Host "`n✗ Excel file must contain a 'Site URL' column" -ForegroundColor Red
            Close-ExcelPackage $excelPackage -NoSave
            return $null
        }

        # Extract data with hyperlinks
        $excelData = @()

        for ($row = 2; $row -le $rowCount; $row++) {
            $siteUrlCell = $worksheet.Cells[$row, $siteUrlCol]
            $userEmailCell = $worksheet.Cells[$row, $newUsersCol]

            # Extract actual URL from hyperlink if it exists, otherwise use cell value
            $siteUrl = if ($siteUrlCell.Hyperlink) {
                $siteUrlCell.Hyperlink.AbsoluteUri
            } else {
                $siteUrlCell.Value
            }

            $userEmail = if ($userEmailCell.Hyperlink) {
                $userEmailCell.Hyperlink.AbsoluteUri
            } else {
                $userEmailCell.Value
            }

            # Skip empty rows
            if ([string]::IsNullOrWhiteSpace($siteUrl) -and [string]::IsNullOrWhiteSpace($userEmail)) {
                continue
            }

            $excelData += [PSCustomObject]@{
                "Site URL" = $siteUrl
                "New Users" = $userEmail
            }
        }

        Close-ExcelPackage $excelPackage -NoSave

        Write-Host "✓ Excel file loaded successfully" -ForegroundColor Green
        Write-Host "  Found $($excelData.Count) row(s) with hyperlinks properly extracted" -ForegroundColor Gray

        return $excelData

    } catch {
        Write-Host "✗ Error reading Excel file: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

function Get-ManualData {
    Write-Host "`nManual Entry Mode" -ForegroundColor Cyan
    Write-Host "=================" -ForegroundColor Cyan

    # Collect site URLs
    $siteUrls = @()
    Write-Host "`nEnter Site URLs (one at a time, press Enter with empty input to finish):" -ForegroundColor Yellow

    $counter = 1
    do {
        $url = Read-Host "  Site URL #$counter"
        if ($url.Trim() -ne "") {
            $siteUrls += $url.Trim()
            Write-Host "    ✓ Added: $url" -ForegroundColor Green
            $counter++
        }
    } while ($url.Trim() -ne "")

    if ($siteUrls.Count -eq 0) {
        Write-Host "✗ No site URLs entered" -ForegroundColor Red
        return $null
    }

    # Collect user emails
    $userEmails = @()
    Write-Host "`nEnter User Emails (one at a time, press Enter with empty input to finish):" -ForegroundColor Yellow

    $counter = 1
    do {
        $email = Read-Host "  User Email #$counter"
        if ($email.Trim() -ne "") {
            $userEmails += $email.Trim()
            Write-Host "    ✓ Added: $email" -ForegroundColor Green
            $counter++
        }
    } while ($email.Trim() -ne "")

    if ($userEmails.Count -eq 0) {
        Write-Host "✗ No user emails entered" -ForegroundColor Red
        return $null
    }

    # Create data structure matching Excel format
    $manualData = @()
    foreach ($url in $siteUrls) {
        foreach ($email in $userEmails) {
            $manualData += [PSCustomObject]@{
                "Site URL" = $url
                "New Users" = $email
            }
        }
    }

    Write-Host "`n✓ Manual data prepared: $($siteUrls.Count) site(s) x $($userEmails.Count) user(s) = $($manualData.Count) operation(s)" -ForegroundColor Green

    return $manualData
}

function Clean-SharePointUrl {
    param([string]$url)

    # Remove common SharePoint page paths to get the root site URL
    # Patterns to remove: /pages/, /SitePages/, /Lists/, /Shared Documents/, /_layouts/, etc.
    $cleanedUrl = $url -replace '/pages/.*$', '' `
                       -replace '/SitePages/.*$', '' `
                       -replace '/Lists/.*$', '' `
                       -replace '/Shared%20Documents/.*$', '' `
                       -replace '/_layouts/.*$', '' `
                       -replace '/Forms/.*$', '' `
                       -replace '\.aspx.*$', ''

    # Remove trailing slashes
    $cleanedUrl = $cleanedUrl.TrimEnd('/')

    return $cleanedUrl
}

function Process-UserAdditions {
    param([array]$data)

    if ($null -eq $data -or $data.Count -eq 0) {
        Write-Host "`n✗ No data to process" -ForegroundColor Red
        return
    }

    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Processing User Additions" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Total operations to perform: $($data.Count)" -ForegroundColor Gray
    Write-Host ""

    # Group data by site URL for efficient processing
    $groupedBySite = $data | Group-Object -Property "Site URL"

    foreach ($siteGroup in $groupedBySite) {
        $rawSiteUrl = $siteGroup.Name

        # Clean the URL to remove page paths
        $siteUrl = Clean-SharePointUrl -url $rawSiteUrl

        # Validate URL format (in case it's just a site name)
        if ($siteUrl -notmatch "^https://") {
            $siteUrl = "$tenantUrl/sites/$siteUrl"
        }

        Write-Host "`n----------------------------------------" -ForegroundColor Cyan
        if ($rawSiteUrl -ne $siteUrl) {
            Write-Host "Original URL: $rawSiteUrl" -ForegroundColor Gray
            Write-Host "Cleaned to: $siteUrl" -ForegroundColor Yellow
        } else {
            Write-Host "Site: $siteUrl" -ForegroundColor Cyan
        }
        Write-Host "----------------------------------------" -ForegroundColor Cyan

        # Connect to the site
        try {
            Write-Host "Connecting to site..." -ForegroundColor Gray
            Connect-PnPOnline -Url $siteUrl -ClientId $clientId -Interactive
            Write-Host "✓ Connected successfully" -ForegroundColor Green
        } catch {
            Write-Host "✗ Failed to connect: $($_.Exception.Message)" -ForegroundColor Red

            # Mark all users for this site as failed
            foreach ($row in $siteGroup.Group) {
                $script:totalAttempts++
                $script:failedAdds++
                $script:results += [PSCustomObject]@{
                    Site = $siteUrl
                    User = $row.'New Users'
                    Status = "Failed - Connection Error"
                    Message = $_.Exception.Message
                }
            }
            continue
        }

        # Process each target group
        foreach ($groupName in $targetGroups) {
            Write-Host "`n  Target Group: $groupName" -ForegroundColor Yellow

            # Verify group exists
            try {
                $group = Get-PnPGroup -Identity $groupName -ErrorAction Stop
                Write-Host "  ✓ Group found" -ForegroundColor Green
            } catch {
                Write-Host "  ✗ Group '$groupName' not found on this site - skipping" -ForegroundColor Red
                continue
            }

            # Get current group members
            try {
                $groupMembers = Get-PnPGroupMember -Identity $groupName
            } catch {
                Write-Host "  ✗ Failed to retrieve group members: $($_.Exception.Message)" -ForegroundColor Red
                continue
            }

            # Add each user
            foreach ($row in $siteGroup.Group) {
                $userEmail = $row.'New Users'

                if ([string]::IsNullOrWhiteSpace($userEmail)) {
                    continue
                }

                $script:totalAttempts++

                Write-Host "`n    Processing user: $userEmail" -ForegroundColor Gray

                # Check if user already exists in group
                $userExists = $groupMembers | Where-Object { $_.Email -eq $userEmail }

                if ($userExists) {
                    Write-Host "    ⊘ User already in group - skipping" -ForegroundColor Yellow
                    $script:skippedUsers++
                    $script:results += [PSCustomObject]@{
                        Site = $siteUrl
                        Group = $groupName
                        User = $userEmail
                        Status = "Skipped"
                        Message = "User already in group"
                    }
                } else {
                    # Add user to group
                    try {
                        Add-PnPGroupMember -Identity $groupName -EmailAddress $userEmail
                        Write-Host "    ✓ User added successfully to $groupName" -ForegroundColor Green
                        $script:successfulAdds++
                        $script:results += [PSCustomObject]@{
                            Site = $siteUrl
                            Group = $groupName
                            User = $userEmail
                            Status = "Success"
                            Message = "Added successfully"
                        }
                    } catch {
                        Write-Host "    ✗ Failed to add user: $($_.Exception.Message)" -ForegroundColor Red
                        $script:failedAdds++
                        $script:results += [PSCustomObject]@{
                            Site = $siteUrl
                            Group = $groupName
                            User = $userEmail
                            Status = "Failed"
                            Message = $_.Exception.Message
                        }
                    }
                }
            }
        }
    }
}

function Show-Summary {
    Write-Host "`n`n========================================" -ForegroundColor Cyan
    Write-Host "SUMMARY REPORT" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    Write-Host "`nTotal Operations:    $totalAttempts" -ForegroundColor White
    Write-Host "✓ Successful Adds:   $successfulAdds" -ForegroundColor Green
    Write-Host "⊘ Skipped (Existing): $skippedUsers" -ForegroundColor Yellow
    Write-Host "✗ Failed:            $failedAdds" -ForegroundColor Red

    # Show detailed results
    if ($results.Count -gt 0) {
        Write-Host "`n----------------------------------------" -ForegroundColor Cyan
        Write-Host "Detailed Results:" -ForegroundColor Cyan
        Write-Host "----------------------------------------" -ForegroundColor Cyan

        $results | Format-Table -Property Site, Group, User, Status, Message -AutoSize
    }

    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Script completed!" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
}

# ========================================
# Main Script Execution
# ========================================

Show-Menu

$choice = Read-Host "Select an option [1, 2, or Exit]"

switch ($choice.ToLower()) {
    "1" {
        # Excel Import Mode
        $data = Get-ExcelData
        if ($null -ne $data) {
            Process-UserAdditions -data $data
            Show-Summary
        }
    }
    "2" {
        # Manual Entry Mode
        $data = Get-ManualData
        if ($null -ne $data) {
            Process-UserAdditions -data $data
            Show-Summary
        }
    }
    "exit" {
        Write-Host "`nExiting script. Goodbye!" -ForegroundColor Yellow
        exit
    }
    default {
        Write-Host "`n✗ Invalid option. Please run the script again." -ForegroundColor Red
    }
}
