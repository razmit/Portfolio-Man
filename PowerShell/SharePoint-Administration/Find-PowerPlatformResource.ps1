# Find-PowerPlatformResource.ps1
#
# Purpose: Locate Power Platform Canvas Apps or Cloud Flows across environments
#          Especially useful when users report issues but don't know where the resource is located
#
# Features:
#   - Search by name (partial match) or full URL
#   - Automatically extracts environment from URL
#   - Priority search: production environment first, then custom order
#   - Displays comprehensive resource information including suspension/error states
#
# Usage:
#   .\Find-PowerPlatformResource.ps1
#   .\Find-PowerPlatformResource.ps1 -ClientId "your-azure-app-id"
#
# Parameters:
#   -ClientId: (Optional) Azure AD app registration ID for authentication
#
# Requirements:
#   - Microsoft.PowerApps.Administration.PowerShell module
#   - Microsoft.PowerApps.PowerShell module
#   - Azure AD app registration with appropriate permissions

param(
    [Parameter(Mandatory=$false)]
    [string]$ClientId
)

# ============================================================================
# CONFIGURATION
# ============================================================================

# If ClientId not provided, use interactive login
$UseInteractive = [string]::IsNullOrEmpty($ClientId)

# ============================================================================
# BANNER
# ============================================================================

Clear-Host
Write-Host "`n╔════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     POWER PLATFORM RESOURCE LOCATOR                    ║" -ForegroundColor Cyan
Write-Host "║     Find Apps & Flows Across Environments              ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Write-SectionHeader {
    param([string]$Title)
    Write-Host "`n═══════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host " $Title" -ForegroundColor White
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
}

function Write-InfoLine {
    param([string]$Label, [string]$Value, [string]$Color = "White")
    $paddedLabel = $Label.PadRight(25)
    Write-Host "  $paddedLabel" -NoNewline -ForegroundColor DarkGray
    Write-Host $Value -ForegroundColor $Color
}

function Parse-PowerPlatformUrl {
    param([string]$Url)

    $result = @{
        IsValid = $false
        Type = $null
        EnvironmentId = $null
        ResourceId = $null
        ResourceName = $null
    }

    # Canvas App URL patterns:
    # https://apps.powerapps.com/play/e/{appId}?tenantId={tenantId}&source=...
    # https://apps.powerapps.com/play/{appId}?tenantId={tenantId}

    # Flow URL patterns:
    # https://make.powerapps.com/environments/{envId}/flows/{flowId}/details
    # https://make.powerautomate.com/environments/{envId}/flows/{flowId}/details

    if ($Url -match 'apps\.powerapps\.com/play.*/([a-f0-9\-]{36})') {
        $result.IsValid = $true
        $result.Type = "App"
        $result.ResourceId = $Matches[1]
    }
    elseif ($Url -match 'environments/([a-f0-9\-]{36})/flows/([a-f0-9\-]{36})') {
        $result.IsValid = $true
        $result.Type = "Flow"
        $result.EnvironmentId = $Matches[1]
        $result.ResourceId = $Matches[2]
    }
    elseif ($Url -match '(make\.powerapps|make\.powerautomate)\.com') {
        Write-Host "  ⚠ This appears to be a Power Platform URL, but the format isn't recognized" -ForegroundColor Yellow
        Write-Host "    Supported formats:" -ForegroundColor DarkGray
        Write-Host "      - Canvas Apps: https://apps.powerapps.com/play/.../appId" -ForegroundColor DarkGray
        Write-Host "      - Flows: https://make.powerautomate.com/environments/{envId}/flows/{flowId}" -ForegroundColor DarkGray
    }

    return $result
}

function Get-EnvironmentDisplayName {
    param([string]$EnvironmentId, [array]$Environments)

    $env = $Environments | Where-Object { $_.EnvironmentName -eq $EnvironmentId }
    if ($env) {
        return $env.DisplayName
    }
    return $EnvironmentId
}

