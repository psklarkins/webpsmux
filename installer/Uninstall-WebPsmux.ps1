#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Uninstalls webpsmux and optionally psmux.

.PARAMETER InstallDir
    webpsmux installation directory. Default: C:\webpsmux

.PARAMETER KeepPsmux
    Don't remove psmux binaries from C:\psmux.

.EXAMPLE
    .\Uninstall-WebPsmux.ps1

.EXAMPLE
    .\Uninstall-WebPsmux.ps1 -KeepPsmux
#>
param(
    [string]$InstallDir = "C:\webpsmux",
    [switch]$KeepPsmux
)

$ErrorActionPreference = 'Continue'

function Write-Step {
    param([string]$Message)
    Write-Host "`n[$script:stepNum] $Message" -ForegroundColor Cyan
    $script:stepNum++
}

function Write-OK {
    param([string]$Message)
    Write-Host "    OK: $Message" -ForegroundColor Green
}

function Write-Skip {
    param([string]$Message)
    Write-Host "    SKIP: $Message" -ForegroundColor Yellow
}

$script:stepNum = 1

Write-Host "`nUninstalling webpsmux..." -ForegroundColor Yellow

# ─── Step 1: Stop and remove scheduled task ──────────────────────────

Write-Step "Scheduled task"

$task = Get-ScheduledTask -TaskName 'webpsmux' -ErrorAction SilentlyContinue
if ($task) {
    Stop-ScheduledTask -TaskName 'webpsmux' -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName 'webpsmux' -Confirm:$false
    Write-OK "Scheduled task removed"
} else {
    Write-Skip "No scheduled task found"
}

# ─── Step 2: Stop and remove IIS site + app pool ────────────────────

Write-Step "IIS site and app pool"

Import-Module WebAdministration -ErrorAction SilentlyContinue

$site = Get-IISSite -Name 'webpsmux' -ErrorAction SilentlyContinue
if ($site) {
    # Get hostname from binding for SSL cleanup
    $binding = Get-WebBinding -Name 'webpsmux' -Protocol https -ErrorAction SilentlyContinue
    $bindingHost = ''
    if ($binding) {
        $bindingHost = ($binding.bindingInformation -split ':')[-1]
    }

    Stop-IISSite -Name 'webpsmux' -Confirm:$false -ErrorAction SilentlyContinue
    Remove-IISSite -Name 'webpsmux' -Confirm:$false
    Write-OK "IIS site removed"

    # Remove SSL binding
    if ($bindingHost) {
        netsh http delete sslcert hostnameport="${bindingHost}:443" 2>$null | Out-Null
        Write-OK "SSL binding removed for $bindingHost"
    }
} else {
    Write-Skip "No IIS site found"
}

$pool = Get-IISAppPool -Name 'webpsmux' -ErrorAction SilentlyContinue
if ($pool) {
    Stop-WebAppPool -Name 'webpsmux' -ErrorAction SilentlyContinue
    Remove-WebAppPool -Name 'webpsmux'
    Write-OK "App pool removed"
} else {
    Write-Skip "No app pool found"
}

# ─── Step 3: Remove webpsmux files ──────────────────────────────────

Write-Step "webpsmux files"

if (Test-Path $InstallDir) {
    Remove-Item $InstallDir -Recurse -Force
    Write-OK "Removed $InstallDir"
} else {
    Write-Skip "$InstallDir not found"
}

# ─── Step 4: Remove psmux ───────────────────────────────────────────

Write-Step "psmux"

$psmuxDir = "C:\psmux"

if ($KeepPsmux) {
    Write-Skip "Keeping psmux (user requested)"
} else {
    if (Test-Path $psmuxDir) {
        Remove-Item $psmuxDir -Recurse -Force
        Write-OK "Removed $psmuxDir"
    } else {
        Write-Skip "$psmuxDir not found"
    }

    # Remove from system PATH
    $currentPath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    if ($currentPath -like "*$psmuxDir*") {
        $newPath = ($currentPath -split ';' | Where-Object { $_ -ne $psmuxDir }) -join ';'
        [Environment]::SetEnvironmentVariable('Path', $newPath, 'Machine')
        Write-OK "Removed $psmuxDir from system PATH"
    }
}

# ─── Step 5: Remove firewall rule ───────────────────────────────────

Write-Step "Firewall rule"

$rule = Get-NetFirewallRule -DisplayName 'webpsmux HTTPS' -ErrorAction SilentlyContinue
if ($rule) {
    Remove-NetFirewallRule -DisplayName 'webpsmux HTTPS'
    Write-OK "Firewall rule removed"
} else {
    Write-Skip "No firewall rule found"
}

# ─── Done ────────────────────────────────────────────────────────────

Write-Host "`n  webpsmux uninstalled." -ForegroundColor Green
Write-Host ""
