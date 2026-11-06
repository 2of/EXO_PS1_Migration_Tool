# DL Migration Tool
# Load Working Data from CSV


function ConvertTo-Boolean {

    param (
        $Value
    )

    if ($null -eq $Value) {
        return $false
    }

    $Value = $Value.ToString().Trim().ToLower()

    return ($Value -eq "1" -or
            $Value -eq "true" -or
            $Value -eq "yes" -or
            $Value -eq "y")
}


function Load-WorkingDataCSV {

    Add-Type -AssemblyName System.Windows.Forms

    $OpenDialog = New-Object System.Windows.Forms.OpenFileDialog

    $OpenDialog.Title = "Load DL Migration CSV"
    $OpenDialog.Filter = "CSV Files (*.csv)|*.csv|All Files (*.*)|*.*"
    $OpenDialog.Multiselect = $false
    $OpenDialog.CheckFileExists = $true

    $Result = $OpenDialog.ShowDialog()

    if ($Result -ne [System.Windows.Forms.DialogResult]::OK) {

        $OpenDialog.Dispose()

        Write-Host ""
        Write-Host "Load cancelled."

        Start-Sleep -Seconds 1
        return
    }

    $Path = $OpenDialog.FileName
    $OpenDialog.Dispose()


    # --------------------------------------------------------
    # Import CSV
    # --------------------------------------------------------

    try {

        $ImportedRows = @(
            Import-Csv -Path $Path -ErrorAction Stop
        )
    }
    catch {

        Write-Host ""
        Write-Host "Failed to load CSV."
        Write-Host $_.Exception.Message
        Write-Host ""

        Read-Host "Press Enter to continue"
        return
    }


    if ($ImportedRows.Count -eq 0) {

        Write-Host ""
        Write-Host "CSV contains no rows."
        Write-Host ""

        Read-Host "Press Enter to continue"
        return
    }


    # --------------------------------------------------------
    # Validate required columns
    # --------------------------------------------------------

    $RequiredColumns = @(
        "SourceDL"
        "TargetDL"
        "DisplayName"
        "TargetDisplayName"
        "OldAddress"
        "NewAddress"
        "IsOwner"
        "ExtSendersAllowed"
    )

    $ActualColumns = @(
        $ImportedRows[0].PSObject.Properties.Name
    )

    foreach ($Column in $RequiredColumns) {

        if ($ActualColumns -notcontains $Column) {

            Write-Host ""
            Write-Host "CSV is missing required column: $Column"
            Write-Host ""

            Read-Host "Press Enter to continue"
            return
        }
    }


    # --------------------------------------------------------
    # Build DL objects
    #
    # One CSV contains multiple rows per DL.
    # Group them back into one object per target DL.
    # --------------------------------------------------------

    $LoadedDLs = @()

    $Groups = $ImportedRows | Group-Object TargetDL

    foreach ($Group in $Groups) {

        $Rows = @($Group.Group)
        $FirstRow = $Rows[0]


        # ----------------------------------------------------
        # External sender setting
        # ----------------------------------------------------

        $ExternalSendersAllowed = $null

        if ($FirstRow.ExtSendersAllowed.Trim().Length -gt 0) {
            $ExternalSendersAllowed =
                ConvertTo-Boolean $FirstRow.ExtSendersAllowed
        }


        # ----------------------------------------------------
        # Create DL object
        # ----------------------------------------------------

        $DL = [PSCustomObject]@{

            source_email        = $FirstRow.SourceDL
            display_name        = $FirstRow.DisplayName

            target_email        = $FirstRow.TargetDL
            target_display_name = $FirstRow.TargetDisplayName

            members             = @()
            owners              = @()

            ext_senders_allowed = $ExternalSendersAllowed
        }


        # ----------------------------------------------------
        # Rebuild members and owners
        # ----------------------------------------------------

        foreach ($Row in $Rows) {

            $OldAddress = $Row.OldAddress
            $NewAddress = $Row.NewAddress


            # Empty row means the DL had no member/owner
            # records but still needed to be exported.

            if (
                ($null -eq $OldAddress -or $OldAddress.Trim().Length -eq 0) -and
                ($null -eq $NewAddress -or $NewAddress.Trim().Length -eq 0)
            ) {
                continue
            }


            if ($null -ne $OldAddress) {
                $OldAddress = $OldAddress.Trim()
            }

            if ($null -ne $NewAddress) {

                $NewAddress = $NewAddress.Trim()

                if ($NewAddress.Length -eq 0) {
                    $NewAddress = $null
                }
            }


            $Recipient = [PSCustomObject]@{
                DHBemail      = $OldAddress
                MigratedEmail = $NewAddress
            }


            # ------------------------------------------------
            # Owner or member
            # ------------------------------------------------

            $IsOwner = ConvertTo-Boolean $Row.IsOwner

            if ($IsOwner) {
                $DL.owners += $Recipient
            }
            else {
                $DL.members += $Recipient
            }
        }


        $LoadedDLs += $DL
    }


    # --------------------------------------------------------
    # Only replace existing data once everything succeeded
    # --------------------------------------------------------

    $Details.DLs = $LoadedDLs


    # --------------------------------------------------------
    # Summary
    # --------------------------------------------------------

    $MemberCount = 0
    $OwnerCount = 0

    foreach ($DL in $Details.DLs) {
        $MemberCount += $DL.members.Count
        $OwnerCount += $DL.owners.Count
    }


    Clear-Host

    Write-Host "CSV import complete"
    Write-Host ""
    Write-Host "DLs:     $($Details.DLs.Count)"
    Write-Host "Members: $MemberCount"
    Write-Host "Owners:  $OwnerCount"
    Write-Host ""
    Write-Host "File: $Path"
    Write-Host ""

    Read-Host "Press Enter to continue"
}