function Search-CanvasApp {
    param(
        [string]$SearchTerm,
        [array]$EnvironmentIds,
        [array]$AllEnvironments,
        [string]$SpecificAppId = $null
    )

    $results = @()
    $envCount = 0
    $totalEnvs = $EnvironmentIds.Count

    foreach ($envId in $EnvironmentIds) {
        $envCount++
        $envName = Get-EnvironmentDisplayName -EnvironmentId $envId -Environments $AllEnvironments

        Write-Host "`r  [$envCount/$totalEnvs] Searching: $envName..." -NoNewline -ForegroundColor Cyan

        try {
            if ($SpecificAppId) {
                # Search for specific app by ID
                $app = Get-AdminPowerApp -AppName $SpecificAppId -EnvironmentName $envId -ErrorAction SilentlyContinue
                if ($app) {
                    $results += [PSCustomObject]@{
                        EnvironmentId = $envId
                        EnvironmentName = $envName
                        AppName = $app.AppName
                        DisplayName = $app.DisplayName
                        Owner = $app.Owner.displayName
                        OwnerEmail = $app.Owner.email
                        CreatedTime = $app.CreatedTime
                        LastModifiedTime = $app.LastModifiedTime
                        AppType = $app.Internal.properties.appType
                        State = if ($app.Internal.properties.lifecycleId -eq "Published") { "Published" } else { "Not Published" }
                        AppUrl = "https://apps.powerapps.com/play/$($app.AppName)"
                        EditUrl = "https://make.powerapps.com/environments/$envId/apps/$($app.AppName)/details"
                    }
                }
            }
            else {
                # Search by name (partial match)
                $apps = Get-AdminPowerApp -EnvironmentName $envId -ErrorAction SilentlyContinue
                $matchedApps = $apps | Where-Object { $_.DisplayName -like "*$SearchTerm*" }

                foreach ($app in $matchedApps) {
                    $results += [PSCustomObject]@{
                        EnvironmentId = $envId
                        EnvironmentName = $envName
                        AppName = $app.AppName
                        DisplayName = $app.DisplayName
                        Owner = $app.Owner.displayName
                        OwnerEmail = $app.Owner.email
                        CreatedTime = $app.CreatedTime
                        LastModifiedTime = $app.LastModifiedTime
                        AppType = $app.Internal.properties.appType
                        State = if ($app.Internal.properties.lifecycleId -eq "Published") { "Published" } else { "Not Published" }
                        AppUrl = "https://apps.powerapps.com/play/$($app.AppName)"
                        EditUrl = "https://make.powerapps.com/environments/$envId/apps/$($app.AppName)/details"
                    }
                }
            }
        }
        catch {
            # Silently continue if environment access fails
        }

        # If found and searching by ID, stop immediately
        if ($results.Count -gt 0 -and $SpecificAppId) {
            break
        }
    }

    Write-Host "`r" -NoNewline
    Write-Host ("  " + (" " * 100)) -NoNewline  # Clear the search line
    Write-Host "`r" -NoNewline

    return $results
}

