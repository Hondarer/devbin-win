param([string]$TargetPath)

$aliases = @{
    "win_flex.exe" = "flex.exe"
    "win_bison.exe" = "bison.exe"
}

foreach ($sourceName in $aliases.Keys) {
    $sourcePath = Join-Path $TargetPath $sourceName
    $destPath = Join-Path $TargetPath $aliases[$sourceName]

    if (-not (Test-Path $sourcePath)) {
        Write-Host "Warning: $sourceName not found at $sourcePath" -ForegroundColor Yellow
        continue
    }

    Copy-Item -Path $sourcePath -Destination $destPath -Force
    Write-Host "Created alias: $($aliases[$sourceName])"
}
