@echo off
setlocal enabledelayedexpansion

REM Development Tools Complete Uninstallation Bootstrap Script
REM Removes C:\ProgramData\%USERNAME%\devbin-win and references that point at it

echo Development Tools Complete Uninstallation
echo ==========================================
echo.

REM Get current script directory
set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

REM Set target installation directory (product root is the parent devbin-win folder)
set "INSTALL_DIR=%ProgramData%\%USERNAME%\devbin-win\bin"

echo Target directory: %INSTALL_DIR%
echo Product folder: %ProgramData%\%USERNAME%\devbin-win
echo.

REM Check if Setup-Bin.ps1 exists in subscripts directory
if not exist "%SCRIPT_DIR%\subscripts\Setup-Bin.ps1" (
    echo Error: Setup-Bin.ps1 not found in subscripts directory
    echo Please run this script from the devbin-win directory
    pause
    exit /b 1
)

REM Execute PowerShell uninstall even if the folder is already gone
echo Running complete uninstallation...
echo.

powershell.exe -ExecutionPolicy Bypass -File "%SCRIPT_DIR%\subscripts\Setup-Bin.ps1" -Uninstall -InstallDir "%INSTALL_DIR%"

set "PS_EXIT_CODE=%errorLevel%"

if !PS_EXIT_CODE! equ 2 (
    echo.
    echo Uninstallation cancelled. Nothing was removed.
    echo.
    pause
    exit /b 0
)

if !PS_EXIT_CODE! equ 0 (
    echo.
    echo ================================
    echo Complete uninstallation finished
    echo ================================
    echo.
    echo Please restart your terminal for environment changes to take effect.
    echo.
) else (
    echo.
    echo ================================
    echo Uninstallation failed!
    echo ================================
    echo.
    echo PowerShell script exited with code: !PS_EXIT_CODE!
    echo Please check the output above for error details.
    echo.
)

pause
exit /b %PS_EXIT_CODE%
