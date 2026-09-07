# LifecycleScript.ps1
# パッケージ定義の後処理スクリプトを実行する

function Invoke-PackageLifecycleScripts {
    param(
        [hashtable]$PackageConfig,
        [string]$Phase,
        [string]$InstallDir,
        [string]$ScriptDir
    )

    $scriptKey = switch ($Phase) {
        "Install" { "PostInstallScripts" }
        "Uninstall" { "PostUninstallScripts" }
        default { $null }
    }

    if (-not $scriptKey) {
        Write-Host "Warning: Unknown lifecycle phase '$Phase'" -ForegroundColor Yellow
        return
    }

    if (-not $PackageConfig.ContainsKey($scriptKey)) {
        return
    }

    $scripts = @($PackageConfig[$scriptKey]) | Where-Object { $_ }
    foreach ($scriptConfig in $scripts) {
        if (-not ($scriptConfig -is [hashtable]) -or -not $scriptConfig.Path) {
            Write-Host "Warning: Invalid $scriptKey entry for '$($PackageConfig.Name)'" -ForegroundColor Yellow
            continue
        }

        $scriptPath = Join-Path $ScriptDir $scriptConfig.Path
        if (-not (Test-Path $scriptPath)) {
            Write-Host "Warning: Lifecycle script not found: $scriptPath" -ForegroundColor Yellow
            continue
        }

        $rawArgs = if ($scriptConfig.ContainsKey("Arguments")) { @($scriptConfig.Arguments) } else { @() }
        $resolvedArgs = foreach ($arg in $rawArgs) {
            if ($null -eq $arg) {
                ""
            } else {
                "$arg".Replace("<InstallDir>", $InstallDir)
            }
        }

        Write-Host ""
        Write-Host "  後処理を実行中 ($Phase): $($scriptConfig.Path)"

        try {
            $extension = [System.IO.Path]::GetExtension($scriptPath)
            if ($extension -ieq ".ps1") {
                & powershell.exe -ExecutionPolicy Bypass -File $scriptPath @resolvedArgs
            } else {
                & $scriptPath @resolvedArgs
            }

            if ($LASTEXITCODE -ne 0) {
                Write-Host "Warning: Lifecycle script exited with code ${LASTEXITCODE}: $($scriptConfig.Path)" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "Warning: Lifecycle script failed: $($scriptConfig.Path)" -ForegroundColor Yellow
            Write-Host $_.Exception.Message -ForegroundColor Yellow
        }
    }
}
