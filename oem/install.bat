@echo off
setlocal EnableExtensions
title Windows setup - Office LTSC 2024
set "OEM=C:\OEM"
set "LOGS=%OEM%\logs"
set "SHARE=\\host.lan\Data\_setup-logs"
set "PS=powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File"

if exist "%LOGS%\done.flag" exit /b 0
if not exist "%LOGS%" mkdir "%LOGS%"
if not exist "%SHARE%\" mkdir "%SHARE%" >nul 2>&1
rem Resume at the next logon if interrupted (RunOnce would also fire in this logon)
schtasks /Create /TN "OEMSetup" /TR "%OEM%\install.bat" /SC ONLOGON /RL HIGHEST /F >nul

call :status "1/3 Optimizing Windows"
%PS% "%OEM%\scripts\optimize.ps1"

call :status "2/3 Installing Office LTSC 2024: Word, Excel, PowerPoint"
%PS% "%OEM%\scripts\office.ps1"
if errorlevel 1 goto failed

call :status "3/3 Finishing"
rem dockur turns UAC off during setup, turn it back on
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v EnableLUA /t REG_DWORD /d 1 /f >nul
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v EnableLinkedConnections /t REG_DWORD /d 1 /f >nul
powershell.exe -NoLogo -NoProfile -Command "Optimize-Volume -DriveLetter C -ReTrim" >nul 2>&1
schtasks /Delete /TN "OEMSetup" /F >nul 2>&1
type nul > "%LOGS%\done.flag"
call :status "Done, restarting in 30 seconds"
call :copylogs
shutdown.exe /r /t 30 /c "Setup complete, restarting..."
exit /b 0

:failed
call :status "ERROR: Office installation failed, it will be retried at the next logon"
call :copylogs
echo See C:\OEM\logs\office.log
pause
exit /b 1

:status
echo [%time:~0,8%] %~1
>>"%LOGS%\setup.log" echo [%date% %time:~0,8%] %~1
if exist "%SHARE%\" >>"%SHARE%\status.log" echo [%date% %time:~0,8%] %~1
exit /b 0

:copylogs
robocopy "%LOGS%" "%SHARE%" /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP >nul 2>&1
exit /b 0
