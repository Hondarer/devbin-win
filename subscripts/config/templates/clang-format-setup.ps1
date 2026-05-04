param([string]$TargetPath)

$filePath = Join-Path $TargetPath "git-clang-format.cmd"
if (-not (Test-Path $filePath)) {
    Write-Host "Warning: git-clang-format.cmd not found at $filePath" -ForegroundColor Yellow
    return
}

$content = Get-Content -Path $filePath -Raw -Encoding Default
$patched = $content -replace '(?m)^(@?)py\b', '${1}python3'

if ($content -ne $patched) {
    [System.IO.File]::WriteAllText($filePath, $patched, [System.Text.Encoding]::ASCII)
    Write-Host "Patched git-clang-format.cmd: py -> python3"
} else {
    Write-Host "git-clang-format.cmd already patched or pattern not found."
}
