# ============================================================
# DL Migration Tool
# Export Working Data
# ============================================================


function Get-FlattenedWorkingData {

    $Output = @()

    foreach ($DL in $Details.DLs) {

        # Members
        foreach ($Member in $DL.members) {

            $Output += [PSCustomObject]@{
                SourceDL          = $DL.source_email
                TargetDL          = $DL.target_email
                DisplayName       = $DL.display_name
                TargetDisplayName = $DL.target_display_name
                OldAddress        = $Member.DHBemail
                NewAddress        = $Member.MigratedEmail
                IsOwner           = 0
                ExtSendersAllowed = $DL.ext_senders_allowed
            }
        }

        # Owners
        foreach ($Owner in $DL.owners) {

            $Output += [PSCustomObject]@{
                SourceDL          = $DL.source_email
                TargetDL          = $DL.target_email
                DisplayName       = $DL.display_name
                TargetDisplayName = $DL.target_display_name
                OldAddress        = $Owner.DHBemail
                NewAddress        = $Owner.MigratedEmail
                IsOwner           = 1
                ExtSendersAllowed = $DL.ext_senders_allowed
            }
        }

        # If the DL has no members or owners, still export it
        if ($DL.members.Count -eq 0 -and $DL.owners.Count -eq 0) {

            $Output += [PSCustomObject]@{
                SourceDL          = $DL.source_email
                TargetDL          = $DL.target_email
                DisplayName       = $DL.display_name
                TargetDisplayName = $DL.target_display_name
                OldAddress        = $null
                NewAddress        = $null
                IsOwner           = 0
                ExtSendersAllowed = $DL.ext_senders_allowed
            }
        }
    }

    return $Output
}

function Get-ExportSavePath {

    param (
        [Parameter(Mandatory)]
        [string]$Filter,

        [Parameter(Mandatory)]
        [string]$DefaultExtension,

        [Parameter(Mandatory)]
        [string]$DefaultFileName
    )

    Add-Type -AssemblyName System.Windows.Forms

    $SaveDialog = New-Object System.Windows.Forms.SaveFileDialog

    $SaveDialog.Title = "Export DL Migration Data"
    $SaveDialog.Filter = $Filter
    $SaveDialog.DefaultExt = $DefaultExtension
    $SaveDialog.FileName = $DefaultFileName
    $SaveDialog.AddExtension = $true
    $SaveDialog.OverwritePrompt = $true

    $Result = $SaveDialog.ShowDialog()

    if ($Result -eq [System.Windows.Forms.DialogResult]::OK) {

        $Path = $SaveDialog.FileName

        $SaveDialog.Dispose()

        return $Path
    }

    $SaveDialog.Dispose()

    return $null
}


function Export-WorkingDataCSV {

    if ($Details.DLs.Count -eq 0) {

        Write-Host ""
        Write-Host "There is no working data to export." -ForegroundColor Yellow
        Write-Host ""

        Read-Host "Press Enter to continue"
        return
    }

    $Path = Get-ExportSavePath `
        -Filter "CSV Files (*.csv)|*.csv|All Files (*.*)|*.*" `
        -DefaultExtension "csv" `
        -DefaultFileName "DL_Migration_Export.csv"

    if ($null -eq $Path) {

        Write-Host ""
        Write-Host "Export cancelled." -ForegroundColor Yellow

        Start-Sleep -Seconds 1
        return
    }

    $ExportData = Get-FlattenedWorkingData

    $ExportData |
        Export-Csv `
            -Path $Path `
            -NoTypeInformation `
            -Encoding UTF8

    Write-Host ""
    Write-Host "CSV export complete." -ForegroundColor Green
    Write-Host $Path -ForegroundColor Cyan
    Write-Host ""

    Read-Host "Press Enter to continue"
}

