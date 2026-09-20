# 開発環境セットアップ スクリプト
# コンポーネント マネージャーの起動および製品の完全アンインストールを実行します。

param(
    [string]$InstallDir = ".\bin",
    [switch]$Uninstall,
    [switch]$Manage,
    [switch]$Force,
    [switch]$RemoveData,
    [switch]$RemoveLogs
)

if (($PSBoundParameters.ContainsKey('RemoveData') -or $PSBoundParameters.ContainsKey('RemoveLogs')) -and (-not $Uninstall -or $Manage)) {
    Write-Error '-RemoveData / -RemoveLogs require -Uninstall without -Manage.'
    exit 1
}

# スクリプトの格納先ディレクトリを取得
$ScriptDir = if ($PSScriptRoot) {
    $PSScriptRoot
} elseif ($MyInvocation.MyCommand.Path) {
    Split-Path -Parent $MyInvocation.MyCommand.Path
} else {
    # 代替処理: 現在の作業ディレクトリを使用
    Get-Location | Select-Object -ExpandProperty Path
}

# 内部モジュールのインポート
$devbinModulePath = "$ScriptDir\Devbin"
try {
    Import-Module $devbinModulePath -Force -ErrorAction Stop
} catch {
    Write-Host "Error importing Devbin: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# パッケージ定義の読み込み (完全アンインストール時は定義ファイルに依存しない)
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

# パラメーターが指定されていない場合は使用方法を表示
if (-not ($Uninstall -or $Manage)) {
    Write-Host "Development Tools Setup Script"
    Write-Host "================================"
    Write-Host ""
    Write-Host "Usage:"
    Write-Host "  .\Setup-Bin.ps1 -Manage [-InstallDir <path>]     # Interactive component manager"
    Write-Host "  .\Setup-Bin.ps1 -Uninstall [-InstallDir <path>] [-Force] [-RemoveData] [-RemoveLogs]"
    Write-Host "      # Remove bin, its references, and optionally data / previous logs"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -InstallDir <path>  Installation directory (default: .\bin)"
    Write-Host "  -Force              Skip the complete-uninstall confirmation prompt"
    Write-Host "  -RemoveData         Delete %ProgramData%\%USERNAME%\devbin-win\data and its environment references"
    Write-Host "  -RemoveLogs         Delete previous logs; keep the current transcript"
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

# 昇格した管理者権限での実行を検出 (本スクリプトは一般ユーザー権限での実行を前提とする)
$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
if ($currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Warning: This script is not intended to be run with elevated administrator privileges." -ForegroundColor Yellow
    Write-Host "Please run it from a non-elevated (standard user) shell." -ForegroundColor Yellow
    exit 1
}

# Manage モード: 対話型コンポーネント マネージャーの起動
if ($Manage) {
    # インストール先には実行コンテキストで解決された絶対パスを使用
    $absoluteInstallDir = $DevbinContext.InstallDir
    $operationExitCode = 0
    Start-DevbinOperationLog -InstallDir $absoluteInstallDir
    try {
        # ユーザー単位の data / log を用意し、HOME と XDG を設定 (個々のコンポーネントの保存先はこの配下に作成)
        try {
            Initialize-DevbinUserStorage | Out-Null

            $homePlan = Get-DevbinHomePlan
            if (-not $homePlan.IsEmpty) {
                Write-Host "ユーザー データの保存先を設定しています..."
                $homeResult = Invoke-DevbinHomePlan -Plan $homePlan
                foreach ($message in $homeResult.Messages) {
                    Write-Host "  $message"
                }
                if (-not $homeResult.Success) {
                    Write-Host "Warning: ユーザー データの保存先を設定できません" -ForegroundColor Yellow
                }
                Sync-EnvironmentVariables -VariableNames @($homePlan.EnvVars | ForEach-Object { $_.Name }) -Silent | Out-Null
                Write-Host ""
            }
        } catch {
            Write-Host "Warning: ユーザー データの保存先を用意できません: $($_.Exception.Message)" -ForegroundColor Yellow
        }

        # レジストリから環境変数を同期
        Sync-EnvironmentVariables -VariableNames @("PATH", "DOTNET_HOME", "DOTNET_CLI_TELEMETRY_OPTOUT", "PLANTUML_HOME", "BROWSER_PATH", "PUPPETEER_EXECUTABLE_PATH") -Silent | Out-Null

        Invoke-MenuLoop -Packages $Packages -InstallDir $absoluteInstallDir -ScriptDir $ScriptDir
    } finally {
        Stop-DevbinOperationLog
    }
    exit $operationExitCode
}

# アンインストール処理 (状態に依存しない機械的な完全削除)
if ($Uninstall) {
    $absoluteInstallDir = $DevbinContext.InstallDir
    $operationExitCode = 1
    Start-DevbinOperationLog -InstallDir $absoluteInstallDir
    try {
        $cleanupOptions = @{}
        foreach ($name in @('RemoveData', 'RemoveLogs')) {
            if ($PSBoundParameters.ContainsKey($name)) { $cleanupOptions[$name] = $PSBoundParameters[$name] }
        }
        $result = Invoke-ProductUninstall -InstallDir $absoluteInstallDir -Force:$Force @cleanupOptions
        switch ($result.Status) {
            "Success" {
                $operationExitCode = 0
            }
            "Cancelled" {
                # キャンセルは失敗と区別する (呼び出し元での完了メッセージ出力を抑止するため)
                $operationExitCode = 2
            }
            "Refused" {
                $operationExitCode = 1
            }
            default {
                Write-Host ""
                Write-Host "Error: Complete uninstallation failed." -ForegroundColor Red
                $operationExitCode = 1
            }
        }
    } finally {
        Stop-DevbinOperationLog
    }
    exit $operationExitCode
}
