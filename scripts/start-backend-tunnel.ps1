# Starts the Ziren backend on 0.0.0.0:8000, LOCAL ONLY (not tunneled).
#
# This is the "same-venue, some laptops on WiFi" case: the backend just
# needs to be reachable on the LAN. Other laptops hit it via
# http://192.168.100.9:8000 (see ziren_backend/.env CORS_ORIGINS_RAW for the
# allowed LAN origins — update the IP there if it changes).
#
# For stations with NO shared network at all (phone hotspot / pocket WiFi
# per-station instead), use start-unified-tunnel.ps1 instead — that one
# gives both the backend AND the dashboard a single public URL that works
# over any internet connection, not just this LAN.

$backendDir = Join-Path $PSScriptRoot "..\ziren_backend"
Set-Location $backendDir

Write-Host "Starting backend (uvicorn) on 0.0.0.0:8000..." -ForegroundColor Cyan
.\.venv\Scripts\Activate.ps1
uvicorn app.main:app --host 0.0.0.0 --port 8000
