#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installs webpsmux (browser-based terminal) and psmux (Windows tmux) on Windows.

.DESCRIPTION
    Self-contained installer that sets up:
    - psmux terminal multiplexer (C:\psmux, added to PATH)
    - webpsmux Go binary with IIS reverse proxy
    - HTTPS with self-signed or provided certificate
    - Scheduled task for auto-start
    - Firewall rule for HTTPS access

.PARAMETER Hostname
    Required. The hostname for the IIS site (e.g., webpsmux.mycompany.com).

.PARAMETER Username
    Basic auth username. Default: admin

.PARAMETER Password
    Basic auth password. Default: auto-generated 16-char random string.

.PARAMETER Port
    Internal port for the Go binary. Default: 8080

.PARAMETER PsmuxSession
    psmux session name to attach to. Default: default

.PARAMETER InstallDir
    Installation directory for webpsmux. Default: C:\webpsmux

.PARAMETER CertThumbprint
    Use an existing certificate instead of generating self-signed.

.PARAMETER SkipIISFeatures
    Skip IIS feature installation (assume already installed).

.PARAMETER SkipFirewall
    Skip firewall rule creation.

.EXAMPLE
    .\Install-WebPsmux.ps1 -Hostname "webpsmux.mycompany.com"

.EXAMPLE
    .\Install-WebPsmux.ps1 -Hostname "term.example.com" -CertThumbprint "AB12CD34..."
#>
param(
    [Parameter(Mandatory)]
    [string]$Hostname,

    [string]$Username = "admin",
    [string]$Password,
    [int]$Port = 8080,
    [string]$PsmuxSession = "default",
    [string]$InstallDir = "C:\webpsmux",
    [string]$CertThumbprint,
    [switch]$SkipIISFeatures,
    [switch]$SkipFirewall
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# ─── Helper Functions ────────────────────────────────────────────────

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

function Write-Fail {
    param([string]$Message)
    Write-Host "    FAIL: $Message" -ForegroundColor Red
}

function New-RandomPassword {
    param([int]$Length = 16)
    $chars = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#%'
    -join (1..$Length | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
}

$script:stepNum = 1

# ─── Step 1: Preflight ──────────────────────────────────────────────

Write-Step "Preflight checks"

# Windows x64
if ([Environment]::Is64BitOperatingSystem -eq $false) {
    throw "webpsmux requires 64-bit Windows."
}
Write-OK "Windows x64"

# PowerShell version
if ($PSVersionTable.PSVersion.Major -lt 5) {
    throw "PowerShell 5.1 or later required. Current: $($PSVersionTable.PSVersion)"
}
Write-OK "PowerShell $($PSVersionTable.PSVersion)"

# Windows version
$os = [System.Environment]::OSVersion.Version
if ($os.Major -lt 10) {
    throw "Windows 10/Server 2016 or later required."
}
Write-OK "Windows $($os.Major).$($os.Minor) Build $($os.Build)"

# Verify installer files
$binDir = Join-Path $scriptDir "bin"
$configDir = Join-Path $scriptDir "config"

foreach ($file in @("$binDir\webpsmux.exe", "$binDir\psmux.exe", "$configDir\web.config")) {
    if (-not (Test-Path $file)) {
        throw "Missing required file: $file"
    }
}
Write-OK "Installer files present"

# ─── Step 2: Credentials ─────────────────────────────────────────────

Write-Step "Credentials"

if (-not $Password) {
    Write-Host ""
    Write-Host "    Choose a password for basic auth (username: $Username)" -ForegroundColor White
    Write-Host "    Press Enter to auto-generate a random password." -ForegroundColor Gray
    Write-Host ""
    $securePass = Read-Host -Prompt "    Password" -AsSecureString
    $typedPass = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePass))

    if ([string]::IsNullOrWhiteSpace($typedPass)) {
        $Password = New-RandomPassword
        Write-OK "Generated random password (shown in summary)"
    } else {
        if ($typedPass.Length -lt 8) {
            throw "Password must be at least 8 characters."
        }
        $Password = $typedPass
        Write-OK "Using provided password"
    }
} else {
    Write-OK "Using password from -Password parameter"
}

