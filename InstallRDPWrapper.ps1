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
# 8. Apply updated rdpwrap.ini
# ============================================================

Write-Host ""
Write-Host "[+] Downloading updated rdpwrap.ini..." -ForegroundColor Cyan

try {
    if (-not (Test-Path $installPath)) {
        New-Item -ItemType Directory -Path $installPath -Force | Out-Null
    }

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

# ============================================================
# 12. Finished
# ============================================================

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "                 INSTALLATION COMPLETE" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""

if (Test-Path $rdpConf) {
    Write-Host "[+] RDPConf.exe installed successfully." -ForegroundColor Green
    Write-Host "    $rdpConf" -ForegroundColor White
    Write-Host ""
    Write-Host "[+] RDPConf.exe will NOT be launched automatically." -ForegroundColor Cyan
}
else {
    Write-Host "[!] RDPConf.exe could not be located." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "The installer has finished." -ForegroundColor Green
Write-Host ""

Start-Sleep -Seconds 3
```
