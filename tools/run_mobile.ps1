<#
.SYNOPSIS
    Start the Ziren mobile app on a USB-attached phone, tunnel included and
    kept alive for as long as the app runs.

.DESCRIPTION
    `adb reverse` is per-connection state, not configuration. It is dropped
    every time the cable is unplugged, the phone reboots, USB debugging is
    re-authorised, or the adb server restarts — and nothing announces it. The
    app then cannot reach http://localhost:8000, so Home shows "Walang signal"
    and My Reports comes back empty, which looks exactly like a backend fault.

    Setting it once at launch is not enough: it has been observed vanishing
    mid-session, while the device stayed attached and the backend stayed up. So
    a watcher re-applies it whenever it goes missing, and records when that
    happened — the timestamps are the evidence for what actually knocks it out.

.PARAMETER CheckOnly
    Run the checks and set up the tunnel, then stop without launching the app.

.PARAMETER NoWatch
    Set the tunnel once and do not keep watching it.

.EXAMPLE
    .\tools\run_mobile.ps1
    .\tools\run_mobile.ps1 -CheckOnly
#>
[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [switch]$NoWatch,
    [int]$Port = 8000,
    [int]$WatchSeconds = 3
)

$ErrorActionPreference = 'Stop'
$mobileDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'ziren_mobile'

# ── 1. A phone has to be attached ────────────────────────────
$attached = @(adb devices | Select-Object -Skip 1 | Where-Object { $_ -match '\sdevice$' })
if ($attached.Count -eq 0) {
    Write-Host "No device attached." -ForegroundColor Red
    Write-Host "  Plug the phone in, unlock it, and accept the USB debugging prompt."
    Write-Host "  'adb devices' should list it as 'device', not 'unauthorized'."
    exit 1
}
Write-Host ("Device: " + ($attached[0] -split '\s+')[0]) -ForegroundColor Green

# ── 2. The tunnel ────────────────────────────────────────────
# Re-created unconditionally. Asking whether it exists first would cost a
# round trip to say what re-creating it says anyway, and it is idempotent.
adb reverse tcp:$Port tcp:$Port | Out-Null
$forwards = @(adb reverse --list)
if ($forwards -match "tcp:$Port tcp:$Port") {
    Write-Host "Tunnel: phone localhost:$Port -> this laptop" -ForegroundColor Green
} else {
    Write-Host "adb reverse did not take. Check 'adb reverse --list'." -ForegroundColor Red
    exit 1
}

# ── 3. Something has to answer on the other end ──────────────
# A warning, not an error: the backend can legitimately be started afterwards,
# and the app retries its health ping every 30 seconds.
$listening = $null
try {
    $listening = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction Stop
} catch {
    $listening = $null
}
if ($null -eq $listening) {
    Write-Host "Nothing is listening on port $Port." -ForegroundColor Yellow
    Write-Host "  Start the backend first, or Home will show 'Walang signal':"
    Write-Host "    cd ziren_backend; uvicorn app.main:app --reload"
} else {
    Write-Host "Backend: listening on port $Port" -ForegroundColor Green
}

if ($CheckOnly) {
    Write-Host "`nChecks done (-CheckOnly), not launching." -ForegroundColor Cyan
    exit 0
}

# ── 4. Keep the tunnel alive while the app runs ──────────────
# The repair is one adb call and costs nothing; the log is the point. Each
# entry is a moment the phone had no route to the backend, which is what an
# unexplained "Could not reach the server" in the Flutter console looks like
# from the other side.
$repairLog = Join-Path $env:TEMP 'ziren_tunnel_repairs.log'
$watcher = $null

if (-not $NoWatch) {
    if (Test-Path $repairLog) { Remove-Item $repairLog -Force }
    $watcher = Start-Job -Name 'ziren-tunnel' -ScriptBlock {
        param($port, $logPath, $every)
        while ($true) {
            $ok = $false
            $list = & adb reverse --list 2>$null
            foreach ($line in $list) {
                if ($line -match "tcp:$port tcp:$port") { $ok = $true }
            }
            if (-not $ok) {
                & adb reverse tcp:$port tcp:$port 2>$null | Out-Null
                $stamp = Get-Date -Format 'HH:mm:ss'
                Add-Content -Path $logPath -Value "$stamp  tunnel was gone - re-applied"
            }
            Start-Sleep -Seconds $every
        }
    } -ArgumentList $Port, $repairLog, $WatchSeconds
    Write-Host "Watcher: re-applying the tunnel if it drops (every ${WatchSeconds}s)" -ForegroundColor Green
}

# ── 5. Run ───────────────────────────────────────────────────
Write-Host "`nStarting the app...`n" -ForegroundColor Cyan
Set-Location $mobileDir
try {
    flutter run --dart-define-from-file=dart_defines.json
} finally {
    if ($null -ne $watcher) {
        Stop-Job $watcher -ErrorAction SilentlyContinue
        Remove-Job $watcher -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $repairLog) {
        $repairs = @(Get-Content $repairLog)
        if ($repairs.Count -gt 0) {
            Write-Host "`nThe tunnel dropped $($repairs.Count) time(s) and was repaired:" -ForegroundColor Yellow
            $repairs | ForEach-Object { Write-Host "  $_" }
            Write-Host "  (log: $repairLog)"
        } else {
            Write-Host "`nTunnel held for the whole session." -ForegroundColor Green
        }
    }
}
