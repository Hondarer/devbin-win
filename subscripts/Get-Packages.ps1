# Get-Packages.ps1
# packages ディレクトリにパッケージを取得するスクリプト
#
# 引数処理とモジュール呼び出し、終了コードへの変換だけを行う。
# 取得・検証・旧ファイル整理の実装は Devbin/Packages にある。

param(
    [switch]$Force = $false,
    [string[]]$PackageShortNames = @()
)

# スクリプトのディレクトリを取得
$ScriptDir = if ($PSScriptRoot) {
    $PSScriptRoot
} elseif ($MyInvocation.MyCommand.Path) {
    Split-Path -Parent $MyInvocation.MyCommand.Path
} else {
    Get-Location | Select-Object -ExpandProperty Path
}

# Devbin モジュールを読み込む
try {
    Import-Module (Join-Path $ScriptDir "Devbin") -Force -ErrorAction Stop
} catch {
    Write-Host "Error importing Devbin: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$DevbinContext = New-DevbinContext -SubscriptsDir $ScriptDir

# パッケージ設定を読み込む
$catalog = Import-PackageCatalog -Path $DevbinContext.ConfigPath
if (-not $catalog.Success) {
    Write-Host "Error: パッケージ定義に問題があります" -ForegroundColor Red
    foreach ($message in $catalog.Errors) {
        Write-Host "  $message" -ForegroundColor Red
    }
    exit 1
}

$result = Invoke-PackageAcquisition `
    -Packages $catalog.Packages `
    -Context $DevbinContext `
    -ShortNames $PackageShortNames `
    -Force:$Force

Write-Host ""
Write-Host "=== 取得結果 ==="
foreach ($message in $result.Messages) {
    Write-Host "  $message"
}

if ($result.Success) {
    exit 0
}

Write-Host ""
Write-Host "取得できなかったものがあります。" -ForegroundColor Yellow
if ($result.FailedShortNames.Count -gt 0) {
    Write-Host "  対象: $($result.FailedShortNames -join ', ')" -ForegroundColor Yellow
}
exit 1