function Export-FailuresCSV {

    if ($Details.Failures.Count -eq 0) {

        Write-Host ""
        Write-Host "There are no failures to export."
        Write-Host ""

        Read-Host "Press Enter to continue"
        return
    }

    $Path = Get-ExportSavePath `
        -Filter "CSV Files (*.csv)|*.csv|All Files (*.*)|*.*" `
        -DefaultExtension "csv" `
        -DefaultFileName "DL_Migration_Failures.csv"

    if ($null -eq $Path) {
        Write-Host "Export cancelled."
        Start-Sleep -Seconds 1
        return
    }

    $Output = @()

    foreach ($Failure in $Details.Failures) {

        # Find the parent DL so we can reconstruct
        # the normal migration CSV format

        $DL = $Details.DLs |
            Where-Object {
                $_.target_email -eq $Failure.TargetDL
            } |
            Select-Object -First 1


        if ($null -eq $DL) {

            Write-Host "Could not find working DL for: $($Failure.TargetDL)"
            continue
        }


        # Owner failure = 1
        # Member failure = 0

        $IsOwner = 0

        if ($Failure.Stage -eq "Owner") {
            $IsOwner = 1
        }


        $Output += [PSCustomObject]@{
            SourceDL          = $DL.source_email
            TargetDL          = $DL.target_email
            DisplayName       = $DL.display_name
            TargetDisplayName = $DL.target_display_name
            OldAddress        = $Failure.DHBEmail
            NewAddress        = $Failure.MigratedEmail
            IsOwner           = $IsOwner
            ExtSendersAllowed = $DL.ext_senders_allowed
        }
    }


    if ($Output.Count -eq 0) {

        Write-Host ""
        Write-Host "No failure rows could be exported."
        Write-Host ""

        Read-Host "Press Enter to continue"
        return
    }


    try {

        $Output |
            Export-Csv `
                -Path $Path `
                -NoTypeInformation `
                -Encoding UTF8 `
                -ErrorAction Stop

        Write-Host ""
        Write-Host "Failure export complete."
        Write-Host "Rows: $($Output.Count)"
        Write-Host $Path
    }
    catch {

        Write-Host ""
        Write-Host "Failure export failed."
        Write-Host $_.Exception.Message
    }

    Write-Host ""
    Read-Host "Press Enter to continue"
}
function Export-WorkingDataTSV {

    if ($Details.DLs.Count -eq 0) {

        Write-Host ""
        Write-Host "There is no working data to export." -ForegroundColor Yellow
        Write-Host ""

        Read-Host "Press Enter to continue"
        return
    }

    $Path = Get-ExportSavePath `
        -Filter "TSV Files (*.tsv)|*.tsv|All Files (*.*)|*.*" `
        -DefaultExtension "tsv" `
        -DefaultFileName "DL_Migration_Export.tsv"

    if ($null -eq $Path) {

        Write-Host ""
        Write-Host "Export cancelled." -ForegroundColor Yellow

        Start-Sleep -Seconds 1
        return
    }

    $ExportData = Get-FlattenedWorkingData

    $ExportData |
        Export-Csv `
            -Path $Path `
            -NoTypeInformation `
            -Delimiter "`t" `
            -Encoding UTF8

    Write-Host ""
    Write-Host "TSV export complete." -ForegroundColor Green
    Write-Host $Path -ForegroundColor Cyan
    Write-Host ""

    Read-Host "Press Enter to continue"
}


function Export-WorkingDataJSON {

    if ($Details.DLs.Count -eq 0) {

        Write-Host ""
        Write-Host "There is no working data to export." -ForegroundColor Yellow
        Write-Host ""

        Read-Host "Press Enter to continue"
        return
    }

    $Path = Get-ExportSavePath `
        -Filter "JSON Files (*.json)|*.json|All Files (*.*)|*.*" `
        -DefaultExtension "json" `
        -DefaultFileName "DL_Migration_Export.json"

    if ($null -eq $Path) {

        Write-Host ""
        Write-Host "Export cancelled." -ForegroundColor Yellow

        Start-Sleep -Seconds 1
        return
    }

    $Details.DLs |
        ConvertTo-Json -Depth 10 |
        Out-File `
            -FilePath $Path `
            -Encoding UTF8

    Write-Host ""
    Write-Host "JSON export complete." -ForegroundColor Green
    Write-Host $Path -ForegroundColor Cyan
    Write-Host ""

    Read-Host "Press Enter to continue"
}