# ─── Step 3: Install IIS features ───────────────────────────────────

Write-Step "IIS features"

if ($SkipIISFeatures) {
    Write-Skip "IIS feature installation (user requested skip)"
} else {
    $features = @('Web-Server', 'Web-WebSockets', 'Web-Filtering', 'Web-Mgmt-Console')

    # Detect Server vs Desktop
    $isServer = (Get-CimInstance Win32_OperatingSystem).ProductType -ne 1

    foreach ($feature in $features) {
        if ($isServer) {
            $installed = (Get-WindowsFeature -Name $feature -ErrorAction SilentlyContinue).Installed
            if (-not $installed) {
                Install-WindowsFeature -Name $feature -ErrorAction Stop | Out-Null
                Write-OK "Installed $feature"
            } else {
                Write-OK "$feature (already installed)"
            }
        } else {
            # Desktop Windows uses different feature names
            $featureMap = @{
                'Web-Server'       = 'IIS-WebServer'
                'Web-WebSockets'   = 'IIS-WebSockets'
                'Web-Filtering'    = 'IIS-RequestFiltering'
                'Web-Mgmt-Console' = 'IIS-ManagementConsole'
            }
            $desktopName = $featureMap[$feature]
            if ($desktopName) {
                $state = (Get-WindowsOptionalFeature -Online -FeatureName $desktopName -ErrorAction SilentlyContinue).State
                if ($state -ne 'Enabled') {
                    Enable-WindowsOptionalFeature -Online -FeatureName $desktopName -NoRestart -ErrorAction Stop | Out-Null
                    Write-OK "Enabled $desktopName"
                } else {
                    Write-OK "$desktopName (already enabled)"
                }
            }
        }
    }
}

# ─── Step 4: URL Rewrite module ─────────────────────────────────────

Write-Step "URL Rewrite module"

Import-Module WebAdministration -ErrorAction SilentlyContinue

$rewriteInstalled = $null -ne (Get-WebGlobalModule -Name "RewriteModule" -ErrorAction SilentlyContinue)

