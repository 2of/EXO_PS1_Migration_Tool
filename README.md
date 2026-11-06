# EXO PS1 Migration Tool

A PowerShell wrapper for migrating Distribution Lists (DLs), mail-enabled groups, members, and owners between Microsoft Exchange Online / Microsoft 365 tenants.

Works in two stages:

1. Connect to the **source tenant**, collect the existing DL configuration, resolve migrated identities, generate the proposed target configuration, and export the migration data.
2. Connect to the **target tenant**, import that data, validate it with a dry run, then recreate and populate the DLs.

The migration data is kept in a human-readable CSV format so it can be reviewed and corrected in Excel before being applied to the target tenant.

---

## Overview

```text
        ______________________
       |                      |__
       |   DL MIGRATION TOOL  |  \
       |______________________|___|
          O              O

 Source Tenant  ==================>  Target Tenant
```

The tool collects and tracks:

- Source DL address
- Source display name
- Proposed target DL address
- Proposed target display name
- Members
- Owners
- Original/source email addresses
- Migrated/target email addresses
- External sender configuration
- Migration failures

---

## Requirements

The tool is intended to run in PowerShell with access to the Exchange Online PowerShell module.

You will need:

- PowerShell
- ExchangeOnlineManagement
- Appropriate Exchange Online permissions in the source and target tenants
- Access to the source DLs
- Permission to create and modify distribution groups in the target tenant

The Exchange Online module can be loaded with:

```powershell
Import-Module ExchangeOnlineManagement
```

Run the tool with:

```powershell
.\script.ps1
```

---

# Migration workflow

## 1. Source tenant

Start by connecting to the source Exchange Online tenant.

The normal source workflow is:

```text
1 -> Connect to source EXO
2 -> Enter source DL addresses
3 -> Retrieve members, owners and display names
4 -> Resolve migrated addresses
5 -> Generate proposed target names
6 -> Review working data
7 -> Export CSV
```

### Source DL discovery

For each DL, the tool builds an internal object containing roughly:

```text
Source DL
├── Source email
├── Source display name
├── Target email
├── Target display name
├── Members
│   ├── DHBemail
│   └── MigratedEmail
├── Owners
│   ├── DHBemail
│   └── MigratedEmail
└── External senders allowed
```

Members and owners retain both identities:

```text
DHBemail        = original/source address
MigratedEmail   = target/migrated address
```

The original identity is therefore retained throughout the migration for troubleshooting and manual correction.

---

## 2. Migrated address resolution

The tool can use mailbox forwarding configuration in the source tenant to populate migrated addresses.

For example:

```text
Original address:
someone@source.example

Forwarding address:
someone@target.example

Result:
DHBemail      = someone@source.example
MigratedEmail = someone@target.example
```

The original address stays in the migration data even after the migrated address has been discovered.

When the target migration is performed, the member resolution logic can use both the new and old addresses.

The preferred path is:

```text
MigratedEmail
      |
      v
Resolve target recipient
      |
      v
Valid target recipient
      |
      v
Add to target DL
```

Where appropriate, the tool can fall back to the original address.

This is particularly useful for migration scenarios involving objects such as `MailUser` recipients.

---

## 3. Target naming

The tool generates proposed target DL addresses and display names using configurable naming rules.

Environment-specific naming configuration lives in:

```text
support/add_target_names_config.ps1
```

The configuration controls values such as:

- Existing group prefixes
- Source naming identifiers
- Region codes
- Source domain mappings
- Target email domain
- Unknown/fallback region code

A sanitized example config can be committed as:

```text
support/add_target_names_config.example.ps1
```

The real configuration can then be excluded from Git:

```gitignore
support/add_target_names_config.ps1
```

This allows tenant names, source domains, business identifiers, region mappings, and other environment-specific values to remain outside the public repository.

### Example configuration

```powershell
$TargetNamingConfig = [PSCustomObject]@{

    Prefixes = @(
        "dl"
        "grp"
        "dg"
    )

    RegionMap = @{
        "NorthRegion" = "NR"
        "SouthRegion" = "SR"
    }

    DomainRegionMap = @{
        "north.example.com" = "NR"
        "south.example.com" = "SR"
    }

    TargetDomain = "newdomain.example.com"

    UnknownRegionCode = "UNKNOWN"
}
```

A source address such as:

```text
grp-ClinicalTeamNorthRegion@north.example.com
```

could therefore become:

```text
DL-NR-ClinicalTeam@newdomain.example.com
```

---

# Export formats

The tool can export the working data as:

```text
CSV
TSV
JSON
```

CSV is the recommended format for the actual migration workflow.

JSON preserves the nested PowerShell object structure and is useful as a full-fidelity representation of the working data.

---

## CSV structure

The CSV is intentionally human-readable and editable in Excel.

