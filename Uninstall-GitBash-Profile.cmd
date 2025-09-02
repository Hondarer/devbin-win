@echo off
setlocal enabledelayedexpansion

REM Get current script directory
set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

powershell.exe -ExecutionPolicy Bypass -File "%SCRIPT_DIR%\Update-GitBash-Profile.ps1" -UnInstall

set "PS_EXIT_CODE=%errorLevel%"

pause
exit /b %PS_EXIT_CODE%
