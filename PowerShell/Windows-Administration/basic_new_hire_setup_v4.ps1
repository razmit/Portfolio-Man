# Check if the script is running with Administrator privileges
$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
$adminRole = [Security.Principal.WindowsBuiltInRole]::Administrator

if (-Not $principal.IsInRole($adminRole)) {
    # Relaunch the script as administrator
    $scriptPath = $MyInvocation.MyCommand.Path
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs
    exit
}

Write-Host "Running as Administrator!"

# Define Edge bookmarks file path
$BookmarksFile = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Bookmarks"

# New bookmarks to add
$NewBookmarks = @(
    @{ "name" = "DASH"; "url" = "https://dash.company.com/now/nav/ui/classic/params/target/welcome.do" }
    @{ "name" = "Workday"; "url" = "https://www.myworkday.com/rsm/d/pex/home.htmld" }
    @{ "name" = "Owning My Future"; "url" = "https://sso.company.com/idp/startSSO.ping?PartnerSpId=CSOD_SSO&TargetResource=" }
    @{ "name" = "COMPANY_NAME US-El Salvador Team Site"; "url" = "https://companynet.sharepoint.com/sites/Teams/Consulting/elsalvadorteam/Pages/default.aspx" }
    @{ "name" = "COMPANY_NAME US SV Office"; "url" = "https://companynet.sharepoint.com/sites/Teams/Consulting/elsalvadorteam/Pages/COMPANY_NAME-US-SV-Office.aspx" }
    @{ "name" = "Secret Server"; "url" = "https://secret.company_old.rsm.net/dashboard.aspx" }
    @{ "name" = "US-El Salvador Careers"; "url" = "https://company.com/careers/el-salvador.html" }
)

# Ensure Edge is closed before modifying bookmarks
Stop-Process -Name "msedge" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2  # Give it time to close

# If the bookmarks file doesn't exist, launch Edge once to generate it
if (-Not (Test-Path $BookmarksFile)) {
    Write-Host "Edge has never been run before. Launching Edge to generate the bookmarks file..."
    Start-Process "msedge.exe"
    Start-Sleep -Seconds 5  # Give Edge time to initialize
    Stop-Process -Name "msedge" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2  # Wait for Edge to fully close
}

# If the bookmarks file still doesn't exist, create a minimal structure
if (-Not (Test-Path $BookmarksFile)) {
    Write-Host "Edge bookmarks file still missing. Creating a minimal bookmarks file..."
    $DefaultBookmarks = @{
        roots = @{
            bookmark_bar = @{
                children = @()
            }
        }
    }
    $DefaultBookmarks | ConvertTo-Json -Depth 10 | Set-Content -Path $BookmarksFile -Force
}

# Read bookmarks JSON
$BookmarksJson = Get-Content $BookmarksFile -Raw | ConvertFrom-Json -Depth 10

# Ensure bookmark bar exists
if (-Not $BookmarksJson.roots.bookmark_bar) {
    $BookmarksJson.roots | Add-Member -MemberType NoteProperty -Name "bookmark_bar" -Value @{ "children" = @() }
}

# Ensure children array exists
if (-Not $BookmarksJson.roots.bookmark_bar.children) {
    $BookmarksJson.roots.bookmark_bar | Add-Member -MemberType NoteProperty -Name "children" -Value @()
}

$BookmarkBar = $BookmarksJson.roots.bookmark_bar.children

# Add new bookmarks
foreach ($Bookmark in $NewBookmarks) {
    $Exists = $BookmarkBar | Where-Object { $_.url -eq $Bookmark.url }
    if (-not $Exists) {
        $BookmarkBar += @{
            "type" = "url"
            "name" = $Bookmark.name
            "url" = $Bookmark.url
        }
    }
}

# Save updated bookmarks JSON
$BookmarksJson | ConvertTo-Json -Depth 10 | Set-Content -Path $BookmarksFile -Force

# Restart Edge
Start-Process "msedge.exe"

Write-Host "Bookmarks added successfully!"

#Add the US-International keyboard layout to the newly imaged PC

$LanguageList = Get-WinUserLanguageList
$LanguageList[0].InputMethodTips.Add('0409:00020409') #Code for US-Int keyboard
$LanguageList[0].InputMethodTips.Remove('0409:00000409') #Remove original US keyboard
Set-WinUserLanguageList $LanguageList -Force #Set Language List 

# Set TimeZone to UTC-06:00

Set-TimeZone -Id "Central America Standard Time"

Read-Host "Press Enter to continue with QA"

#QA Checklist .exe#

# Aliases don't work for full paths, only for executables or cmdlets
# New-Alias QaChecklistApp "C:\Source\QA Checklist\QA Checklist.exe"
# Invoke-Item QaChecklistApp

function QaChecklistApp { Invoke-Item "C:\Source\QA Checklist\QA Checklist.exe" }
QaChecklistApp
Read-Host "Press Enter to exit"