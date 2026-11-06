# DLTools.ps1
# Minimal library exposing a single function: SafelyAddToDL
# Concern: add a member to an EXISTING DL, using New/Old address fallback logic.
# - No DL existence checks
# - No DL creation
# - No owner changes


function AddOwnertoDL {
    param(
        [string] $DL_TargetIdentity,  # TargetDL (name/alias/SMTP)
        [string] $Username            # accept DN or SMTP
    )

    if (-not $ActuallyExecute) { 
        Write-Host "DRY RUN: Would add OWNER '$Username' -> '$DL_TargetIdentity'"
        return 1 
    }

    try {
        Set-DistributionGroup -Identity $DL_TargetIdentity `
                              -ManagedBy @{ Add = $Username } `
                              -BypassSecurityGroupManagerCheck:$true `
                              -ErrorAction Stop
        Write-Host "OWNER ADDED: $Username -> $DL_TargetIdentity" -ForegroundColor Magenta
        return 1
    } 
    catch {
        $failedRecipients += $Username
        Write-Host "OWNER ADD FAILED: $Username -> $DL_TargetIdentity  --> $_" -ForegroundColor Red
        return 3
    }
}


function CreateDL {

    param (
        [Parameter(Mandatory)]
        [string]$DL_PrimarySmtpAddress,

        [Parameter(Mandatory)]
        [string]$DL_TargetName,

        [Parameter(Mandatory)]
        [string]$DL_TargetDisplayName
    )

    Write-Host "    Name        : $DL_TargetName"
    Write-Host "    DisplayName : $DL_TargetDisplayName"
    Write-Host "    Address     : $DL_PrimarySmtpAddress"

    # Check whether it already exists by SMTP
    $Existing = Get-DistributionGroup `
        -Identity $DL_PrimarySmtpAddress `
        -ErrorAction SilentlyContinue

    # Then try name
    if (-not $Existing) {

        $Existing = Get-DistributionGroup `
            -Identity $DL_TargetName `
            -ErrorAction SilentlyContinue
    }

    if ($Existing) {

        Write-Host "    Already exists: $($Existing.PrimarySmtpAddress)"

        return 0
    }

    # Dry run
    if (-not $ActuallyExecute) {

        Write-Host "    Dry run: would create DL."

        return 1
    }

    # Actually create
    try {

        New-DistributionGroup `
            -Name $DL_TargetName `
            -DisplayName $DL_TargetDisplayName `
            -PrimarySmtpAddress $DL_PrimarySmtpAddress `
            -ErrorAction Stop |
            Out-Null

        Write-Host "    Created: $DL_PrimarySmtpAddress"

        return 1
    }
    catch {

        Write-Host "    Failed: $($_.Exception.Message)"

        return 3
    }
}






function Resolve-RecipientUnique {
    param([Parameter(Mandatory)][string]$Address)

    if ([string]::IsNullOrWhiteSpace($Address)) {
        return [pscustomobject]@{ Success=$false; DN=$null; Type=$null; Reason="Empty address"; Matches=0 }
    }

    $proxy = 'smtp:' + $Address.ToLower()
    $candidates = Get-Recipient -ResultSize Unlimited -Filter "PrimarySmtpAddress -eq '$Address' -or EmailAddresses -eq '$proxy'" -ErrorAction SilentlyContinue

    if (-not $candidates -or $candidates.Count -eq 0) {
        return [pscustomobject]@{ Success=$false; DN=$null; Type=$null; Reason="No recipient matched '$Address'"; Matches=0 }
    }

    # Prefer exact Primary SMTP match of type UserMailbox
    $primaryMailbox = $candidates | Where-Object { $_.PrimarySmtpAddress -ieq $Address -and $_.RecipientType -eq 'UserMailbox' } | Select-Object -First 1
    if ($primaryMailbox) {
        return [pscustomobject]@{ Success=$true; DN=$primaryMailbox.DistinguishedName; Type=$primaryMailbox.RecipientType; Reason="Exact Primary SMTP match (UserMailbox)."; Matches=$candidates.Count }
    }

    # Otherwise any UserMailbox
    $userMailbox = $candidates | Where-Object { $_.RecipientType -eq 'UserMailbox' } | Select-Object -First 1
    if ($userMailbox) {
        return [pscustomobject]@{ Success=$true; DN=$userMailbox.DistinguishedName; Type=$userMailbox.RecipientType; Reason="Chose UserMailbox among multiple."; Matches=$candidates.Count }
    }

    # Not suitable as owner
    $first = $candidates | Select-Object -First 1
    return [pscustomobject]@{ Success=$false; DN=$null; Type=$first.RecipientType; Reason="Address does not resolve to a UserMailbox (found $($first.RecipientType))."; Matches=$candidates.Count }
}
function SafelyAddToDL {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$DlName,
        [Parameter(Mandatory=$false)][AllowEmptyString()][string]$NewAddress,
        [Parameter(Mandatory=$false)][AllowEmptyString()][string]$OldAddress,
        [Parameter(Mandatory=$false)][bool]$ActuallyExecute = $false
    )

    # --- Local helper to try resolving OldAddress to a DN ---
    function _Try-ResolveOldToDN {
        param([string]$Address)
        if ([string]::IsNullOrWhiteSpace($Address)) { return $null }
        # Lookup by PrimarySmtpAddress to get a DN
        $r = Get-Recipient -Filter "PrimarySmtpAddress -eq '$Address'" -ErrorAction SilentlyContinue
        if ($null -ne $r) { return $r.DistinguishedName }
        return $null
    }

    # --- Resolve final recipient identity per your rules (unchanged logic) ---
    $finalIdentity = $null
    $reason = $null

    $primaryfound = 0

    if ([string]::IsNullOrWhiteSpace($NewAddress)) {
        # Rule 1: New empty -> Old
        if ([string]::IsNullOrWhiteSpace($OldAddress)) {
            return [pscustomobject]@{
                DL        = $DlName
                Recipient = $null
                Reason    = "NewAddress empty and OldAddress empty."
                Success   = $false
                Simulated = -not $ActuallyExecute
                ErrorCode = "NO_ADDRESS"
            }
        }
        $finalIdentity = $OldAddress
        $reason = "NewAddress was empty."
    }
    else {
        # Rule 2: Try resolve New
        $newRecip = Get-Recipient -Identity $NewAddress -ErrorAction SilentlyContinue
        if ($null -ne $newRecip) {
            if ($newRecip.RecipientType -eq "MailUser") {
                # Fallback to Old (original behavior)
                if ([string]::IsNullOrWhiteSpace($OldAddress)) {
                    $finalIdentity = $NewAddress
                    $reason = "NewAddress resolved to MailUser; OldAddress missing, proceeding with NewAddress."
                } else {
                    $oldDN = _Try-ResolveOldToDN -Address $OldAddress
                    if ($oldDN) {
                        $finalIdentity = $oldDN
                        $reason = "NewAddress resolved to MailUser; using OldAddress (resolved DN)."
                    } else {
                        $finalIdentity = $OldAddress
                        $reason = "NewAddress resolved to MailUser; using OldAddress as string (not resolvable)."
                    }
                }
            } else {
                # New is valid and not MailUser
                $finalIdentity = $NewAddress
                $reason = "NewAddress is valid (RecipientType: $($newRecip.RecipientType))."
                $primaryfound = 1
            }
        } else {
            # Rule 3: New not found -> Old
            if ([string]::IsNullOrWhiteSpace($OldAddress)) {
                return [pscustomobject]@{
                    DL        = $DlName
                    Recipient = $null
                    Reason    = "NewAddress not found; OldAddress missing."
                    Success   = $false
                    Simulated = -not $ActuallyExecute
                    ErrorCode = "NOT_FOUND"
                }
            }
            $oldDN = _Try-ResolveOldToDN -Address $OldAddress
            if ($oldDN) {
                $finalIdentity = $oldDN
                $reason = "NewAddress not found; using OldAddress (resolved DN)."
            } else {
                $finalIdentity = $OldAddress
                $reason = "NewAddress not found; using OldAddress as string (not resolvable)."
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($finalIdentity)) {
        return [pscustomobject]@{
            DL        = $DlName
            Recipient = $null
            Reason    = "Failed to determine recipient identity."
            Success   = $false
            Simulated = -not $ActuallyExecute
            ErrorCode = "NO_IDENTITY"
        }
    }

    # --- Perform add (member only), or simulate ---


     Write-Host "Final check, is this hidden in GAL?"

$finalRecipient = Get-Recipient -Identity $finalIdentity -ErrorAction SilentlyContinue

if ($finalRecipient -and $finalRecipient.HiddenFromAddressListsEnabled) {
    Write-Host "Hidden in GAL"

    if ($primaryfound) {
    $reason = "New addy hidden in GAL."
    $Ec = "NEW_ADDRESS_GAL_HIDDEN"
}
else {
    $reason = "fellback to old address and it is hidden in GAL."
        $Ec = "OLD_ADDRESS_GAL_HIDDEN"
}




    return [pscustomobject]@{
        DL        = $DlName
        Recipient = $null
        Reason    = $Reason
        Success   = $false
        Simulated = -not $ActuallyExecute
        ErrorCode = $Ec
    }
}

Write-Host "Not hidden in GAL - happy days"




    if ($ActuallyExecute) {
        try {

            Add-DistributionGroupMember -Identity $DlName -Member $finalIdentity -ErrorAction Stop
            return [pscustomobject]@{
                DL        = $DlName
                Recipient = $finalIdentity
                Reason    = $reason
                Success   = $true
                Simulated = $false
                ErrorCode = $null
            }
        } catch {
            $errMsg = $_.Exception.Message

            # --- NEW: catch the specific ambiguity case and print the flag you want
# --- NEW: catch the specific ambiguity case and print the flag you want
# --- AMBIGUITY HANDLER: print ONLY the multiple recipients it might be ---
if ($errMsg -like '*There are multiple recipients matching the identity*') {
    $addr  = $finalIdentity
    $proxy = 'smtp:' + $addr.ToLower()

    Get-Recipient -ResultSize Unlimited -Filter "PrimarySmtpAddress -eq '$addr' -or EmailAddresses -eq '$proxy'" |
        Select-Object Name, RecipientType, PrimarySmtpAddress, ExternalEmailAddress, DistinguishedName, Guid |
        Format-Table -AutoSize

    return [pscustomobject]@{
        DL        = $DlName
        Recipient = $finalIdentity
        Reason    = "Ambiguous SMTP identity. $reason"
        Success   = $false
        Simulated = $false
        ErrorCode = "AMBIGUOUS_RECIPIENT"
        RawError  = $errMsg
    }
}

            # Generic failure
            return [pscustomobject]@{
                DL        = $DlName
                Recipient = $finalIdentity
                Reason    = "Add failed: $errMsg | $reason"
                Success   = $false
                Simulated = $false
                ErrorCode = "ADD_FAILED"
                RawError  = $errMsg
            }
        }
    } else {
        # Simulation
        return [pscustomobject]@{
            DL        = $DlName
            Recipient = $finalIdentity
            Reason    = "SIMULATION: Would add member. $reason"
            Success   = $true
            Simulated = $true
            ErrorCode = $null
        }
    }
}