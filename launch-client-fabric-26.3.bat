@echo off
chcp 65001>nul
title Minecraft 26.3 Fabric - MC-LAN-Server
cd /d "C:\.minecraft\versions\fabric-loader-0.20.1-26.3"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0launch-client-fabric-26.3.ps1"
echo.
pause
