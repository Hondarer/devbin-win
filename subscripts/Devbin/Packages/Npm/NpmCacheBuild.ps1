# NpmCacheBuild.ps1
# npm オフラインキャッシュの作成

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
    $archiveDirectory = Join-Path $stagingDirectory $script:NpmCacheArchiveDirectoryName
    $tempProject = Join-Path ([System.IO.Path]::GetTempPath()) ("devbin-npm-project-" + [guid]::NewGuid().ToString("N"))
    $oldDirectory = $null

    New-Item -ItemType Directory -Path $archiveDirectory -Force | Out-Null
    New-Item -ItemType Directory -Path $tempProject -Force | Out-Null

    $ignoreScripts = $true
    if ($PackageConfig.ContainsKey("NpmIgnoreScripts")) {
        $ignoreScripts = [bool]$PackageConfig.NpmIgnoreScripts
    }
    $previousSkip = $env:PUPPETEER_SKIP_DOWNLOAD
    try {
        # Preparation must never fetch Puppeteer's browser payload.
        $env:PUPPETEER_SKIP_DOWNLOAD = "1"
        $packageSpecs = @(Get-NpmPackageSpecs -PackageConfig $PackageConfig)
        Write-Host "  Installing $($packageSpecs -join ', ') into a temporary project for packing..."
        $installArgs = @("install", "--no-audit", "--no-fund", "--package-lock=true", "--prefix", $tempProject)
        if ($ignoreScripts) {
            $installArgs += "--ignore-scripts"
        }
        $installArgs += @($packageSpecs)
        & $NpmCommandPath @installArgs | Out-Host
        if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) {
            return $LASTEXITCODE
        }

        $lockSource = Join-Path $tempProject "package-lock.json"
        if (-not (Test-Path $lockSource -PathType Leaf)) {
            Write-Host "  package-lock.json was not generated for $($PackageConfig.ShortName)" -ForegroundColor Red
            return 1
        }
        Copy-Item -LiteralPath $lockSource -Destination (Join-Path $stagingDirectory $script:NpmCacheLockName) -Force

        $nodeModulesDirectory = Join-Path $tempProject "node_modules"
        $packageJsonFiles = @(Get-NpmPackageManifestFiles -NodeModulesDirectory $nodeModulesDirectory)
        if ($packageJsonFiles.Count -eq 0) {
            Write-Host "  No npm packages were installed for $($PackageConfig.ShortName)" -ForegroundColor Red
            return 1
        }

        $archiveRecords = @()
        $archiveByIdentity = @{}
        $archiveNameByIdentity = @{}
        $script:NpmCurrentArchiveDirectory = $archiveDirectory

        foreach ($manifestFile in $packageJsonFiles) {
            try {
                $packageJson = Get-Content $manifestFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            } catch {
                Write-Host "  Invalid package.json: $($manifestFile.FullName)" -ForegroundColor Red
                return 1
            }

            $packageName = [string]$packageJson.name
            $packageVersion = [string]$packageJson.version
            if ([string]::IsNullOrWhiteSpace($packageName) -or [string]::IsNullOrWhiteSpace($packageVersion)) {
                continue
            }

            $identity = Get-NpmPackageIdentity -Name $packageName -Version $packageVersion
            if ($archiveByIdentity.ContainsKey($identity)) {
                continue
            }

            $packageStageDirectory = Join-Path $stagingDirectory ("pack-" + [guid]::NewGuid().ToString("N"))
            New-Item -ItemType Directory -Path $packageStageDirectory -Force | Out-Null
            try {
                Write-Host "  Packing $identity"
                $packArgs = @("pack", $manifestFile.DirectoryName, "--pack-destination", $packageStageDirectory)
                if ($ignoreScripts) {
                    $packArgs += "--ignore-scripts"
                }
                $packOutput = @(& $NpmCommandPath @packArgs 2>&1)
                $packOutput | ForEach-Object { Write-Host "    $_" }
                if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) {
                    return $LASTEXITCODE
                }

                $packedFile = Get-ChildItem -Path $packageStageDirectory -Filter "*.tgz" -File -ErrorAction SilentlyContinue | Select-Object -First 1
                if (-not $packedFile) {
                    Write-Host "  npm pack produced no archive for $identity" -ForegroundColor Red
                    return 1
                }

                $baseName = Get-NpmPackageArchiveFileName -PackageName $packageName -Version $packageVersion
                $targetName = $baseName
                if ($archiveNameByIdentity.Values -contains $targetName) {
                    $targetName = Get-NpmUniqueArchiveFileName -BaseName $baseName -PackageName $packageName
                }
                $targetPath = Join-Path $archiveDirectory $targetName
                Move-Item -LiteralPath $packedFile.FullName -Destination $targetPath -Force

                $archiveNameByIdentity[$identity] = $targetName
                $archiveByIdentity[$identity] = $targetPath
                $archiveRecords += [ordered]@{
                    name = $packageName
                    version = $packageVersion
                    identity = $identity
                    relativePath = Join-Path $script:NpmCacheArchiveDirectoryName $targetName
                    size = [int64](Get-Item $targetPath).Length
                    integrity = Get-NpmArchiveIntegrity -Path $targetPath
                }
            } finally {
                Remove-Item -LiteralPath $packageStageDirectory -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        $rootVersion = if ($PackageConfig.ContainsKey("Version")) { [string]$PackageConfig.Version } else { "" }
        $rootManifestFile = Find-NpmPackageManifest -NodeModulesDirectory $nodeModulesDirectory -PackageName $npmPackage
        if (-not $rootManifestFile) {
            Write-Host "  Root npm package was not found after install: $npmPackage" -ForegroundColor Red
            return 1
        }
        $rootJson = Get-Content $rootManifestFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not [string]::IsNullOrWhiteSpace($rootVersion) -and [string]$rootJson.version -ne $rootVersion) {
            Write-Host "  Root npm version mismatch: expected $rootVersion, got $($rootJson.version)" -ForegroundColor Red
            return 1
        }

        $rootIdentity = Get-NpmPackageIdentity -Name ([string]$rootJson.name) -Version ([string]$rootJson.version)
        if (-not $archiveByIdentity.ContainsKey($rootIdentity)) {
            Write-Host "  Root npm archive was not packed: $rootIdentity" -ForegroundColor Red
            return 1
        }

        $installArchives = @($archiveRecords | Where-Object { $_.identity -eq $rootIdentity })
        $explicitDependencies = if ($PackageConfig.ContainsKey("NpmDependencies")) { @($PackageConfig.NpmDependencies) } else { @() }
        foreach ($dependencySpec in $explicitDependencies) {
            $dependencyName = Get-NpmPackageNameFromSpec -PackageSpec ([string]$dependencySpec)
            if ([string]::IsNullOrWhiteSpace($dependencyName)) {
                continue
            }
            $dependencyManifest = Find-NpmPackageManifest -NodeModulesDirectory $nodeModulesDirectory -PackageName $dependencyName
            if (-not $dependencyManifest) {
                Write-Host "  Explicit npm dependency was not installed: $dependencySpec" -ForegroundColor Red
                return 1
            }
            $dependencyJson = Get-Content $dependencyManifest.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            $dependencyIdentity = Get-NpmPackageIdentity -Name ([string]$dependencyJson.name) -Version ([string]$dependencyJson.version)
            $dependencyRecord = $archiveRecords | Where-Object { $_.identity -eq $dependencyIdentity } | Select-Object -First 1
            if (-not $dependencyRecord) {
                Write-Host "  Explicit npm dependency archive was not packed: $dependencyIdentity" -ForegroundColor Red
                return 1
            }
            $installArchives += $dependencyRecord
        }

        $manifest = [ordered]@{
            schemaVersion = $script:NpmCacheSchemaVersion
            shortName = [string]$PackageConfig.ShortName
            rootPackage = [string]$rootJson.name
            rootVersion = [string]$rootJson.version
            requestedPackages = @($packageSpecs)
            rootArchive = [string]$installArchives[0].relativePath
            installArchives = @($installArchives | ForEach-Object { [string]$_.relativePath } | Select-Object -Unique)
            archives = @($archiveRecords)
            platform = [string]$env:PROCESSOR_ARCHITECTURE
            os = [string]$env:OS
            nodeVersion = ""
            npmVersion = ""
            generatedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        }

        $nodeCommand = Get-Command node.exe -ErrorAction SilentlyContinue
        if ($nodeCommand) {
            $manifest.nodeVersion = (& $nodeCommand.Source --version 2>$null | Select-Object -First 1)
        }
        $npmVersionOutput = & $NpmCommandPath --version 2>$null
        if ($npmVersionOutput) {
            $manifest.npmVersion = [string]($npmVersionOutput | Select-Object -First 1)
        }

        $manifestPath = Get-NpmCacheManifestPath -CacheDirectory $stagingDirectory
        $manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

        $validationConfig = @{}
        foreach ($key in $PackageConfig.Keys) {
            $validationConfig[$key] = $PackageConfig[$key]
        }
        $validationStatus = Get-NpmCacheStatus -PackageConfig $validationConfig -PackagesDir $PackagesDir -CacheDirectory $stagingDirectory
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
        Remove-Item -LiteralPath $tempProject -Recurse -Force -ErrorAction SilentlyContinue
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
