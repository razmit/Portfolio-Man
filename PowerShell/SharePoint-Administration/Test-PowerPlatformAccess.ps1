# Test-PowerPlatformAccess.ps1
#
# Purpose: Verify Power Platform CLI/PowerShell access
# Tests what tools are available and if authentication works
#
# Usage: .\Test-PowerPlatformAccess.ps1

Write-Host "`n╔════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║        POWER PLATFORM ACCESS TEST                      ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

$testResults = @{
    CLI_Installed = $false
    PS_Module_Installed = $false
    CLI_Auth = $false
    PS_Auth = $false
    Environments = @()
}

# ============================================================================
# TEST 1: Check if Power Platform CLI is installed
# ============================================================================

Write-Host "[1/4] Checking Power Platform CLI installation..." -ForegroundColor Yellow

try {
    $pacVersion = pac --version 2>$null
    if ($LASTEXITCODE -eq 0) {
        $testResults.CLI_Installed = $true
        Write-Host "  ✓ Power Platform CLI is installed" -ForegroundColor Green
        Write-Host "    Version: $pacVersion" -ForegroundColor DarkGray
    } else {
        Write-Host "  ✗ Power Platform CLI not found" -ForegroundColor Red
        Write-Host "    Install from: https://aka.ms/PowerPlatformCLI" -ForegroundColor DarkGray
    }
} catch {
    Write-Host "  ✗ Power Platform CLI not found" -ForegroundColor Red
    Write-Host "    Install from: https://aka.ms/PowerPlatformCLI" -ForegroundColor DarkGray
}

# ============================================================================
# TEST 2: Check if PowerShell modules are installed
# ============================================================================

Write-Host "`n[2/4] Checking PowerShell modules..." -ForegroundColor Yellow

$adminModule = Get-Module -ListAvailable -Name "Microsoft.PowerApps.Administration.PowerShell" -ErrorAction SilentlyContinue
$appsModule = Get-Module -ListAvailable -Name "Microsoft.PowerApps.PowerShell" -ErrorAction SilentlyContinue

if ($adminModule -or $appsModule) {
    $testResults.PS_Module_Installed = $true
    Write-Host "  ✓ PowerShell modules found:" -ForegroundColor Green

    if ($adminModule) {
        Write-Host "    • Microsoft.PowerApps.Administration.PowerShell (v$($adminModule.Version))" -ForegroundColor DarkGray
    }
    if ($appsModule) {
        Write-Host "    • Microsoft.PowerApps.PowerShell (v$($appsModule.Version))" -ForegroundColor DarkGray
    }
} else {
    Write-Host "  ✗ PowerShell modules not found" -ForegroundColor Red
    Write-Host "    Install with: Install-Module -Name Microsoft.PowerApps.Administration.PowerShell" -ForegroundColor DarkGray
}

# ============================================================================
# TEST 3: Test CLI Authentication
# ============================================================================

Write-Host "`n[3/4] Testing Power Platform CLI authentication..." -ForegroundColor Yellow

