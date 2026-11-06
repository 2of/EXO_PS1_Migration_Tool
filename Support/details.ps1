# ============================================================
# DL Migration Tool
# Runtime State
# ============================================================
$Details = [PSCustomObject]@{
    EXOConnected = $false
    DLs          = @()
    Failures     = @()
}


function Add-Failure {

    param (
        [string]$Stage,
        [string]$TargetDL,
        [string]$DHBEmail,
        [string]$MigratedEmail,
        [string]$Reason
    )

    $Details.Failures += [PSCustomObject]@{
        Stage         = $Stage
        TargetDL      = $TargetDL
        DHBEmail      = $DHBEmail
        MigratedEmail = $MigratedEmail
        Reason        = $Reason
    }
}


function Clear-Failures {

    $Details.Failures = @()
}


function View-Failures {

    Clear-Host

    Write-Host "Migration failures"
    Write-Host ""

    if ($Details.Failures.Count -eq 0) {

        Write-Host "No failures recorded."
    }
    else {

        Write-Host "Failures: $($Details.Failures.Count)"
        Write-Host ""

        $Details.Failures |
            Format-Table `
                Stage,
                TargetDL,
                DHBEmail,
                MigratedEmail,
                Reason `
                -AutoSize `
                -Wrap
    }

    Write-Host ""
    Read-Host "Press Enter to continue"
}
function Add-DLDetail {

    param (
        [Parameter(Mandatory)]
        [string]$SourceEmail
    )

 $row = [PSCustomObject]@{
    source_email        = $SourceEmail
    display_name        = $null

    target_email        = $null
    target_display_name = $null

    members             = @()
    owners              = @()

    ext_senders_allowed = $null
}

    $Details.DLs += $row
}


function Interactive-Add-Row {

    Clear-Host

    Write-Host "========================================"
    Write-Host "          ADD SOURCE ADDRESSES"
    Write-Host "========================================"
    Write-Host ""
    Write-Host "Paste source DL email addresses below."
    Write-Host "Enter a blank line when finished."
    Write-Host ""

    $Added = 0

    while ($true) {

        $SourceEmail = Read-Host

        if ($null -eq $SourceEmail -or $SourceEmail.Trim().Length -eq 0) {
            break
        }

        $SourceEmail = $SourceEmail.Trim()

        Add-DLDetail -SourceEmail $SourceEmail

        $Added++
    }

    Write-Host ""
    Write-Host "$Added source address(es) added." -ForegroundColor Green
    Write-Host ""

    Read-Host "Press Enter to continue"
}


function View-WorkingData {

    Clear-Host

    Write-Host "========================================"
    Write-Host "            WORKING DATA"
    Write-Host "========================================"
    Write-Host ""

    if ($Details.DLs.Count -eq 0) {

        Write-Host "No DL data currently loaded." -ForegroundColor Yellow

    }
    else {

        foreach ($DL in $Details.DLs) {

            Write-Host "========================================" -ForegroundColor DarkGray
Write-Host "Source Email : $($DL.source_email)"
Write-Host "Display Name : $($DL.display_name)"
Write-Host "Target Email : $($DL.target_email)"
Write-Host "Target Name  : $($DL.target_display_name)"
Write-Host "External     : $($DL.ext_senders_allowed)"
            Write-Host ""

            # ------------------------------------------------
            # Members
            # ------------------------------------------------

            Write-Host "Members:" -ForegroundColor Cyan

            if ($DL.members.Count -eq 0) {

                Write-Host "  None"
            }
            else {

                $DL.members |
                    Format-Table `
                        DHBemail,
                        MigratedEmail `
                        -AutoSize
            }


            # ------------------------------------------------
            # Owners
            # ------------------------------------------------

            Write-Host ""
            Write-Host "Owners:" -ForegroundColor Cyan

            if ($DL.owners.Count -eq 0) {

                Write-Host "  None"
            }
            else {

                $DL.owners |
                    Format-Table `
                        DHBemail,
                        MigratedEmail `
                        -AutoSize
            }

            Write-Host ""
        }
    }

    Write-Host ""
    Read-Host "Press Enter to continue"
}