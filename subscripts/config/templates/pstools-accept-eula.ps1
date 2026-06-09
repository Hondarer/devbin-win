param(
    [Parameter(Mandatory = $true)]
    [string]$InstallDir
)

$psToolsDir = Join-Path $InstallDir "pstools"
if (-not (Test-Path $psToolsDir)) {
    Write-Host "Warning: PsTools directory not found: $psToolsDir" -ForegroundColor Yellow
    exit 0
}

$tools = Get-ChildItem -Path $psToolsDir -Filter "Ps*.exe" -File -ErrorAction SilentlyContinue |
    Sort-Object Name

if (-not $tools -or $tools.Count -eq 0) {
    Write-Host "Warning: PsTools executables not found: $psToolsDir" -ForegroundColor Yellow
    exit 0
}

Write-Host "Accepting Sysinternals EULA for PsTools..."

foreach ($tool in $tools) {
    $stdout = Join-Path $env:TEMP ("devbin-pstools-{0}.out" -f ([guid]::NewGuid().ToString("N")))
    $stderr = Join-Path $env:TEMP ("devbin-pstools-{0}.err" -f ([guid]::NewGuid().ToString("N")))

    try {
        $process = Start-Process `
            -FilePath $tool.FullName `
            -ArgumentList @("-accepteula", "-nobanner") `
            -WindowStyle Hidden `
            -RedirectStandardOutput $stdout `
            -RedirectStandardError $stderr `
            -PassThru `
            -ErrorAction Stop

        if (-not $process.WaitForExit(5000)) {
            try {
                $process.Kill()
            } catch {
                # Best effort only.
            }
            Write-Host "  Warning: Timed out while accepting EULA: $($tool.Name)" -ForegroundColor Yellow
        } else {
            Write-Host "  Accepted: $($tool.Name)"
        }
    } catch {
        Write-Host "  Warning: Failed to run $($tool.Name): $($_.Exception.Message)" -ForegroundColor Yellow
    } finally {
        Remove-Item -LiteralPath $stdout -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $stderr -Force -ErrorAction SilentlyContinue
    }
}

