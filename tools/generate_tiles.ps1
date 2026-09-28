# generate_tiles.ps1
# 6C.1 — Biliran Island MBTiles generation
# Usage: .\tools\generate_tiles.ps1
# Output: ziren_mobile\assets\map\biliran.mbtiles
#
# Requirements: Java 11+ on PATH
# Cache: tools\cache\ (gitignored) — PBF and JAR are reused on re-runs

$ErrorActionPreference = "Stop"

$RepoRoot   = Split-Path $PSScriptRoot -Parent
$CacheDir   = "$PSScriptRoot\cache"
$AssetOut   = "$RepoRoot\ziren_mobile\assets\map\biliran.mbtiles"

$PlanetilerVersion = "0.8.3"
$PlanetilerJar     = "$CacheDir\planetiler-$PlanetilerVersion.jar"
$PlanetilerUrl     = "https://github.com/onthegomap/planetiler/releases/download/v$PlanetilerVersion/planetiler.jar"

$PbfFile = "$CacheDir\philippines-latest.osm.pbf"
$PbfUrl  = "https://download.geofabrik.de/asia/philippines-latest.osm.pbf"

# Biliran Island bounding box
$MinLon = "124.30"
$MinLat = "11.48"
$MaxLon = "124.58"
$MaxLat = "11.72"

function Download-File($url, $dest, $label) {
    if ((Test-Path $dest) -and (Get-Item $dest).Length -gt 1KB) {
        Write-Host "  [skip] $label already cached" -ForegroundColor DarkGray
        return
    }
    Write-Host "  [download] $label ..." -ForegroundColor Cyan
    $tmp = "$dest.tmp"
    try {
        # Use curl.exe if available (faster, shows progress), else Invoke-WebRequest
        if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
            & curl.exe -L --progress-bar -o $tmp $url
            if ($LASTEXITCODE -ne 0) { throw "curl exited $LASTEXITCODE" }
        } else {
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing
        }
        if (-not (Test-Path $tmp) -or (Get-Item $tmp).Length -lt 1KB) {
            throw "Downloaded file is empty or missing"
        }
        Move-Item -Force $tmp $dest
        $sizeMb = [math]::Round((Get-Item $dest).Length / 1MB, 1)
        Write-Host "  [ok] $label ($sizeMb MB)" -ForegroundColor Green
    } catch {
        if (Test-Path $tmp) { Remove-Item $tmp -Force }
        throw "Failed to download ${label}: $_"
    }
}

Write-Host ""
Write-Host "=== Ziren 6C.1 - Biliran MBTiles Generator ===" -ForegroundColor Yellow
Write-Host ""

# 1. Ensure cache dir exists
New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null

# 2. Download planetiler JAR
Download-File $PlanetilerUrl $PlanetilerJar "planetiler-$PlanetilerVersion.jar"

# 3. Download Philippines PBF (~1.2 GB, takes a while)
Write-Host "  [note] Philippines PBF is ~1.2 GB - this will take several minutes on first run" -ForegroundColor DarkYellow
Download-File $PbfUrl $PbfFile "philippines-latest.osm.pbf"

# 4. Run planetiler
$MbtilesTemp = "$CacheDir\biliran.mbtiles"

Write-Host "  [run] planetiler - clipping to Biliran bounding box ..." -ForegroundColor Cyan
Write-Host "        bbox: $MinLon,$MinLat to $MaxLon,$MaxLat" -ForegroundColor DarkGray

$javaArgs = @(
    "-Xmx2g",
    "-jar", $PlanetilerJar,
    "--osm-path=$PbfFile",
    "--output=$MbtilesTemp",
    "--bounds=$MinLon,$MinLat,$MaxLon,$MaxLat",
    "--minzoom=9",
    "--maxzoom=15",
    "--download",
    "--force"
)

$proc = Start-Process -FilePath "java" -ArgumentList $javaArgs -NoNewWindow -Wait -PassThru
if ($proc.ExitCode -ne 0) {
    throw "planetiler exited with code $($proc.ExitCode)"
}

# 5. Copy to Flutter asset
Write-Host "  [copy] $MbtilesTemp -> $AssetOut" -ForegroundColor Cyan
Copy-Item -Force $MbtilesTemp $AssetOut

$sizeMb = [math]::Round((Get-Item $AssetOut).Length / 1MB, 1)
Write-Host ""
Write-Host "=== Done! biliran.mbtiles ($sizeMb MB) written to assets/map/ ===" -ForegroundColor Green
Write-Host "    Run: flutter run --dart-define-from-file=dart_defines.json" -ForegroundColor DarkGray
Write-Host ""
