param([string]$TargetPath)

$filePath = Join-Path $TargetPath "git-clang-format.bat"
if (-not (Test-Path $filePath)) {
    Write-Host "Warning: git-clang-format.bat not found at $filePath" -ForegroundColor Yellow
    return
}

$content = Get-Content -Path $filePath -Raw -Encoding Default
$patched = $content -replace '(?m)^(@?)py\b(\s+-3)?', '${1}python3'

if ($content -ne $patched) {
    [System.IO.File]::WriteAllText($filePath, $patched, [System.Text.Encoding]::ASCII)
    Write-Host "Patched git-clang-format.bat: py -> python3"
} else {
    Write-Host "git-clang-format.bat already patched or pattern not found."
}
