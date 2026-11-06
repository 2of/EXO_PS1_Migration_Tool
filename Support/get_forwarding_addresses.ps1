# ============================================================
# DL Migration Tool
# Get Migrated Addresses from Mailbox Forwarding
# ============================================================

function Get-ForwardingTarget {

    param (
        [Parameter(Mandatory)]
        [string]$EmailAddress
    )

    try {

        $Mailbox = Get-Mailbox `
            -Identity $EmailAddress `
            -ErrorAction Stop

        $ForwardingTarget = $null


        # ----------------------------------------------------
        # ForwardingSmtpAddress
        # ----------------------------------------------------

        if ($Mailbox.ForwardingSmtpAddress) {

            $ForwardingTarget = $Mailbox.ForwardingSmtpAddress.ToString()

            # Strip smtp: or SMTP:
            $ForwardingTarget = $ForwardingTarget -replace '(?i)^smtp:', ''
        }


        # ----------------------------------------------------
        # ForwardingAddress
        # ----------------------------------------------------

        elseif ($Mailbox.ForwardingAddress) {

            try {

                $ForwardingRecipient = Get-Recipient `
                    -Identity $Mailbox.ForwardingAddress `
                    -ErrorAction Stop

                if ($ForwardingRecipient.PrimarySmtpAddress) {

                    $ForwardingTarget =
                        $ForwardingRecipient.PrimarySmtpAddress.ToString()
                }
            }
            catch {
                return $null
            }
        }


        # ----------------------------------------------------
        # Return resolved target
        # ----------------------------------------------------

        if ($null -ne $ForwardingTarget) {

            $ForwardingTarget = $ForwardingTarget.Trim()

            if ($ForwardingTarget.Length -gt 0) {
                return $ForwardingTarget
            }
        }

        return $null
    }
    catch {
        return $null
    }
}


function Get-ForwardingAddresses {

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
    Write-Host "       GET FORWARDING ADDRESSES"
    Write-Host "========================================"
    Write-Host ""


    $MemberResolved = 0
    $MemberMissing  = 0

    $OwnerResolved = 0
    $OwnerMissing  = 0


    foreach ($DL in $Details.DLs) {

        Write-Host "DL: $($DL.source_email)" -ForegroundColor Magenta
        Write-Host ""


        # ====================================================
        # MEMBERS
        # ====================================================

        Write-Host "  MEMBERS" -ForegroundColor Cyan

        foreach ($Member in $DL.members) {

            $DHBEmail = $Member.DHBemail

            Write-Host "    $DHBEmail" -NoNewline

            $ForwardingTarget = Get-ForwardingTarget `
                -EmailAddress $DHBEmail

            if ($null -ne $ForwardingTarget) {

                $Member.MigratedEmail = $ForwardingTarget

                Write-Host " -> $ForwardingTarget" `
                    -ForegroundColor Green

                $MemberResolved++
            }
            else {

                Write-Host " -> No forwarding" `
                    -ForegroundColor DarkYellow

                $MemberMissing++
            }
        }


        # ====================================================
        # OWNERS
        # ====================================================

        Write-Host ""
        Write-Host "  OWNERS" -ForegroundColor Cyan

        foreach ($Owner in $DL.owners) {

            $DHBEmail = $Owner.DHBemail

            Write-Host "    $DHBEmail" -NoNewline

            $ForwardingTarget = Get-ForwardingTarget `
                -EmailAddress $DHBEmail

            if ($null -ne $ForwardingTarget) {

                $Owner.MigratedEmail = $ForwardingTarget

                Write-Host " -> $ForwardingTarget" `
                    -ForegroundColor Green

                $OwnerResolved++
            }
            else {

                Write-Host " -> No forwarding" `
                    -ForegroundColor DarkYellow

                $OwnerMissing++
            }
        }


        Write-Host ""
        Write-Host "----------------------------------------"
        Write-Host ""
    }


    # ========================================================
    # Summary
    # ========================================================

    Write-Host "========================================"
    Write-Host "        FORWARDING LOOKUP COMPLETE"
    Write-Host "========================================"
    Write-Host ""

    Write-Host "Members"
    Write-Host "  Resolved       : $MemberResolved" -ForegroundColor Green
    Write-Host "  Not resolved   : $MemberMissing" -ForegroundColor Yellow

    Write-Host ""

    Write-Host "Owners"
    Write-Host "  Resolved       : $OwnerResolved" -ForegroundColor Green
    Write-Host "  Not resolved   : $OwnerMissing" -ForegroundColor Yellow

    Write-Host ""

    Read-Host "Press Enter to continue"
}