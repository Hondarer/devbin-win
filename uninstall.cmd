@echo off
setlocal enabledelayedexpansion

REM Development Tools Uninstallation Bootstrap Script
REM Removes tools from C:\ProgramData\devbin-win

echo Development Tools Uninstallation
echo ==================================
echo.

REM Get current script directory
set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

REM Set target installation directory
set "INSTALL_DIR=C:\ProgramData\devbin-win\bin"

echo Target directory: %INSTALL_DIR%
echo.

REM Check if installation directory exists
if not exist "%INSTALL_DIR%" (
    echo No installation found at: %INSTALL_DIR%
    echo Nothing to uninstall.
    pause
    exit /b 0
)

REM Check if setup.ps1 exists in current directory
if not exist "%SCRIPT_DIR%\setup.ps1" (
    echo Error: setup.ps1 not found in current directory
    echo Please run this script from the devbin-win directory
    pause
    exit /b 1
)

REM Execute PowerShell uninstall script with Bypass execution policy
echo Running uninstallation...
echo.

powershell.exe -ExecutionPolicy Bypass -File "%SCRIPT_DIR%\setup.ps1" -Uninstall -InstallDir "%INSTALL_DIR%"

set "PS_EXIT_CODE=%errorLevel%"

if %PS_EXIT_CODE% equ 0 (
    echo.
    echo Removing parent directory if empty...
    set "PARENT_DIR=C:\ProgramData\devbin-win"
    if exist "!PARENT_DIR!" (
        rmdir "!PARENT_DIR!" 2>nul
        if %errorLevel% equ 0 (
            echo Parent directory removed: !PARENT_DIR!
        ) else (
            echo Parent directory not empty or in use: !PARENT_DIR!
        )
    ) else (
        echo Parent directory already removed: !PARENT_DIR!
    )
    
    echo.
    echo ================================
    echo Uninstallation completed successfully!
    echo ================================
    echo.
    echo The following actions were performed:
    echo - Removed PATH environment variables
    echo - Deleted installation directory: %INSTALL_DIR%
    echo - Removed parent directory: C:\ProgramData\devbin-win
    echo.
    echo Please restart your terminal for PATH changes to take effect.
    echo.
) else (
    echo.
    echo ================================
    echo Uninstallation failed!
    echo ================================
    echo.
    echo PowerShell script exited with code: %PS_EXIT_CODE%
    echo Please check the output above for error details.
    echo.
)

pause
exit /b %PS_EXIT_CODE%
