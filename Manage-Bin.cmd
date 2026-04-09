@echo off
setlocal enabledelayedexpansion

REM Development Tools Component Manager Bootstrap Script
REM Interactive menu for selective setup/unsetup of components

echo Development Tools Component Manager
echo =====================================
echo.

REM Get current script directory
set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

REM Set target installation directory to C:\ProgramData\devbin-win\bin
set "INSTALL_DIR=C:\ProgramData\devbin-win\bin"

echo Target directory: %INSTALL_DIR%
echo.

REM Check if Setup-Bin.ps1 exists
if not exist "%SCRIPT_DIR%\subscripts\Setup-Bin.ps1" (
    echo Error: Setup-Bin.ps1 not found in subscripts directory
    echo Please run this script from the devbin-win directory
    pause
    exit /b 1
)

REM Execute PowerShell script in Manage mode
powershell.exe -ExecutionPolicy Bypass -File "%SCRIPT_DIR%\subscripts\Setup-Bin.ps1" -Manage -InstallDir "%INSTALL_DIR%"

set "PS_EXIT_CODE=%errorLevel%"

if %PS_EXIT_CODE% neq 0 (
    echo.
    echo PowerShell script exited with code: %PS_EXIT_CODE%
    echo Please check the output above for error details.
    echo.
)

exit /b %PS_EXIT_CODE%