if ($testResults.CLI_Installed) {
    try {
        Write-Host "  Checking existing auth profiles..." -ForegroundColor DarkGray
        $authList = pac auth list 2>$null

        if ($LASTEXITCODE -eq 0 -and $authList) {
            Write-Host "  ✓ Found existing authentication profile(s)" -ForegroundColor Green
            $testResults.CLI_Auth = $true

            # Try to get environments
            Write-Host "  Testing environment access..." -ForegroundColor DarkGray
            $envOutput = pac admin list 2>$null

            if ($LASTEXITCODE -eq 0) {
                Write-Host "  ✓ Successfully accessed environments via CLI" -ForegroundColor Green
                $testResults.Environments += "CLI"
            } else {
                Write-Host "  ⚠ Auth exists but couldn't list environments" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  ⚠ No active authentication found" -ForegroundColor Yellow
            Write-Host "    You'll need to authenticate with: pac auth create" -ForegroundColor DarkGray
        }
    } catch {
        Write-Host "  ✗ Error checking CLI auth: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host "  ⊘ Skipped (CLI not installed)" -ForegroundColor DarkGray
}

# ============================================================================
# TEST 4: Test PowerShell Authentication
# ============================================================================

Write-Host "`n[4/4] Testing PowerShell module authentication..." -ForegroundColor Yellow

if ($testResults.PS_Module_Installed) {
    try {
        Import-Module Microsoft.PowerApps.Administration.PowerShell -ErrorAction Stop

        Write-Host "  Module loaded. Testing connection..." -ForegroundColor DarkGray
        Write-Host "  (This may prompt for interactive login)" -ForegroundColor DarkYellow

        # Try to get environments - this will prompt for login if needed
        Add-PowerAppsAccount -ErrorAction Stop
        $environments = Get-AdminPowerAppEnvironment -ErrorAction Stop

        if ($environments) {
            $testResults.PS_Auth = $true
            Write-Host "  ✓ Successfully authenticated and accessed environments" -ForegroundColor Green
            Write-Host "    Found $($environments.Count) environment(s)" -ForegroundColor DarkGray
            $testResults.Environments += "PowerShell"
        } else {
            Write-Host "  ⚠ Authenticated but no environments found" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  ✗ Error: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "    PowerShell authentication may require additional setup" -ForegroundColor DarkGray
    }
} else {
    Write-Host "  ⊘ Skipped (modules not installed)" -ForegroundColor DarkGray
}

# ============================================================================
# SUMMARY & RECOMMENDATIONS
# ============================================================================

Write-Host "`n╔════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                   TEST SUMMARY                         ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

Write-Host "Installation Status:" -ForegroundColor White
Write-Host "  Power Platform CLI:     $(if($testResults.CLI_Installed){'✓ Installed'}else{'✗ Not Installed'})" -ForegroundColor $(if($testResults.CLI_Installed){'Green'}else{'Red'})
Write-Host "  PowerShell Modules:     $(if($testResults.PS_Module_Installed){'✓ Installed'}else{'✗ Not Installed'})" -ForegroundColor $(if($testResults.PS_Module_Installed){'Green'}else{'Red'})

Write-Host "`nAuthentication Status:" -ForegroundColor White
Write-Host "  CLI Auth:               $(if($testResults.CLI_Auth){'✓ Working'}else{'✗ Not Configured'})" -ForegroundColor $(if($testResults.CLI_Auth){'Green'}else{'Red'})
Write-Host "  PowerShell Auth:        $(if($testResults.PS_Auth){'✓ Working'}else{'✗ Not Configured'})" -ForegroundColor $(if($testResults.PS_Auth){'Green'}else{'Red'})

Write-Host "`n───────────────────────────────────────────────────────" -ForegroundColor Cyan

# Recommendations
Write-Host "`nRECOMMENDATIONS:" -ForegroundColor Yellow

if ($testResults.CLI_Auth -or $testResults.PS_Auth) {
    Write-Host "  ✓ You're ready to go! " -ForegroundColor Green

    if ($testResults.CLI_Auth) {
        Write-Host "    Recommended: Use Power Platform CLI (faster and more modern)" -ForegroundColor Green
    } else {
        Write-Host "    We'll use PowerShell modules for the locator script" -ForegroundColor Green
    }
} else {
    Write-Host "  ⚠ Setup required before using the locator script:" -ForegroundColor Yellow

    if ($testResults.CLI_Installed) {
        Write-Host "    1. Authenticate CLI: pac auth create --interactive" -ForegroundColor White
    } elseif ($testResults.PS_Module_Installed) {
        Write-Host "    1. Already authenticated via PowerShell test above" -ForegroundColor White
    } else {
        Write-Host "    1. Install Power Platform CLI: https://aka.ms/PowerPlatformCLI" -ForegroundColor White
        Write-Host "       OR" -ForegroundColor DarkGray
        Write-Host "    1. Install PowerShell: Install-Module -Name Microsoft.PowerApps.Administration.PowerShell" -ForegroundColor White
    }
}

Write-Host "`n═══════════════════════════════════════════════════════`n" -ForegroundColor Cyan