Instead of placing an entire DL into one complicated row, the export contains **one row per member or owner**.

Typical columns are:

```text
SourceDL
TargetDL
DisplayName
TargetDisplayName
OldAddress
NewAddress
IsOwner
ExtSendersAllowed
```

Example:

```csv
SourceDL,TargetDL,DisplayName,TargetDisplayName,OldAddress,NewAddress,IsOwner,ExtSendersAllowed
old-group@source.example,DL-NR-old-group@target.example,Old Group,DL NR Old Group,user1@source.example,user1@target.example,0,False
old-group@source.example,DL-NR-old-group@target.example,Old Group,DL NR Old Group,user2@source.example,user2@target.example,0,False
old-group@source.example,DL-NR-old-group@target.example,Old Group,DL NR Old Group,owner@source.example,owner@target.example,1,False
```

`IsOwner` determines how the row is reconstructed:

```text
0 = Member
1 = Owner
```

The CSV can be opened directly in Excel and corrected before being used in the target environment.

---

# Target tenant workflow

After completing the source collection and export:

1. Switch to the target Exchange Online tenant.
2. Load the exported migration CSV.
3. Review the reconstructed working data.
4. Run a dry run.
5. Execute the migration when satisfied.

Typical workflow:

```text
90 -> Load migration CSV
92 -> Review imported data
93 -> Dry run full migration
96 -> Execute full migration
```

---

## Loading the CSV

Option `90` loads the CSV and reconstructs the internal DL objects.

Rows are grouped back into DLs, with `IsOwner` deciding whether each recipient is placed into:

```powershell
$DL.members
```

or:

```powershell
$DL.owners
```

This means the user-facing CSV can remain flat and Excel-friendly while the PowerShell tool works with proper nested objects internally.

---

# Dry runs

Options `93-95` allow the destination migration logic to be tested before actually changing Exchange.

```text
93   Preview the full migration
94   Preview creating empty DLs only
95   Preview adding owners and members only
```

Dry runs are intended to expose problems such as:

- Missing migrated addresses
- Invalid target DL information
- Recipients that cannot be resolved
- Existing DLs
- Unsupported owner recipient types
- Hidden recipients
- Ambiguous Exchange recipients
- Old/new address resolution problems

Dry run before using the execution options.

---

# Creating target DLs

Execution can be performed either as one operation or in stages.

```text
96   Create DLs and add owners and members
97   Create empty DLs only
98   Add owners and members to existing DLs
```

For a staged migration:

```text
97 -> Create empty DLs
          |
          v
      Verify DLs
          |
          v
98 -> Add owners and members
```

This is useful when you want to inspect the newly created groups before populating them.

---

# Member resolution

Member migration uses both:

```text
OldAddress / DHBemail
NewAddress / MigratedEmail
```

The target/migrated address is preferred.

The member resolution logic handles cases where:

- `NewAddress` is populated and resolves correctly
- `NewAddress` resolves as a `MailUser`
- `NewAddress` cannot be found
- `NewAddress` is blank
- The old address needs to be used as a fallback
- The recipient identity is ambiguous
- The recipient is hidden from address lists

Before the selected recipient is added, the tool checks:

```powershell
HiddenFromAddressListsEnabled
```

If the selected recipient is hidden from the GAL/address lists, the member is rejected and recorded as a migration failure instead of being silently added.

The failure can distinguish between situations such as:

```text
NEW_ADDRESS_GAL_HIDDEN
OLD_ADDRESS_GAL_HIDDEN
AMBIGUOUS_RECIPIENT
ADD_FAILED
NO_ADDRESS
NOT_FOUND
```

---

# Owner resolution

Owners are handled more strictly than normal DL members.

The proposed migrated owner must resolve successfully to a suitable:

```text
UserMailbox
```

before it is added to the target DL.

The owner operation ultimately uses:

```powershell
Set-DistributionGroup -ManagedBy
```

with the resolved target identity.

Owners that cannot be resolved appropriately are added to the failure collection for manual review.

---

# External senders

The working data also tracks:

```text
ExtSendersAllowed
```

This can be used when creating/configuring the target group to preserve whether authenticated/internal senders are required.

The corresponding Exchange configuration is based on:

```powershell
RequireSenderAuthenticationEnabled
```

---

# Failure handling

Failures are stored separately from the normal working data.

The tool displays the current failure count in its status:

```text
Status
  EXO      : Connected
  DLs      : 20
  Failures : 4
```

Use:

```text
99   Review failures from the latest run
100  Export failures
```

---

## Failure repair workflow

The failure export deliberately uses the **same CSV schema as the standard migration CSV**.

That is important.

It means the intended failure workflow is:

```text
Run migration
      |
      v
Some recipients fail
      |
      v
99 - Review failures
      |
      v
100 - Export failures CSV
  
