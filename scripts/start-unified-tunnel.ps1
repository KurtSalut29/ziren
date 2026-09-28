# For stations/residents with NO shared network — not even WiFi, only
# whatever internet a phone hotspot/pocket WiFi/cellular data gives them.
#
# Gives BOTH the dashboard AND the backend API a single public HTTPS URL,
# using only one ngrok tunnel (the free ngrok plan only allows one public
# endpoint at a time — this works around that instead of needing a paid
# plan). The trick: the backend stays local (never tunneled directly); the
# dashboard's Next.js server proxies /api/* to it server-side (see
# next.config.ts), so ngrok only has to expose the dashboard's port 3000,
# and both the dashboard UI and the API ride through that one URL.
#
# What to do with the printed https://*.ngrok-free.dev URL:
#   - Dashboard: open it directly in a browser on any device with internet.
#   - Mobile app: rebuild the APK with
#       API_BASE_URL=https://<that-url>/api
#     (note the /api suffix — that's what routes through the proxy above).
#     Distribute the APK to test phones; no WiFi/USB debugging needed.
#
# Keep this window open for the whole testing session — restarting ngrok on
# the free plan gives a new random URL, which breaks the already-built APK.

$backendDir = Join-Path $PSScriptRoot "..\ziren_backend"
$dashboardDir = Join-Path $PSScriptRoot "..\ziren_dashboard"

Write-Host "Starting backend (uvicorn) on 0.0.0.0:8000 in a new window..." -ForegroundColor Cyan
Start-Process powershell -ArgumentList @(
    '-NoExit', '-Command',
    "Set-Location '$backendDir'; .\.venv\Scripts\Activate.ps1; uvicorn app.main:app --host 0.0.0.0 --port 8000"
)

Write-Host "Starting dashboard (next dev) on 0.0.0.0:3000 in a new window, routed through /api..." -ForegroundColor Cyan
Start-Process powershell -ArgumentList @(
    '-NoExit', '-Command',
    "Set-Location '$dashboardDir'; `$env:NEXT_PUBLIC_API_BASE_URL='/api'; npm run dev"
)

Write-Host "Waiting for both to come up..." -ForegroundColor Cyan
Start-Sleep -Seconds 8

Write-Host "Starting ngrok tunnel -> http://localhost:3000" -ForegroundColor Cyan
Write-Host "Copy the https://*.ngrok-free.dev 'Forwarding' URL below." -ForegroundColor Yellow
& "$backendDir\ngrok.exe" http 3000
