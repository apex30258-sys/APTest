# Ensure the script runs with Administrator privileges
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[-] Error: Please run this script as an Administrator!" -ForegroundColor Red
    Start-Sleep -Seconds 3
    exit
}

$installPath = "C:\Program Files\RDP Wrapper"
$zipUrl = "https://github.com/stascorp/rdpwrap/releases/download/v1.6.2/RDPWrap-v1.6.2.zip"
$tempZip = "$env:TEMP\rdpwrap_v1.6.2.zip"
$extractDir = "$env:TEMP\rdpwrap_extracted"

# REPLACE THIS URL WITH YOUR OWN CUSTOM RAW INI LINK
$customIniUrl = "https://raw.githubusercontent.com/affinityv/INI-RDPWRAP/refs/heads/master/rdpwrap.ini"

Write-Host "[+] Stopping Remote Desktop Service (TermService)..." -ForegroundColor Cyan
Stop-Service -Name "TermService" -Force -ErrorAction SilentlyContinue

# 1. Download and Extract RDP Wrapper v1.6.2
Write-Host "[+] Downloading RDP Wrapper v1.6.2 from official repository..." -ForegroundColor Cyan
try {
    Invoke-WebRequest -Uri $zipUrl -OutFile $tempZip -UseBasicParsing
}
catch {
    Write-Host "[-] Failed to download RDP Wrapper v1.6.2 zip package." -ForegroundColor Red
    exit
}

Write-Host "[+] Extracting package files..." -ForegroundColor Cyan
if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
Expand-Archive -Path $tempZip -DestinationPath $extractDir -Force

# 2. Run the base installation files
Write-Host "[+] Installing RDP Wrapper binaries..." -ForegroundColor Cyan
if (-not (Test-Path $installPath)) {
    New-Item -ItemType Directory -Path $installPath -Force | Out-Null
}
Copy-Item "$extractDir\*" $installPath -Recurse -Force

# 3. Download and overwrite with your custom/updated rdpwrap.ini
Write-Host "[+] Downloading your custom rdpwrap.ini from GitHub..." -ForegroundColor Cyan
try {
    Invoke-WebRequest -Uri $customIniUrl -OutFile "$installPath\rdpwrap.ini" -UseBasicParsing
    Write-Host "[+] Successfully applied custom rdpwrap.ini!" -ForegroundColor Green
}
catch {
    Write-Host "[-] Failed to download custom INI file. Falling back to default package INI." -ForegroundColor Yellow
}

# 4. Restart the Remote Desktop Service
Write-Host "[+] Restarting Remote Desktop Service (TermService)..." -ForegroundColor Cyan
Start-Service -Name "TermService" -ErrorAction SilentlyContinue

# Cleanup temp files
Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "[*] Complete! You can now launch C:\Program Files\RDP Wrapper\RDPConf.exe to check status." -ForegroundColor Green
Start-Sleep -Seconds 3