# 開発ツール セットアップ スクリプト
# コンポーネント マネージャーの起動と、製品の完全アンインストールを行う

param(
    [string]$InstallDir = ".\bin",
    [switch]$Uninstall,
    [switch]$Manage,
    [switch]$Force
)

# スクリプトのディレクトリを取得
$ScriptDir = if ($PSScriptRoot) {
    $PSScriptRoot
} elseif ($MyInvocation.MyCommand.Path) {
    Split-Path -Parent $MyInvocation.MyCommand.Path
} else {
    # フォールバック: 現在の実行ディレクトリを使用
    Get-Location | Select-Object -ExpandProperty Path
}

# モジュールをインポート
$devbinModulePath = "$ScriptDir\Devbin"
try {
    Import-Module $devbinModulePath -Force -ErrorAction Stop
} catch {
    Write-Host "Error importing Devbin: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# パッケージ設定を読み込む (完全アンインストールは定義に依存しない)
$DevbinContext = New-DevbinContext -InstallDir $InstallDir -SubscriptsDir $ScriptDir
$Packages = @()
if (-not $Uninstall) {
    $catalog = Import-PackageCatalog -Path $DevbinContext.ConfigPath
    if (-not $catalog.Success) {
        Write-Host "Error: パッケージ定義に問題があります" -ForegroundColor Red
        foreach ($message in $catalog.Errors) {
            Write-Host "  $message" -ForegroundColor Red
        }
        exit 1
    }
    $Packages = $catalog.Packages
}

# オプションが指定されていない場合は使用方法を表示
if (-not ($Uninstall -or $Manage)) {
    Write-Host "Development Tools Setup Script"
    Write-Host "================================"
    Write-Host ""
    Write-Host "Usage:"
    Write-Host "  .\Setup-Bin.ps1 -Manage [-InstallDir <path>]     # Interactive component manager"
    Write-Host "  .\Setup-Bin.ps1 -Uninstall [-InstallDir <path>] [-Force]"
    Write-Host "      # Remove the product folder and references that point at it"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -InstallDir <path>  Installation directory (default: .\bin)"
    Write-Host "  -Force              Skip the complete-uninstall confirmation prompt"
    Write-Host ""
    Write-Host "Note: -Uninstall only targets %ProgramData%\%USERNAME%\devbin-win."
    Write-Host "      Other locations are refused without removing anything."
    Write-Host ""
    Write-Host "Note: 一括導入はコンポーネント マネージャーの全選択に集約しました。"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\Setup-Bin.ps1 -Manage                          # Open component manager"
    Write-Host "  .\Setup-Bin.ps1 -Uninstall -InstallDir `"`$env:ProgramData\`$env:USERNAME\devbin-win\bin`""
    Write-Host "      # Complete uninstall of the standard location (-Force skips the prompt)"
    exit 0
}

# 昇格された管理者権限での実行を検出する (本スクリプトは非昇格ユーザーでの実行を想定)
$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
if ($currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Warning: This script is not intended to be run with elevated administrator privileges." -ForegroundColor Yellow
    Write-Host "Please run it from a non-elevated (standard user) shell." -ForegroundColor Yellow
    exit 1
}

# Manage モード: 対話型コンポーネント マネージャー
if ($Manage) {
    # 導入先は実行コンテキストで解決済みの絶対パスを使用する
    $absoluteInstallDir = $DevbinContext.InstallDir

    # 環境変数をレジストリから同期
    Sync-EnvironmentVariables -VariableNames @("PATH", "DOTNET_HOME", "DOTNET_CLI_TELEMETRY_OPTOUT", "PLANTUML_HOME", "BROWSER_PATH", "PUPPETEER_EXECUTABLE_PATH") -Silent | Out-Null

    Invoke-MenuLoop -Packages $Packages -InstallDir $absoluteInstallDir -ScriptDir $ScriptDir
    exit 0
}

# アンインストール処理 (状態に依存しない機械的な完全削除)
if ($Uninstall) {
    $absoluteInstallDir = $DevbinContext.InstallDir
    $result = Invoke-ProductUninstall -InstallDir $absoluteInstallDir -Force:$Force
    switch ($result.Status) {
        "Success" {
            exit 0
        }
        "Cancelled" {
            # キャンセルは失敗と区別する (呼び出し元が完了メッセージを出力しないようにする)
            exit 2
        }
        "Refused" {
            exit 1
        }
        default {
            Write-Host ""
            Write-Host "Error: Complete uninstallation failed." -ForegroundColor Red
            exit 1
        }
    }
}

