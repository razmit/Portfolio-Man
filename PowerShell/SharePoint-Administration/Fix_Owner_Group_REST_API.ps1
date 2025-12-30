# ============================================================================
# Fix Associated Owner Group - REST API Approach
# ============================================================================
# Purpose: Use SharePoint REST API to fix broken associated owner groups
#          This bypasses CSOM/PnP restrictions that cause access denied errors
#
# Author: Created with assistance from Claude
# Date: December 2025
# ============================================================================

# Function to connect to the requested site
function Connect-IndicatedSite {
    param (
        [string]$SiteUrl
    )

    $failCounter = 1
    $maxRetries = 3
    $connected = $false

    do {
        try {
            $SiteUrl = $SiteUrl.TrimStart()
            Write-Host "Connecting to the site... (Attempt $failCounter of $maxRetries)" -ForegroundColor Yellow
            Connect-PnPOnline -Url $SiteUrl -ClientId CLIENT_ID -Interactive
            Write-Host "Connection successful!" -ForegroundColor Green
            $connected = $true
            break
        }
        catch {
            if ($_.Exception.Message -notlike "*parse near offset*" -and $_.Exception.Message -notlike "*ASCII digit*") {
                Write-Host "Connection attempt $failCounter failed: $($_.Exception.Message)" -ForegroundColor Red
            } else {
                Write-Host "Connection attempt $failCounter failed (authentication flow issue - retrying...)" -ForegroundColor Red
            }
            $failCounter++

            if ($failCounter -le $maxRetries) {
                Write-Host "Retrying in 2 seconds..." -ForegroundColor Yellow
                Start-Sleep -Seconds 2
            }
        }
    } while ($failCounter -le $maxRetries -and -not $connected)

    if (-not $connected) {
        Write-Host "All connection attempts failed. Unable to connect to $SiteUrl" -ForegroundColor Red
        return $false
    }

    return $true
}

