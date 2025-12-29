# :notebook: PowerShell Scripts

Automation scripts for Windows administration, Microsoft 365 management, and enterprise IT workflows. I've made the names of the scripts to be pretty self-descriptive, but for any doubts, there's documentation inside of them. And feel free to contact me for any clarifications, suggestions, or comments in general.

> [!WARNING]
> Some scripts may be incomplete and/or undergoing development. They'll be separated in their respective folders for "Completed" and "In-Progress".

## Categories

### SharePoint-Administration/
Scripts for SharePoint Online management using PnP PowerShell:
- **Site lockdown automation** - Post-migration permission management.
- **Permission auditing** - Export and analyze SharePoint permissions.
- **Content migration tools** - Document library and metadata migration.
- **Bulk operations** - Mass user management, domain whitelisting.


### Windows-Automation/
System administration and user provisioning scripts:
- **New hire setup automation** - Standardized workstation configuration.
- **Application deployment** - Silent installations and configurations.
- **System utilities** - Scheduled tasks, registry management.


## Technologies Used

- **PnP / SPO PowerShell** - SharePoint Online management.
- **Microsoft Graph API** - Microsoft 365 automation.
- **Windows Management** - Registry, user profiles, scheduled tasks, file exports and imports.


## Usage Notes

These scripts are designed for enterprise environments and include:
- Error handling and retry logic
- Dry-run modes for safe testing
- Detailed logging and progress indicators
- CSV exports for audit trails


> [!IMPORTANT] 
> Update placeholder values (URLs, Client IDs, tenant names) before use in your environment.
