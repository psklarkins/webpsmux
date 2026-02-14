<#
.SYNOPSIS
    Builds the webpsmux installer zip bundle.

.DESCRIPTION
    Assembles webpsmux.exe (freshly built), psmux binaries, web.config,
    and installer scripts into a self-contained zip.

.PARAMETER PsmuxPath
    Path to psmux binaries. Default: $env:LOCALAPPDATA\psmux

.PARAMETER SkipBuild
    Skip building webpsmux.exe (use existing binary).

.PARAMETER OutputPath
    Output zip file path. Default: webpsmux-installer.zip in repo root.
#>
param(
    [string]$PsmuxPath = "$env:LOCALAPPDATA\psmux",
    [switch]$SkipBuild,
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$installerDir = Join-Path $repoRoot "installer"
$binDir = Join-Path $installerDir "bin"
$configDir = Join-Path $installerDir "config"

if (-not $OutputPath) {
    $OutputPath = Join-Path $repoRoot "webpsmux-installer.zip"
}

Write-Host "Building webpsmux installer..." -ForegroundColor Cyan

# ─── Step 1: Build webpsmux.exe ─────────────────────────────────────

if ($SkipBuild) {
    Write-Host "  Skipping Go build (using existing binary)" -ForegroundColor Yellow
} else {
    Write-Host "  Building webpsmux.exe..." -ForegroundColor Gray
    Push-Location $repoRoot
    try {
        & go build -o webpsmux.exe . 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Go build failed" }
    } finally {
        Pop-Location
    }
    Write-Host "  OK: webpsmux.exe built" -ForegroundColor Green
}

# ─── Step 2: Copy binaries ──────────────────────────────────────────

New-Item -Path $binDir -ItemType Directory -Force | Out-Null
New-Item -Path $configDir -ItemType Directory -Force | Out-Null

# webpsmux
Copy-Item "$repoRoot\webpsmux.exe" "$binDir\webpsmux.exe" -Force
Write-Host "  OK: webpsmux.exe copied" -ForegroundColor Green

# psmux binaries
foreach ($exe in @('psmux.exe', 'pmux.exe', 'tmux.exe')) {
    $src = Join-Path $PsmuxPath $exe
    if (Test-Path $src) {
        Copy-Item $src "$binDir\$exe" -Force
        Write-Host "  OK: $exe copied from $PsmuxPath" -ForegroundColor Green
    } else {
        Write-Warning "  Missing: $src - skipping $exe"
    }
}

# ─── Step 3: Copy config ────────────────────────────────────────────

Copy-Item "$repoRoot\deploy\web.config" "$configDir\web.config" -Force
Write-Host "  OK: web.config copied" -ForegroundColor Green

# ─── Step 4: Create zip ─────────────────────────────────────────────

Write-Host "  Creating zip archive..." -ForegroundColor Gray

# Remove existing zip
if (Test-Path $OutputPath) { Remove-Item $OutputPath -Force }

# Include: Install script, Uninstall script, bin/, config/
$filesToZip = @(
    "$installerDir\Install-WebPsmux.ps1",
    "$installerDir\Uninstall-WebPsmux.ps1",
    "$binDir",
    "$configDir"
)

Compress-Archive -Path $filesToZip -DestinationPath $OutputPath -Force

$size = [math]::Round((Get-Item $OutputPath).Length / 1MB, 1)
Write-Host ""
Write-Host "  ========================================" -ForegroundColor Green
Write-Host "    Installer built: $OutputPath" -ForegroundColor Green
Write-Host "    Size: ${size} MB" -ForegroundColor Green
Write-Host "  ========================================" -ForegroundColor Green
Write-Host ""
Write-Host "  To install on a target machine:" -ForegroundColor Yellow
Write-Host "    1. Copy and extract the zip" -ForegroundColor White
Write-Host "    2. Run as Administrator:" -ForegroundColor White
Write-Host "       .\Install-WebPsmux.ps1 -Hostname 'webpsmux.mycompany.com'" -ForegroundColor Cyan
Write-Host ""