if ($rewriteInstalled) {
    Write-OK "URL Rewrite module (already installed)"
} else {
    $msiUrl = "https://download.microsoft.com/download/1/2/8/128E2E22-C1B9-44A4-BE2A-5859ED1D4592/rewrite_amd64_en-US.msi"
    $msiPath = Join-Path $env:TEMP "rewrite_amd64.msi"

    Write-Host "    Downloading URL Rewrite module..." -ForegroundColor Gray
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath -UseBasicParsing

    Write-Host "    Installing URL Rewrite module..." -ForegroundColor Gray
    $proc = Start-Process msiexec.exe -ArgumentList "/i `"$msiPath`" /qn" -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        throw "URL Rewrite installation failed (exit code: $($proc.ExitCode))"
    }
    Remove-Item $msiPath -Force -ErrorAction SilentlyContinue
    Write-OK "URL Rewrite module installed"
}

# ─── Step 5: Enable ARR proxy ───────────────────────────────────────

Write-Step "Application Request Routing (ARR) proxy"

try {
    $proxyEnabled = (Get-WebConfigurationProperty -pspath 'MACHINE/WEBROOT/APPHOST' `
        -filter 'system.webServer/proxy' -name 'enabled' -ErrorAction SilentlyContinue).Value

    if ($proxyEnabled -eq $true) {
        Write-OK "ARR proxy (already enabled)"
    } else {
        Set-WebConfigurationProperty -pspath 'MACHINE/WEBROOT/APPHOST' `
            -filter 'system.webServer/proxy' -name 'enabled' -value 'True'
        Write-OK "ARR proxy enabled"
    }
} catch {
    # ARR module may not be installed — install it
    Write-Host "    ARR not available. Installing..." -ForegroundColor Gray
    $arrUrl = "https://download.microsoft.com/download/E/9/8/E9849D6A-020E-47E4-9FD0-A023E99B54EB/requestRouter_amd64.msi"
    $arrPath = Join-Path $env:TEMP "requestRouter_amd64.msi"

    Invoke-WebRequest -Uri $arrUrl -OutFile $arrPath -UseBasicParsing
    $proc = Start-Process msiexec.exe -ArgumentList "/i `"$arrPath`" /qn" -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        throw "ARR installation failed (exit code: $($proc.ExitCode))"
    }
    Remove-Item $arrPath -Force -ErrorAction SilentlyContinue

    Set-WebConfigurationProperty -pspath 'MACHINE/WEBROOT/APPHOST' `
        -filter 'system.webServer/proxy' -name 'enabled' -value 'True'
    Write-OK "ARR installed and proxy enabled"
}

# ─── Step 6: Deploy webpsmux ────────────────────────────────────────

Write-Step "Deploy webpsmux to $InstallDir"

New-Item -Path $InstallDir -ItemType Directory -Force | Out-Null
Copy-Item "$binDir\webpsmux.exe" "$InstallDir\webpsmux.exe" -Force
Copy-Item "$configDir\web.config" "$InstallDir\web.config" -Force
Write-OK "webpsmux.exe and web.config deployed"

# ─── Step 7: Install psmux ──────────────────────────────────────────

Write-Step "Install psmux to C:\psmux"

$psmuxDir = "C:\psmux"
New-Item -Path $psmuxDir -ItemType Directory -Force | Out-Null

foreach ($exe in @('psmux.exe', 'pmux.exe', 'tmux.exe')) {
    $src = Join-Path $binDir $exe
    if (Test-Path $src) {
        Copy-Item $src "$psmuxDir\$exe" -Force
        Write-OK "$exe copied"
    }
}

# Add to system PATH if not already there
$currentPath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
if ($currentPath -notlike "*$psmuxDir*") {
    [Environment]::SetEnvironmentVariable('Path', "$currentPath;$psmuxDir", 'Machine')
    $env:Path = "$env:Path;$psmuxDir"
    Write-OK "C:\psmux added to system PATH"
} else {
    Write-OK "C:\psmux already in PATH"
}

# ─── Step 8: SSL certificate ────────────────────────────────────────

Write-Step "SSL certificate for $Hostname"

if ($CertThumbprint) {
    $cert = Get-ChildItem "Cert:\LocalMachine\My\$CertThumbprint" -ErrorAction SilentlyContinue
    if (-not $cert) {
        throw "Certificate with thumbprint $CertThumbprint not found in Cert:\LocalMachine\My"
    }
    Write-OK "Using existing certificate: $($cert.Subject)"
} else {
    $cert = New-SelfSignedCertificate `
        -DnsName $Hostname `
        -CertStoreLocation 'Cert:\LocalMachine\My' `
        -NotAfter (Get-Date).AddYears(2) `
        -FriendlyName "webpsmux - $Hostname"
    $CertThumbprint = $cert.Thumbprint
    Write-OK "Generated self-signed certificate (expires $($cert.NotAfter.ToString('yyyy-MM-dd')))"
}

# Bind cert via netsh (remove existing first)
netsh http delete sslcert hostnameport="${Hostname}:443" 2>$null | Out-Null
$appId = '{4dc3e181-e14b-4a21-b022-59fc669b0914}'
$result = netsh http add sslcert hostnameport="${Hostname}:443" certhash=$CertThumbprint certstorename=MY appid="$appId" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Fail "SSL binding: $result"
    throw "Failed to bind SSL certificate"
}
Write-OK "SSL certificate bound to ${Hostname}:443"

# ─── Step 9: Unlock IIS config sections ─────────────────────────────

Write-Step "Unlock IIS configuration sections"

$appcmd = "$env:SystemRoot\System32\inetsrv\appcmd.exe"
$sections = @(
    'system.webServer/rewrite/rules',
    'system.webServer/webSocket',
    'system.webServer/rewrite/allowedServerVariables'
)

foreach ($section in $sections) {
    $output = & $appcmd unlock config -section:$section 2>&1
    if ($output -match "Unlocked|already") {
        Write-OK "Unlocked $section"
    } else {
        Write-OK "$section (processed)"
    }
}

# ─── Step 10: Allow server variables ────────────────────────────────

Write-Step "Allow rewrite server variables"

$serverVars = @('HTTP_X_FORWARDED_PROTO', 'HTTP_X_FORWARDED_HOST')
foreach ($var in $serverVars) {
    try {
        $existing = Get-WebConfigurationProperty -pspath 'MACHINE/WEBROOT/APPHOST' `
            -filter "system.webServer/rewrite/allowedServerVariables/add[@name='$var']" `
            -name 'name' -ErrorAction SilentlyContinue

        if (-not $existing) {
            Add-WebConfigurationProperty -pspath 'MACHINE/WEBROOT/APPHOST' `
                -filter 'system.webServer/rewrite/allowedServerVariables' `
                -name '.' -value @{name=$var}
            Write-OK "Allowed $var"
        } else {
            Write-OK "$var (already allowed)"
        }
    } catch {
        Write-OK "$var (processed)"
    }
}

# ─── Step 11: Create IIS site ───────────────────────────────────────

Write-Step "Create IIS site"

# Remove existing site/pool if present
if (Get-IISSite -Name 'webpsmux' -ErrorAction SilentlyContinue) {
    Stop-IISSite -Name 'webpsmux' -Confirm:$false -ErrorAction SilentlyContinue
    Remove-IISSite -Name 'webpsmux' -Confirm:$false
    Write-OK "Removed existing webpsmux site"
}

# Create app pool
if (-not (Get-IISAppPool -Name 'webpsmux' -ErrorAction SilentlyContinue)) {
    $pool = New-WebAppPool -Name 'webpsmux'
    Set-ItemProperty "IIS:\AppPools\webpsmux" -Name managedRuntimeVersion -Value ''
    Write-OK "Created app pool (No Managed Code)"
} else {
    Write-OK "App pool exists"
}

# Reset IIS server manager to avoid config commit conflicts
Reset-IISServerManager -Confirm:$false -ErrorAction SilentlyContinue

# Create site with HTTPS + SNI binding
New-IISSite -Name 'webpsmux' `
    -PhysicalPath $InstallDir `
    -BindingInformation "*:443:${Hostname}" `
    -Protocol https `
    -SslFlag Sni `
    -CertificateThumbPrint $CertThumbprint `
    -CertStoreLocation 'Cert:\LocalMachine\My'

# Assign app pool
Set-ItemProperty "IIS:\Sites\webpsmux" -Name applicationPool -Value 'webpsmux'
Write-OK "IIS site created: https://${Hostname}"

# ─── Step 12: Create scheduled task ─────────────────────────────────

Write-Step "Create scheduled task"

# Remove existing
Unregister-ScheduledTask -TaskName 'webpsmux' -Confirm:$false -ErrorAction SilentlyContinue

$taskArgs = "-w -a 127.0.0.1 -p $Port -c ${Username}:${Password} psmux attach -t $PsmuxSession"

$action = New-ScheduledTaskAction `
    -Execute "$InstallDir\webpsmux.exe" `
    -Argument $taskArgs `
    -WorkingDirectory $InstallDir

