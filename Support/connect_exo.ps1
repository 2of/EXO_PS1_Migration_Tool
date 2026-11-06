
function Connect-EXOSession {

    Write-Host ""
    Write-Host "Connecting to Exchange Online..." -ForegroundColor Cyan

    try {

        Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop

        # Confirm the connection is actually usable
        Get-OrganizationConfig -ErrorAction Stop | Out-Null

        $Details.EXOConnected = $true

        Write-Host ""
        Write-Host "Connected to Exchange Online." -ForegroundColor Green
    }
    catch {

        $Details.EXOConnected = $false

        Write-Host ""
        Write-Host "Failed to connect to Exchange Online." -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
    }

    Write-Host ""
    Read-Host "Press Enter to continue"
}