######## Script for when I'm preparing a new hire's laptop ########

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

Write-Host "IT'S ALIIIIIIIIVEEEEEEE!"

# Insert the favorites links to Edge

# Define path to Edge's bookmarks file
$BookmarksFile = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Bookmarks"

# Links to add

$NewBookmarks = @(
    @{ "name" = "DASH"; "url" = "https://dash.company.com/now/nav/ui/classic/params/target/welcome.do"}
    @{ "name" = "Workday"; "url" = "https://www.myworkday.com/rsm/d/pex/home.htmld"}
    @{ "name" = "Owning My Future"; "url" = "https://sso.company.com/idp/startSSO.ping?PartnerSpId=CSOD_SSO&TargetResource="}
    @{ "name" = "COMPANY_NAME US-El Salvador Team Site"; "url" = "https://companynet.sharepoint.com/sites/Teams/Consulting/elsalvadorteam/Pages/default.aspx?xsdata=MDV8MDJ8fGY2MDFiZjM2ODE4NjQzMmFhMjI0MDhkYzQyMTRjMjZifDFlM2U3MWJlZmNjYTQyODQ5MDMxNjg4Y2M4ZjM3YjZifDB8MHw2Mzg0NTc5MDQxMDgzODA3MDh8VW5rbm93bnxWR1ZoYlhOVFpXTjFjbWwwZVZObGNuWnBZMlY4ZXlKV0lqb2lNQzR3TGpBd01EQWlMQ0pRSWpvaVYybHVNeklpTENKQlRpSTZJazkwYUdWeUlpd2lWMVFpT2pFeGZRPT18MXxMMk5vWVhSekx6RTVPamsxWVdGaU5qazRMV1ZpWmpVdE5HVTNaaTA0WmpKaExUSmxORFptWVRZM056UmlZbDloTURjeU5tRmlOeTAxTW1Ka0xUUTVabVV0WWpKaFlTMDVaamc1TnpReVltVTNNakJBZFc1eExtZGliQzV6Y0dGalpYTXZiV1Z6YzJGblpYTXZNVGN4TURFNU16WXdPVFl3TXc9PXw0ODYzNjQ5ZWM0YTY0NzVmNDAwNDA4ZGM0MjE0YzI2OXxhODA1NjA0MDU0MzU0YmY3OWNmMjE1ODk5ZjQ1NjNlYw%3D%3D&sdata=ZndEYWFUcktyaFlDZWVLSzFuSlZ5SFVHdGpwM2lkZ2k5OUE0MFNWRkozND0%3D&ovuser=1e3e71be-fcca-4284-9031-688cc8f37b6b%2CE107152%40company_old.rsm.net&OR=Teams-HL&CT=1710193877467&clickparams=eyJBcHBOYW1lIjoiVGVhbXMtRGVza3RvcCIsIkFwcFZlcnNpb24iOiIyNy8yNDAyMDExOTMwMyIsIkhhc0ZlZGVyYXRlZFVzZXIiOmZhbHNlfQ%3D%3D"}
    @{ "name" = "COMPANY_NAME US SV Office"; "url" = "https://companynet.sharepoint.com/sites/Teams/Consulting/elsalvadorteam/Pages/COMPANY_NAME-US-SV-Office.aspx?xsdata=MDV8MDJ8fGE3N2RlMTBmNzdlYjQ1NTkyOGRiMDhkYzQyMTRjNTJlfDFlM2U3MWJlZmNjYTQyODQ5MDMxNjg4Y2M4ZjM3YjZifDB8MHw2Mzg0NTc5MDQxNTQ2ODM2MTF8VW5rbm93bnxWR1ZoYlhOVFpXTjFjbWwwZVZObGNuWnBZMlY4ZXlKV0lqb2lNQzR3TGpBd01EQWlMQ0pRSWpvaVYybHVNeklpTENKQlRpSTZJazkwYUdWeUlpd2lWMVFpT2pFeGZRPT18MXxMMk5vWVhSekx6RTVPamsxWVdGaU5qazRMV1ZpWmpVdE5HVTNaaTA0WmpKaExUSmxORFptWVRZM056UmlZbDloTURjeU5tRmlOeTAxTW1Ka0xUUTVabVV0WWpKaFlTMDVaamc1TnpReVltVTNNakJBZFc1eExtZGliQzV6Y0dGalpYTXZiV1Z6YzJGblpYTXZNVGN4TURFNU16WXhORE0wTlE9PXxlZmUzZTMzN2Y2ODA0M2M4MjhkYjA4ZGM0MjE0YzUyZXwwY2ZkYzEwY2UzM2I0YTBlOGUwZGUxYmIwNjExNzU5Zg%3D%3D&sdata=eHBkNUtlRkc0Y1g2Yk1JMi9NdlhzWmhZOEdFVUY2ZWsrc1pkVDl4RitxTT0%3D&ovuser=1e3e71be-fcca-4284-9031-688cc8f37b6b%2CE107152%40company_old.rsm.net&OR=Teams-HL&CT=1710193885149&clickparams=eyJBcHBOYW1lIjoiVGVhbXMtRGVza3RvcCIsIkFwcFZlcnNpb24iOiIyNy8yNDAyMDExOTMwMyIsIkhhc0ZlZGVyYXRlZFVzZXIiOmZhbHNlfQ%3D%3D"}
    @{ "name" = "Secret Server"; "url" = "https://secret.company_old.rsm.net/dashboard.aspx"}
    @{ "name" = "US-El Salvador Careers"; "url" = "https://company.com/careers/el-salvador.html"}
)

# Check Bookmarks file exists

if (Test-Path $BookmarksFile) {
    $BookmarksJson = Get-Content $BookmarksFile -Raw | ConvertFrom-Json
} else {
    Write-Host "Edge bookmarks file not found. Exiting..."
    exit 1
}

$BookmarkBar = $BookmarksJson.roots.bookmark_bar

# Add new bookmarks

foreach ($Bookmark in $NewBookmarks) {
    $Exists = $BookmarkBar.children | Where-Object { $_.url -eq $Bookmark.url}
    if (-not $Exists) {
        $BookmarkBar.children += @{
            "type" = "url"
            "name" = $Bookmark.name
            "url" = $Bookmark.url
        }
    }
}

# Save the file 

$BookmarksJson | ConvertTo-Json -Depth 10 | Set-Content $BookmarksFile

# Restart Edge

Stop-Process -Name "msedge" -Force -ErrorAction SilentlyContinue
Start-Process "msedge.exe"

Write-Host "Bookmarks added successfully!"

#Add the US-International keyboard layout to the newly imaged PC

$LanguageList = Get-WinUserLanguageList
$LanguageList[0].InputMethodTips.Add('0409:00020409') #Code for US-Int keyboard
$LanguageList[0].InputMethodTips.Remove('0409:00000409') #Remove original US keyboard
Set-WinUserLanguageList $LanguageList -Force #Set Language List 

# Set TimeZone to UTC-06:00

Set-TimeZone -Id "Central America Standard Time"

Write-Host -Object ("The key that was pressed was: {0}" -f [System.Console]::ReadKey().Key.ToString())

#QA Checklist .exe#

# Aliases don't work for full paths, only for executables or cmdlets
# New-Alias QaChecklistApp "C:\Source\QA Checklist\QA Checklist.exe"
# Invoke-Item QaChecklistApp

function QaChecklistApp { Invoke-Item "C:\Source\QA Checklist\QA Checklist.exe" }
QaChecklistApp
Write-Host -Object ("The key that was pressed was: {0}" -f [System.Console]::ReadKey().Key.ToString())