function Search-CloudFlow {
    param(
        [string]$SearchTerm,
        [array]$EnvironmentIds,
        [array]$AllEnvironments,
        [string]$SpecificFlowId = $null
    )

    $results = @()
    $envCount = 0
    $totalEnvs = $EnvironmentIds.Count

    foreach ($envId in $EnvironmentIds) {
        $envCount++
        $envName = Get-EnvironmentDisplayName -EnvironmentId $envId -Environments $AllEnvironments

        Write-Host "`r  [$envCount/$totalEnvs] Searching: $envName..." -NoNewline -ForegroundColor Cyan

        try {
            if ($SpecificFlowId) {
                # Search for specific flow by ID
                $flow = Get-AdminFlow -FlowName $SpecificFlowId -EnvironmentName $envId -ErrorAction SilentlyContinue
                if ($flow) {
                    # Determine actual state
                    $flowState = "Unknown"
                    $stateColor = "Gray"

                    if ($flow.Internal.properties.state) {
                        $actualState = $flow.Internal.properties.state

                        if ($actualState -eq "Suspended") {
                            $flowState = "Suspended (Error)"
                            $stateColor = "Red"
                        }
                        elseif ($actualState -eq "Started" -and $flow.Enabled) {
                            $flowState = "Enabled"
                            $stateColor = "Green"
                        }
                        elseif ($actualState -eq "Stopped" -or -not $flow.Enabled) {
                            $flowState = "Disabled"
                            $stateColor = "Yellow"
                        }
                        else {
                            $flowState = $actualState
                            $stateColor = "White"
                        }
                    }
                    elseif ($flow.Enabled) {
                        $flowState = "Enabled"
                        $stateColor = "Green"
                    }
                    else {
                        $flowState = "Disabled"
                        $stateColor = "Yellow"
                    }

                    $results += [PSCustomObject]@{
                        EnvironmentId = $envId
                        EnvironmentName = $envName
                        FlowName = $flow.FlowName
                        DisplayName = $flow.DisplayName
                        Owner = $flow.CreatedBy.userPrincipalName
                        OwnerEmail = $flow.CreatedBy.email
                        CreatedTime = $flow.CreatedTime
                        LastModifiedTime = $flow.LastModifiedTime
                        State = $flowState
                        StateColor = $stateColor
                        TriggerType = $flow.Internal.properties.definitionSummary.triggers.PSObject.Properties.Name -join ", "
                        EditUrl = "https://make.powerautomate.com/environments/$envId/flows/$($flow.FlowName)/details"
                    }
                }
            }
            else {
                # Search by name (partial match)
                $flows = Get-AdminFlow -EnvironmentName $envId -ErrorAction SilentlyContinue
                $matchedFlows = $flows | Where-Object { $_.DisplayName -like "*$SearchTerm*" }

                foreach ($flow in $matchedFlows) {
                    # Determine actual state
                    $flowState = "Unknown"
                    $stateColor = "Gray"

                    if ($flow.Internal.properties.state) {
                        $actualState = $flow.Internal.properties.state

                        if ($actualState -eq "Suspended") {
                            $flowState = "Suspended (Error)"
                            $stateColor = "Red"
                        }
                        elseif ($actualState -eq "Started" -and $flow.Enabled) {
                            $flowState = "Enabled"
                            $stateColor = "Green"
                        }
                        elseif ($actualState -eq "Stopped" -or -not $flow.Enabled) {
                            $flowState = "Disabled"
                            $stateColor = "Yellow"
                        }
                        else {
                            $flowState = $actualState
                            $stateColor = "White"
                        }
                    }
                    elseif ($flow.Enabled) {
                        $flowState = "Enabled"
                        $stateColor = "Green"
                    }
                    else {
                        $flowState = "Disabled"
                        $stateColor = "Yellow"
                    }

                    $results += [PSCustomObject]@{
                        EnvironmentId = $envId
                        EnvironmentName = $envName
                        FlowName = $flow.FlowName
                        DisplayName = $flow.DisplayName
                        Owner = $flow.CreatedBy.userPrincipalName
                        OwnerEmail = $flow.CreatedBy.email
                        CreatedTime = $flow.CreatedTime
                        LastModifiedTime = $flow.LastModifiedTime
                        State = $flowState
                        StateColor = $stateColor
                        TriggerType = $flow.Internal.properties.definitionSummary.triggers.PSObject.Properties.Name -join ", "
                        EditUrl = "https://make.powerautomate.com/environments/$envId/flows/$($flow.FlowName)/details"
                    }
                }
            }
        }
        catch {
            # Silently continue if environment access fails
        }

        # If found and searching by ID, stop immediately
        if ($results.Count -gt 0 -and $SpecificFlowId) {
            break
        }
    }

    Write-Host "`r" -NoNewline
    Write-Host ("  " + (" " * 100)) -NoNewline  # Clear the search line
    Write-Host "`r" -NoNewline

    return $results
}

# ============================================================================
# AUTHENTICATION
# ============================================================================

Write-SectionHeader "AUTHENTICATION"

