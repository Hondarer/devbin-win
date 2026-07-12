# PowerShell 7 Post-Setup Script
# pwsh.exe からアイコンを抽出し pwsh.ico を生成
# パラメータ: $TargetPath - PowerShell 7 がインストールされたディレクトリ

param(
    [Parameter(Mandatory=$true)]
    [string]$TargetPath
)

Write-Host "Running PowerShell 7 post-setup..."

$exePath = Join-Path $TargetPath "pwsh.exe"
$icoPath = Join-Path $TargetPath "pwsh.ico"

if (-not (Test-Path $exePath)) {
    Write-Host "Warning: pwsh.exe not found: $exePath" -ForegroundColor Yellow
    exit 0
}

Add-Type -AssemblyName System.Drawing

$icon = $null
$stream = $null
try {
    $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($exePath)
    $stream = [System.IO.File]::Create($icoPath)
    $icon.Save($stream)
    Write-Host "Icon extracted: $icoPath"
} catch {
    Write-Host "Warning: Failed to extract icon: $($_.Exception.Message)" -ForegroundColor Yellow
} finally {
    if ($stream) { $stream.Dispose() }
    if ($icon) { $icon.Dispose() }
}
