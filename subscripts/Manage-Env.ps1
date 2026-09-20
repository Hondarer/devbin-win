#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\Devbin\Menu\ConsoleInput.ps1"
. "$PSScriptRoot\Devbin\Environment\EnvironmentManager.ps1"
try {
    Start-EnvironmentManager
} catch {
    Write-Host "環境変数マネージャー: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