try {
    Import-Module Microsoft.PowerApps.Administration.PowerShell -ErrorAction Stop -WarningAction SilentlyContinue
    Import-Module Microsoft.PowerApps.PowerShell -ErrorAction Stop -WarningAction SilentlyContinue

    if ($UseInteractive) {
        Write-Host "  Authenticating with interactive login..." -ForegroundColor Yellow
        Add-PowerAppsAccount -ErrorAction Stop | Out-Null
    }
    else {
        Write-Host "  Authenticating with ClientId: $ClientId..." -ForegroundColor Yellow
        Add-PowerAppsAccount -ApplicationId $ClientId -ErrorAction Stop | Out-Null
    }

    Write-Host "  ✓ Authentication successful!" -ForegroundColor Green
}
catch {
    Write-Host "  ✗ Authentication failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "`nExiting...`n" -ForegroundColor Red
    exit 1
}

# ============================================================================
# GET ALL ENVIRONMENTS
# ============================================================================

Write-SectionHeader "LOADING ENVIRONMENTS"

Write-Host "  Retrieving environments..." -ForegroundColor Yellow

try {
    $allEnvironments = Get-AdminPowerAppEnvironment -ErrorAction Stop
    Write-Host "  ✓ Found $($allEnvironments.Count) environment(s)" -ForegroundColor Green
}
catch {
    Write-Host "  ✗ Failed to retrieve environments: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "`nExiting...`n" -ForegroundColor Red
    exit 1
}

if ($allEnvironments.Count -eq 0) {
    Write-Host "  ✗ No environments found. You may not have access to any environments." -ForegroundColor Red
    Write-Host "`nExiting...`n" -ForegroundColor Red
    exit 1
}

# Display available environments
Write-Host "`n  Available Environments:" -ForegroundColor White
$envIndex = 1
foreach ($env in $allEnvironments) {
    $envType = if ($env.EnvironmentType -eq "Production") { "[PROD]" } else { "[$($env.EnvironmentType)]" }
    Write-Host "    $envIndex. " -NoNewline -ForegroundColor DarkGray
    Write-Host "$($env.DisplayName) " -NoNewline -ForegroundColor White
    Write-Host "$envType" -ForegroundColor $(if ($env.EnvironmentType -eq "Production") { "Green" } else { "Yellow" })
    Write-Host "       ID: $($env.EnvironmentName)" -ForegroundColor DarkGray
    $envIndex++
}

# ============================================================================
# PROMPT: RESOURCE TYPE
# ============================================================================

Write-SectionHeader "RESOURCE TYPE"

Write-Host "`n  What are you looking for?" -ForegroundColor White
Write-Host "    1. Canvas App" -ForegroundColor Cyan
Write-Host "    2. Cloud Flow (Power Automate)" -ForegroundColor Cyan

do {
    $typeChoice = Read-Host "`n  Enter choice (1 or 2)"
} while ($typeChoice -notin @("1", "2"))

$resourceType = if ($typeChoice -eq "1") { "App" } else { "Flow" }
$resourceTypeName = if ($typeChoice -eq "1") { "Canvas App" } else { "Cloud Flow" }

Write-Host "  ✓ Searching for: $resourceTypeName" -ForegroundColor Green

# ============================================================================
# PROMPT: SEARCH INPUT
# ============================================================================

Write-SectionHeader "SEARCH INPUT"

Write-Host "`n  How do you want to search?" -ForegroundColor White
Write-Host "    1. By Name (partial match)" -ForegroundColor Cyan
Write-Host "    2. By Full URL" -ForegroundColor Cyan

do {
    $searchChoice = Read-Host "`n  Enter choice (1 or 2)"
} while ($searchChoice -notin @("1", "2"))

