# NpmCacheBuild.ps1
# npm パッケージのオフライン キャッシュ生成 (npm install -g による取得と、オフラインでの再現確認)

# 一時 prefix へ npm install -g を実行し、npm 自身のキャッシュをそのまま保存します。
# 保存したキャッシュだけで npm install -g --offline が完了することを確認してから、既存のキャッシュと置き換えます。
function Save-NpmPackageCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$NpmCommandPath,

        [Parameter(Mandatory)]
        [string]$PackagesDir,

        [Parameter(Mandatory)]
        [hashtable]$PackageConfig,

        [switch]$Force
    )

    $npmPackage = if ($PackageConfig.ContainsKey("NpmPackage")) { [string]$PackageConfig.NpmPackage } else { "" }
    if ([string]::IsNullOrWhiteSpace($npmPackage)) {
        Write-Host "  NpmPackage is missing for $($PackageConfig.ShortName)" -ForegroundColor Red
        return 1
    }

    $existingStatus = Get-NpmCacheStatus -PackageConfig $PackageConfig -PackagesDir $PackagesDir
    if ($existingStatus.IsValid -and -not $Force) {
        Write-Host "  npm cache for $($PackageConfig.ShortName) is already valid. Skipping."
        return 0
    }

    $npmRoot = Join-Path $PackagesDir "npm-packages"
    $cacheDirectory = Get-NpmPackageCacheDirectory -PackagesDir $PackagesDir -PackageConfig $PackageConfig
    $stagingRoot = Join-Path $npmRoot ".staging"
    $stagingDirectory = Join-Path $stagingRoot ("{0}-{1}" -f $PackageConfig.ShortName, [guid]::NewGuid().ToString("N"))
    $stagingContent = Get-NpmCacheContentDirectory -CacheDirectory $stagingDirectory
    $workDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("devbin-npm-cache-" + [guid]::NewGuid().ToString("N"))
    $downloadPrefix = Join-Path $workDirectory "download"
    $verifyPrefix = Join-Path $workDirectory "verify"
    $logsDirectory = Join-Path $workDirectory "logs"
    $oldDirectory = $null

    foreach ($directory in @($stagingContent, $downloadPrefix, $verifyPrefix, $logsDirectory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $packageSpecs = @(Get-NpmPackageSpecs -PackageConfig $PackageConfig)
    $previousSkip = $env:PUPPETEER_SKIP_DOWNLOAD
    try {
        # キャッシュ作成時のブラウザー バイナリ自動ダウンロードを抑止 (完全オフライン化)
        $env:PUPPETEER_SKIP_DOWNLOAD = "1"

        $commonArguments = @("--cache", $stagingContent, "--logs-dir", $logsDirectory) + @(Get-NpmScriptArguments -PackageConfig $PackageConfig)

        Write-Host "  Downloading $($packageSpecs -join ', ') with npm install -g..."
        $downloadArguments = @(Get-NpmGlobalArguments -Command "install" -Prefix $downloadPrefix) + $commonArguments + $packageSpecs
        $exitCode = Invoke-NpmCli -NpmCommandPath $NpmCommandPath -Arguments $downloadArguments
        if ($exitCode -ne 0) {
            return $exitCode
        }

        # 保存したキャッシュだけで導入を再現できることを、別の prefix へのオフライン導入で確認します。
        Write-Host "  Verifying that the npm cache installs $($PackageConfig.ShortName) offline..."
        $verifyArguments = @(Get-NpmGlobalArguments -Command "install" -Prefix $verifyPrefix) + @("--offline") + $commonArguments + $packageSpecs
        $exitCode = Invoke-NpmCli -NpmCommandPath $NpmCommandPath -Arguments $verifyArguments
        if ($exitCode -ne 0) {
            Write-Host "  The npm cache for $($PackageConfig.ShortName) cannot install offline" -ForegroundColor Red
            return 1
        }

        $rootVersion = Get-NpmGlobalPackageVersion -BinDir $verifyPrefix -PackageName $npmPackage
        $expectedVersion = if ($PackageConfig.ContainsKey("Version")) { [string]$PackageConfig.Version } else { "" }
        if ([string]::IsNullOrWhiteSpace($rootVersion)) {
            Write-Host "  Root npm package was not found after install: $npmPackage" -ForegroundColor Red
            return 1
        }
        if (-not [string]::IsNullOrWhiteSpace($expectedVersion) -and $rootVersion -ne $expectedVersion) {
            Write-Host "  Root npm version mismatch: expected $expectedVersion, got $rootVersion" -ForegroundColor Red
            return 1
        }

        $installedPackages = [ordered]@{}
        foreach ($name in @(Get-NpmRequestedPackageNames -PackageConfig $PackageConfig)) {
            $installedPackages[$name] = Get-NpmGlobalPackageVersion -BinDir $verifyPrefix -PackageName $name
        }

        # 作業用の一時ファイルはキャッシュの内容ではないため保存しません。
        Remove-Item -LiteralPath (Join-Path $stagingContent "_cacache\tmp") -Recurse -Force -ErrorAction SilentlyContinue

        $manifest = [ordered]@{
            schemaVersion     = $script:NpmCacheSchemaVersion
            shortName         = [string]$PackageConfig.ShortName
            rootPackage       = $npmPackage
            rootVersion       = $rootVersion
            requestedPackages = @($packageSpecs)
            installedPackages = $installedPackages
            platform          = [string]$env:PROCESSOR_ARCHITECTURE
            os                = [string]$env:OS
            nodeVersion       = ""
            npmVersion        = ""
            generatedAt       = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        }
        $nodeCommand = Get-Command node.exe -ErrorAction SilentlyContinue
        if ($nodeCommand) {
            $manifest.nodeVersion = [string](& $nodeCommand.Source --version 2>$null | Select-Object -First 1)
        }
        $npmVersionOutput = & $NpmCommandPath --version 2>$null
        if ($npmVersionOutput) {
            $manifest.npmVersion = [string]($npmVersionOutput | Select-Object -First 1)
        }
        $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Get-NpmCacheManifestPath -CacheDirectory $stagingDirectory) -Encoding UTF8

        $validationStatus = Get-NpmCacheStatus -PackageConfig $PackageConfig -PackagesDir $PackagesDir -CacheDirectory $stagingDirectory
        if (-not $validationStatus.IsValid) {
            Write-Host "  Generated npm cache failed validation: $($validationStatus.Invalid -join '; ') $($validationStatus.Missing -join '; ')" -ForegroundColor Red
            return 1
        }

        if (Test-Path $cacheDirectory) {
            $oldDirectory = "$cacheDirectory.old-$([guid]::NewGuid().ToString('N'))"
            Move-Item -LiteralPath $cacheDirectory -Destination $oldDirectory -Force
        }
        Move-Item -LiteralPath $stagingDirectory -Destination $cacheDirectory -Force
        if ($oldDirectory -and (Test-Path $oldDirectory)) {
            Remove-Item -LiteralPath $oldDirectory -Recurse -Force -ErrorAction SilentlyContinue
        }

        Write-Host "  npm cache prepared: $cacheDirectory"
        return 0
    } catch {
        if ($oldDirectory -and (Test-Path $oldDirectory) -and -not (Test-Path $cacheDirectory)) {
            Move-Item -LiteralPath $oldDirectory -Destination $cacheDirectory -Force -ErrorAction SilentlyContinue
        }
        Write-Host "  Failed to prepare npm cache for $($PackageConfig.ShortName): $($_.Exception.Message)" -ForegroundColor Red
        return 1
    } finally {
        if ($null -eq $previousSkip) {
            Remove-Item Env:\PUPPETEER_SKIP_DOWNLOAD -ErrorAction SilentlyContinue
        } else {
            $env:PUPPETEER_SKIP_DOWNLOAD = $previousSkip
        }
        Remove-Item -LiteralPath $workDirectory -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path $stagingDirectory) {
            Remove-Item -LiteralPath $stagingDirectory -Recurse -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path $stagingRoot -PathType Container) {
            $stagingEntries = @(Get-ChildItem -LiteralPath $stagingRoot -Force -ErrorAction SilentlyContinue)
            if ($stagingEntries.Count -eq 0) {
                Remove-Item -LiteralPath $stagingRoot -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
