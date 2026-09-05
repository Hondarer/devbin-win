@echo off
setlocal enabledelayedexpansion

REM MinGW PATH 動的削除スクリプト
REM Git MinGW バイナリを現在のセッションの PATH から削除します

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "MINGW_PATH=%SCRIPT_DIR%\git\mingw64\bin"
set "USR_PATH=%SCRIPT_DIR%\git\usr\bin"

REM 現在の PATH をセミコロンで分割して処理
set "NEW_PATH="
set "PATH_CHANGED=0"

for %%i in ("%PATH:;=" "%") do (
    set "CURRENT_ITEM=%%~i"
    
    REM 削除対象のパスかどうかをチェック
    if /i "!CURRENT_ITEM!"=="%MINGW_PATH%" (
        set "PATH_CHANGED=1"
    ) else if /i "!CURRENT_ITEM!"=="%USR_PATH%" (
        set "PATH_CHANGED=1"
    ) else (
        REM 空でない場合のみ新しい PATH に追加
        if not "!CURRENT_ITEM!"=="" (
            if defined NEW_PATH (
                set "NEW_PATH=!NEW_PATH!;!CURRENT_ITEM!"
            ) else (
                set "NEW_PATH=!CURRENT_ITEM!"
            )
        )
    )
)

if %PATH_CHANGED%==1 (
    set "PATH=!NEW_PATH!"
    echo MinGW PATH removal completed.
) else (
    echo MinGW PATH was not set.
)

endlocal & set "PATH=%PATH%"