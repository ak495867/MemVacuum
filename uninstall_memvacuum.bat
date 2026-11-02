@echo off
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)
schtasks /end /tn "MemVacuumSentinel" >nul 2>&1
schtasks /delete /tn "MemVacuumSentinel" /f >nul 2>&1
echo MemVacuum Sentinel removed.
pause