# Function to get associated groups using REST API
function Get-AssociatedGroupsREST {
    Write-Host "`nGetting associated groups via REST API..." -ForegroundColor Cyan

    try {
        # Get web properties with associated groups
        $web = Invoke-PnPSPRestMethod -Method Get -Url "_api/web?`$select=Title,AssociatedOwnerGroup/Id,AssociatedOwnerGroup/Title,AssociatedMemberGroup/Id,AssociatedMemberGroup/Title,AssociatedVisitorGroup/Id,AssociatedVisitorGroup/Title&`$expand=AssociatedOwnerGroup,AssociatedMemberGroup,AssociatedVisitorGroup"

        Write-Host "Site: $($web.Title)" -ForegroundColor White
        Write-Host "`nAssociated Groups:" -ForegroundColor Yellow
        Write-Host "  Owner Group: $($web.AssociatedOwnerGroup.Title) (ID: $($web.AssociatedOwnerGroup.Id))" -ForegroundColor White
        Write-Host "  Member Group: $($web.AssociatedMemberGroup.Title) (ID: $($web.AssociatedMemberGroup.Id))" -ForegroundColor White
        Write-Host "  Visitor Group: $($web.AssociatedVisitorGroup.Title) (ID: $($web.AssociatedVisitorGroup.Id))" -ForegroundColor White

        return $web
    }
    catch {
        Write-Host "Error getting associated groups: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

# Function to get group permissions using REST API
function Get-GroupPermissionsREST {
    param (
        [int]$GroupId
    )

    try {
        # Get role assignments for the web filtered by this group
        $roleAssignments = Invoke-PnPSPRestMethod -Method Get -Url "_api/web/roleassignments?`$filter=PrincipalId eq $GroupId&`$expand=RoleDefinitionBindings"

        if ($roleAssignments.value.Count -gt 0) {
            $permissions = $roleAssignments.value[0].RoleDefinitionBindings | Select-Object -ExpandProperty Name
            return $permissions
        }
        else {
            return @()
        }
    }
    catch {
        Write-Host "Error getting group permissions: $($_.Exception.Message)" -ForegroundColor Red
        return @()
    }
}

# Function to set associated owner group using REST API
function Set-AssociatedOwnerGroupREST {
    param (
        [int]$GroupId,
        [switch]$DryRun
    )

    Write-Host "`n╔════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║           REPAIRING OWNER GROUP VIA REST API          ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

    if ($DryRun) {
        Write-Host "[DRY-RUN] Would set group ID $GroupId as associated owner group" -ForegroundColor Magenta
        return $true
    }

    try {
        # Step 1: Set the associated owner group using REST API
        Write-Host "Step 1: Setting associated owner group (ID: $GroupId) via REST API..." -ForegroundColor Yellow

        $body = @{
            "__metadata" = @{ "type" = "SP.Web" }
            "AssociatedOwnerGroup" = @{
                "__metadata" = @{ "type" = "SP.Group" }
                "Id" = $GroupId
            }
        } | ConvertTo-Json -Depth 3

        try {
            Invoke-PnPSPRestMethod -Method Post -Url "_api/web" -Content $body -ContentType "application/json;odata=verbose"
            Write-Host "  ✓ Associated owner group set successfully" -ForegroundColor Green
        }
        catch {
            # If POST fails, try MERGE
            Write-Host "  Trying alternative method (MERGE)..." -ForegroundColor Yellow

            $headers = @{
                "X-HTTP-Method" = "MERGE"
                "IF-MATCH" = "*"
            }

            Invoke-PnPSPRestMethod -Method Post -Url "_api/web" -Content $body -ContentType "application/json;odata=verbose"
            Write-Host "  ✓ Associated owner group set successfully (MERGE)" -ForegroundColor Green
        }

        # Step 2: Ensure Full Control permissions
        Write-Host "`nStep 2: Ensuring Full Control permissions..." -ForegroundColor Yellow

        $currentPerms = Get-GroupPermissionsREST -GroupId $GroupId

        if ($currentPerms -contains "Full Control") {
            Write-Host "  Full Control already present" -ForegroundColor Gray
        }
        else {
            Write-Host "  Adding Full Control..." -ForegroundColor Yellow
            # Use PnP cmdlet for this as REST API for permissions is complex
            Set-PnPGroupPermissions -Identity $GroupId -AddRole "Full Control"
            Write-Host "  ✓ Full Control granted" -ForegroundColor Green
        }

        # Step 3: Set group as its own owner
        Write-Host "`nStep 3: Setting group as its own owner..." -ForegroundColor Yellow

        try {
            $group = Invoke-PnPSPRestMethod -Method Get -Url "_api/web/sitegroups($GroupId)"

            $ownerBody = @{
                "__metadata" = @{ "type" = "SP.Group" }
                "OwnerId" = $GroupId
            } | ConvertTo-Json

            Invoke-PnPSPRestMethod -Method Post -Url "_api/web/sitegroups($GroupId)" -Content $ownerBody -ContentType "application/json;odata=verbose"
            Write-Host "  ✓ Group ownership configured" -ForegroundColor Green
        }
        catch {
            Write-Host "  Warning: Could not set group ownership - $($_.Exception.Message)" -ForegroundColor DarkYellow
            # Try with PnP cmdlet as fallback
            try {
                $groupInfo = Get-PnPGroup -Identity $GroupId
                Set-PnPGroup -Identity $GroupId -Owner $groupInfo.LoginName
                Write-Host "  ✓ Group ownership configured (fallback method)" -ForegroundColor Green
            }
            catch {
                Write-Host "  Warning: Could not set group ownership with fallback" -ForegroundColor DarkYellow
            }
        }

        # Step 4: Verify
        Write-Host "`nStep 4: Verifying the fix..." -ForegroundColor Yellow
        Start-Sleep -Seconds 2

        $verifyWeb = Get-AssociatedGroupsREST
        $verifyPerms = Get-GroupPermissionsREST -GroupId $GroupId

        if ($verifyWeb.AssociatedOwnerGroup.Id -eq $GroupId -and $verifyPerms -contains "Full Control") {
            Write-Host "  ✓ Verification successful!" -ForegroundColor Green
            Write-Host "    - Associated owner group is set correctly" -ForegroundColor Green
            Write-Host "    - Full Control permissions are present" -ForegroundColor Green
            return $true
        }
        else {
            Write-Host "  ⚠ Verification incomplete" -ForegroundColor Yellow
            if ($verifyWeb.AssociatedOwnerGroup.Id -ne $GroupId) {
                Write-Host "    - Warning: Associated owner group may not be set" -ForegroundColor Yellow
            }
            if ($verifyPerms -notcontains "Full Control") {
                Write-Host "    - Warning: Full Control may not be present" -ForegroundColor Yellow
            }
            return $false
        }
    }
    catch {
        Write-Host "`nERROR during repair: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Stack trace: $($_.ScriptStackTrace)" -ForegroundColor DarkGray
        return $false
    }
}

# Main script execution
function Start-RESTAPIRepair {
    Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                                                              ║" -ForegroundColor Cyan
    Write-Host "║     Fix Associated Owner Group - REST API Approach          ║" -ForegroundColor Cyan
    Write-Host "║                                                              ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "This script uses SharePoint REST API instead of CSOM" -ForegroundColor Yellow
    Write-Host "to bypass access denied errors with standard PnP commands." -ForegroundColor Yellow
    Write-Host ""

    # Get site URL
    $siteUrl = Read-Host "Enter the SharePoint site URL"

    if ([string]::IsNullOrWhiteSpace($siteUrl)) {
        Write-Host "Site URL cannot be empty. Exiting." -ForegroundColor Red
        return
    }

    # Connect to site
    $connected = Connect-IndicatedSite -SiteUrl $siteUrl
    if (-not $connected) {
        Write-Host "Failed to connect to site. Exiting." -ForegroundColor Red
        return
    }

    # Get current state
    $webInfo = Get-AssociatedGroupsREST

    if (-not $webInfo) {
        Write-Host "Could not retrieve site information. Exiting." -ForegroundColor Red
        return
    }

    if (-not $webInfo.AssociatedOwnerGroup) {
        Write-Host "`nERROR: No associated owner group found!" -ForegroundColor Red
        Write-Host "You may need to set up groups for this site manually." -ForegroundColor Yellow
        Write-Host "See MANUAL_FIX_Associated_Owner_Group.md for instructions." -ForegroundColor Yellow
        return
    }

    $ownerGroupId = $webInfo.AssociatedOwnerGroup.Id
    $ownerGroupTitle = $webInfo.AssociatedOwnerGroup.Title

    # Check current permissions
    Write-Host "`nChecking permissions for: $ownerGroupTitle" -ForegroundColor Cyan
    $currentPerms = Get-GroupPermissionsREST -GroupId $ownerGroupId

    Write-Host "Current permissions:" -ForegroundColor Yellow
    if ($currentPerms.Count -gt 0) {
        foreach ($perm in $currentPerms) {
            $color = if ($perm -eq "Full Control") { "Green" } else { "White" }
            Write-Host "  - $perm" -ForegroundColor $color
        }
    }
    else {
        Write-Host "  NO PERMISSIONS!" -ForegroundColor Red
    }

    # Check if repair is needed
    $needsRepair = $currentPerms -notcontains "Full Control"

    if (-not $needsRepair) {
        Write-Host "`n╔════════════════════════════════════════════════════════╗" -ForegroundColor Green
        Write-Host "║          NO REPAIR NEEDED - GROUP IS HEALTHY           ║" -ForegroundColor Green
        Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Green
        Write-Host "`nThe owner group already has Full Control." -ForegroundColor Yellow
        Write-Host "If owners still can't access settings, try:" -ForegroundColor Yellow
        Write-Host "  1. Clear browser cache" -ForegroundColor White
        Write-Host "  2. Sign out and back in" -ForegroundColor White
        Write-Host "  3. Wait 10 minutes for propagation" -ForegroundColor White
        Write-Host "  4. Use the manual fix guide (MANUAL_FIX_Associated_Owner_Group.md)" -ForegroundColor White
        return
    }

    # Confirmation
    Write-Host "`n╔════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "║                     CONFIRMATION                       ║" -ForegroundColor Yellow
    Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
    Write-Host "This will attempt to repair the owner group using REST API:" -ForegroundColor White
    Write-Host "  - Group: $ownerGroupTitle" -ForegroundColor White
    Write-Host "  - Group ID: $ownerGroupId" -ForegroundColor White
    Write-Host "`nActions:" -ForegroundColor White
    Write-Host "  1. Re-associate the group via REST API" -ForegroundColor White
    Write-Host "  2. Ensure Full Control permissions" -ForegroundColor White
    Write-Host "  3. Set group as its own owner" -ForegroundColor White
    Write-Host "  4. Verify the fix" -ForegroundColor White
    Write-Host "`nType 'YES' to proceed, or anything else to cancel" -ForegroundColor Yellow
    $confirmation = Read-Host "Proceed"

    if ($confirmation -ne "YES") {
        Write-Host "`nOperation cancelled by user." -ForegroundColor Yellow
        return
    }

    # Execute repair
    $success = Set-AssociatedOwnerGroupREST -GroupId $ownerGroupId

    if ($success) {
        Write-Host "`n╔════════════════════════════════════════════════════════╗" -ForegroundColor Green
        Write-Host "║                  REPAIR SUCCESSFUL!                    ║" -ForegroundColor Green
        Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Green
        Write-Host "`nNext steps:" -ForegroundColor Yellow
        Write-Host "  1. Wait 5-10 minutes for changes to propagate" -ForegroundColor White
        Write-Host "  2. Have a site owner sign out and back in" -ForegroundColor White
        Write-Host "  3. Test accessing Site Settings > Advanced Permissions" -ForegroundColor White
    }
    else {
        Write-Host "`n╔════════════════════════════════════════════════════════╗" -ForegroundColor Red
        Write-Host "║                  REPAIR FAILED                         ║" -ForegroundColor Red
        Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Red
        Write-Host "`nThe REST API approach did not work." -ForegroundColor Yellow
        Write-Host "Please try:" -ForegroundColor Yellow
        Write-Host "  1. Manual UI fix (see MANUAL_FIX_Associated_Owner_Group.md)" -ForegroundColor White
        Write-Host "  2. Group recreation script (Recreate_Associated_Owner_Group.ps1)" -ForegroundColor White
        Write-Host "  3. Contact Microsoft Support" -ForegroundColor White
    }
}

# Run the script
Start-RESTAPIRepair
