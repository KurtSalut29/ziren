# Runs every automated test in the repository and prints one summary.
#
# Evaluator finding #27 (2026-10-05): repeatable checks should not depend on
# someone remembering to run them. This runs, in order:
#   1. backend   - pytest (unit + router tests, mocked Supabase, no network)
#   2. dashboard - vitest unit tests, then the TypeScript type check
#   3. mobile    - flutter analyze, then flutter test
# Exit code is non-zero if any step failed, so it can gate a deploy.
#
# Usage (from the repository root):   powershell -File tools/test-all.ps1
#         skip a part:                powershell -File tools/test-all.ps1 -SkipMobile

param(
    [switch]$SkipBackend,
    [switch]$SkipDashboard,
    [switch]$SkipMobile
)

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$results = [ordered]@{}

function Step($name, $dir, [scriptblock]$cmd) {
    Write-Host "`n=== $name ===" -ForegroundColor Cyan
    Push-Location (Join-Path $root $dir)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    & $cmd
    $ok = ($LASTEXITCODE -eq 0)
    $sw.Stop()
    Pop-Location
    $results[$name] = @{ ok = $ok; secs = [math]::Round($sw.Elapsed.TotalSeconds) }
}

if (-not $SkipBackend) {
    Step 'backend: pytest' 'ziren_backend' { & .\.venv\Scripts\python.exe -m pytest -q -p no:cacheprovider }
}
if (-not $SkipDashboard) {
    Step 'dashboard: vitest' 'ziren_dashboard' { npx vitest run }
    Step 'dashboard: tsc' 'ziren_dashboard' { npx tsc --noEmit -p . }
}
if (-not $SkipMobile) {
    Step 'mobile: analyze' 'ziren_mobile' { flutter analyze lib }
    Step 'mobile: test' 'ziren_mobile' { flutter test }
}

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
$failed = 0
foreach ($k in $results.Keys) {
    $r = $results[$k]
    if ($r.ok) { Write-Host ("PASS  {0}  ({1}s)" -f $k, $r.secs) -ForegroundColor Green }
    else { Write-Host ("FAIL  {0}  ({1}s)" -f $k, $r.secs) -ForegroundColor Red; $failed++ }
}
exit $failed