if ($searchChoice -eq "1") {
    # Search by name
    $searchTerm = Read-Host "`n  Enter the name (or part of the name) to search for"

    if ([string]::IsNullOrWhiteSpace($searchTerm)) {
        Write-Host "`n  ✗ Search term cannot be empty" -ForegroundColor Red
        Write-Host "`nExiting...`n" -ForegroundColor Red
        exit 1
    }

    Write-Host "  ✓ Will search for: '$searchTerm'" -ForegroundColor Green

    # ========================================================================
    # PROMPT: ENVIRONMENT PRIORITY
    # ========================================================================

    Write-SectionHeader "SEARCH PRIORITY"

    Write-Host "`n  Do you want to define a custom search order?" -ForegroundColor White
    Write-Host "    Otherwise, Production environments will be searched first" -ForegroundColor DarkGray

    $useCustomOrder = Read-Host "`n  Use custom order? (y/n)"

    if ($useCustomOrder -eq "y" -or $useCustomOrder -eq "yes") {
        Write-Host "`n  Enter environment IDs or indices (comma-separated)" -ForegroundColor White
        Write-Host "  Example: 1,3,5 or mix of indices and IDs" -ForegroundColor DarkGray

        $orderInput = Read-Host "`n  Enter order"
        $orderedEnvIds = @()

        foreach ($item in ($orderInput -split ",")) {
            $item = $item.Trim()

            # Check if it's a number (index)
            if ($item -match '^\d+$') {
                $index = [int]$item - 1
                if ($index -ge 0 -and $index -lt $allEnvironments.Count) {
                    $orderedEnvIds += $allEnvironments[$index].EnvironmentName
                }
            }
            # Otherwise treat as environment ID
            else {
                $orderedEnvIds += $item
            }
        }

        # Add remaining environments
        foreach ($env in $allEnvironments) {
            if ($env.EnvironmentName -notin $orderedEnvIds) {
                $orderedEnvIds += $env.EnvironmentName
            }
        }

        Write-Host "  ✓ Custom search order configured" -ForegroundColor Green
    }
    else {
        # Default: Production first, then others
        $prodEnvs = $allEnvironments | Where-Object { $_.EnvironmentType -eq "Production" }
        $otherEnvs = $allEnvironments | Where-Object { $_.EnvironmentType -ne "Production" }

        $orderedEnvIds = @()
        $orderedEnvIds += $prodEnvs | ForEach-Object { $_.EnvironmentName }
        $orderedEnvIds += $otherEnvs | ForEach-Object { $_.EnvironmentName }

        Write-Host "  ✓ Will search Production environments first" -ForegroundColor Green
    }

    # ========================================================================
    # SEARCH BY NAME
    # ========================================================================

    Write-SectionHeader "SEARCHING"

    Write-Host "`n  Searching across environments..." -ForegroundColor Yellow

    if ($resourceType -eq "App") {
        $searchResults = Search-CanvasApp -SearchTerm $searchTerm -EnvironmentIds $orderedEnvIds -AllEnvironments $allEnvironments
    }
    else {
        $searchResults = Search-CloudFlow -SearchTerm $searchTerm -EnvironmentIds $orderedEnvIds -AllEnvironments $allEnvironments
    }
}
else {
    # Search by URL
    $url = Read-Host "`n  Enter the full URL"

    if ([string]::IsNullOrWhiteSpace($url)) {
        Write-Host "`n  ✗ URL cannot be empty" -ForegroundColor Red
        Write-Host "`nExiting...`n" -ForegroundColor Red
        exit 1
    }

    # Parse the URL
    $urlInfo = Parse-PowerPlatformUrl -Url $url

    if (-not $urlInfo.IsValid) {
        Write-Host "`n  ✗ Could not parse the URL" -ForegroundColor Red
        Write-Host "`nExiting...`n" -ForegroundColor Red
        exit 1
    }

    # Check if URL type matches selected resource type
    if ($urlInfo.Type -ne $resourceType) {
        Write-Host "`n  ⚠ URL appears to be for a $($urlInfo.Type), but you selected $resourceType" -ForegroundColor Yellow
        $continue = Read-Host "  Continue anyway? (y/n)"
        if ($continue -ne "y" -and $continue -ne "yes") {
            Write-Host "`nExiting...`n" -ForegroundColor Red
            exit 1
        }
    }

    Write-Host "  ✓ Parsed URL successfully" -ForegroundColor Green
    Write-Host "    Resource ID: $($urlInfo.ResourceId)" -ForegroundColor DarkGray

    # ========================================================================
    # SEARCH BY URL
    # ========================================================================

    Write-SectionHeader "SEARCHING"

    # If environment ID was in URL, search only that environment
    if ($urlInfo.EnvironmentId) {
        Write-Host "`n  Searching in specific environment from URL..." -ForegroundColor Yellow
        $searchEnvIds = @($urlInfo.EnvironmentId)
    }
    else {
        Write-Host "`n  Environment not in URL, searching all environments..." -ForegroundColor Yellow
        $searchEnvIds = $allEnvironments | ForEach-Object { $_.EnvironmentName }
    }

    if ($resourceType -eq "App") {
        $searchResults = Search-CanvasApp -SearchTerm "" -EnvironmentIds $searchEnvIds -AllEnvironments $allEnvironments -SpecificAppId $urlInfo.ResourceId
    }
    else {
        $searchResults = Search-CloudFlow -SearchTerm "" -EnvironmentIds $searchEnvIds -AllEnvironments $allEnvironments -SpecificFlowId $urlInfo.ResourceId
    }
}

