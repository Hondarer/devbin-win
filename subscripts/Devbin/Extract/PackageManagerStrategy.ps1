# PackageManagerStrategy.ps1
# pip および npm のローカルキャッシュを用いたオフライン導入戦略

function Invoke-PipInstallStrategy {
    param(
        [string]$BinDir,
        [hashtable]$Config,
        [string]$PackagesDir = "",
        [array]$Packages = @()
    )

    if ([string]::IsNullOrWhiteSpace($PackagesDir)) {
        $PackagesDir = Get-DevbinDefaultPackagesDir
    }

    $pipPackage = $Config.PipPackage
    if ([string]::IsNullOrWhiteSpace($pipPackage)) {
        Write-Host "    Error: PipPackage not specified in config" -ForegroundColor Red
        return $false
    }

    $version = if ($Config.ContainsKey("Version")) { $Config.Version } else { "" }
    $packageSpec = if (-not [string]::IsNullOrWhiteSpace($version)) { "$pipPackage==$version" } else { $pipPackage }

    Write-Host "    Installing $($Config.Name) via pip ($packageSpec)..."

    # Python の配置先パスをパッケージ定義の TargetDirectory から解決
    $pythonDir = Get-PythonDirectory -Packages $Packages -InstallDir $BinDir
    if ([string]::IsNullOrWhiteSpace($pythonDir)) {
        $pythonDir = Join-Path $BinDir "python"
    }
    $pythonExe = Join-Path $pythonDir "python.exe"
    if (-not (Test-Path $pythonExe)) {
        Write-Host "    Error: Python not found at: $pythonExe" -ForegroundColor Red
        return $false
    }

    try {
        $pipPackagesDir = Join-Path $PackagesDir "pip-packages"
        $requiredPipWheels = Get-PipWheelPackageNames -PackageConfigs @($Config)
        $missingWheels = Test-PipWheelPackages -DirectoryPath $pipPackagesDir -PackageNames $requiredPipWheels

        if ($missingWheels.Count -gt 0) {
            Write-Host "    Error: pip wheel cache is incomplete: $($missingWheels -join ', ')" -ForegroundColor Red
            Write-Host "    Please run Get-Packages.ps1 to prepare packages\pip-packages." -ForegroundColor Yellow
            return $false
        }

        Write-Host "    Using offline installation with local wheel files..."
        $pipPackagesAbsPath = $pipPackagesDir
        & $pythonExe -m pip install --no-warn-script-location `
            --no-index --find-links=$pipPackagesAbsPath $packageSpec

        if ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE) {
            Write-Host "    $($Config.Name) installation completed."
            return $true
        } else {
            Write-Host "    Warning: pip install may have issues (exit code: $LASTEXITCODE)" -ForegroundColor Yellow
            return $false
        }
    } catch {
        Write-Host "    Error: Failed to install $($Config.Name): $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "    $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# NpmInstall 戦略: オフライン一時 prefix から node_modules および shim スクリプトを bin 配下に配置
function Invoke-NpmInstallStrategy {
    param(
        [string]$BinDir,
        [hashtable]$Config,
        [string]$PackagesDir = ""
    )

    $npmCmd = Join-Path $BinDir "npm.cmd"
    if (-not (Test-Path $npmCmd)) {
        Write-Host "    Error: npm not found at: $npmCmd" -ForegroundColor Red
        return $false
    }

    if ([string]::IsNullOrWhiteSpace($PackagesDir)) {
        $PackagesDir = Get-DevbinDefaultPackagesDir
    }

    return Invoke-NpmInstallFromCache `
        -NpmCommandPath $npmCmd `
        -BinDir $BinDir `
        -PackagesDir $PackagesDir `
        -PackageConfig $Config
}
