# ============================================================================
# Fix Associated Owner Group Script
# ============================================================================
# Purpose: Diagnose and repair broken associated owner group permissions
#          Fixes issues where owners can't access advanced settings/permissions
#          even after manually adding Full Control back
#
# Author: Created with assistance from Claude
# Date: December 2025
# ============================================================================

# Function to connect to the requested site and retry if it failed
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

# Function to get and display current associated groups
function Get-CurrentAssociatedGroups {
    Write-Host "`n╔════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║          CURRENT ASSOCIATED GROUPS STATUS             ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

    try {
        $web = Get-PnPWeb -Includes AssociatedOwnerGroup, AssociatedMemberGroup, AssociatedVisitorGroup
        $ctx = Get-PnPContext

        $groupsInfo = @{
            OwnerGroup = $null
            MemberGroup = $null
            VisitorGroup = $null
        }

        # Get Owner Group
        if ($web.AssociatedOwnerGroup) {
            $ctx.Load($web.AssociatedOwnerGroup)
            $ctx.Load($web.AssociatedOwnerGroup.Users)
            $ctx.ExecuteQuery()

            Write-Host "Associated Owner Group:" -ForegroundColor Yellow
            Write-Host "  Title: $($web.AssociatedOwnerGroup.Title)" -ForegroundColor White
            Write-Host "  ID: $($web.AssociatedOwnerGroup.Id)" -ForegroundColor Gray
            Write-Host "  Login Name: $($web.AssociatedOwnerGroup.LoginName)" -ForegroundColor Gray
            Write-Host "  Members Count: $($web.AssociatedOwnerGroup.Users.Count)" -ForegroundColor White

            $groupsInfo.OwnerGroup = $web.AssociatedOwnerGroup
        }
        else {
            Write-Host "Associated Owner Group: NOT SET" -ForegroundColor Red
        }

        # Get Member Group
        if ($web.AssociatedMemberGroup) {
            $ctx.Load($web.AssociatedMemberGroup)
            $ctx.ExecuteQuery()

            Write-Host "`nAssociated Member Group:" -ForegroundColor Yellow
            Write-Host "  Title: $($web.AssociatedMemberGroup.Title)" -ForegroundColor White
            Write-Host "  ID: $($web.AssociatedMemberGroup.Id)" -ForegroundColor Gray

            $groupsInfo.MemberGroup = $web.AssociatedMemberGroup
        }
        else {
            Write-Host "`nAssociated Member Group: NOT SET" -ForegroundColor Red
        }

        # Get Visitor Group
        if ($web.AssociatedVisitorGroup) {
            $ctx.Load($web.AssociatedVisitorGroup)
            $ctx.ExecuteQuery()

            Write-Host "`nAssociated Visitor Group:" -ForegroundColor Yellow
            Write-Host "  Title: $($web.AssociatedVisitorGroup.Title)" -ForegroundColor White
            Write-Host "  ID: $($web.AssociatedVisitorGroup.Id)" -ForegroundColor Gray

            $groupsInfo.VisitorGroup = $web.AssociatedVisitorGroup
        }
        else {
            Write-Host "`nAssociated Visitor Group: NOT SET" -ForegroundColor Red
        }

        return $groupsInfo
    }
    catch {
        Write-Host "Error getting associated groups: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}

# Function to check permissions for a group
function Get-GroupPermissions {
    param (
        [int]$GroupId
    )

    try {
        $group = Get-PnPGroup -Identity $GroupId
        $web = Get-PnPWeb
        $ctx = Get-PnPContext

        # Get role assignments for the web
        $ctx.Load($web.RoleAssignments)
        $ctx.ExecuteQuery()

        $permissions = @()

        foreach ($roleAssignment in $web.RoleAssignments) {
            $ctx.Load($roleAssignment.Member)
            $ctx.Load($roleAssignment.RoleDefinitionBindings)
            $ctx.ExecuteQuery()

            if ($roleAssignment.Member.Id -eq $GroupId) {
                foreach ($role in $roleAssignment.RoleDefinitionBindings) {
                    $permissions += $role.Name
                }
                break
            }
        }

        return $permissions
    }
    catch {
        Write-Host "Error getting group permissions: $($_.Exception.Message)" -ForegroundColor Red
        return @()
    }
}

# Function to display permissions for all associated groups
function Show-AssociatedGroupPermissions {
    param (
        [hashtable]$GroupsInfo
    )

    Write-Host "`n╔════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║           ASSOCIATED GROUPS PERMISSIONS               ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

    $permissionsReport = @()

    # Check Owner Group Permissions
    if ($GroupsInfo.OwnerGroup) {
        $ownerPerms = Get-GroupPermissions -GroupId $GroupsInfo.OwnerGroup.Id
        Write-Host "Owner Group Permissions:" -ForegroundColor Yellow
        if ($ownerPerms.Count -gt 0) {
            foreach ($perm in $ownerPerms) {
                $color = if ($perm -eq "Full Control") { "Green" } else { "Yellow" }
                Write-Host "  - $perm" -ForegroundColor $color
            }
        }
        else {
            Write-Host "  NO PERMISSIONS ASSIGNED!" -ForegroundColor Red
        }

        $permissionsReport += [PSCustomObject]@{
            GroupType = "Owner"
            GroupTitle = $GroupsInfo.OwnerGroup.Title
            Permissions = ($ownerPerms -join ", ")
            HasFullControl = ($ownerPerms -contains "Full Control")
        }
    }

    # Check Member Group Permissions
    if ($GroupsInfo.MemberGroup) {
        $memberPerms = Get-GroupPermissions -GroupId $GroupsInfo.MemberGroup.Id
        Write-Host "`nMember Group Permissions:" -ForegroundColor Yellow
        if ($memberPerms.Count -gt 0) {
            foreach ($perm in $memberPerms) {
                Write-Host "  - $perm" -ForegroundColor White
            }
        }
        else {
            Write-Host "  NO PERMISSIONS ASSIGNED!" -ForegroundColor Red
        }

        $permissionsReport += [PSCustomObject]@{
            GroupType = "Member"
            GroupTitle = $GroupsInfo.MemberGroup.Title
            Permissions = ($memberPerms -join ", ")
            HasFullControl = ($memberPerms -contains "Full Control")
        }
    }

    # Check Visitor Group Permissions
    if ($GroupsInfo.VisitorGroup) {
        $visitorPerms = Get-GroupPermissions -GroupId $GroupsInfo.VisitorGroup.Id
        Write-Host "`nVisitor Group Permissions:" -ForegroundColor Yellow
        if ($visitorPerms.Count -gt 0) {
            foreach ($perm in $visitorPerms) {
                Write-Host "  - $perm" -ForegroundColor White
            }
        }
        else {
            Write-Host "  NO PERMISSIONS ASSIGNED!" -ForegroundColor Red
        }

        $permissionsReport += [PSCustomObject]@{
            GroupType = "Visitor"
            GroupTitle = $GroupsInfo.VisitorGroup.Title
            Permissions = ($visitorPerms -join ", ")
            HasFullControl = ($visitorPerms -contains "Full Control")
        }
    }

    return $permissionsReport
}

# Function to fix the associated owner group
function Repair-AssociatedOwnerGroup {
    param (
        [hashtable]$GroupsInfo,
        [switch]$DryRun
    )

    if ($DryRun) {
        Write-Host "`n╔════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
        Write-Host "║          DRY-RUN MODE - NO CHANGES WILL BE MADE        ║" -ForegroundColor Magenta
        Write-Host "╚════════════════════════════════════════════════════════╝`n" -ForegroundColor Magenta
    }
    else {
        Write-Host "`n╔════════════════════════════════════════════════════════╗" -ForegroundColor Green
        Write-Host "║              REPAIRING OWNER GROUP - LIVE              ║" -ForegroundColor Green
        Write-Host "╚════════════════════════════════════════════════════════╝`n" -ForegroundColor Green
    }

    $repairLog = @()

    if (-not $GroupsInfo.OwnerGroup) {
        Write-Host "ERROR: No associated owner group found. Cannot repair." -ForegroundColor Red
        return $repairLog
    }

    $ownerGroup = $GroupsInfo.OwnerGroup

    try {
        # Step 1: Re-associate the owner group at the web level
        Write-Host "Step 1: Re-associating owner group at web level..." -ForegroundColor Yellow

        if (-not $DryRun) {
            $web = Get-PnPWeb
            $ctx = Get-PnPContext

            # Set the associated owner group
            $web.AssociatedOwnerGroup = $ownerGroup
            $web.Update()
            $ctx.ExecuteQuery()

            Write-Host "  Owner group re-associated" -ForegroundColor Green
        }
        else {
            Write-Host "  [DRY-RUN] Would re-associate owner group" -ForegroundColor Cyan
        }

        $repairLog += [PSCustomObject]@{
            Step = "1"
            Action = "Re-associate owner group"
            Status = "Completed"
            Details = "Set $($ownerGroup.Title) as AssociatedOwnerGroup"
        }

        # Step 2: Ensure Full Control permissions are present
        Write-Host "`nStep 2: Ensuring Full Control permissions..." -ForegroundColor Yellow

        if (-not $DryRun) {
            # Check if Full Control already exists
            $currentPerms = Get-GroupPermissions -GroupId $ownerGroup.Id
            if ($currentPerms -contains "Full Control") {
                Write-Host "  Full Control already present" -ForegroundColor Gray
            }
            else {
                Set-PnPGroupPermissions -Identity $ownerGroup.Id -AddRole "Full Control"
                Write-Host "  Full Control granted" -ForegroundColor Green
            }
        }
        else {
            Write-Host "  [DRY-RUN] Would ensure Full Control is present" -ForegroundColor Cyan
        }

        $repairLog += [PSCustomObject]@{
            Step = "2"
            Action = "Ensure Full Control"
            Status = "Completed"
            Details = "Ensured Full Control permission level is present"
        }

        # Step 3: Ensure the group is set as the Owner of itself (best practice)
        Write-Host "`nStep 3: Setting owner group as its own owner..." -ForegroundColor Yellow

        if (-not $DryRun) {
            try {
                Set-PnPGroup -Identity $ownerGroup.Id -Owner $ownerGroup.LoginName
                Write-Host "  Group ownership configured" -ForegroundColor Green
            }
            catch {
                Write-Host "  Warning: Could not set group ownership - $($_.Exception.Message)" -ForegroundColor DarkYellow
            }
        }
        else {
            Write-Host "  [DRY-RUN] Would set group as its own owner" -ForegroundColor Cyan
        }

        $repairLog += [PSCustomObject]@{
            Step = "3"
            Action = "Configure group ownership"
            Status = "Completed"
            Details = "Set group as its own owner"
        }

        # Step 4: Verify the fix
        Write-Host "`nStep 4: Verifying repair..." -ForegroundColor Yellow

        if (-not $DryRun) {
            Start-Sleep -Seconds 2  # Give SharePoint a moment to propagate changes

            $verifyPerms = Get-GroupPermissions -GroupId $ownerGroup.Id

            if ($verifyPerms -contains "Full Control") {
                Write-Host "  ✓ Verification successful - Full Control confirmed" -ForegroundColor Green
                $repairLog += [PSCustomObject]@{
                    Step = "4"
                    Action = "Verification"
                    Status = "SUCCESS"
                    Details = "Full Control verified"
                }
            }
            else {
                Write-Host "  ⚠ Verification warning - Full Control not detected" -ForegroundColor Yellow
                $repairLog += [PSCustomObject]@{
                    Step = "4"
                    Action = "Verification"
                    Status = "WARNING"
                    Details = "Could not verify Full Control"
                }
            }
        }
        else {
            Write-Host "  [DRY-RUN] Would verify Full Control permissions" -ForegroundColor Cyan
            $repairLog += [PSCustomObject]@{
                Step = "4"
                Action = "Verification"
                Status = "DRY-RUN"
                Details = "Would verify permissions"
            }
        }

    }
    catch {
        Write-Host "ERROR during repair: $($_.Exception.Message)" -ForegroundColor Red
        $repairLog += [PSCustomObject]@{
            Step = "ERROR"
            Action = "Repair process"
            Status = "FAILED"
            Details = $_.Exception.Message
        }
    }

    return $repairLog
}

# Function to list all site groups and their permissions
function Get-AllSiteGroups {
    Write-Host "`n╔════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                ALL SITE GROUPS & PERMISSIONS           ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

    try {
        $groups = Get-PnPGroup

        $groupsReport = @()

        foreach ($group in $groups) {
            $permissions = Get-GroupPermissions -GroupId $group.Id
            $permString = if ($permissions.Count -gt 0) { $permissions -join ", " } else { "None" }

            Write-Host "Group: $($group.Title)" -ForegroundColor Yellow
            Write-Host "  Permissions: $permString" -ForegroundColor White

            $groupsReport += [PSCustomObject]@{
                GroupTitle = $group.Title
                GroupId = $group.Id
                Permissions = $permString
            }
        }

        return $groupsReport
    }
    catch {
        Write-Host "Error getting site groups: $($_.Exception.Message)" -ForegroundColor Red
        return @()
    }
}

# Main script execution
function Start-OwnerGroupRepair {
    Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                                                              ║" -ForegroundColor Cyan
    Write-Host "║          Associated Owner Group Repair Script               ║" -ForegroundColor Cyan
    Write-Host "║                                                              ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
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

    # Create output directory
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $outputDir = Join-Path $PSScriptRoot "OwnerGroupRepair_$timestamp"
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    Write-Host "Output directory: $outputDir" -ForegroundColor Cyan

    # Step 1: Get current state
    $groupsInfo = Get-CurrentAssociatedGroups
    $permissionsReport = Show-AssociatedGroupPermissions -GroupsInfo $groupsInfo

    # Export initial state
    $initialStatePath = Join-Path $outputDir "01_Initial_State.csv"
    $permissionsReport | Export-Csv -Path $initialStatePath -NoTypeInformation -Encoding UTF8
    Write-Host "`nInitial state saved: $initialStatePath" -ForegroundColor Cyan

    # Get all site groups for reference
    $allGroupsReport = Get-AllSiteGroups
    $allGroupsPath = Join-Path $outputDir "02_All_Site_Groups.csv"
    $allGroupsReport | Export-Csv -Path $allGroupsPath -NoTypeInformation -Encoding UTF8
    Write-Host "All groups report saved: $allGroupsPath" -ForegroundColor Cyan

    # Check if repair is needed
    $ownerPerms = Get-GroupPermissions -GroupId $groupsInfo.OwnerGroup.Id
    $needsRepair = $ownerPerms -notcontains "Full Control"

    if (-not $needsRepair) {
        Write-Host "`n╔════════════════════════════════════════════════════════╗" -ForegroundColor Green
        Write-Host "║          NO REPAIR NEEDED - GROUP IS HEALTHY           ║" -ForegroundColor Green
        Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Green
        Write-Host "`nThe owner group already has Full Control." -ForegroundColor Yellow
        Write-Host "If owners still can't access advanced settings, the issue may be:" -ForegroundColor Yellow
        Write-Host "  1. Browser cache - try clearing cache or incognito mode" -ForegroundColor White
        Write-Host "  2. User not in the owner group - verify membership" -ForegroundColor White
        Write-Host "  3. Permission propagation delay - wait 5-10 minutes" -ForegroundColor White
        return
    }

    # Dry-run first
    Write-Host "`n╔════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
    Write-Host "║                  DRY-RUN PREVIEW                       ║" -ForegroundColor Magenta
    Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Magenta

    $dryRunLog = Repair-AssociatedOwnerGroup -GroupsInfo $groupsInfo -DryRun

    $dryRunPath = Join-Path $outputDir "03_DryRun_Preview.csv"
    $dryRunLog | Export-Csv -Path $dryRunPath -NoTypeInformation -Encoding UTF8
    Write-Host "`nDry-run preview saved: $dryRunPath" -ForegroundColor Cyan

    # Ask for confirmation
    Write-Host "`n╔════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "║                     CONFIRMATION                       ║" -ForegroundColor Yellow
    Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
    Write-Host "Do you want to proceed with repairing the owner group?" -ForegroundColor Yellow
    Write-Host "This will:" -ForegroundColor White
    Write-Host "  1. Re-associate the owner group at web level" -ForegroundColor White
    Write-Host "  2. Ensure Full Control permissions are present" -ForegroundColor White
    Write-Host "  3. Configure group ownership" -ForegroundColor White
    Write-Host "  4. Verify the repair" -ForegroundColor White
    Write-Host "`nType 'YES' to proceed, or anything else to cancel" -ForegroundColor Yellow
    $confirmation = Read-Host "Proceed"

    if ($confirmation -ne "YES") {
        Write-Host "`nOperation cancelled by user. No changes were made." -ForegroundColor Yellow
        Write-Host "All reports have been saved to: $outputDir" -ForegroundColor Cyan
        return
    }

    # Execute the repair
    Write-Host "`nProceeding with live execution..." -ForegroundColor Green
    $executionLog = Repair-AssociatedOwnerGroup -GroupsInfo $groupsInfo

    $executionLogPath = Join-Path $outputDir "04_Execution_Log.csv"
    $executionLog | Export-Csv -Path $executionLogPath -NoTypeInformation -Encoding UTF8
    Write-Host "`nExecution log saved: $executionLogPath" -ForegroundColor Cyan

    # Verify final state
    Write-Host "`n╔════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                   FINAL VERIFICATION                   ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

    $finalGroupsInfo = Get-CurrentAssociatedGroups
    $finalPermissionsReport = Show-AssociatedGroupPermissions -GroupsInfo $finalGroupsInfo

    $finalStatePath = Join-Path $outputDir "05_Final_State.csv"
    $finalPermissionsReport | Export-Csv -Path $finalStatePath -NoTypeInformation -Encoding UTF8
    Write-Host "`nFinal state saved: $finalStatePath" -ForegroundColor Cyan

    Write-Host "`n╔════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║                  REPAIR COMPLETE                       ║" -ForegroundColor Green
    Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host "All reports saved to: $outputDir" -ForegroundColor Cyan
    Write-Host "`nGenerated files:" -ForegroundColor White
    Write-Host "  1. Initial State: 01_Initial_State.csv" -ForegroundColor White
    Write-Host "  2. All Site Groups: 02_All_Site_Groups.csv" -ForegroundColor White
    Write-Host "  3. Dry-run Preview: 03_DryRun_Preview.csv" -ForegroundColor White
    Write-Host "  4. Execution Log: 04_Execution_Log.csv" -ForegroundColor White
    Write-Host "  5. Final State: 05_Final_State.csv" -ForegroundColor White

    Write-Host "`n╔════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "║                  NEXT STEPS                            ║" -ForegroundColor Yellow
    Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
    Write-Host "1. Wait 5-10 minutes for changes to propagate" -ForegroundColor White
    Write-Host "2. Have a site owner log out and log back in" -ForegroundColor White
    Write-Host "3. Try accessing Site Settings > Advanced Permissions" -ForegroundColor White
    Write-Host "4. If still not working, clear browser cache or try incognito" -ForegroundColor White
}

# Run the script
Start-OwnerGroupRepair
