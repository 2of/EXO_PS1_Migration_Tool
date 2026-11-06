
function Get-TargetDLName {

    param (
        [Parameter(Mandatory = $true)]
        [string]$TargetEmail
    )

    $Parts = $TargetEmail.Trim() -split "@", 2

    if ($Parts.Count -ne 2) {
        return $null
    }

    return $Parts[0].Trim()
}


function Invoke-TargetDLMigration {

    param (
        [bool]$ActuallyExecute = $false,
        [bool]$SkipCreate = $false,
        [bool]$SkipOwners = $false,
        [bool]$SkipMembers = $false
    )

    if (-not $Details.EXOConnected) {
        Write-Host ""
        Write-Host "EXO is not connected." -ForegroundColor Red
        Read-Host "Press Enter to continue"
        return
    }

    if ($Details.DLs.Count -eq 0) {
        Write-Host ""
        Write-Host "There is no DL working data." -ForegroundColor Yellow
        Write-Host "Load the migration CSV first."
        Read-Host "Press Enter to continue"
        return
    }

    Clear-Host
    Clear-Failures

    $RunMode = if ($ActuallyExecute) {
        "Execute"
    }
    else {
        "DryRun"
    }

    Write-Host "Mode: $RunMode"
    Write-Host "DLs: $($Details.DLs.Count)"
    Write-Host ""

    $CountCreated       = 0
    $CountExisting      = 0
    $CountOwners        = 0
    $CountMembers       = 0
    $CountAlreadyMember = 0
    $CountSkipped       = 0
    $CountFailed        = 0

    # Track DLs that could not be created.
    # This stops us producing misleading owner/member failures later.
    $UnavailableDLs = @()


    # ========================================================
    # Pass 1: Create target DLs
    # ========================================================

    if (-not $SkipCreate) {

        Write-Host "Create DLs" -ForegroundColor Cyan
        Write-Host ""

        foreach ($DL in $Details.DLs) {

            $TargetEmail       = $DL.target_email
            $TargetDisplayName = $DL.target_display_name

            if (
                $null -eq $TargetEmail -or
                $TargetEmail.ToString().Trim().Length -eq 0
            ) {
                $Reason = "Target email is empty."

                Write-Host "  Failed: $Reason" -ForegroundColor Red

                Add-Failure `
                    -Stage "Create" `
                    -TargetDL $TargetEmail `
                    -DHBEmail $DL.source_email `
                    -MigratedEmail $null `
                    -Reason $Reason `
                    -Skipped:$false `
                    -RunMode $RunMode

                $UnavailableDLs += $TargetEmail
                $CountFailed++
                continue
            }

            if (
                $null -eq $TargetDisplayName -or
                $TargetDisplayName.ToString().Trim().Length -eq 0
            ) {
                $Reason = "Target display name is empty."

                Write-Host "  $TargetEmail"
                Write-Host "    Failed: $Reason" -ForegroundColor Red

                Add-Failure `
                    -Stage "Create" `
                    -TargetDL $TargetEmail `
                    -DHBEmail $DL.source_email `
                    -MigratedEmail $null `
                    -Reason $Reason `
                    -Skipped:$false `
                    -RunMode $RunMode

                $UnavailableDLs += $TargetEmail
                $CountFailed++
                continue
            }

            $TargetEmail       = $TargetEmail.Trim()
            $TargetDisplayName = $TargetDisplayName.Trim()
            $TargetName        = Get-TargetDLName -TargetEmail $TargetEmail

            if ($null -eq $TargetName -or $TargetName.Length -eq 0) {
                $Reason = "Could not derive the target DL name from '$TargetEmail'."

                Write-Host "  $TargetEmail"
                Write-Host "    Failed: $Reason" -ForegroundColor Red

                Add-Failure `
                    -Stage "Create" `
                    -TargetDL $TargetEmail `
                    -DHBEmail $DL.source_email `
                    -MigratedEmail $null `
                    -Reason $Reason `
                    -Skipped:$false `
                    -RunMode $RunMode

                $UnavailableDLs += $TargetEmail
                $CountFailed++
                continue
            }

            Write-Host "  $TargetEmail"

            try {
                $CreateResult = CreateDL `
                    -DL_TargetName $TargetName `
                    -DL_TargetDisplayName $TargetDisplayName `
                    -DL_PrimarySmtpAddress $TargetEmail

                switch ($CreateResult) {

                    0 {
                        Write-Host "    DL already exists."
                        $CountExisting++
                    }

                    1 {
                        if ($ActuallyExecute) {
                            Write-Host "    DL created." -ForegroundColor Green
                        }
                        else {
                            Write-Host "    Dry run: would create DL." -ForegroundColor Yellow
                        }

                        $CountCreated++
                    }

                    default {
                        $Reason = "DL creation failed. Support method returned '$CreateResult'."

                        Write-Host "    Failed: $Reason" -ForegroundColor Red

                        Add-Failure `
                            -Stage "Create" `
                            -TargetDL $TargetEmail `
                            -DHBEmail $DL.source_email `
                            -MigratedEmail $null `
                            -Reason $Reason `
                            -Skipped:$false `
                            -RunMode $RunMode

                        $UnavailableDLs += $TargetEmail
                        $CountFailed++
                    }
                }
            }
            catch {
                $Reason = $_.Exception.Message

                Write-Host "    Failed: $Reason" -ForegroundColor Red

                Add-Failure `
                    -Stage "Create" `
                    -TargetDL $TargetEmail `
                    -DHBEmail $DL.source_email `
                    -MigratedEmail $null `
                    -Reason $Reason `
                    -Skipped:$false `
                    -RunMode $RunMode

                $UnavailableDLs += $TargetEmail
                $CountFailed++
            }
        }

        Write-Host ""
    }


    # ========================================================
    # Pass 2: Add owners
    # ========================================================

    if (-not $SkipOwners) {

        Write-Host "Add owners" -ForegroundColor Cyan
        Write-Host ""

        foreach ($DL in $Details.DLs) {

            $TargetDL = $DL.target_email

            if ($UnavailableDLs -contains $TargetDL) {
                Write-Host "  $TargetDL"
                Write-Host "    Skipped because DL creation failed." -ForegroundColor Yellow
                continue
            }

            Write-Host "  $TargetDL"

            foreach ($Owner in $DL.owners) {

                $OldAddress = $Owner.DHBemail
                $NewAddress = $Owner.MigratedEmail

                if (
                    $null -eq $NewAddress -or
                    $NewAddress.ToString().Trim().Length -eq 0
                ) {
                    $Reason = "Owner has no MigratedEmail value."

                    Write-Host "    Failed: $OldAddress - $Reason" -ForegroundColor Red

                    Add-Failure `
                        -Stage "Owner" `
                        -TargetDL $TargetDL `
                        -DHBEmail $OldAddress `
                        -MigratedEmail $NewAddress `
                        -Reason $Reason `
                        -Skipped:$true `
                        -RunMode $RunMode

                    $CountSkipped++
                    continue
                }

                $NewAddress = $NewAddress.Trim()

                # Owners must resolve uniquely to a UserMailbox.
                $OwnerResolution = Resolve-RecipientUnique `
                    -Address $NewAddress

                if (
                    -not $OwnerResolution.Success -or
                    $OwnerResolution.Type -ne "UserMailbox"
                ) {
                    $Reason = $OwnerResolution.Reason

                    Write-Host "    Failed: $NewAddress - $Reason" -ForegroundColor Red

                    Add-Failure `
                        -Stage "Owner" `
                        -TargetDL $TargetDL `
                        -DHBEmail $OldAddress `
                        -MigratedEmail $NewAddress `
                        -Reason $Reason `
                        -Skipped:$true `
                        -RunMode $RunMode

                    $CountSkipped++
                    continue
                }

                try {
                    $OwnerResult = AddOwnertoDL `
                        -DL_TargetIdentity $TargetDL `
                        -Username $OwnerResolution.DN

                    if ($OwnerResult -eq 1) {
                        Write-Host "    $NewAddress added/planned as owner." -ForegroundColor Green
                        $CountOwners++
                    }
                    else {
                        $Reason = "Owner add failed. Support method returned '$OwnerResult'."

                        Write-Host "    Failed: $NewAddress - $Reason" -ForegroundColor Red

                        Add-Failure `
                            -Stage "Owner" `
                            -TargetDL $TargetDL `
                            -DHBEmail $OldAddress `
                            -MigratedEmail $NewAddress `
                            -Reason $Reason `
                            -Skipped:$false `
                            -RunMode $RunMode

                        $CountFailed++
                    }
                }
                catch {
                    $Reason = $_.Exception.Message

                    Write-Host "    Failed: $NewAddress - $Reason" -ForegroundColor Red

                    Add-Failure `
                        -Stage "Owner" `
                        -TargetDL $TargetDL `
                        -DHBEmail $OldAddress `
                        -MigratedEmail $NewAddress `
                        -Reason $Reason `
                        -Skipped:$false `
                        -RunMode $RunMode

                    $CountFailed++
                }
            }
        }

        Write-Host ""
    }


    # ========================================================
    # Pass 3: Add members
    # ========================================================

    if (-not $SkipMembers) {

        Write-Host "Add members" -ForegroundColor Cyan
        Write-Host ""

        foreach ($DL in $Details.DLs) {

            $TargetDL = $DL.target_email

            if ($UnavailableDLs -contains $TargetDL) {
                Write-Host "  $TargetDL"
                Write-Host "    Skipped because DL creation failed." -ForegroundColor Yellow
                continue
            }

            Write-Host "  $TargetDL"

            foreach ($Member in $DL.members) {

                $OldAddress = $Member.DHBemail
                $NewAddress = $Member.MigratedEmail

                try {
                    $MemberResult = SafelyAddToDL `
                        -DlName $TargetDL `
                        -NewAddress $NewAddress `
                        -OldAddress $OldAddress `
                        -ActuallyExecute:$ActuallyExecute

                    if ($MemberResult.Success) {
                        Write-Host "    $($MemberResult.Recipient): $($MemberResult.Reason)" `
                            -ForegroundColor Green

                        $CountMembers++
                        continue
                    }

                    $FailureText = @(
                        $MemberResult.Reason
                        $MemberResult.ErrorCode
                    ) -join " "

                    $AlreadyMember = $FailureText -match `
                        "(?i)(already\s+(a\s+)?member|is\s+already\s+a\s+member|member\s+already\s+exists|already\s+exists)"

                    if ($AlreadyMember) {
                        Write-Host "    Already a member: $NewAddress" -ForegroundColor Yellow
                        $CountAlreadyMember++
                        continue
                    }

                    $Reason = $MemberResult.Reason

                    if (
                        $null -ne $MemberResult.ErrorCode -and
                        $MemberResult.ErrorCode.ToString().Trim().Length -gt 0
                    ) {
                        $Reason = "$Reason [$($MemberResult.ErrorCode)]"
                    }

                    Write-Host "    Failed: $OldAddress - $Reason" -ForegroundColor Red

                    Add-Failure `
                        -Stage "Member" `
                        -TargetDL $TargetDL `
                        -DHBEmail $OldAddress `
                        -MigratedEmail $NewAddress `
                        -Reason $Reason `
                        -Skipped:$false `
                        -RunMode $RunMode

                    $CountFailed++
                }
                catch {
                    $Reason = $_.Exception.Message

                    Write-Host "    Failed: $OldAddress - $Reason" -ForegroundColor Red

                    Add-Failure `
                        -Stage "Member" `
                        -TargetDL $TargetDL `
                        -DHBEmail $OldAddress `
                        -MigratedEmail $NewAddress `
                        -Reason $Reason `
                        -Skipped:$false `
                        -RunMode $RunMode

                    $CountFailed++
                }
            }
        }

        Write-Host ""
    }


    # ========================================================
    # Summary
    # ========================================================

    Write-Host "Summary"
    Write-Host ""
    Write-Host "DLs created/planned     : $CountCreated"
    Write-Host "DLs already existing    : $CountExisting"
    Write-Host "Owners added/planned    : $CountOwners"
    Write-Host "Members added/planned   : $CountMembers"
    Write-Host "Members already present : $CountAlreadyMember"
    Write-Host "Skipped                 : $CountSkipped"
    Write-Host "Failed                  : $CountFailed"
    Write-Host "Failure records         : $($Details.Failures.Count)"
    Write-Host ""

    if ($Details.Failures.Count -gt 0) {
        $Details.Failures |
            Format-Table `
                Stage,
                TargetDL,
                DHBEmail,
                MigratedEmail,
                Skipped,
                Reason `
                -AutoSize `
                -Wrap
    }

    Write-Host ""
    Read-Host "Press Enter to continue"
}