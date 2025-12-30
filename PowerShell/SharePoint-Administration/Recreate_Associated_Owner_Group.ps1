# ============================================================================
# Recreate Associated Owner Group - Nuclear Option
# ============================================================================
# Purpose: Create a brand new associated owner group and migrate members
#          Use this when the existing group is too broken to fix
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

# Function to get members from old group
function Get-OldGroupMembers {
    param (
        [string]$GroupName
    )

    Write-Host "`nGetting members from old group: $GroupName" -ForegroundColor Cyan

    try {
        $group = Get-PnPGroup -Identity $GroupName -ErrorAction Stop
        $members = Get-PnPGroupMember -Identity $GroupName

        Write-Host "Found $($members.Count) members:" -ForegroundColor Yellow
        foreach ($member in $members) {
            Write-Host "  - $($member.Title) ($($member.LoginName))" -ForegroundColor White
        }

        return $members
    }
    catch {
        Write-Host "Error getting members: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

# Function to create new group
function New-OwnerGroup {
    param (
        [string]$GroupName,
        [string]$Description,
        [array]$Members,
        [switch]$DryRun
    )

    Write-Host "`n╔════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║              CREATING NEW OWNER GROUP                  ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

    if ($DryRun) {
        Write-Host "[DRY-RUN] Would create group: $GroupName" -ForegroundColor Magenta
        Write-Host "[DRY-RUN] Would add $($Members.Count) members" -ForegroundColor Magenta
        return $null
    }

    try {
        # Step 1: Create the new group
        Write-Host "Step 1: Creating new group '$GroupName'..." -ForegroundColor Yellow

        $newGroup = New-PnPGroup -Title $GroupName -Description $Description
        Write-Host "  ✓ Group created (ID: $($newGroup.Id))" -ForegroundColor Green

        # Step 2: Add members
        Write-Host "`nStep 2: Adding members to new group..." -ForegroundColor Yellow

        $addedCount = 0
        $failedCount = 0

        foreach ($member in $Members) {
            try {
                Add-PnPGroupMember -LoginName $member.LoginName -Group $GroupName
                Write-Host "  ✓ Added: $($member.Title)" -ForegroundColor Green
                $addedCount++
            }
            catch {
                Write-Host "  ✗ Failed to add: $($member.Title) - $($_.Exception.Message)" -ForegroundColor Red
                $failedCount++
            }
        }

        Write-Host "`nMember migration summary:" -ForegroundColor Cyan
        Write-Host "  Added: $addedCount" -ForegroundColor Green
        Write-Host "  Failed: $failedCount" -ForegroundColor Red

        # Step 3: Grant Full Control
        Write-Host "`nStep 3: Granting Full Control to new group..." -ForegroundColor Yellow

        Set-PnPGroupPermissions -Identity $newGroup.Id -AddRole "Full Control"
        Write-Host "  ✓ Full Control granted" -ForegroundColor Green

        # Step 4: Set group as its own owner
        Write-Host "`nStep 4: Setting group as its own owner..." -ForegroundColor Yellow

        try {
            Set-PnPGroup -Identity $newGroup.Id -Owner $newGroup.LoginName
            Write-Host "  ✓ Group ownership configured" -ForegroundColor Green
        }
        catch {
            Write-Host "  Warning: Could not set group ownership - $($_.Exception.Message)" -ForegroundColor DarkYellow
        }

        return $newGroup
    }
    catch {
        Write-Host "ERROR creating new group: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

# Function to set as associated owner group
function Set-AsAssociatedOwnerGroup {
    param (
        [int]$GroupId,
        [string]$GroupTitle,
        [switch]$DryRun
    )

    Write-Host "`n╔════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║        SETTING AS ASSOCIATED OWNER GROUP               ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

    if ($DryRun) {
        Write-Host "[DRY-RUN] Would set group ID $GroupId as associated owner group" -ForegroundColor Magenta
        return $true
    }

    try {
        Write-Host "Setting '$GroupTitle' as associated owner group..." -ForegroundColor Yellow

        # Try REST API approach
        try {
            $body = @{
                "__metadata" = @{ "type" = "SP.Web" }
                "AssociatedOwnerGroup" = @{
                    "__metadata" = @{ "type" = "SP.Group" }
                    "Id" = $GroupId
                }
            } | ConvertTo-Json -Depth 3

            Invoke-PnPSPRestMethod -Method Post -Url "_api/web" -Content $body -ContentType "application/json;odata=verbose"
            Write-Host "  ✓ Associated owner group set (REST API)" -ForegroundColor Green
            return $true
        }
        catch {
            # Try CSOM approach
            Write-Host "  REST API failed, trying CSOM..." -ForegroundColor Yellow

            $web = Get-PnPWeb
            $ctx = Get-PnPContext
            $group = Get-PnPGroup -Identity $GroupId

            $web.AssociatedOwnerGroup = $group
            $web.Update()
            $ctx.ExecuteQuery()

            Write-Host "  ✓ Associated owner group set (CSOM)" -ForegroundColor Green
            return $true
        }
    }
    catch {
        Write-Host "  ✗ ERROR: Could not set as associated owner group" -ForegroundColor Red
        Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "`n  You'll need to set this manually:" -ForegroundColor Yellow
        Write-Host "    1. Go to Site Settings > Site Permissions" -ForegroundColor White
        Write-Host "    2. Click Settings > Site Settings" -ForegroundColor White
        Write-Host "    3. Click 'Set Up Groups for this Site'" -ForegroundColor White
        Write-Host "    4. Select '$GroupTitle' as the Owner group" -ForegroundColor White
        return $false
    }
}

# Function to remove old group
function Remove-OldGroup {
    param (
        [string]$GroupName,
        [switch]$DryRun
    )

    Write-Host "`n╔════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║              REMOVING OLD GROUP                        ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

    if ($DryRun) {
        Write-Host "[DRY-RUN] Would remove old group: $GroupName" -ForegroundColor Magenta
        return $true
    }

    Write-Host "⚠️  WARNING: About to delete the old group: $GroupName" -ForegroundColor Yellow
    Write-Host "This action cannot be undone!" -ForegroundColor Red
    Write-Host "`nType 'DELETE' to confirm deletion: " -ForegroundColor Yellow -NoNewline
    $confirmation = Read-Host

    if ($confirmation -ne "DELETE") {
        Write-Host "Deletion cancelled. Old group will remain." -ForegroundColor Yellow
        return $false
    }

    try {
        Write-Host "Removing old group..." -ForegroundColor Yellow

        # First remove all permissions
        $web = Get-PnPWeb
        $group = Get-PnPGroup -Identity $GroupName

        # Remove from role assignments
        try {
            $ctx = Get-PnPContext
            $ctx.Load($web.RoleAssignments)
            $ctx.ExecuteQuery()

            foreach ($roleAssignment in $web.RoleAssignments) {
                $ctx.Load($roleAssignment.Member)
                $ctx.ExecuteQuery()

                if ($roleAssignment.Member.Id -eq $group.Id) {
                    $roleAssignment.DeleteObject()
                    $ctx.ExecuteQuery()
                    break
                }
            }
        }
        catch {
            Write-Host "  Warning: Could not remove role assignments" -ForegroundColor DarkYellow
        }

        # Delete the group
        Remove-PnPGroup -Identity $GroupName -Force
        Write-Host "  ✓ Old group removed" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "  ✗ ERROR removing old group: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  You may need to remove it manually from Site Settings > People and groups" -ForegroundColor Yellow
        return $false
    }
}

# Main script execution
function Start-GroupRecreation {
    Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                                                              ║" -ForegroundColor Cyan
    Write-Host "║        Recreate Associated Owner Group - Nuclear Option      ║" -ForegroundColor Cyan
    Write-Host "║                                                              ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "⚠️  WARNING: This is the NUCLEAR OPTION!" -ForegroundColor Red
    Write-Host "This script will:" -ForegroundColor Yellow
    Write-Host "  1. Create a brand new owner group" -ForegroundColor White
    Write-Host "  2. Copy all members from the old group" -ForegroundColor White
    Write-Host "  3. Set the new group as the associated owner group" -ForegroundColor White
    Write-Host "  4. Optionally delete the old broken group" -ForegroundColor White
    Write-Host "`nOnly use this if all other methods have failed!" -ForegroundColor Yellow
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

    # Get old group name
    Write-Host "`nEnter the name of the CURRENT (broken) owner group" -ForegroundColor Yellow
    Write-Host "Example: 'WPs Content Owners'" -ForegroundColor Gray
    $oldGroupName = Read-Host "Old group name"

    if ([string]::IsNullOrWhiteSpace($oldGroupName)) {
        Write-Host "Group name cannot be empty. Exiting." -ForegroundColor Red
        return
    }

    # Verify the old group exists and get members
    $oldMembers = Get-OldGroupMembers -GroupName $oldGroupName

    if (-not $oldMembers) {
        Write-Host "Could not find or access the old group. Exiting." -ForegroundColor Red
        return
    }

    if ($oldMembers.Count -eq 0) {
        Write-Host "`n⚠️  WARNING: The old group has no members!" -ForegroundColor Yellow
        Write-Host "Are you sure this is the correct group?" -ForegroundColor Yellow
        $continue = Read-Host "Continue anyway? (yes/no)"
        if ($continue -ne "yes") {
            Write-Host "Operation cancelled." -ForegroundColor Yellow
            return
        }
    }

    # Get new group name
    Write-Host "`nEnter the name for the NEW owner group" -ForegroundColor Yellow
    Write-Host "Suggestion: '$oldGroupName - NEW' or just '$oldGroupName' if you'll delete the old one" -ForegroundColor Gray
    $newGroupName = Read-Host "New group name"

    if ([string]::IsNullOrWhiteSpace($newGroupName)) {
        Write-Host "Group name cannot be empty. Exiting." -ForegroundColor Red
        return
    }

    # Check if new group name already exists
    try {
        $existingGroup = Get-PnPGroup -Identity $newGroupName -ErrorAction SilentlyContinue
        if ($existingGroup) {
            Write-Host "`nERROR: A group named '$newGroupName' already exists!" -ForegroundColor Red
            Write-Host "Please choose a different name." -ForegroundColor Yellow
            return
        }
    }
    catch {
        # Good, group doesn't exist
    }

    # Confirmation
    Write-Host "`n╔════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "║                     CONFIRMATION                       ║" -ForegroundColor Yellow
    Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
    Write-Host "Ready to proceed with the following plan:" -ForegroundColor White
    Write-Host "`nOld group: $oldGroupName" -ForegroundColor Cyan
    Write-Host "  - Members to migrate: $($oldMembers.Count)" -ForegroundColor White
    Write-Host "`nNew group: $newGroupName" -ForegroundColor Green
    Write-Host "  - Will be created with Full Control" -ForegroundColor White
    Write-Host "  - Will be set as associated owner group" -ForegroundColor White
    Write-Host "  - All members will be copied" -ForegroundColor White
    Write-Host "`nType 'YES' to proceed, or anything else to cancel" -ForegroundColor Yellow
    $confirmation = Read-Host "Proceed"

    if ($confirmation -ne "YES") {
        Write-Host "`nOperation cancelled by user." -ForegroundColor Yellow
        return
    }

    # Create the new group
    $newGroup = New-OwnerGroup -GroupName $newGroupName -Description "Site Owners - Recreated $(Get-Date -Format 'yyyy-MM-dd')" -Members $oldMembers

    if (-not $newGroup) {
        Write-Host "`nFailed to create new group. Exiting." -ForegroundColor Red
        return
    }

    # Set as associated owner group
    $setSuccess = Set-AsAssociatedOwnerGroup -GroupId $newGroup.Id -GroupTitle $newGroupName

    if (-not $setSuccess) {
        Write-Host "`n⚠️  The new group was created but could not be set as the associated owner group automatically." -ForegroundColor Yellow
        Write-Host "You'll need to complete this step manually (see instructions above)." -ForegroundColor Yellow
    }

    # Ask about removing old group
    Write-Host "`n╔════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "║              CLEAN UP OLD GROUP?                       ║" -ForegroundColor Yellow
    Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
    Write-Host "Do you want to remove the old group '$oldGroupName'?" -ForegroundColor Yellow
    Write-Host "It's recommended to:" -ForegroundColor White
    Write-Host "  1. Wait 24 hours" -ForegroundColor White
    Write-Host "  2. Verify the new group works" -ForegroundColor White
    Write-Host "  3. Then remove the old group" -ForegroundColor White
    Write-Host "`nRemove old group now? (yes/no)" -ForegroundColor Yellow -NoNewline
    $removeOld = Read-Host

    if ($removeOld -eq "yes") {
        Remove-OldGroup -GroupName $oldGroupName
    }
    else {
        Write-Host "Old group will remain. You can remove it later from Site Settings > People and groups" -ForegroundColor Cyan
    }

    # Final summary
    Write-Host "`n╔════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║                  OPERATION COMPLETE                    ║" -ForegroundColor Green
    Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host "`nSummary:" -ForegroundColor Cyan
    Write-Host "  ✓ New group created: $newGroupName (ID: $($newGroup.Id))" -ForegroundColor Green
    Write-Host "  ✓ Members migrated: $($oldMembers.Count)" -ForegroundColor Green
    Write-Host "  ✓ Full Control granted" -ForegroundColor Green

    if ($setSuccess) {
        Write-Host "  ✓ Set as associated owner group" -ForegroundColor Green
    }
    else {
        Write-Host "  ⚠ Needs manual association (see instructions above)" -ForegroundColor Yellow
    }

    Write-Host "`nNext steps:" -ForegroundColor Yellow
    Write-Host "  1. Wait 5-10 minutes for changes to propagate" -ForegroundColor White
    Write-Host "  2. Have a site owner sign out and back in" -ForegroundColor White
    Write-Host "  3. Test accessing Site Settings > Advanced Permissions" -ForegroundColor White
    Write-Host "  4. If everything works, you can remove the old group later" -ForegroundColor White
}

# Run the script
Start-GroupRecreation
