# NpmOfflineInstall.ps1
# オフラインキャッシュからの npm パッケージインストールおよび shim スクリプト配置

function Get-NpmPackageNameFromLockPath {
    param([Parameter(Mandatory)][string]$Path)

    $normalizedPath = $Path -replace '\\', '/'
    $separator = $normalizedPath.LastIndexOf('node_modules/')
    if ($separator -lt 0) {
        return ""
    }

    $packagePath = $normalizedPath.Substring($separator + 'node_modules/'.Length)
    $parts = @($packagePath -split '/')
    if ($parts.Count -eq 0 -or [string]::IsNullOrWhiteSpace([string]$parts[0])) {
        return ""
    }
    if ([string]$parts[0] -like '@*') {
        if ($parts.Count -lt 2) {
            return ""
        }
        return "$($parts[0])/$($parts[1])"
    }

    return [string]$parts[0]
}

function Set-NpmJsonProperty {
    param(
        [Parameter(Mandatory)]
        [object]$Object,

        [Parameter(Mandatory)]
        [string]$Name,

        [AllowNull()]
        [object]$Value
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($null -ne $property) {
        $property.Value = $Value
    } else {
        Add-Member -InputObject $Object -MemberType NoteProperty -Name $Name -Value $Value
    }
}

function Test-NpmPlatformValuesMatchCurrent {
    param(
        [object]$Values,
        [Parameter(Mandatory)][string]$CurrentValue
    )

    $items = @($Values | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($items.Count -eq 0) {
        return $true
    }

    $allowedValues = @($items | Where-Object { -not $_.StartsWith('!') })
    foreach ($item in $items) {
        if ($item.StartsWith('!') -and $item.Substring(1) -ieq $CurrentValue) {
            return $false
        }
    }

    return ($allowedValues.Count -eq 0 -or @($allowedValues | Where-Object { $_ -ieq $CurrentValue }).Count -gt 0)
}

function Test-NpmOptionalLockEntryForCurrentPlatform {
    param([Parameter(Mandatory)][object]$Entry)

    $currentCpu = [string]$env:PROCESSOR_ARCHITECTURE
    if ([string]$env:PROCESSOR_ARCHITEW6432 -ieq 'AMD64') {
        $currentCpu = 'AMD64'
    }
    switch -Regex ($currentCpu.ToUpperInvariant()) {
        '^(AMD64|X64)$' { $currentCpu = 'x64'; break }
        '^(ARM64)$' { $currentCpu = 'arm64'; break }
        '^(X86|I86PC)$' { $currentCpu = 'x86'; break }
        default { $currentCpu = $currentCpu.ToLowerInvariant() }
    }

    $osMatches = $true
    $cpuMatches = $true
    $propertyNames = @($Entry.PSObject.Properties | ForEach-Object { $_.Name })
    if ($propertyNames -contains 'os') {
        $osMatches = Test-NpmPlatformValuesMatchCurrent -Values $Entry.os -CurrentValue 'win32'
    }
    if ($propertyNames -contains 'cpu') {
        $cpuMatches = Test-NpmPlatformValuesMatchCurrent -Values $Entry.cpu -CurrentValue $currentCpu
    }

    return ($osMatches -and $cpuMatches)
}

function Test-NpmLockEntryHasPlatformConstraint {
    param([Parameter(Mandatory)][object]$Entry)

    $propertyNames = @($Entry.PSObject.Properties | ForEach-Object { $_.Name })
    return ($propertyNames -contains 'os' -or $propertyNames -contains 'cpu')
}

function Test-NpmSpecIsDistTag {
    param([string]$Spec)

    if ([string]::IsNullOrWhiteSpace($Spec)) {
        return $false
    }

    # dist-tag (latest や next 等) を判定します (SemVer 範囲指定や file: / git: プロトコルは対象外)。
    return [bool]($Spec -match '^[A-Za-z][A-Za-z0-9._-]*$')
}

function Get-NpmLockedDependencyVersion {
    param(
        [Parameter(Mandatory)][object[]]$PackageProperties,
        [Parameter(Mandatory)][string]$ParentPath,
        [Parameter(Mandatory)][string]$DependencyName
    )

    $candidates = @(
        "$ParentPath/node_modules/$DependencyName"
        "node_modules/$DependencyName"
    )
    foreach ($candidate in $candidates) {
        $property = $PackageProperties | Where-Object { $_.Name -eq $candidate } | Select-Object -First 1
        if ($null -eq $property) {
            continue
        }
        $names = @($property.Value.PSObject.Properties | ForEach-Object { $_.Name })
        if ($names -contains 'version' -and -not [string]::IsNullOrWhiteSpace([string]$property.Value.version)) {
            return [string]$property.Value.version
        }
    }

    return $null
}

function Set-NpmDistTagSpecsToLockedVersions {
    param(
        [Parameter(Mandatory)][object]$Entry,
        [Parameter(Mandatory)][string]$ParentPath,
        [Parameter(Mandatory)][object[]]$PackageProperties
    )

    $entryPropertyNames = @($Entry.PSObject.Properties | ForEach-Object { $_.Name })
    foreach ($dependencyKind in @('dependencies', 'optionalDependencies')) {
        if ($entryPropertyNames -notcontains $dependencyKind) {
            continue
        }

        $dependencies = $Entry.$dependencyKind
        if ($null -eq $dependencies) {
            continue
        }

        foreach ($dependencyProperty in @($dependencies.PSObject.Properties)) {
            if (-not (Test-NpmSpecIsDistTag -Spec ([string]$dependencyProperty.Value))) {
                continue
            }

            $lockedVersion = Get-NpmLockedDependencyVersion `
                -PackageProperties $PackageProperties `
                -ParentPath $ParentPath `
                -DependencyName ([string]$dependencyProperty.Name)
            if ([string]::IsNullOrWhiteSpace($lockedVersion)) {
                continue
            }

            Set-NpmJsonProperty -Object $dependencies -Name ([string]$dependencyProperty.Name) -Value $lockedVersion
        }
    }
}

function Write-NpmNativeOutput {
    param([object[]]$Output)

    foreach ($item in @($Output)) {
        $text = [string]$item
        if ([string]::IsNullOrWhiteSpace($text)) {
            continue
        }

        # 標準エラー出力 (2>&1) の ErrorRecord によるコンソール赤字化を防ぎ、テキストのみを手順の詳細として字下げして出力します。
        Write-Host "    $text"
    }
}

function Get-NpmOfflineFileSpec {
    param([Parameter(Mandatory)][string]$Path)

    $absolutePath = (Get-Item -LiteralPath $Path -ErrorAction Stop).FullName -replace '\\', '/'
    return "file:$absolutePath"
}

function New-NpmOfflineInstallProject {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$CacheStatus,

        [Parameter(Mandatory)]
        [hashtable]$PackageConfig,

        [Parameter(Mandatory)]
        [string]$ProjectDirectory
    )

    $lockText = Get-Content $CacheStatus.LockPath -Raw -Encoding UTF8
    $normalizedLockText = $lockText -replace '("packages"\s*:\s*\{\s*)""(\s*:)', '$1"__devbin_npm_root__"$2'
    $lock = $normalizedLockText | ConvertFrom-Json
    $packageProperties = @($lock.packages.PSObject.Properties)
    $rootProperty = $packageProperties | Where-Object { $_.Name -eq '__devbin_npm_root__' } | Select-Object -First 1
    if ($null -eq $rootProperty) {
        throw 'package-lock.json root package is missing'
    }

    $manifestRecords = @{}
    foreach ($archive in @($CacheStatus.Manifest.archives)) {
        $manifestRecords[[string]$archive.identity] = $archive
    }

    $rootArchiveSpec = Get-NpmOfflineFileSpec -Path $CacheStatus.RootArchivePath
    $rootDependencies = $rootProperty.Value.dependencies
    if ($null -eq $rootDependencies) {
        $rootDependencies = [pscustomobject]@{}
        Set-NpmJsonProperty -Object $rootProperty.Value -Name 'dependencies' -Value $rootDependencies
    }

    $projectDependencies = [ordered]@{}
    $dependencyProperties = @($rootDependencies.PSObject.Properties)
    foreach ($dependencyProperty in $dependencyProperties) {
        $dependencyName = [string]$dependencyProperty.Name
        $dependencyPackagePath = "node_modules/$dependencyName"
        $dependencyPackageProperty = $packageProperties | Where-Object { $_.Name -eq $dependencyPackagePath } | Select-Object -First 1
        if ($null -eq $dependencyPackageProperty) {
            throw "package-lock.json direct dependency is missing: $dependencyName"
        }

        $dependencyVersion = [string]$dependencyPackageProperty.Value.version
        $dependencyIdentity = Get-NpmPackageIdentity -Name $dependencyName -Version $dependencyVersion
        if (-not $manifestRecords.ContainsKey($dependencyIdentity)) {
            throw "npm archive is missing for direct dependency: $dependencyIdentity"
        }

        $dependencySpec = Get-NpmOfflineFileSpec -Path (Join-Path $CacheStatus.CacheDirectory $manifestRecords[$dependencyIdentity].relativePath)
        Set-NpmJsonProperty -Object $rootDependencies -Name $dependencyName -Value $dependencySpec
        $projectDependencies[$dependencyName] = $dependencySpec
    }

    $optionalEntriesToRemove = @()
    foreach ($packageProperty in $packageProperties) {
        if ($packageProperty.Name -eq '__devbin_npm_root__') {
            continue
        }

        $entry = $packageProperty.Value
        $entryPropertyNames = @($entry.PSObject.Properties | ForEach-Object { $_.Name })
        if ($entryPropertyNames -notcontains 'version') {
            continue
        }

        $packageName = Get-NpmPackageNameFromLockPath -Path ([string]$packageProperty.Name)
        if ([string]::IsNullOrWhiteSpace($packageName)) {
            continue
        }
        $identity = Get-NpmPackageIdentity -Name $packageName -Version ([string]$entry.version)
        if (-not $manifestRecords.ContainsKey($identity)) {
            $isOptional = ($entryPropertyNames -contains 'optional' -and [bool]$entry.optional)
            if ($isOptional -and -not (Test-NpmOptionalLockEntryForCurrentPlatform -Entry $entry)) {
                # 他プラットフォーム向けのオプショナルネイティブパッケージは、
                # 当該環境でインストール・アーカイブされていない場合でも lockfile に記録されます。
                continue
            }
            if ($isOptional -and -not (Test-NpmLockEntryHasPlatformConstraint -Entry $entry)) {
                # スキップされたプラットフォーム固有パッケージの間接オプショナル依存関係 (wasm32 向け @emnapi/runtime 等)。
                # 当該環境でインストールされないためアーカイブも存在しません。
                $optionalEntriesToRemove += [string]$packageProperty.Name
                continue
            }
            throw "npm archive is missing for lockfile package: $identity"
        }

        $archivePath = Join-Path $CacheStatus.CacheDirectory $manifestRecords[$identity].relativePath
        Set-NpmJsonProperty -Object $entry -Name 'resolved' -Value (Get-NpmOfflineFileSpec -Path $archivePath)
        Set-NpmJsonProperty -Object $entry -Name 'integrity' -Value ([string]$manifestRecords[$identity].integrity)
        Set-NpmDistTagSpecsToLockedVersions `
            -Entry $entry `
            -ParentPath ([string]$packageProperty.Name) `
            -PackageProperties $packageProperties
    }

    foreach ($packagePath in $optionalEntriesToRemove) {
        $lock.packages.PSObject.Properties.Remove($packagePath)
    }

    $projectName = "devbin-offline-$([string]$PackageConfig.ShortName)"
    $packageJson = [ordered]@{
        name = $projectName
        version = '1.0.0'
        private = $true
        dependencies = $projectDependencies
    }
    Set-NpmJsonProperty -Object $lock -Name 'name' -Value $projectName
    Set-NpmJsonProperty -Object $lock -Name 'version' -Value '1.0.0'
    [IO.File]::WriteAllText((Join-Path $ProjectDirectory 'package.json'), ($packageJson | ConvertTo-Json -Depth 20))

    $localLockJson = $lock | ConvertTo-Json -Depth 100
    $localLockJson = $localLockJson -replace '"__devbin_npm_root__"\s*:', '"":'
    [IO.File]::WriteAllText((Join-Path $ProjectDirectory $script:NpmCacheLockName), $localLockJson)
}

function Copy-NpmOfflineInstallToPrefix {
    param(
        [Parameter(Mandatory)][string]$ProjectDirectory,
        [Parameter(Mandatory)][string]$BinDir
    )

    $sourceNodeModules = Join-Path $ProjectDirectory 'node_modules'
    $targetNodeModules = Join-Path $BinDir 'node_modules'
    New-Item -ItemType Directory -Path $targetNodeModules -Force | Out-Null

    $robocopy = Get-Command robocopy.exe -ErrorAction SilentlyContinue
    if (-not $robocopy) {
        throw 'robocopy.exe is required to copy the offline npm installation'
    }

    # グローバルな npm インベントリファイルを上書きすることなく、パッケージディレクトリをマージします。
    # robocopy の終了コード 0 から 7 は正常終了 (ファイルコピー成功を含む) を示します。
    & $robocopy.Source $sourceNodeModules $targetNodeModules '/E' '/XD' (Join-Path $sourceNodeModules '.bin') '/XF' '.package-lock.json' '/NFL' '/NDL' '/NJH' '/NJS' '/NP' | Out-Null
    if ($LASTEXITCODE -gt 7) {
        throw "robocopy failed for npm node_modules (exit code: $LASTEXITCODE)"
    }

    $sourceBinDirectory = Join-Path $sourceNodeModules '.bin'
    if (Test-Path $sourceBinDirectory -PathType Container) {
        New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
        & $robocopy.Source $sourceBinDirectory $BinDir '/E' '/NFL' '/NDL' '/NJH' '/NJS' '/NP' | Out-Null
        if ($LASTEXITCODE -gt 7) {
            throw "robocopy failed for npm command shims (exit code: $LASTEXITCODE)"
        }
    }
}

function Invoke-NpmInstallFromCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$NpmCommandPath,

        [Parameter(Mandatory)]
        [string]$BinDir,

        [Parameter(Mandatory)]
        [string]$PackagesDir,

        [Parameter(Mandatory)]
        [hashtable]$PackageConfig
    )

    $status = Get-NpmCacheStatus -PackageConfig $PackageConfig -PackagesDir $PackagesDir
    if (-not $status.IsValid) {
        Write-Host "    Error: npm cache is incomplete for '$($PackageConfig.ShortName)'" -ForegroundColor Red
        if ($status.Missing.Count -gt 0) {
            Write-Host "      Missing: $($status.Missing -join ', ')" -ForegroundColor Red
        }
        if ($status.Invalid.Count -gt 0) {
            Write-Host "      Invalid: $($status.Invalid -join ', ')" -ForegroundColor Red
        }
        return $false
    }

    $tempCacheDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("devbin-npm-cache-" + [guid]::NewGuid().ToString("N"))
    $tempProjectDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("devbin-npm-offline-install-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempCacheDirectory -Force | Out-Null
    New-Item -ItemType Directory -Path $tempProjectDirectory -Force | Out-Null
    $previousSkip = $env:PUPPETEER_SKIP_DOWNLOAD
    try {
        $env:PUPPETEER_SKIP_DOWNLOAD = "1"
        foreach ($archivePath in @($status.ArchivePaths)) {
            $cacheAddOutput = @(& $NpmCommandPath cache add $archivePath --cache $tempCacheDirectory --offline 2>&1)
            $cacheAddExitCode = $LASTEXITCODE
            Write-NpmNativeOutput -Output $cacheAddOutput
            if ($cacheAddExitCode -ne 0 -and $null -ne $cacheAddExitCode) {
                Write-Host "    Error: npm cache add failed for $archivePath" -ForegroundColor Red
                return $false
            }
        }

        $ignoreScripts = $true
        if ($PackageConfig.ContainsKey("NpmIgnoreScripts")) {
            $ignoreScripts = [bool]$PackageConfig.NpmIgnoreScripts
        }
        New-NpmOfflineInstallProject -CacheStatus $status -PackageConfig $PackageConfig -ProjectDirectory $tempProjectDirectory

        $args = @("install", "--prefix", $tempProjectDirectory, "--cache", $tempCacheDirectory, "--offline", "--no-audit", "--no-fund")
        if ($ignoreScripts) {
            $args += "--ignore-scripts"
        }

        Write-Host "    Installing $($PackageConfig.ShortName) from the offline npm cache..."
        $installOutput = @(& $NpmCommandPath @args 2>&1)
        $installExitCode = $LASTEXITCODE
        Write-NpmNativeOutput -Output $installOutput
        if ($installExitCode -ne 0 -and $null -ne $installExitCode) {
            Write-Host "    Error: npm install failed for '$($PackageConfig.ShortName)' (exit code: $installExitCode)" -ForegroundColor Red
            return $false
        }

        $expectedVersion = if ($PackageConfig.ContainsKey("Version")) { [string]$PackageConfig.Version } else { "" }
        $rootPackage = if ($PackageConfig.ContainsKey("NpmPackage")) { [string]$PackageConfig.NpmPackage } else { "" }
        $rootPackagePath = $rootPackage -replace '/', [System.IO.Path]::DirectorySeparatorChar
        $installedManifest = Join-Path (Join-Path $tempProjectDirectory "node_modules") (Join-Path $rootPackagePath "package.json")
        if (-not (Test-Path $installedManifest -PathType Leaf)) {
            Write-Host "    Error: installed npm package was not found: $installedManifest" -ForegroundColor Red
            return $false
        }
        if (-not [string]::IsNullOrWhiteSpace($expectedVersion)) {
            try {
                $installedJson = Get-Content $installedManifest -Raw -Encoding UTF8 | ConvertFrom-Json
                if ([string]$installedJson.version -ne $expectedVersion) {
                    Write-Host "    Error: installed npm version mismatch for '$rootPackage': expected $expectedVersion, got $($installedJson.version)" -ForegroundColor Red
                    return $false
                }
            } catch {
                Write-Host "    Error: failed to inspect installed npm package: $($_.Exception.Message)" -ForegroundColor Red
                return $false
            }
        }

        Copy-NpmOfflineInstallToPrefix -ProjectDirectory $tempProjectDirectory -BinDir $BinDir

        Write-Host "    $($PackageConfig.Name) installation completed."
        return $true
    } catch {
        Write-Host "    Error: Failed to install $($PackageConfig.Name): $($_.Exception.Message)" -ForegroundColor Red
        return $false
    } finally {
        if ($null -eq $previousSkip) {
            Remove-Item Env:\PUPPETEER_SKIP_DOWNLOAD -ErrorAction SilentlyContinue
        } else {
            $env:PUPPETEER_SKIP_DOWNLOAD = $previousSkip
        }
        Remove-Item -LiteralPath $tempCacheDirectory -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tempProjectDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}
