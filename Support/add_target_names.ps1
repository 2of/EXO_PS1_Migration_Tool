# DL Migration Tool
# Generate target names


# ------------------------------------------------------------
# Load configuration
# ------------------------------------------------------------

$ConfigPath = Join-Path `
    -Path $PSScriptRoot `
    -ChildPath "add_target_names_config.ps1"

if (-not (Test-Path -Path $ConfigPath)) {
    throw "Target naming configuration was not found: $ConfigPath"
}

. $ConfigPath


# ------------------------------------------------------------
# Validate configuration
# ------------------------------------------------------------

if ($null -eq $TargetNamingConfig) {
    throw "The config file did not define `$TargetNamingConfig."
}

if ($null -eq $TargetNamingConfig.Prefixes) {
    throw "TargetNamingConfig.Prefixes is missing."
}

if ($null -eq $TargetNamingConfig.RegionMap) {
    throw "TargetNamingConfig.RegionMap is missing."
}

if ($null -eq $TargetNamingConfig.DomainRegionMap) {
    throw "TargetNamingConfig.DomainRegionMap is missing."
}

if (
    $null -eq $TargetNamingConfig.TargetDomain -or
    $TargetNamingConfig.TargetDomain.ToString().Trim().Length -eq 0
) {
    throw "TargetNamingConfig.TargetDomain is missing."
}


function Reformat-Addy {

    param (
        [Parameter(Mandatory = $true)]
        [string]$Address,

        [bool]$StripRepeated = $false
    )


    # --------------------------------------------------------
    # Read configuration
    # --------------------------------------------------------

    $Prefixes        = $TargetNamingConfig.Prefixes
    $RegionMap       = $TargetNamingConfig.RegionMap
    $DomainRegionMap = $TargetNamingConfig.DomainRegionMap

    $TargetDomain = $TargetNamingConfig.TargetDomain

    if (
        $null -eq $TargetDomain -or
        $TargetDomain.ToString().Trim().Length -eq 0
    ) {
        throw "TargetDomain is missing from add_target_names_config.ps1."
    }

    $TargetDomain = $TargetDomain.ToString().Trim()


    # UnknownRegionCode is optional.

    if (
        $null -eq $TargetNamingConfig.UnknownRegionCode -or
        $TargetNamingConfig.UnknownRegionCode.ToString().Trim().Length -eq 0
    ) {
        $UnknownRegionCode = "UNKNOWN"
    }
    else {
        $UnknownRegionCode =
            $TargetNamingConfig.UnknownRegionCode.ToString().Trim()
    }


    # --------------------------------------------------------
    # Validate source email
    # --------------------------------------------------------

    if ($null -eq $Address -or $Address.Trim().Length -eq 0) {
        throw "Source email address is empty."
    }

    $Parts = $Address.Trim() -split "@", 2

    if ($Parts.Count -ne 2) {
        throw "Invalid email address: $Address"
    }

    $UserPart = $Parts[0].Trim()
    $Domain   = $Parts[1].Trim()

    if ($UserPart.Length -eq 0) {
        throw "Email address has no local part: $Address"
    }

    if ($Domain.Length -eq 0) {
        throw "Email address has no domain: $Address"
    }


    # --------------------------------------------------------
    # Build removable prefix list
    # --------------------------------------------------------

    $CheckPrefixes = @(
        foreach ($BasePrefix in $Prefixes) {

            if ($null -eq $BasePrefix) {
                continue
            }

            $CleanPrefix = $BasePrefix.ToString().Trim()

            if ($CleanPrefix.Length -eq 0) {
                continue
            }

            "$CleanPrefix-"
            "$CleanPrefix`_"
            "$CleanPrefix."
            $CleanPrefix
        }
    ) |
        Sort-Object Length -Descending |
        Select-Object -Unique


    # --------------------------------------------------------
    # Remove existing prefixes
    # --------------------------------------------------------

    if ($StripRepeated) {

        do {
            $Changed = $false

            foreach ($Prefix in $CheckPrefixes) {

                if (
                    $UserPart.StartsWith(
                        $Prefix,
                        [System.StringComparison]::OrdinalIgnoreCase
                    )
                ) {
                    $UserPart = $UserPart.Substring($Prefix.Length)
                    $Changed = $true
                    break
                }
            }

        } while ($Changed -and $UserPart.Length -gt 0)
    }
    else {

        foreach ($Prefix in $CheckPrefixes) {

            if (
                $UserPart.StartsWith(
                    $Prefix,
                    [System.StringComparison]::OrdinalIgnoreCase
                )
            ) {
                $UserPart = $UserPart.Substring($Prefix.Length)
                break
            }
        }
    }


    # --------------------------------------------------------
    # Detect region from the email local part
    # --------------------------------------------------------

    $Region = $null

    $RegionKeys = @(
        $RegionMap.Keys |
            Sort-Object Length -Descending
    )

    foreach ($Key in $RegionKeys) {

        if ($null -eq $Key) {
            continue
        }

        $KeyText = $Key.ToString()

        if ($KeyText.Length -eq 0) {
            continue
        }

        $Index = $UserPart.IndexOf(
            $KeyText,
            [System.StringComparison]::OrdinalIgnoreCase
        )

        if ($Index -ge 0) {

            $Region = $RegionMap[$Key]

            $UserPart = $UserPart.Remove(
                $Index,
                $KeyText.Length
            )

            break
        }
    }


    # --------------------------------------------------------
    # Fall back to domain-based region detection
    # --------------------------------------------------------

    if (
        $null -eq $Region -or
        $Region.ToString().Trim().Length -eq 0
    ) {
        $DomainKey = $Domain.ToLowerInvariant()

        if ($DomainRegionMap.ContainsKey($DomainKey)) {
            $Region = $DomainRegionMap[$DomainKey]
        }
        else {
            $Region = $UnknownRegionCode
        }
    }

    if (
        $null -eq $Region -or
        $Region.ToString().Trim().Length -eq 0
    ) {
        throw "No region could be determined for: $Address"
    }

    $Region = $Region.ToString().Trim()


    # --------------------------------------------------------
    # Clean the remaining local part
    # --------------------------------------------------------

    $UserPart = $UserPart.Trim()
    $UserPart = $UserPart.Trim("-")
    $UserPart = $UserPart.Trim("_")
    $UserPart = $UserPart.Trim(".")

    # Replace spaces and underscores with hyphens.
    $UserPart = $UserPart -replace "[\s_]+", "-"

    # Replace unsuitable characters with hyphens.
    $UserPart = $UserPart -replace "[^a-zA-Z0-9.-]", "-"

    # Collapse repeated separators.
    $UserPart = $UserPart -replace "-{2,}", "-"
    $UserPart = $UserPart -replace "\.{2,}", "."

    # Remove separators left at either end.
    $UserPart = $UserPart.Trim("-")
    $UserPart = $UserPart.Trim(".")

    if ($UserPart.Length -eq 0) {
        throw "No usable address name remained after processing: $Address"
    }


    # --------------------------------------------------------
    # Generate target values
    # --------------------------------------------------------

    $AliasOut   = "DL-$Region-$UserPart"
    $AddressOut = "$AliasOut@$TargetDomain"
    $NameOut    = "DL $Region $UserPart"

    return [PSCustomObject]@{
        Address = $AddressOut
        Name    = $NameOut
        Region  = $Region
        Alias   = $AliasOut
    }
}


