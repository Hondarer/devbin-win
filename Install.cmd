@echo off
setlocal enabledelayedexpansion

REM Development Tools Installation Bootstrap Script
REM Installs tools to C:\ProgramData\devbin-win

echo Development Tools Installation
echo ================================
echo.

REM Get current script directory
set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

REM Set target installation directory to C:\ProgramData\devbin-win\bin
set "INSTALL_DIR=C:\ProgramData\devbin-win\bin"

echo Target directory: %INSTALL_DIR%
echo.

REM Check if setup.ps1 exists
if not exist "%SCRIPT_DIR%\Setup.ps1" (
    echo Error: setup.ps1 not found in current directory
    echo Please run this script from the devbin-win directory
    pause
    exit /b 1
)

REM Check if packages folder exists
if not exist "%SCRIPT_DIR%\packages" (
    echo Error: packages folder not found
    echo Please ensure packages folder contains all required installation files
    pause
    exit /b 1
)

REM Execute PowerShell script with Bypass execution policy
echo Running installation...
echo This may take several minutes...
echo.

powershell.exe -ExecutionPolicy Bypass -File "%SCRIPT_DIR%\Setup.ps1" -Install -InstallDir "%INSTALL_DIR%"

set "PS_EXIT_CODE=%errorLevel%"

if %PS_EXIT_CODE% equ 0 (
    echo.
    echo ================================
    echo Installation completed successfully!
    echo ================================
    echo.
    echo Tools have been installed to: %INSTALL_DIR%
    echo PATH environment variables have been updated.
    echo.
    echo Please restart your terminal for PATH changes to take effect.
    echo.
) else (
    echo.
    echo ================================
    echo Installation failed!
    echo ================================
    echo.
    echo PowerShell script exited with code: %PS_EXIT_CODE%
    echo Please check the output above for error details.
    echo.
)

pause
exit /b %PS_EXIT_CODE%
