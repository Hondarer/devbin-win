@echo off
setlocal enabledelayedexpansion

REM MinGW PATH 動的追加スクリプト
REM Git MinGW バイナリを現在のセッションの PATH に追加します

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "MINGW_PATH=%SCRIPT_DIR%\git\mingw64\bin"
set "USR_PATH=%SCRIPT_DIR%\git\usr\bin"

REM MinGW パスの存在確認
if not exist "%MINGW_PATH%" (
    echo Error: MinGW path not found: %MINGW_PATH%
    echo Please ensure Git is properly installed
    exit /b 1
)

if not exist "%USR_PATH%" (
    echo Error: usr/bin path not found: %USR_PATH%
    echo Please ensure Git is properly installed
    exit /b 1
)

set "PATH_CHANGED=0"

REM 既存の PATH に MinGW パスが含まれているかチェック
echo %PATH% | findstr /C:"%MINGW_PATH%" >nul
if %ERRORLEVEL% neq 0 (
    set "PATH=%MINGW_PATH%;%PATH%"
    set "PATH_CHANGED=1"
)

echo %PATH% | findstr /C:"%USR_PATH%" >nul
if %ERRORLEVEL% neq 0 (
    set "PATH=%USR_PATH%;%PATH%"
    set "PATH_CHANGED=1"
)

if %PATH_CHANGED%==1 (
    echo MinGW PATH addition completed.
) else (
    echo MinGW PATH already set.
)

endlocal & set "PATH=%PATH%"