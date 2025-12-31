# 🔍 Find_Lost_File_Site-Wide.ps1

> Fast site-wide file search utility for SharePoint Online. Because sometimes the best things are the simplest

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-blue.svg)](https://github.com/PowerShell/PowerShell)
[![PnP](https://img.shields.io/badge/PnP-PowerShell-orange.svg)](https://pnp.github.io/powershell/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)


## 📋 Overview

A lightweight utility that searches across **all document libraries** in a SharePoint site to locate files by name. Solves the common problem of "I uploaded a file but can't remember where I put it."

It is also useful in cases where multiple people have several libraries of the same site synced to their OneDrive, and they "accidentally" move a file/folder to where it shouldn't be. 

### The problem

SharePoint sites often have dozens of document libraries, and users frequently upload them to the wrong library, forget the specific folder where they put it, or moved it to the wrong destination and can't find it again. 
**Why not just use SharePoint's search function?** Well, if it worked then I wouldn't have needed to make this script. It sometimes requires exact names, can be slow, or just not recognize the file/folder entirely; and when the user is in a panic trying to find a very important file, speed is of the essence. 

### The solution

This script provides **instant, comprehensive file discovery** by:
- Scanning all document libraries in real-time (no search index delays)
- Supporting partial name matching
- Displaying full file metadata - of particular interest, the path where it's located, its name, and when it was last modified
- Presenting results in a clean, readable format

**Typical use case:** User says "I uploaded the Q4 report yesterday but I can't find it!" or something equally panic-inducing → Run script → Found in seconds; if it exists, anyway


## ✨ Features

- **Site-wide scanning** - Searches every document library automatically
- **Partial name matching** - We can't expect the user to remember the exact name of the file that's missing
- **Detailed metadata** - Shows library name, full path, and modification date
- **Multiple matches** - Finds all files matching the search term 
- **Lightweight** - Fast execution with minimal overhead


## 🚀 Usage

### Basic setup

1. **Edit the script** to set your search parameters:

```powershell

# Line 1: Set your site URL 
Connect-PnPOnline -Url https://companynet.sharepoint.com/sites/YourSite -ClientId CLIENT_ID -Interactive

# Line 4: Set the filename to search for
$fileName = "Budget report"

```

2. **Run the script**

```powershell
.\Find_Lost_File_Site-Wide.ps1
```


### Search example

<details> <summary><b>Example: Find partial filename</b></summary>

**Search for:** "Budget" without any file extension or even sure if that's the file's full name.

```powershell
$fileName = "Budget"
```

**Output:**

```powershell
Searching for file 'Budget' across all document libraries...
======================================
Searching in library: Finance
Found something!
Found something!
Found something!
Searching in library: Archive
Found something!
Search completed!

There were 4 matches found.
======================================
File's Full Name: Budget-2024-Draft.xlsx
Found in library: Finance
File URL: /sites/MySite/Finance/Budget-2024-Draft.xlsx
Modified On: 2025-01-10 09:15:32
======================================
File's Full Name: Budget-2024-Final.xlsx
Found in library: Finance
File URL: /sites/MySite/Finance/Budget-2024-Final.xlsx
Modified On: 2025-01-15 16:42:11
======================================
File's Full Name: 2023-Budget-Archive.xlsx
Found in library: Archive
File URL: /sites/MySite/Archive/2023-Budget-Archive.xlsx
Modified On: 2024-12-31 17:05:00
======================================
File's Full Name: Budget Proposal Deck.pptx
Found in library: Finance
File URL: /sites/MySite/Finance/Budget Proposal Deck.pptx
Modified On: 2025-01-12 11:30:22
======================================

```

You can then take a screenshot of the results and send it to the inquiring user so they can confirm if they recognize one of the results of the search.
</details>


## 📊 Output format

**Console output:**
* **Color-coded feedback:**
    * 🟢 $\color{Green}{Green:}$ Match found
    * 🟡 $\color{Yellow}{Yellow:}$ Currently searching library
    * 🔴 $\color{Red}{Red:}$ No matches found
    * 🔵 $\color{Cyan}{Cyan:}$ Progress updates and section separators

* **Returned data fields**
For each match found:

| Field | Description | Example |
| - | - | - | - |
| File's full name | Complete filename with extension | Budget-Q4-2024.xlsx |
| Found in library | Document library title | Finance Documents | 
| File URL | Server-relative path | /sites/Finance/Documents/Budget-Q4-2024.xlsx |
| Modified On | Last modification timestamp | 2025-01-15 09:22:35 |


## ⚙️ Customization

**Case-sensitive search:**

```powershell
# Line 26 - change from:
if($item.FieldValues.FileLeafRef -like "*$fileName*")

# To:
if($item.FieldValues.FileLeafRef -clike "*$fileName*")  # -clike = case-sensitive
```

**Exact match only (no wildcards):**

```powershell
# Line 26 - Change from:
if($item.FieldValues.FileLeafRef -like "*$fileName*")

# To:
if($item.FieldValues.FileLeafRef -eq $fileName)
```

**Search by file extension:**

```powershell
# Find all Excel files
$fileName = ".xlsx"

# Find all Word documents
$fileName = ".docx"
```

**Additional file properties can be displayed** - Given that we're retrieving file objects from SharePoint, we can use any of their properties to display should we need to. In order to see which properties are available, we can use: 

```powershell
Get-PnPListItem | Get-Member
```


## ⚙️ Prerequisites

### Required modules

**SharePoint PnP** must be installed in your PC and have local administrator permissions. It can be installed via this command:

```powershell
Install-Module -Name PnP.PowerShell -Scope CurrentUser
```
Though please double-check the most recent and correct way of installing PowerShell modules in your PC

### Required permissions

* **SharePoint:** Site member or higher. Read access is required to all libraries and all folders
* **App Registration:** The script uses interactive authentication with Client ID and Azure


## ⚠️ Limitations

* **Site-scoped only** - Searches one site at a time
* **Document libraries only** - Doesn't search lists
* **Filename matching only** - Doesn't match file content
* **Manual configuration** - Filename must be edited in script


## 🤝 Contributing

Simple enhancement suggestions welcome!

## 📝 Licence

MIT Licence - Free to use and modify