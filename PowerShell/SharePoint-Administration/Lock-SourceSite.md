# 🔒 Lock-SourceSite.ps1

> Post-migration site lockdown automation for SharePoint Online

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-blue.svg)](https://github.com/PowerShell/PowerShell)
[![PnP](https://img.shields.io/badge/PnP-PowerShell-orange.svg)](https://pnp.github.io/powershell/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)


## 📋 Overview

This script automates the process of locking down SharePoint sites after a successful migration by converting all non-Full Control permissions to Read-Only; i.e., all permission groups that aren't Owners of the site, will have their permissions set to Read-Only. 
This prevents accidental modifications to the source site while preserving administrative access for cleanup and archival tasks. It also helps in forcing users to use the new site instead of continuing on the old one, potentially losing work. 


### Use Case

**Problem:** After migrating SharePoint content to a new site, the source site should be preserved as read-only to maintain data integrity and prevent users from continuing to work in the old location. 

**Solution:** This script systematically identifies and converts all permissions (except Full Control) to Read-Only across:
- Site-level groups
- Lists and document libraries with broken inheritance
- Folders with unique permissions
- Nested subsites (recursive)


## ✨ Features

- **Intelligent permission management:**
    - Preserves Full Control permissions
    - Converts Contribute, Edit, Design, etc., to Read-Only
    - Handles broken inheritance at all levels
    
- **Safety & auditability:**
    - Dry-run mode for testing (`-DryRun` parameter)
    - Confirmation prompts before changes
    - CSV export of all modifications
    - Progress indicators for large datasets
    
- **Enterprise-ready:**
    - Retry logic for authentication
    - Error handling and reporting
    - Optimized for large tenants ("quiet mode" for 100+ items)
    
## 🚀 Usage

### Basic syntax

```powershell
.\Lock-SourceSite.ps1 -SiteUrl "https://companynet.sharepoint.com/sites/SourceSite" [-DryRun]
```

### Parameters

| Parameter | Type | Required | Description |
| - | - | - | - |
| -SiteUrl | String | ✅ Yes | The full URL of the SharePoint site to lock down |
| -DryRun | Switch | ❌ No | Preview changes without applying them |

### Examples

<details><summary><b>Example 1: Dry run (preview-only)</b></summary>

```powershell
╔════════════════════════════════════════════════════════╗
║           SOURCE SITE LOCKDOWN SCRIPT                         ║
╚════════════════════════════════════════════════════════╝

⚠️  DRY-RUN MODE - NO CHANGES WILL BE MADE ⚠️

Target Site: https://companynet.sharepoint.com/sites/OldProject
Connecting to the site... (Attempt 1 of 3)
Connection successful!

--- Analyzing Group Permissions ---
✓ Retrieved 45 total groups in 2.3 seconds
✓ Filtered to 12 groups (33 system groups excluded)

  🔒 Will lock to Read: Project Members
  🔒 Will lock to Read: Project Visitors
  ✓ Preserve Full Control: Project Owners

=== Analysis Summary ===
Groups to preserve (Full Control): 1
Groups to lock (Set to Read): 11
```
</details>

<details> <summary><b>Example 2: Production run with full lockdown</b></summary>

```powershell
.\Lock-SourceSite.ps1 -SiteUrl "https://companynet.sharepoint.com/sites/Migration2024"
```

The script will:
1. Analyze all site groups
2. Prompt for confirmation
3. Lock site-level permissions
4. Ask if you want to scan for broken inheritance
5. Ask if you want to process subsites
6. Offer to export audit report
</details>

<details> <summary><b>Example 3: Subsites with broken inheritance</b></summary

When prompted during execution, the script will ask:
1. Scan for broken inheritance? → Y
2. Lock these items? → Y
3. Process subsites recursively? → Y
4. Export lockdown report to CSV? → Y

**Result:** Complete lockdown, including all nested contents and with an audit trail.

</details>


## 📊 Output

**Console output:**
* **Color-coded feedback:**
    * 🟢 $\color{Green}{Green:}$ Successful operations
    * 🟡 $\color{Yellow}{Yellow:}$ Warnings and items to be changed
    * 🔴 $\color{Red}{Red:}$ Errors
    * 🔵 $\color{Cyan}{Cyan:}$ Sections headers and progress
* **Progress tracking:**
    * Quiet mode activates for 100+ items
    * Periodic updates (1, 5, 10, 20, then every 50)
    

## ⚙️ Prerequisites

### Required modules

**SharePoint PnP** must be installed in your PC and have local administrator permissions. It can be installed via this command:

```powershell
Install-Module -Name PnP.PowerShell -Scope CurrentUser
```
Though please double-check the most recent and correct way of installing PowerShell modules in your PC.

### Required permissions

* **SharePoint:** Site Collection Administrator on the target site. Being merely a site owner with "Full Control" permissions will not suffice. 
* **App Registration:** The script uses interactive authentication with Client ID and Azure.
    * _Update line 48 with your own Client ID or use delegated permissions_


## 🔐 Security considerations

### What's not modified

The script excludes these system groups automatically:

* Limited Access*
* SharingLinks*
* STE_*
* Everyone*
* Company Administrator*
* GUID-named groups (temporary sharing links)


## 🛠️ Customization

### Modify System Group filters

Edit the `Get-AllSiteGroups` function (lines 93 - 103):

```powershell
$filteredGroups = $allGroups | Where-Object {
    $title = $_.Title
    $title -notlike "Limited Access*" -and
    $title -notlike "AnotherCustomPattern" # Add whatever you'd like to exclude
}
```

## 📈 Performance notes

* **Small sites (<50 groups):** ~30 seconds
* **Medium sites (50 - 200 groups):** 2 - 5 minutes
* **Large sites (200+ groups, broken inheritance):** 10 - 30 minutes
* **For really large sites with lots of broken inheritance and subsites:** 1 hour or more


## ⚠️ Known limitations

* Does not modify individual user permissions (only groups)
* Requires manual cleanup of temporary sharing links
* Subsites must be processed one at a time and you have to confirm "Y" in order to proceed with the next one
* Still susceptible to SharePoint timeouts if ran continously or multiple times for a long, consecutive time period

## 📝 Licence

MIT Licence - Free to use and modify for your environment