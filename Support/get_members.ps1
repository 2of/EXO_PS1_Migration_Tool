# ============================================================
# DL Migration Tool
# Get Source DL Details
# ============================================================

function Get-SourceDLDetails {

    if (-not $Details.EXOConnected) {
        Write-Host ""
        Write-Host "EXO session is not connected." -ForegroundColor Red
        Write-Host ""
        Read-Host "Press Enter to continue"
        return
    }

    if ($Details.DLs.Count -eq 0) {
        Write-Host ""
        Write-Host "No source DLs have been added." -ForegroundColor Yellow
        Write-Host ""
        Read-Host "Press Enter to continue"
        return
    }

    Clear-Host

    Write-Host "========================================"
    Write-Host "     GET MEMBERS, OWNERS AND NAMES"
    Write-Host "========================================"
    Write-Host ""

    $Current = 0
    $Total   = $Details.DLs.Count

    foreach ($Row in $Details.DLs) {

        $Current++

        Write-Host "[$Current/$Total] $($Row.source_email)" -ForegroundColor Cyan

        try {

            # ------------------------------------------------
            # Get source distribution group
            # ------------------------------------------------

            $Group = Get-DistributionGroup `
                -Identity $Row.source_email `
                -ErrorAction Stop


            # ------------------------------------------------
            # Display Name
            # ------------------------------------------------

            $Row.display_name = $Group.DisplayName

            Write-Host "  Name    : $($Group.DisplayName)"


            # ------------------------------------------------
            # Owners
            # ------------------------------------------------

            $Owners = @()

            foreach ($ManagedBy in $Group.ManagedBy) {

                try {

                    $Owner = Get-Recipient `
                        -Identity $ManagedBy `
                        -ErrorAction Stop

                    if ($Owner.PrimarySmtpAddress) {

                        $Owners += [PSCustomObject]@{
                            DHBemail      = $Owner.PrimarySmtpAddress.ToString()
                            MigratedEmail = $null
                        }
                    }
                }
                catch {

                    Write-Host `
                        "  Unable to resolve owner: $ManagedBy" `
                        -ForegroundColor Yellow
                }
            }

            $Row.owners = $Owners

            Write-Host "  Owners  : $($Owners.Count)"


            # ------------------------------------------------
            # Members
            # ------------------------------------------------

            $Members = @(
                Get-DistributionGroupMember `
                    -Identity $Row.source_email `
                    -ResultSize Unlimited `
                    -ErrorAction Stop |
                    Where-Object {
                        $_.PrimarySmtpAddress
                    } |
                    ForEach-Object {

                        [PSCustomObject]@{
                            DHBemail      = $_.PrimarySmtpAddress.ToString()
                            MigratedEmail = $null
                        }
                    }
            )

            $Row.members = $Members

            Write-Host "  Members : $($Members.Count)" -ForegroundColor Green
            Write-Host ""
        }
        catch {

            Write-Host "  FAILED: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host ""
        }
    }

    Write-Host "========================================"
    Write-Host " Source DL lookup complete." -ForegroundColor Green
    Write-Host "========================================"
    Write-Host ""

    Read-Host "Press Enter to continue"
}