$trigger = New-ScheduledTaskTrigger -AtStartup

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -RestartCount 3 `
    -RestartInterval ([TimeSpan]::FromMinutes(1))

$principal = New-ScheduledTaskPrincipal `
    -UserId 'SYSTEM' `
    -LogonType ServiceAccount `
    -RunLevel Highest

Register-ScheduledTask `
    -TaskName 'webpsmux' `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal `
    -Description "WebPsmux - browser terminal for psmux sessions at https://$Hostname" `
    -Force | Out-Null

Write-OK "Scheduled task registered (runs as SYSTEM at startup)"

# ─── Step 13: Firewall rule ─────────────────────────────────────────

Write-Step "Firewall"

if ($SkipFirewall) {
    Write-Skip "Firewall rule (user requested skip)"
} else {
    $existing = Get-NetFirewallRule -DisplayName 'webpsmux HTTPS' -ErrorAction SilentlyContinue
    if ($existing) {
        Write-OK "Firewall rule exists"
    } else {
        New-NetFirewallRule `
            -DisplayName 'webpsmux HTTPS' `
            -Direction Inbound `
            -Protocol TCP `
            -LocalPort 443 `
            -Action Allow `
            -Description "Allow HTTPS for webpsmux terminal" | Out-Null
        Write-OK "Firewall rule created (TCP 443 inbound)"
    }
}

