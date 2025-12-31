# 🔄 Auto_migrate_perm_groups.ps1

> Comprehensive SharePoint permission migration automation for enterprise-scale site migrations.

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-blue.svg)](https://github.com/PowerShell/PowerShell)
[![PnP](https://img.shields.io/badge/PnP-PowerShell-orange.svg)](https://pnp.github.io/powershell/)
[![Lines of Code](https://img.shields.io/badge/lines-2,233-success.svg)](Auto_migrate_perm_groups.ps1)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)


## 📋 Overview

A production-ready, enterprise-scale tool that automates the complete migration of SharePoint permissions, groups, and security configurations between sites. Designed to handle complex migration scenarios, including Classic-to-Modern transformations, site flattening, and massive permission structures with thousands of unique assignments. 

It is recommended to be used _after_ a migration performed by Sharegate, especially for big and **really big** sites with dozens of document libraries, lists, and folders with broken inheritance, and where permissions are required to be the same as in the old, source site. 

### The problem

SharePoint migrations can be notoriously complex:
- **Permissions don't migrate automatically** - Groups, members, and custom permission levels must be recreated
- **Broken inheritance** creates thousands of unique permission assignments across lists, libraries, and folders
- **Classic → Modern migrations** often require site structure changes, where what was once a subsite, is now the top-level site. I like to call this _flattening_ of a site
- **Manual migration** of even a single site's permissions can take days and is error-prone
- **No audit trail** leaves compliance and security gaps

### The solution

This script provides full-fidelity permission migrations with:
- Automated group recreation with member assignments
- Deep scanning for broken inheritance (lists, libraries, and individual folders - **no individual files**)
- Subsite support with automatic path mapping
- Site flattening capabilities (subsite → top-level site)
- CSV audit logs
- Dry-run mode for safe testing


## ✨ Features

### 🎯 Comprehensive migration coverage

**Site-level security:**
    - Site collection administrators are migrated
    - SharePoint groups (Owners, Members, Visitors, and custom groups)
    - Group membership (users and nested groups)
    - Custom permission levels
    - Associated group configurations


### 🛡️ Intelligent filtering

**Auto-excluded system artifacts:**
    - `Limited Access*` groups 
    - `SharingLinks*` temporary sharing groups
    - GUID-named groups (anonymous sharing links)
    - `STE_*` system groups
    - `Everyone` and `Company Administrator` built-ins


### 🚀 Advanced capabilities

1. **Site structure transformation:**
    - **Classic → Modern** migrations
    - **Modern → Modern** migrations
    - **Site flattenings:** Convert subsites to top-level sites
        - Original: `https://company.sharepoint.com/sites/ParentSite/SubSite`
        - Migrated: `https://company.sharepoint.com/sites/SubSite`
        - Automatic path remapping for broken inheritance
        
2. **Migration modes:**
    - **CSV-based selection** - Choose from all site collections that are exported to a local CSV the first time this script is ran every day
    - **Manual URL entry (recommended)** - Precise control for subsites and custom scenarios
    
3. **Dry-run mode**

4. **Quiet mode** for large datasets (100+ groups)

5. **Progress tracking** - milestones at 1, 5, 10, 20, and then every 50 items

6. **CSV audit export** - complete record of all migrated permissions

7. **Interactive confirmations** - Safety prompts before destructive operations


## 🚀 Usage

### Basic workflow

The script guides you through an interactive process:

```powershell
.\Auto_migrate_perm_groups.ps1

# 1. Choose site selection method
#   [1] CSV-based for site collections
#   [2] Manual URL entry for subsites/flattening and more precise control

# 2. Select source site
#   - Search by name/URL fragment (if option 1 was chosen)
#       * Preview potential matches before confirming
#   - Insert source site's complete URL (if option 2 was chosen)

# 3. Select destination site
#   - Search by name/URL fragment (if option 1 was chosen)
#       * Preview potential matches before confirming
#   - Script proposes URL mapping automatically (if option 2 was chosen and after searching for a potential match if option 1 was chosen)
#       * The proposed URL can be accepted or a different one can be inserted. Most often used for when site flattening is necessary 

# 4. Review migration plan
#   - Source → Destination mapping
#   - Subsite path transformations (if applicable)

# 5. Migration commences
#   - Groups, their members, and their permissions are gathered from the source
#   - Groups are created in the destination, their members added, and their permissions assigned
#   - Subsites processed recursively if detected (asked for confirmation for each of them)

# 6. CSV reports generated
#   - Group migration log
#   - Subsite migration log
```

### Common scenarios

<details><summary><b> Scenario 1: Classic site collection → Modern site collection</b></summary>

**Use case:** Migrating an entire Classic site collection to a new Modern site with or without subsites

**Steps:**
1. Run the script
2. Choose the input option for the source and destination sites' URLs - it's either through a local CSV search, or by writing the source site's URL in full
3. Accept or reject the proposed URL for the destination site. If rejected, write the URL for the destination site (must be an existing site)
4. The script maps the source site to the destination site: `/sites/OldClassicSite` → `/sites/NewModernSite`
5. Confirm migration
6. As the migration continues, you'll be prompted if you want to migrate subsites as well. Accept or reject it
7. If the subsites are migrated, too, then a prompt will appear for every individual subsite that you'll have to approve or reject
8. Success, warning, or error messages will appear in the console
9. After the migration is completed, you'll be prompted if you want to export all of the migrated groups and permissions to a CSV. Accept or reject it

**What gets migrated:**
- All site-level groups and members
- Custom permission levels
- Site collection admins
- All subsites if there are any and are chosen to be migrated (with path preservation: `/sites/Old/Sub1` → `/sites/New/Sub1`)
- Broken inheritance on all lists/libraries/folders. Individual file permissions are **not** migrated

**Typical runtime:** 30 - 60 minutes for moderate complexity. For very large sites, it can take more
</details>

<details><summary><b> Scenario 2: Subsite flattening</b></summary>

**Use case:** Promoting a subsite to a Modern standalone site

**Before:**

```powershell
Source: https://company.sharepoint.com/sites/OldParent/ImportantSubsite
```

**After:**

```powershell
Destination: https://company.sharepoint.com/sites/ImportantSubsite
```

**Steps:**
1. Run the script
2. Select **[2] Manual URL entry**
3. Enter source: `https://company.sharepoint.com/sites/OldParent/ImportantSubsite`
4. Enter destination: `https://company.sharepoint.com/sites/ImportantSubsite`
5. Script detects flattening and proposes mapping:
    - Any subsites contained in the source will have their paths adjusted to the new top-level site
6. Confirm migration

**Why this matters:**

Classic site hierarchies often need flattening for Modern sites. The recommended structure for modern SharePoint is wide-and-shallow, not narrow and deep as it tended to be with the majority of Classic sites. Since this script is intended to be executed _after_ a Sharegate migration has been completed, it is assumed the resulting destination site will follow the recommended wide-and-shallow structure, and thus will have the Classic subsite as the Modern top-level site.
This script handles that remapping automatically. 
</details>


## 📊 Output and reporting

### Console output

* **Color-Coded feedback:**
    * 🟢 $\color{Green}{Green:}$ Successful operations
    * 🟡 $\color{Yellow}{Yellow:}$ Warnings and items to be changed
    * 🔴 $\color{Red}{Red:}$ Errors
    * 🔵 $\color{Cyan}{Cyan:}$ Sections headers and progress
    * 🟣 $\color{Purple}{Magenta:}$ Dry-run indicators

* **Quiet mode (100+ groups):**

```powershell
Processing 3,547 groups (quiet mode enabled)...
Progress shown at 1, 5, 10, 20, then every 50 groups.

[1/3547] Groups processed...
[5/3547] Groups processed...
[10/3547] Groups processed...
[20/3547] Groups processed...
[50/3547] Groups processed...
[100/3547] Groups processed...
```


## ⚙️ Prerequisites

### Required modules

**SharePoint PnP** must be installed in your PC and have local administrator permissions. It can be installed via this command:

```powershell
Install-Module -Name PnP.PowerShell -Scope CurrentUser
```
Though please double-check the most recent and correct way of installing PowerShell modules in your PC.

### Required permissions

* **SharePoint:** Site Collection Administrator on both sites. Being merely a site owner with "Full Control" permissions will not suffice. 
* **App Registration:** The script uses interactive authentication with Client ID and Azure.


## 🔧 Core architecture

<details><summary><b> Click to expand function overview if you're interested</b></summary>

The script is modular with 20+ specialized functions. Most have self-describing names and follow appropriate naming conventions and verb usage, though others were made at a time of great sleep deprivation. 

### Connection management

* **`Connect-IndicatedSite`** - Retry logic for authentication
* **`Test-UserInput`** - Input validation and sanitization

### Migration core:

* **`Start-Migration`** - Main migration orchestrator
* **`Copy-SourceGroupsToDestination`** - Group recreation
* **`New-GroupInDestination`** - Group creation

### Permission discovery:

* **`Get-GroupsPermissions`** - Extract group permission levels
* **`Get-GroupMembers`** - Recursive member enumeration
* **`Get-ItemsWithBrokenInheritance`** - Deep scan for unique permissions
* **`Get-FoldersRecursively`** - Folder-level permission discovery

### Site structure:

* **`Get-SubSitesRecursively`** - Subsite enumeration
* **`Migrate-SubSitePermissions`** - Recursive subsite processing
* **`Convert-SourcePathToDestination`** - URL path remapping

### Admin & Associated Groups:

* **`Get-SiteCollectionAdministrators`** - Admin discovery
* **`Copy-SiteCollectionAdministrators`** - Admin migration
* **`Get-AssociatedGroups`** - Discover the Owners/Members/Visitros groups
* **`Copy-AssociatedGroups`** - Migrate the Owners/Members/Visitros groups

### Custom permissions:

* **`Copy-CustomPermissionLevels`** - Permission level cloning
* **`Set-ItemLevelPermissions`** - Apply permisions to items/folders (not individual files)

### Site discovery:

* **`Search-RequestedSites`** - Tenant-wide search and connection to the requested sites (source and destination)
* **`Get-SearchedSourceSite`** - Interactive source selection
* **`Get-SearchedDestinationSite`** - Interactive destination selection
* **`Get-ManualSiteUrls`** - Manual URL entry with validation

### Reporting:

* **`Export-PermissionsToCSV`** - Audit log generation
* **`Get-FilteredGroups`** - System group exclusion
</details>


## ⚠️ Known limitations & considerations

- User permissions are not migrated. Only group-based permissions
- Sharing links are not migrated
- OneNote Notebooks may require manual reconnection after migration
- Classic workflows do not migrate. They are being deprecated anyway


## Important notes

### Performance

* Really large sites with lots of libraries and folders that have broken inheritance will cause the script to take at least an hour or more to process everything
* Broken inheritance is the primary performance factor
* Consider migrating subsites separate for very large sites
* If possible, spread out the use of this script for very large sets of migrations over many days, in order to prevent SharePoint API restrictions

### Site structure

Associated groups (Owners, Members, and Visitors) are those that were created alongside the site itself, and have the site's name in their own. These are special groups, and **under no circumstances are their permissions to be removed**. The script does not replace them, but rather identifies the Associated groups from the source and relocates their members to these others in the destination site. 
The previous associated groups (and all other groups whose membership was above 0) will still be migrated to the destination, but as standard, custom-created groups

> [!TIP]
> Educate the would-be Owners and site collection admins in the destination site to **not** alter the permissions for the associated groups thinking they're regular groups. It's a nightmare to restore them



## 🧠 General recommendations

### Before migration

- [x] Run in dry-run first to preview changes. It is nowhere near as slow as the real run, and it allows you to take a peek at what groups have been detected and what would be changed in the destination
- [x] It's most effective right after a content migration, either with Sharegate (ideal) or manual
- [x] Confirm you have Site Collection Admin rights on the source and the destination sites
- [x] While the script is designed to _add_ permissions, it might also overwrite what's already there. I haven't had this happen yet, or at least haven't noticed (and if nobody complained, then it wasn't important), but it's worth to keep in mind

### During migration

- [x] Run during off-hours, but not too late, as you might still need to press "Y" or "N" to move the script forward
- [x] Make sure nobody is using the destination site
- [x] Document any errors that might appear
- [x] "User not found errors" are to be expected. Old sites are particularly affected, as users have left the company

### After migration

- [x] Communicate changes to the users of the destination site, or to their Owners
- [x] Offer to send over the exported CSV files with the permission changes to the Owners
- [x] Grab some permissions from the source site and compare them to the destination to quick-check that permissions were moved over correctly
- [x] With the source site's owner's approval, set all of the permissions to _"Read-Only"_. You can use another one of the scripts in this folder called `Lock-SourceSite.ps1`


## 🤝 Contributing

Found a bug or have an enhancement idea? Go crazy with it and let me know!
This is one of the first scripts I wrote and built upon, and though it already passed a couple of trials by fire in real, huge migrations, I'm no expert. Space for improvement is always there


## 📝 Licence

MIT Licence - Free to use and modify for your environment
