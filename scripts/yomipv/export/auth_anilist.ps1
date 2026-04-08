param(
    [string]$ConfPath
)

$Host.UI.RawUI.WindowTitle = "Yomipv - AniList Setup"

$Url = "https://anilist.co/api/v2/oauth/authorize?client_id=36986&response_type=token"

Write-Host "Opening your web browser..." -ForegroundColor Cyan
Write-Host "Please authorize Yomipv on AniList."
Start-Process $Url

Write-Host ""
$pasted = Read-Host "After clicking Approve, paste the ENTIRE URL from your browser address bar here"

if ($pasted -match "#access_token=([^&]+)") {
    $token = $matches[1]

    if (Test-Path $ConfPath) {
        $Content = Get-Content $ConfPath -Raw
        
        if ($Content -match "(?m)^anilist_token=.*") {
            $Content = $Content -replace "(?m)^anilist_token=.*", "anilist_token=$token"
        } else {
            $Content += "`nanilist_token=$token"
        }

        if ($Content -match "(?m)^anilist_enabled=.*") {
            $Content = $Content -replace "(?m)^anilist_enabled=.*", "anilist_enabled=yes"
        } else {
            $Content += "`nanilist_enabled=yes"
        }

        Set-Content -Path $ConfPath -Value $Content -NoNewline
        Write-Host ""
        Write-Host "Authentication Successful!" -ForegroundColor Green
        Write-Host "Your yomipv.conf has been updated."
        Write-Host "IMPORTANT: Please restart MPV to apply the changes." -ForegroundColor Yellow
    } else {
        Write-Host "Error: Could not find yomipv.conf at path: $ConfPath" -ForegroundColor Red
    }
} else {
    Write-Host ""
    Write-Host "Error: Invalid URL pasted. Could not extract access token." -ForegroundColor Red
}

Write-Host ""
Write-Host "Closing in 5 seconds..."
Start-Sleep -Seconds 5
