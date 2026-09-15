# Get-Packages.ps1
# packages ディレクトリへ各種パッケージアーカイブをダウンロード・配置するスクリプト
#
# パラメーターの解析、内部モジュールの呼び出し、および終了コードの返却を行います。
# パッケージの取得・検証・旧バージョン整理の実処理は Devbin/Packages モジュールが担当します。

param(
    [switch]$Force = $false,
    [string[]]$PackageShortNames = @()
)

# スクリプトの格納先ディレクトリを取得
$ScriptDir = if ($PSScriptRoot) {
    $PSScriptRoot
} elseif ($MyInvocation.MyCommand.Path) {
    Split-Path -Parent $MyInvocation.MyCommand.Path
} else {
    Get-Location | Select-Object -ExpandProperty Path
}

# Devbin モジュールをインポート
try {
    Import-Module (Join-Path $ScriptDir "Devbin") -Force -ErrorAction Stop
} catch {
    Write-Host "Error importing Devbin: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$DevbinContext = New-DevbinContext -SubscriptsDir $ScriptDir

# パッケージ定義の読み込み
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
