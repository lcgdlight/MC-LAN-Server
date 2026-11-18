@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"

net session >nul 2>&1
if "%errorlevel%"=="0" goto run

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0firewall.ps1" -Elevate %*
set "EXITCODE=%ERRORLEVEL%"
if not "%EXITCODE%"=="0" pause
exit /b %EXITCODE%

:run
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0firewall.ps1" %*
set "EXITCODE=%ERRORLEVEL%"
echo.
pause
exit /b %EXITCODE%
