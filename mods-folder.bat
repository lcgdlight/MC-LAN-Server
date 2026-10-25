@echo off
chcp 65001 >nul
cd /d "%~dp0"
if not exist "mods" mkdir "mods"
start "" explorer.exe "%~dp0mods"
