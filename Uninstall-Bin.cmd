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

REM Check if Setup-Bin.ps1 exists in subscripts directory
if not exist "%SCRIPT_DIR%\subscripts\Setup-Bin.ps1" (
    echo Error: Setup-Bin.ps1 not found in subscripts directory
    echo Please run this script from the devbin-win directory
    pause
    exit /b 1
)

REM Execute PowerShell uninstall script with Bypass execution policy
echo Running uninstallation...
echo.

powershell.exe -ExecutionPolicy Bypass -File "%SCRIPT_DIR%\subscripts\Setup-Bin.ps1" -Uninstall -InstallDir "%INSTALL_DIR%"

set "PS_EXIT_CODE=%errorLevel%"

if !PS_EXIT_CODE! equ 0 (
    echo.
    echo Removing parent directory if empty...
    set "PARENT_DIR=C:\ProgramData\devbin-win"
    set "PARENT_REMOVED=0"
    if exist "!PARENT_DIR!" (
        rmdir "!PARENT_DIR!" 2>nul
        if !errorLevel! equ 0 (
            echo Parent directory removed: !PARENT_DIR!
            set "PARENT_REMOVED=1"
        ) else (
            echo Parent directory not empty or in use: !PARENT_DIR!
            echo (This is normal if VS Code data was preserved^)
        )
    ) else (
        echo Parent directory already removed: !PARENT_DIR!
        set "PARENT_REMOVED=1"
    )

    echo.
    echo ================================
    echo Uninstallation completed successfully!
    echo ================================
    echo.
    echo The following actions were performed:
    echo - Removed PATH environment variables
    echo - Removed DOTNET_HOME environment variable
    echo - Removed DOTNET_CLI_TELEMETRY_OPTOUT environment variable
    echo - Deleted installation directory: %INSTALL_DIR%
    if !PARENT_REMOVED! equ 1 (
        echo - Removed parent directory: C:\ProgramData\devbin-win
    ) else (
        echo - Parent directory preserved (contains VS Code data or other files^)
    )
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
