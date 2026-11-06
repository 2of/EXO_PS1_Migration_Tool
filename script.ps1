# DL Migration Tool

# Support files
. "$PSScriptRoot\support\details.ps1"
. "$PSScriptRoot\support\connect_exo.ps1"
. "$PSScriptRoot\support\get_members.ps1"
. "$PSScriptRoot\support\get_forwarding_addresses.ps1"
. "$PSScriptRoot\support\add_target_names.ps1"
. "$PSScriptRoot\support\exports.ps1"
. "$PSScriptRoot\support\load_csv.ps1"
. "$PSScriptRoot\support\create_target_support.ps1"
. "$PSScriptRoot\support\create_target_dls.ps1"


$sillyheader = @"

        ______________________
       |                      |__
       |   DL MIGRATION TOOL  |  \
       |______________________|___|
          O              O

      Source Tenant  ==================>  Target Tenant

"@


$help = @"

Hi, this is a wrapper around some quick DL migration tools.

The basic workflow is:

SOURCE / SRC TENANT EXO
---------------

1. Connect to the source EXO tenant.
2. Enter the source DL email addresses.
3. Retrieve members, owners and display names.
4. Resolve migrated addresses using mailbox forwarding.
5. Generate the proposed Target Tenant EXO DL names and addresses.
6. Review the working data.
7. Export it to CSV.

The CSV is deliberately human-readable.

There is one row per member or owner:

    SourceDL
    TargetDL
    DisplayName
    TargetDisplayName
    OldAddress
    NewAddress
    IsOwner
    ExtSendersAllowed

You can open this in Excel and manually correct anything before
loading it into the destination side.


DESTINATION / Target Tenant EXO
-----------------

90. Load the migration CSV.
91. Connect to the Target Tenant EXO EXO tenant.
92. Review the reconstructed working data.

Use options 93-95 first if you want to check what will happen.

Options 96-98 actually make changes in Exchange Online.


FAILURES
--------

Failures are stored separately while the migration runs.

99  - View failures
100 - Export failures

The failure CSV uses the SAME format as the normal migration CSV.

That means you can:

    Export failures
        ->
    Open in Excel
        ->
    Fix NewAddress / other values
        ->
    Save CSV
        ->
    Load again using option 90
        ->
    Retry the failed objects

This is intentional. You don't need to re-run the entire migration
just because three random addresses are rubbish.


NOTES
-----

TODO:
Implement recursive/special-case owner resolution for those cases.

No warranty. Check the dry run before pressing the spicy buttons.

"@


function Show-MainMenu {

    Clear-Host

    $DLCount      = $Details.DLs.Count
    $FailureCount = $Details.Failures.Count

    $EXOStatus = if ($Details.EXOConnected) {
        "Connected"
    }
    else {
        "Not connected"
    }

    Write-Host $sillyheader -ForegroundColor DarkCyan

    Write-Host "Status" -ForegroundColor White
    Write-Host "  EXO      : $EXOStatus"
    Write-Host "  DLs      : $DLCount"
    Write-Host "  Failures : $FailureCount"
    Write-Host ""

Write-Host "Source / SRC TENANT EXO" -ForegroundColor Cyan
Write-Host "  1   Connect to the source Exchange Online tenant"
Write-Host "  2   Enter DL email addresses to migrate"
Write-Host "  3   Get source DL members, owners and display names"
Write-Host "  4   Get migrated member and owner addresses from forwarding"
Write-Host "  5   Add proposed Target Tenant EXO DL names and email addresses"
Write-Host "  6   VIEW STATUS <<< Use this lots"
Write-Host "  7   Export CSV"
Write-Host "  8   Export TSV"
Write-Host "  9   Export  JSON"
Write-Host ""

Write-Host "Destination / Target Tenant EXO" -ForegroundColor Magenta
Write-Host " 90   Load a CSV in"
Write-Host " 1   Connect to Target Tenant EXO tenant"
Write-Host " 92   Review the imported migration data"
Write-Host ""

Write-Host "Dry run" -ForegroundColor Yellow
Write-Host " 93   Preview creating DLs and adding all owners and members"
Write-Host " 94   Preview creating the empty DLs only"
Write-Host " 95   Preview adding owners and members to existing DLs"
Write-Host ""

Write-Host "Create the DLs in the TWO tenant" -ForegroundColor Green
Write-Host " 96   Create DLs and add all owners and members"
Write-Host " 97   Create the empty DLs only"
Write-Host " 98   Add owners and members to existing DLs"
Write-Host ""

Write-Host "Failures / cleanup - You should use this to export -> fix in excel -> 90: loda in" -ForegroundColor Red
Write-Host " 99   Review failures from the latest migration run"
Write-Host "100   Export failures to an editable and reimportable CSV"
Write-Host "101   Remove the AZ/ADM account from DL ownership"
Write-Host ""

Write-Host "  H   Show workflow notes, help and known issues"
Write-Host "  0   Exit the DL Migration Tool"
}


while ($true) {

    Show-MainMenu

    $Selection = (Read-Host "Option").ToUpper()

    switch ($Selection) {

        # Source
        "1" { Connect-EXOSession }
        "2" { Interactive-Add-Row }
        "3" { Get-SourceDLDetails }
        "4" { Get-ForwardingAddresses }
        "5" { Add-TargetNames }
        "6" { View-WorkingData }

        # Export
        "7" { Export-WorkingDataCSV }
        "8" { Export-WorkingDataTSV }
        "9" { Export-WorkingDataJSON }


        # Destination
        "90" { Load-WorkingDataCSV }

        "91" {
            Write-Host ""
            Write-Host "Destination EXO connection not implemented yet."
            Read-Host "Press Enter to continue"
        }

        "92" { View-WorkingData }


        # Dry run
        "93" {
            Invoke-TargetDLMigration `
                -ActuallyExecute:$false
        }

        "94" {
            Invoke-TargetDLMigration `
                -ActuallyExecute:$false `
                -SkipOwners:$true `
                -SkipMembers:$true
        }

        "95" {
            Invoke-TargetDLMigration `
                -ActuallyExecute:$false `
                -SkipCreate:$true
        }


        # Execute
        "96" {
            Invoke-TargetDLMigration `
                -ActuallyExecute:$true
        }

        "97" {
            Invoke-TargetDLMigration `
                -ActuallyExecute:$true `
                -SkipOwners:$true `
                -SkipMembers:$true
        }

        "98" {
            Invoke-TargetDLMigration `
                -ActuallyExecute:$true `
                -SkipCreate:$true
        }


        # Failures
        "99" {
            View-Failures
        }

        "100" {
            Export-FailuresCSV
        }

        "101" {
            Write-Host ""
            Write-Host "Remove AZ/ADM ownership not implemented yet."
            Read-Host "Press Enter to continue"
        }


        # Help
        "H" {
            Clear-Host

            Write-Host "DL Migration Tool - Help" -ForegroundColor Cyan
            Write-Host $help

            Read-Host "Press Enter to return to the menu"
        }


        # Exit
        "0" {
            Clear-Host
            exit
        }


        default {
            Write-Host ""
            Write-Host "Invalid option: $Selection" -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
}