function Add-TargetNames {

    if ($Details.DLs.Count -eq 0) {
        Write-Host ""
        Write-Host "No source DLs have been added." -ForegroundColor Yellow
        Read-Host "Press Enter to continue"
        return
    }

    Clear-Host

    Write-Host "Generate target names"
    Write-Host ""

    $Current   = 0
    $Total     = $Details.DLs.Count
    $Completed = 0
    $Failed    = 0

    foreach ($DL in $Details.DLs) {

        $Current++
        $SourceEmail = $DL.source_email

        Write-Host "[$Current/$Total] $SourceEmail" -ForegroundColor Cyan

        try {

            if (
                $null -eq $SourceEmail -or
                $SourceEmail.ToString().Trim().Length -eq 0
            ) {
                throw "The DL has no source email address."
            }

            $Result = Reformat-Addy `
                -Address $SourceEmail.ToString() `
                -StripRepeated $true

            $DL.target_email = $Result.Address

            # Preserve the original display name.
            # Only prefix it with DL and the region code.

            if (
                $null -ne $DL.display_name -and
                $DL.display_name.ToString().Trim().Length -gt 0
            ) {
                $SourceDisplayName = $DL.display_name.ToString().Trim()

                $DL.target_display_name =
                    "DL $($Result.Region) $SourceDisplayName"
            }
            else {
                $DL.target_display_name = $Result.Name
            }

            Write-Host "  Region: $($Result.Region)"
            Write-Host "  Email : $($DL.target_email)" -ForegroundColor Green
            Write-Host "  Name  : $($DL.target_display_name)" -ForegroundColor Green
            Write-Host ""

            $Completed++
        }
        catch {

            Write-Host "  Failed: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host ""

            $Failed++
        }
    }

    Write-Host "Target name generation complete"
    Write-Host "Generated: $Completed"
    Write-Host "Failed:    $Failed"
    Write-Host ""

    Read-Host "Press Enter to continue"
}