# ============================================================================
# DISPLAY RESULTS
# ============================================================================

Write-SectionHeader "RESULTS"

if ($searchResults.Count -eq 0) {
    Write-Host "`n  ✗ No matching $resourceTypeName found" -ForegroundColor Red
    Write-Host "`n  Possible reasons:" -ForegroundColor Yellow
    Write-Host "    • The resource doesn't exist" -ForegroundColor DarkGray
    Write-Host "    • You don't have permission to view it" -ForegroundColor DarkGray
    Write-Host "    • The name/URL was incorrect" -ForegroundColor DarkGray
    Write-Host "`nExiting...`n" -ForegroundColor Red
    exit 0
}

Write-Host "`n  ✓ Found $($searchResults.Count) matching $resourceTypeName(s)!" -ForegroundColor Green

# Display each result
$resultIndex = 1
foreach ($result in $searchResults) {
    Write-Host "`n╔═══════════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "║  RESULT #$resultIndex" -ForegroundColor Yellow
    Write-Host "╚═══════════════════════════════════════════════════════╝" -ForegroundColor Yellow

    if ($resourceType -eq "App") {
        Write-InfoLine "Display Name" $result.DisplayName "Cyan"
        Write-InfoLine "App ID" $result.AppName "White"
        Write-InfoLine "Environment" $result.EnvironmentName "Green"
        Write-InfoLine "Environment ID" $result.EnvironmentId "DarkGray"
        Write-InfoLine "Owner" "$($result.Owner) ($($result.OwnerEmail))" "White"
        Write-InfoLine "App Type" $result.AppType "White"
        Write-InfoLine "State" $result.State $(if ($result.State -eq "Published") { "Green" } else { "Yellow" })
        Write-InfoLine "Created" $result.CreatedTime "White"
        Write-InfoLine "Last Modified" $result.LastModifiedTime "White"
        Write-InfoLine "Play URL" $result.AppUrl "Cyan"
        Write-InfoLine "Edit URL" $result.EditUrl "Yellow"
    }
    else {
        Write-InfoLine "Display Name" $result.DisplayName "Cyan"
        Write-InfoLine "Flow ID" $result.FlowName "White"
        Write-InfoLine "Environment" $result.EnvironmentName "Green"
        Write-InfoLine "Environment ID" $result.EnvironmentId "DarkGray"
        Write-InfoLine "Owner" "$($result.Owner)" "White"
        Write-InfoLine "Trigger Type" $result.TriggerType "White"
        Write-InfoLine "State" $result.State $result.StateColor
        Write-InfoLine "Created" $result.CreatedTime "White"
        Write-InfoLine "Last Modified" $result.LastModifiedTime "White"
        Write-InfoLine "Edit URL" $result.EditUrl "Yellow"
    }

    $resultIndex++
}

# ============================================================================
# COMPLETION
# ============================================================================

Write-Host "`n╔════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  SEARCH COMPLETE                                       ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

Write-Host "`n  ✓ All done! You can now access the $resourceTypeName" -ForegroundColor Green
Write-Host "`n" -ForegroundColor White