# ─── Step 14: Start services ────────────────────────────────────────

Write-Step "Start services"

Start-WebAppPool -Name 'webpsmux' -ErrorAction SilentlyContinue
Start-IISSite -Name 'webpsmux' -ErrorAction SilentlyContinue
Write-OK "IIS site started"

Start-ScheduledTask -TaskName 'webpsmux'
Start-Sleep -Seconds 3
Write-OK "Scheduled task started"

# ─── Step 15: Verify ────────────────────────────────────────────────

Write-Step "Verify installation"

try {
    # PS 5.1 compat: use compiled C# delegate for cert validation bypass
    # (script blocks fail on .NET threads without a PowerShell runspace)
    if (-not ([System.Management.Automation.PSTypeName]'WebPsmuxCertBypass').Type) {
        Add-Type -TypeDefinition @"
using System.Net;
using System.Net.Security;
using System.Security.Cryptography.X509Certificates;
public class WebPsmuxCertBypass {
    public static void Enable() {
        ServicePointManager.ServerCertificateValidationCallback =
            new RemoteCertificateValidationCallback(delegate { return true; });
    }
    public static void Disable() {
        ServicePointManager.ServerCertificateValidationCallback = null;
    }
}
"@
    }
    [WebPsmuxCertBypass]::Enable()

    # PS 5.1 defaults to TLS 1.0/1.1 which modern IIS may reject
    $oldProtocol = [System.Net.ServicePointManager]::SecurityProtocol
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

    $authBytes = [Text.Encoding]::ASCII.GetBytes("${Username}:${Password}")
    $authHeader = "Basic $([Convert]::ToBase64String($authBytes))"

    $response = Invoke-WebRequest -Uri "https://localhost/" `
        -Headers @{ Host = $Hostname; Authorization = $authHeader } `
        -TimeoutSec 10 `
        -UseBasicParsing `
        -ErrorAction Stop

    [WebPsmuxCertBypass]::Disable()
    [System.Net.ServicePointManager]::SecurityProtocol = $oldProtocol

    if ($response.StatusCode -eq 200) {
        Write-OK "HTTPS responding (HTTP 200)"
    } else {
        Write-Fail "Unexpected status: $($response.StatusCode)"
    }
} catch {
    [WebPsmuxCertBypass]::Disable()
    [System.Net.ServicePointManager]::SecurityProtocol = $oldProtocol
    Write-Fail "Verification failed: $($_.Exception.Message)"
    Write-Host "    The service may need a moment to start. Try accessing https://$Hostname manually." -ForegroundColor Yellow
}

# ─── Step 16: Summary ───────────────────────────────────────────────

Write-Host "`n" -NoNewline
Write-Host "  ============================================" -ForegroundColor Green
Write-Host "    webpsmux installed successfully!" -ForegroundColor Green
Write-Host "  ============================================" -ForegroundColor Green
Write-Host ""
Write-Host "    URL:       https://$Hostname/" -ForegroundColor White
Write-Host "    Username:  $Username" -ForegroundColor White
Write-Host "    Password:  $Password" -ForegroundColor White
Write-Host "    psmux:     C:\psmux\psmux.exe" -ForegroundColor White
Write-Host "    Session:   $PsmuxSession" -ForegroundColor White
Write-Host ""
Write-Host "  NOTE: You must start a psmux session before" -ForegroundColor Yellow
Write-Host "  the terminal will work. Open a terminal and run:" -ForegroundColor Yellow
Write-Host "    psmux new-session -d -s $PsmuxSession" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Then restart the webpsmux task:" -ForegroundColor Yellow
Write-Host "    Start-ScheduledTask -TaskName webpsmux" -ForegroundColor Cyan
Write-Host ""
