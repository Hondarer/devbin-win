# VSCodeData.ps1
# VS Code のポータブルデータ保存先を構成します。
function Initialize-DevbinVSCodeData {
    $destination = Join-Path (Get-DevbinDataDirectory) 'vscode'
    New-Item -ItemType Directory -Path $destination -Force -ErrorAction Stop | Out-Null
    Set-DevbinUserEnvironmentValue -Name 'VSCODE_PORTABLE' -Value $destination
    Write-Host "VS Code portable data: $destination (restart your terminal to apply)"
}

# VS Code のアンインストール時に VSCODE_PORTABLE を解除します。
# 利用者が別の保存先へ変更している場合は、その値を残します。
function Remove-DevbinVSCodeData {
    $destination = Join-Path (Get-DevbinDataDirectory) 'vscode'
    $current = Get-DevbinUserEnvironmentValue -Name 'VSCODE_PORTABLE'
    if ([string]::IsNullOrWhiteSpace($current)) {
        return $false
    }
    if (-not [string]::Equals($current.TrimEnd('\'), $destination.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }

    Set-DevbinUserEnvironmentValue -Name 'VSCODE_PORTABLE' -Value $null
    return $true
}
