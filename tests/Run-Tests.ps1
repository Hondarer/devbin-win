# Run-Tests.ps1
# Windows PowerShell 5.1 同梱の Pester 3.4 でテストを実行する
param(
    [string[]]$TestName = @()
)

$ErrorActionPreference = "Stop"

Import-Module Pester -ErrorAction Stop
$pester = Get-Module Pester
Write-Host "Pester $($pester.Version)"

$arguments = @{
    Path = $PSScriptRoot
    EnableExit = $true
}
if ($TestName -and $TestName.Count -gt 0) {
    $arguments.TestName = $TestName
}

Invoke-Pester @arguments
