# Connect to Rolin Forgeworld Site for testing
Connect-pnpOnline -Url https://companynet.sharepoint.com/sites/RolinForgeworld -clientId CLIENT_ID -interactive

### Make sure file is not checked out by another user

# Get current CanvasContent1 from the list item
$pageItem = Get-PnPListItem -List "Site Pages" -Id 2 -Fields "CanvasContent1"
$currentCanvas = $pageItem.FieldValues["CanvasContent1"]

Write-Host "===== ORIGINAL CONTENT =====" -ForegroundColor Cyan
Write-Host $currentCanvas
Write-Host "=============================" -ForegroundColor Cyan

# Get page as file
$file = Get-PnPFile -Url "SitePages/TestPage.aspx"
# undo checkout with admin override
$file.UndoCheckOut()
Invoke-PnPQuery
Write-Host "Page checked in" -ForegroundColor Green

# Get the list item using CSOM
$ctx = Get-PnPContext
$list = $ctx.Web.Lists.GetByTitle("Site Pages")
$item = $list.GetItemById(2)
$ctx.Load($item)
$ctx.ExecuteQuery()

# Set CanvasContent1 directly
$freshContent = '[{"controlType":4,"id":"textSection1","position":{"zoneIndex":1,"sectionIndex":1,"controlIndex":1},"innerHTML":"<p>Test content from CSOM</p>"}]'
$item["CanvasContent1"] = $freshContent
$item.Update()
$ctx.ExecuteQuery()

Write-Host "Saved via CSOM" -ForegroundColor Green

# Read it back
$ctx.Load($item)
$ctx.ExecuteQuery()
Write-Host "CanvasContent1: " $item["CanvasContent1"] -ForegroundColor Cyan

# Publish
$item["_ModerationStatus"] = 0
$item.Update()
$ctx.ExecuteQuery()

Write-Host "Published! Check the page now." -ForegroundColor Green

# Write-Host "===== SAVED CANVASCONTENT1 =====" -ForegroundColor Cyan
# Write-Host $savedCanvas
# Write-Host "================================" -ForegroundColor Cyan

# # Check the length
# Write-Host "Length: $($savedCanvas.Length)" -ForegroundColor Yellow

# Write-Host "CanvasContent1 updated successfully." -ForegroundColor Green

# Publish the page
Set-PnPListItem -List "Site Pages" -Identity 2 -Values @{"_ModerationStatus" = 0 }

Write-Host "Page published successfully." -ForegroundColor Green
