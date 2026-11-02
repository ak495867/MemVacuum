@echo off
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)
set SCRIPT_DIR=%~dp0
set PS_SCRIPT=%SCRIPT_DIR%memvacuum.ps1
schtasks /create /tn "MemVacuumSentinel" /tr "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File \"%PS_SCRIPT%\"" /sc onlogon /rl highest /f
schtasks /run /tn "MemVacuumSentinel"
echo MemVacuum Sentinel installed and running with elevated privileges.
pause
