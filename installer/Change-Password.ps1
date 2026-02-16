#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Changes the webpsmux basic auth credentials.

.PARAMETER Username
    New username. Default: keeps current username.

.PARAMETER Password
    New password. If not provided, prompts interactively.

.EXAMPLE
    .\Change-Password.ps1
    # Prompts for new password, keeps current username

.EXAMPLE
    .\Change-Password.ps1 -Username "myuser" -Password "MyNewPass123"
#>
param(
    [string]$Username,
    [string]$Password
)

$ErrorActionPreference = 'Stop'

# ─── Get current task config ─────────────────────────────────────────

$task = Get-ScheduledTask -TaskName 'webpsmux' -ErrorAction SilentlyContinue
if (-not $task) {
    Write-Host "ERROR: Scheduled task 'webpsmux' not found. Is webpsmux installed?" -ForegroundColor Red
    exit 1
}

$currentArgs = $task.Actions[0].Arguments
$currentExe = $task.Actions[0].Execute
$currentDir = $task.Actions[0].WorkingDirectory

# Parse current credentials from -c user:pass
if ($currentArgs -match '-c\s+([^:]+):(\S+)') {
    $currentUser = $Matches[1]
    $currentPass = $Matches[2]
} else {
    Write-Host "ERROR: Could not parse current credentials from task arguments." -ForegroundColor Red
    exit 1
}

# ─── Resolve new credentials ─────────────────────────────────────────

if (-not $Username) {
    $Username = $currentUser
}

if (-not $Password) {
    Write-Host ""
    Write-Host "  Current username: $currentUser" -ForegroundColor Gray
    Write-Host ""
    $securePass = Read-Host -Prompt "  Enter new password" -AsSecureString
    $Password = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePass))

    if ([string]::IsNullOrWhiteSpace($Password)) {
        Write-Host "ERROR: Password cannot be empty." -ForegroundColor Red
        exit 1
    }
}

if ($Password.Length -lt 8) {
    Write-Host "ERROR: Password must be at least 8 characters." -ForegroundColor Red
    exit 1
}

# ─── Update task ──────────────────────────────────────────────────────

$newArgs = $currentArgs -replace '-c\s+\S+', "-c ${Username}:${Password}"

Write-Host ""
Write-Host "  Updating credentials..." -ForegroundColor Cyan

Stop-ScheduledTask -TaskName 'webpsmux' -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

$action = New-ScheduledTaskAction -Execute $currentExe -Argument $newArgs -WorkingDirectory $currentDir
Set-ScheduledTask -TaskName 'webpsmux' -Action $action | Out-Null

Start-ScheduledTask -TaskName 'webpsmux'
Start-Sleep -Seconds 2

$state = (Get-ScheduledTask -TaskName 'webpsmux').State

Write-Host ""
Write-Host "  ========================================" -ForegroundColor Green
Write-Host "    Credentials updated!" -ForegroundColor Green
Write-Host "  ========================================" -ForegroundColor Green
Write-Host ""
Write-Host "    Username:  $Username" -ForegroundColor White
Write-Host "    Password:  $Password" -ForegroundColor White
Write-Host "    Status:    $state" -ForegroundColor White
Write-Host ""
