# ============================================================================
# Mass create SharePoint sites based on a predefined list
# ============================================================================
# Purpose: Mass create SharePoint sites based on a predefined list so I don't have to create 30 sites manually
#
# Date: January 2026
# ============================================================================

# Get the Title from the source subsite to replicate it in the new subsite
function Get-SourceSubSiteInfo {
    param(
        [Parameter(Mandatory=$true)]
        [string]
        $SourceSiteUrl
    )
    
    try {
        Connect-PnPOnline -Url $SourceSiteUrl -clientId CLIENT_ID -interactive
        
        Write-Host "Connected to source subsite: $SourceSiteUrl" -ForegroundColor Green
    }
    catch {
        Write-Host "Error connecting to source subsite: $SourceSiteUrl" -ForegroundColor Red
        exit
    }
    
    try {
        # Get just the title of the source subsite
        $web = Get-PnPWeb -ErrorAction Stop
        $title = $web.Title
        return $title
    }
    catch {
        Write-Host "Error retrieving info for source subsite: $SourceSiteUrl" -ForegroundColor Red
        return $false
    }
    
}


function New-SubSite {
    param (
        [Parameter(Mandatory=$true)]
        [string[]]
        $SubSiteUrls,
        [Parameter(Mandatory=$true)]
        [string[]]
        $SubSiteTitles
    )
    
    $newParentSiteUrl = "https://companynet.sharepoint.com/sites/IWS_ORM_PCAOB_Inspections"
    
    Connect-PnPOnline -Url $newParentSiteUrl -clientId CLIENT_ID -interactive
    
    $i = 0
    # Create the new subsite
    try {
        foreach ($SubSiteUrl in $SubSiteUrls) {
            # Write-Host "Creating new subsite at URL: $newParentSiteUrl/$SubSiteUrl with title $($SubSiteTitles[$i])" -ForegroundColor Cyan
            
            New-PnPWeb -Title $SubSiteTitles[$i] -Url $SubSiteUrl -Template "STS#3" -Locale 1033 -ErrorAction SilentlyContinue
            Write-Host "+++ Successfully created new subsite: $newParentSiteUrl/$SubSiteUrl with title $($SubSiteTitles[$i])" -ForegroundColor Green
            Write-Host "-----------------------------------------" -ForegroundColor White
            $i++
        }
    }
    catch {
        Write-Host "XXX Failed creating the new subsite." -ForegroundColor Red
        continue
    }
}

# We load the file containing the sites to be created
$pathToFile = "C:\Users\E095713\Downloads\PCAOB_Mapping.xlsx"

# Get the data from the Excel file
$excelData = Import-Excel -Path $pathToFile -WorksheetName "Sheet1"

# $excelData | Select-Object 'Source', 'New URL of child site' -First 10 | Format-Table -AutoSize

# Name of column where the source site URLs are stored
$sourceTargetColumn = "Source"

# Name of column where the potential new site URLs are stored
$newSiteTargetColumn = "New URL of child site"

# Array to save all of the URLs for the new subsites
$newSubSiteUrls = @()

# Array to save all of the titles for the new subsites
$newSubSiteTitles = @()

$definedSubSitesCounter = 0

foreach ($row in $excelData) {
    $sourceSite = $row.$sourceTargetColumn
    $newSiteURL = $row.$newSiteTargetColumn
    
    if ($null -ne $newSiteURL) {
        # If there's an already set subsite URL
        $predefinidedNewSiteURL = $newSiteURL -split "/"
        $newSiteName = $predefinidedNewSiteURL[2]
        
        $returnedSourceSiteInfo = Get-SourceSubSiteInfo -SourceSiteUrl $sourceSite
        
        # Right now, the only subsite URL that is returning an error is the "PCAOBInspections/000" one as it appears to not exist anymore
        if (!$returnedSourceSiteInfo) {
            Write-Host "Skipping creation of new subsite due to error in retrieving source site info." -ForegroundColor Red
            continue
        }
        
        # Add the subsite URL to the array
        $newSubSiteUrls += $newSiteName
        
        # Add the title to the array
        $newSubSiteTitles += $returnedSourceSiteInfo
        
        $definedSubSitesCounter++
    } else {
        # If there's no predefined subsite URL, we can use the last segment of the source site URL
        $anchorSegment = "PCAOBInspections"
        
        # Split the URL by "/" and find everything after the anchor
        $urlParts = $sourceSite.TrimEnd('/') -split '/'
        $anchorIndex = $urlParts.IndexOf($anchorSegment)

        # Get all segments AFTER the anchor
        $segmentsAfterAnchor = $urlParts[($anchorIndex + 1)..($urlParts.Count - 1)]
        
        if ($segmentsAfterAnchor.Count -eq 0) {
            Write-Host "No segments found after anchor '$anchorSegment' in URL: $sourceSite. Skipping." -ForegroundColor Red
            continue
        } elseif ($segmentsAfterAnchor.Count -ge 2) {
            Write-Host "Multiple segments found after anchor '$anchorSegment': $($segmentsAfterAnchor -join '/'). Using only the first segment: $($segmentsAfterAnchor[0])" -ForegroundColor Yellow
            $newSiteName = $segmentsAfterAnchor[0]
        } else {
            $newSiteName = $segmentsAfterAnchor[0]
        }
        
        $returnedSourceSiteInfo = Get-SourceSubSiteInfo -SourceSiteUrl $sourceSite
        
        if (!$returnedSourceSiteInfo) {
            Write-Host "Skipping creation of new subsite due to error in retrieving source site info." -ForegroundColor Red
            continue
        }   
        
        # Add the subsite URL to the array
        $newSubSiteUrls += $newSiteName
        
        # Add the title to the array
        $newSubSiteTitles += $returnedSourceSiteInfo
    }
}

# Create the new subsites
New-SubSite -SubSiteUrls $newSubSiteUrls -SubSiteTitle $newSubSiteTitles


Write-Host "Total number of defined subsites: $definedSubSitesCounter" -ForegroundColor Yellow