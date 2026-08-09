```powershell
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

# Paths
$installPath = "C:\Program Files\RDP Wrapper"
$tempDir = "$env:TEMP\rdpwrap_install"
$tempZip = "$tempDir\RDPWrap-v1.6.2.zip"
$extractDir = "$tempDir\extracted"

# Download URLs
$zipUrl = "https://github.com/stascorp/rdpwrap/releases/download/v1.6.2/RDPWrap-v1.6.2.zip"
$customIniUrl = "https://raw.githubusercontent.com/affinityv/INI-RDPWRAP/refs/heads/master/rdpwrap.ini"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "        RDP Wrapper v1.6.2 Automated Installer" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# 2. Prepare temporary directory
Write-Host "[+] Preparing temporary directory..." -ForegroundColor Cyan

if (Test-Path $tempDir) {
    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}

New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
New-Item -ItemType Directory -Path $extractDir -Force | Out-Null


# 3. Stop Remote Desktop Service
Write-Host "[+] Stopping Remote Desktop Service..." -ForegroundColor Cyan

Stop-Service -Name "TermService" -Force -ErrorAction SilentlyContinue


# 4. Download RDP Wrapper
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


# 5. Extract ZIP
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


# 6. Find install.bat
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


# 7. Run install.bat as Administrator
Write-Host ""
Write-Host "[+] Running install.bat as Administrator..." -ForegroundColor Cyan
Write-Host "[!] Please approve the UAC prompt if it appears." -ForegroundColor Yellow

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
    Write-Host "[+] Continuing with the rest of the script..." -ForegroundColor Cyan
}
catch {
    Write-Host "[!] Failed to run install.bat." -ForegroundColor Yellow
    Write-Host $_.Exception.Message -ForegroundColor Yellow
    Write-Host "[+] Continuing anyway..." -ForegroundColor Cyan
}

# 8. Apply updated rdpwrap.ini
Write-Host ""
Write-Host "[+] Downloading updated rdpwrap.ini..." -ForegroundColor Cyan

try {
    Invoke-WebRequest `
        -Uri $customIniUrl `
        -OutFile "$installPath\rdpwrap.ini" `
        -UseBasicParsing `
        -ErrorAction Stop

    Write-Host "[+] Updated rdpwrap.ini applied." -ForegroundColor Green
}
catch {
    Write-Host "[-] Failed to download updated INI." -ForegroundColor Yellow
    Write-Host "[!] Existing INI file will be left unchanged." -ForegroundColor Yellow
}


# 9. Check for RDPConf.exe
$rdpConf = "$installPath\RDPConf.exe"

if (Test-Path $rdpConf) {
    Write-Host "[+] RDPConf.exe found." -ForegroundColor Green
}
else {
    Write-Host "[!] RDPConf.exe was not found at the expected location." -ForegroundColor Yellow
}


# 10. Restart Remote Desktop Service
Write-Host ""
Write-Host "[+] Restarting Remote Desktop Service..." -ForegroundColor Cyan

try {
    Start-Service -Name "TermService" -ErrorAction Stop
    Write-Host "[+] TermService started successfully." -ForegroundColor Green
}
catch {
    Write-Host "[!] Could not start TermService automatically." -ForegroundColor Yellow
}


# 11. Cleanup
Write-Host "[+] Cleaning temporary files..." -ForegroundColor Cyan

Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue


# 12. Finished
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "                 INSTALLATION COMPLETE" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""

if (Test-Path $rdpConf) {
    Write-Host "[+] RDPConf.exe:" -ForegroundColor Green
    Write-Host "    $rdpConf" -ForegroundColor White
    Write-Host ""
    Write-Host "[+] Launching RDPConf.exe..." -ForegroundColor Cyan

    Start-Process $rdpConf
}
else {
    Write-Host "[!] RDPConf.exe could not be located." -ForegroundColor Yellow
}

Start-Sleep -Seconds 3
```
