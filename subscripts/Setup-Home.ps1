# Setup-Home.ps1
# HOME 環境変数およびホームディレクトリのセットアップ スクリプト
#
# 変更計画の生成と適用は Devbin/Platform モジュールが担当します。
# 本スクリプトでは計画内容の表示とユーザー確認のみを実行します。

param(
    [switch]$Force
)

$ScriptDir = if ($PSScriptRoot) {
    $PSScriptRoot
} else {
    Split-Path -Parent $MyInvocation.MyCommand.Path
}

try {
    Import-Module (Join-Path $ScriptDir "Devbin") -Force -ErrorAction Stop
} catch {
    Write-Host "Error importing Devbin: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$plan = Get-DevbinHomePlan

Write-Host "HOME Environment Setup"
Write-Host "======================"
Write-Host ""
Write-Host "Current Status:"
Write-Host "  Username: $([Environment]::UserName)"
Write-Host "  Home: $($plan.HomePath)"
Write-Host ""

if ($plan.IsEmpty) {
    Write-Host "All directories and environment variables already exist."
    exit 0
}

Write-Host "Planned Actions:"
foreach ($action in $plan.Actions) {
    Write-Host $action
}
Write-Host ""

if (-not $Force) {
    if (-not (Read-ConfirmationKey -Prompt "Do you want to proceed? [Y/n/Esc] " -DefaultYes)) {
        Write-Host "Setup cancelled by user."
        exit 0
    }
}

Write-Host ""
Write-Host "Starting setup..."

$result = Invoke-DevbinHomePlan -Plan $plan
foreach ($message in $result.Messages) {
    Write-Host "  $message"
}

if (-not $result.Success) {
    Write-Host ""
    Write-Host "Setup failed." -ForegroundColor Red
    Write-Host "Please ensure the target directory is writable."
    exit 1
}

Write-Host ""
Write-Host "Setup complete!"
Write-Host "Start a new terminal session for environment variables to take effect."
exit 0
