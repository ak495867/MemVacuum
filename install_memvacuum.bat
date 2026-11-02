@echo off
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)
set TARGET_DIR=C:\ProgramData\MemVacuum
if not exist "%TARGET_DIR%" mkdir "%TARGET_DIR%"
if exist "%~dp0memvacuum.ps1" (
    copy /y "%~dp0memvacuum.ps1" "%TARGET_DIR%\memvacuum.ps1" >nul
) else (
    powershell -NoProfile -Command "irm https://raw.githubusercontent.com/ak495867/MemVacuum/main/memvacuum.ps1 -OutFile '%TARGET_DIR%\memvacuum.ps1'"
)
set PS_SCRIPT=%TARGET_DIR%\memvacuum.ps1
schtasks /create /tn "MemVacuumSentinel" /tr "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File \"%PS_SCRIPT%\"" /sc onlogon /rl highest /f
schtasks /run /tn "MemVacuumSentinel"
echo MemVacuum Sentinel installed and running with elevated privileges.
pause
