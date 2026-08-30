# Setup-NpmCache.psm1
# npm パッケージの依存木キャッシュ作成・検証・オフライン導入を共通化する

Set-StrictMode -Version Latest

$script:NpmCacheSchemaVersion = 1
$script:NpmCacheManifestName = "npm-cache-manifest.json"
$script:NpmCacheLockName = "package-lock.json"
$script:NpmCacheArchiveDirectoryName = "archives"

function Get-NpmPackageSpecs {
    param(
        [Parameter(Mandatory)]
        [hashtable]$PackageConfig
    )

    $specs = @()
    $npmPackage = if ($PackageConfig.ContainsKey("NpmPackage")) { [string]$PackageConfig.NpmPackage } else { "" }
    $version = if ($PackageConfig.ContainsKey("Version")) { [string]$PackageConfig.Version } else { "" }

    if (-not [string]::IsNullOrWhiteSpace($npmPackage)) {
        $specs += if ([string]::IsNullOrWhiteSpace($version)) { $npmPackage } else { "$npmPackage@$version" }
    }

    if ($PackageConfig.ContainsKey("NpmDependencies")) {
        $specs += @($PackageConfig.NpmDependencies)
    }

    return @($specs | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
}

function Get-NpmPackageNameFromSpec {
    param([string]$PackageSpec)

    $spec = ([string]$PackageSpec).Trim()
    if ([string]::IsNullOrWhiteSpace($spec)) {
        return ""
    }

    if ($spec.StartsWith("@")) {
        $separator = $spec.IndexOf("@", 1)
        if ($separator -gt 0) {
            return $spec.Substring(0, $separator)
        }
        return $spec
    }

    return ($spec -split '@', 2)[0]
}

function Get-NpmPackageArchiveFileName {
    param(
        [Parameter(Mandatory)]
        [string]$PackageName,

        [Parameter(Mandatory)]
        [string]$Version
    )

    $normalizedName = $PackageName -replace '^@', ''
    $normalizedName = $normalizedName -replace '/', '-'
    return "$normalizedName-$Version.tgz"
}

function Get-NpmPackageCacheDirectory {
    param(
        [Parameter(Mandatory)]
        [string]$PackagesDir,

        [Parameter(Mandatory)]
        [hashtable]$PackageConfig
    )

    return (Join-Path (Join-Path $PackagesDir "npm-packages") ([string]$PackageConfig.ShortName))
}

function Get-NpmCacheManifestPath {
    param([Parameter(Mandatory)][string]$CacheDirectory)

    return (Join-Path $CacheDirectory $script:NpmCacheManifestName)
}

function Get-NpmCacheLockPath {
    param([Parameter(Mandatory)][string]$CacheDirectory)

    return (Join-Path $CacheDirectory $script:NpmCacheLockName)
}

function Get-NpmCacheArchiveDirectory {
    param([Parameter(Mandatory)][string]$CacheDirectory)

    return (Join-Path $CacheDirectory $script:NpmCacheArchiveDirectoryName)
}

function Get-NpmPackageIdentity {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Version
    )

    return "$Name@$Version"
}

function Get-NpmArchiveIntegrity {
    param([Parameter(Mandatory)][string]$Path)

    $sha512 = [System.Security.Cryptography.SHA512]::Create()
    try {
        $stream = [System.IO.File]::OpenRead($Path)
        try {
            $hash = $sha512.ComputeHash($stream)
        } finally {
            $stream.Dispose()
        }
    } finally {
        $sha512.Dispose()
    }

    return "sha512-" + [Convert]::ToBase64String($hash)
}

function Get-NpmPackageManifestFiles {
    param([Parameter(Mandatory)][string]$NodeModulesDirectory)

    if (-not (Test-Path $NodeModulesDirectory -PathType Container)) {
        return @()
    }

    # package contents may contain arbitrary package.json files (for example,
    # test fixtures). Traverse only node_modules' package-directory layout.
    $nodeModulesQueue = New-Object 'System.Collections.Generic.Queue[string]'
    $visitedNodeModules = @{}
    $visitedPackageDirectories = @{}
    $manifestPaths = @{}

    $nodeModulesQueue.Enqueue((Get-Item -LiteralPath $NodeModulesDirectory).FullName)

    while ($nodeModulesQueue.Count -gt 0) {
        $currentNodeModules = $nodeModulesQueue.Dequeue()
        $nodeModulesKey = $currentNodeModules.TrimEnd([char[]]@('\', '/')).ToLowerInvariant()
        if ($visitedNodeModules.ContainsKey($nodeModulesKey)) {
            continue
        }
        $visitedNodeModules[$nodeModulesKey] = $true

        $packageEntries = @(Get-ChildItem -LiteralPath $currentNodeModules -Directory -ErrorAction SilentlyContinue)
        foreach ($packageEntry in $packageEntries) {
            if ($packageEntry.Name -eq '.bin') {
                continue
            }

            if ($packageEntry.Name.StartsWith('@')) {
                $packageDirectories = @(Get-ChildItem -LiteralPath $packageEntry.FullName -Directory -ErrorAction SilentlyContinue)
            } else {
                $packageDirectories = @($packageEntry)
            }

            foreach ($packageDirectory in $packageDirectories) {
                $packageKey = $packageDirectory.FullName.TrimEnd([char[]]@('\', '/')).ToLowerInvariant()
                if ($visitedPackageDirectories.ContainsKey($packageKey)) {
                    continue
                }
                $visitedPackageDirectories[$packageKey] = $true

                $manifestPath = Join-Path $packageDirectory.FullName 'package.json'
                if (Test-Path $manifestPath -PathType Leaf) {
                    try {
                        $packageJson = Get-Content $manifestPath -Raw | ConvertFrom-Json
                    } catch {
                        throw "Failed to parse installed package manifest '$manifestPath': $($_.Exception.Message)"
                    }

                    $propertyNames = @($packageJson.PSObject.Properties | ForEach-Object { $_.Name })
                    if (($propertyNames -contains 'name') -and ($propertyNames -contains 'version') -and
                        -not [string]::IsNullOrWhiteSpace([string]$packageJson.name) -and
                        -not [string]::IsNullOrWhiteSpace([string]$packageJson.version)) {
                        $manifestPaths[$manifestPath] = $true
                    }
                }

                $nestedNodeModules = Join-Path $packageDirectory.FullName 'node_modules'
                if (Test-Path $nestedNodeModules -PathType Container) {
                    $nodeModulesQueue.Enqueue((Get-Item -LiteralPath $nestedNodeModules).FullName)
                }
            }
        }
    }

    return @($manifestPaths.Keys | Sort-Object | ForEach-Object { Get-Item -LiteralPath $_ })
}

function Find-NpmPackageManifest {
    param(
        [Parameter(Mandatory)]
        [string]$NodeModulesDirectory,

        [Parameter(Mandatory)]
        [string]$PackageName
    )

    $directPath = $PackageName -replace '/', [System.IO.Path]::DirectorySeparatorChar
    $directManifest = Join-Path (Join-Path $NodeModulesDirectory $directPath) "package.json"
    if (Test-Path $directManifest -PathType Leaf) {
        return (Get-Item $directManifest)
    }

    return (Get-NpmPackageManifestFiles -NodeModulesDirectory $NodeModulesDirectory |
        Where-Object {
            try {
                $json = Get-Content $_.FullName -Raw | ConvertFrom-Json
                $json.name -eq $PackageName
            } catch {
                $false
            }
        } |
        Select-Object -First 1)
}

function Get-NpmUniqueArchiveFileName {
    param(
        [Parameter(Mandatory)]
        [string]$BaseName,

        [Parameter(Mandatory)]
        [string]$PackageName
    )

    $candidate = $BaseName
    $safeName = ($PackageName -replace '[^A-Za-z0-9_.-]', '-')
    $counter = 0
    while (Test-Path (Join-Path $script:NpmCurrentArchiveDirectory $candidate)) {
        $counter++
        $candidate = "{0}-{1}-{2}.tgz" -f ([System.IO.Path]::GetFileNameWithoutExtension($BaseName)), $safeName, $counter
    }

    return $candidate
}

function Get-NpmCacheStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$PackageConfig,

        [Parameter(Mandatory)]
        [string]$PackagesDir,

        [string]$CacheDirectory = ""
    )

    $cacheDirectory = if ([string]::IsNullOrWhiteSpace($CacheDirectory)) {
        Get-NpmPackageCacheDirectory -PackagesDir $PackagesDir -PackageConfig $PackageConfig
    } else {
        $CacheDirectory
    }
    $manifestPath = Get-NpmCacheManifestPath -CacheDirectory $cacheDirectory
    $lockPath = Get-NpmCacheLockPath -CacheDirectory $cacheDirectory
    $status = [ordered]@{
        IsValid = $false
        CacheDirectory = $cacheDirectory
        ManifestPath = $manifestPath
        LockPath = $lockPath
        RootArchivePath = $null
        InstallArchivePaths = @()
        ArchivePaths = @()
        Missing = @()
        Invalid = @()
        Manifest = $null
    }

    if (-not (Test-Path $manifestPath -PathType Leaf)) {
        $status.Missing += $script:NpmCacheManifestName
        return [pscustomobject]$status
    }

    try {
        $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
        $status.Manifest = $manifest

        if ($manifest.schemaVersion -ne $script:NpmCacheSchemaVersion) {
            $status.Invalid += "unsupported schema version: $($manifest.schemaVersion)"
        }
        if ([string]$manifest.shortName -ne [string]$PackageConfig.ShortName) {
            $status.Invalid += "manifest shortName mismatch"
        }

        $expectedPackage = if ($PackageConfig.ContainsKey("NpmPackage")) { [string]$PackageConfig.NpmPackage } else { "" }
        $expectedVersion = if ($PackageConfig.ContainsKey("Version")) { [string]$PackageConfig.Version } else { "" }
        if ([string]$manifest.rootPackage -ne $expectedPackage) {
            $status.Invalid += "root package mismatch"
        }
        if (-not [string]::IsNullOrWhiteSpace($expectedVersion) -and [string]$manifest.rootVersion -ne $expectedVersion) {
            $status.Invalid += "root version mismatch"
        }

        if (-not (Test-Path $lockPath -PathType Leaf)) {
            $status.Missing += $script:NpmCacheLockName
        } else {
            try {
                # package-lock v2/v3 contains an empty-string root key, which the
                # Windows PowerShell 5.1 JSON parser cannot materialize as a property.
                # Normalize only that known key before parsing; the source lock file is
                # copied unchanged and remains the authoritative artifact.
                $lockText = Get-Content $lockPath -Raw
                $normalizedLockText = $lockText -replace '("packages"\s*:\s*\{\s*)""(\s*:)', '$1"__devbin_npm_root__"$2'
                $lock = $normalizedLockText | ConvertFrom-Json
                $lockProperties = @($lock.PSObject.Properties.Name)
                if ($lockProperties -notcontains "lockfileVersion" -or [int]$lock.lockfileVersion -lt 2) {
                    $status.Invalid += "unsupported package-lock.json format"
                }
                if ($lockProperties -notcontains "packages") {
                    $status.Invalid += "package-lock.json packages section is missing"
                } else {
                    $rootLockProperty = @($lock.packages.PSObject.Properties | Where-Object { $_.Name -eq "__devbin_npm_root__" } | Select-Object -First 1)
                    if ($rootLockProperty.Count -eq 0) {
                        $status.Invalid += "package-lock.json root package is missing"
                    } else {
                        # packages[""] describes the temporary project used during
                        # preparation. The installed package itself is represented by
                        # packages["node_modules/<root package>"].
                        $rootPackageEntryName = "node_modules/$([string]$manifest.rootPackage)"
                        $rootPackageProperty = @($lock.packages.PSObject.Properties | Where-Object { $_.Name -eq $rootPackageEntryName } | Select-Object -First 1)
                        if ($rootPackageProperty.Count -eq 0) {
                            $status.Invalid += "package-lock.json installed root package is missing"
                        } elseif ([string]$rootPackageProperty[0].Value.version -ne [string]$manifest.rootVersion) {
                            $status.Invalid += "package-lock.json installed root version mismatch"
                        }
                    }
                }
            } catch {
                $status.Invalid += "invalid package-lock.json"
            }
        }

        if ([string]::IsNullOrWhiteSpace([string]$manifest.rootArchive)) {
            $status.Invalid += "rootArchive is missing"
        }

        $manifestArchives = @($manifest.archives)
        $archiveRelativePaths = @{}
        if ($manifestArchives.Count -eq 0) {
            $status.Invalid += "archive list is empty"
        }

        foreach ($archive in $manifestArchives) {
            $relativePath = [string]$archive.relativePath
            if ([string]::IsNullOrWhiteSpace($relativePath) -or [System.IO.Path]::IsPathRooted($relativePath) -or $relativePath -match '^[A-Za-z]:' -or $relativePath -match '(^|[\\/])\.\.([\\/]|$)') {
                $status.Invalid += "invalid archive path"
                continue
            }

            $archiveRelativePaths[$relativePath] = $true
            $archivePath = Join-Path $cacheDirectory $relativePath
            $status.ArchivePaths += $archivePath
            if (-not (Test-Path $archivePath -PathType Leaf)) {
                $status.Missing += $relativePath
                continue
            }

            if ($archive.size -ne $null -and [int64](Get-Item $archivePath).Length -ne [int64]$archive.size) {
                $status.Invalid += "size mismatch: $relativePath"
                continue
            }

            if (-not [string]::IsNullOrWhiteSpace([string]$archive.integrity)) {
                try {
                    $actualIntegrity = Get-NpmArchiveIntegrity -Path $archivePath
                    if ($actualIntegrity -ne [string]$archive.integrity) {
                        $status.Invalid += "integrity mismatch: $relativePath"
                    }
                } catch {
                    $status.Invalid += "cannot hash archive: $relativePath"
                }
            } else {
                $status.Invalid += "integrity is missing: $relativePath"
            }
        }

        $rootArchiveRelativePath = [string]$manifest.rootArchive
        if ([string]::IsNullOrWhiteSpace($rootArchiveRelativePath) -or [System.IO.Path]::IsPathRooted($rootArchiveRelativePath) -or $rootArchiveRelativePath -match '^[A-Za-z]:' -or $rootArchiveRelativePath -match '(^|[\\/])\.\.([\\/]|$)') {
            $status.Invalid += "invalid root archive path"
        } elseif (-not $archiveRelativePaths.ContainsKey($rootArchiveRelativePath)) {
            $status.Invalid += "root archive is not listed in archive list"
        }
        $rootArchivePath = if (-not [string]::IsNullOrWhiteSpace($rootArchiveRelativePath) -and [System.IO.Path]::IsPathRooted($rootArchiveRelativePath) -eq $false -and $rootArchiveRelativePath -notmatch '^[A-Za-z]:' -and $rootArchiveRelativePath -notmatch '(^|[\\/])\.\.([\\/]|$)') {
            Join-Path $cacheDirectory $rootArchiveRelativePath
        } else {
            $null
        }
        $status.RootArchivePath = $rootArchivePath
        if ($rootArchivePath -and -not (Test-Path $rootArchivePath -PathType Leaf)) {
            $status.Missing += [string]$manifest.rootArchive
        }

        $installArchivePaths = @()
        foreach ($relativePath in @($manifest.installArchives)) {
            if ([string]::IsNullOrWhiteSpace([string]$relativePath) -or [System.IO.Path]::IsPathRooted([string]$relativePath) -or [string]$relativePath -match '^[A-Za-z]:' -or [string]$relativePath -match '(^|[\\/])\.\.([\\/]|$)') {
                $status.Invalid += "invalid install archive path"
                continue
            }
            if (-not $archiveRelativePaths.ContainsKey([string]$relativePath)) {
                $status.Invalid += "install archive is not listed in archive list: $relativePath"
            }
            $installPath = Join-Path $cacheDirectory ([string]$relativePath)
            if (-not (Test-Path $installPath -PathType Leaf)) {
                $status.Missing += [string]$relativePath
            } else {
                $installArchivePaths += $installPath
            }
        }
        $status.InstallArchivePaths = @($installArchivePaths)

        if ($PackageConfig.ContainsKey("ArchivePattern") -and -not [string]::IsNullOrWhiteSpace([string]$PackageConfig.ArchivePattern) -and (Test-Path $rootArchivePath -PathType Leaf)) {
            if ((Split-Path $rootArchivePath -Leaf) -notmatch [string]$PackageConfig.ArchivePattern) {
                $status.Invalid += "root archive filename does not match ArchivePattern"
            }
        }
    } catch {
        $status.Invalid += "manifest read failed: $($_.Exception.Message)"
    }

    $status.Missing = @($status.Missing | Select-Object -Unique)
    $status.Invalid = @($status.Invalid | Select-Object -Unique)
    $status.IsValid = ($status.Missing.Count -eq 0 -and $status.Invalid.Count -eq 0 -and $null -ne $status.RootArchivePath -and $status.InstallArchivePaths.Count -gt 0)
    return [pscustomobject]$status
}

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

    $lockText = Get-Content $CacheStatus.LockPath -Raw
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
                # npm records optional native packages for other platforms in the
                # lockfile, although npm did not install or pack them here.
                continue
            }
            throw "npm archive is missing for lockfile package: $identity"
        }

        $archivePath = Join-Path $CacheStatus.CacheDirectory $manifestRecords[$identity].relativePath
        Set-NpmJsonProperty -Object $entry -Name 'resolved' -Value (Get-NpmOfflineFileSpec -Path $archivePath)
        Set-NpmJsonProperty -Object $entry -Name 'integrity' -Value ([string]$manifestRecords[$identity].integrity)
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

    # Merge package directories without replacing the global npm inventory
    # file. robocopy exit codes 0..7 are successful (including copied files).
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
                $packageJson = Get-Content $manifestFile.FullName -Raw | ConvertFrom-Json
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
        $rootJson = Get-Content $rootManifestFile.FullName -Raw | ConvertFrom-Json
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
            $dependencyJson = Get-Content $dependencyManifest.FullName -Raw | ConvertFrom-Json
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
        Write-Host "Error: npm cache is incomplete for '$($PackageConfig.ShortName)'" -ForegroundColor Red
        if ($status.Missing.Count -gt 0) {
            Write-Host "  Missing: $($status.Missing -join ', ')" -ForegroundColor Red
        }
        if ($status.Invalid.Count -gt 0) {
            Write-Host "  Invalid: $($status.Invalid -join ', ')" -ForegroundColor Red
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
            & $NpmCommandPath cache add $archivePath --cache $tempCacheDirectory --offline | Out-Host
            if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) {
                Write-Host "Error: npm cache add failed for $archivePath" -ForegroundColor Red
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

        Write-Host "  Installing $($PackageConfig.ShortName) from the offline npm cache..."
        & $NpmCommandPath @args | Out-Host
        if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) {
            Write-Host "Error: npm install failed for '$($PackageConfig.ShortName)' (exit code: $LASTEXITCODE)" -ForegroundColor Red
            return $false
        }

        $expectedVersion = if ($PackageConfig.ContainsKey("Version")) { [string]$PackageConfig.Version } else { "" }
        $rootPackage = if ($PackageConfig.ContainsKey("NpmPackage")) { [string]$PackageConfig.NpmPackage } else { "" }
        $rootPackagePath = $rootPackage -replace '/', [System.IO.Path]::DirectorySeparatorChar
        $installedManifest = Join-Path (Join-Path $tempProjectDirectory "node_modules") (Join-Path $rootPackagePath "package.json")
        if (-not (Test-Path $installedManifest -PathType Leaf)) {
            Write-Host "Error: installed npm package was not found: $installedManifest" -ForegroundColor Red
            return $false
        }
        if (-not [string]::IsNullOrWhiteSpace($expectedVersion)) {
            try {
                $installedJson = Get-Content $installedManifest -Raw | ConvertFrom-Json
                if ([string]$installedJson.version -ne $expectedVersion) {
                    Write-Host "Error: installed npm version mismatch for '$rootPackage': expected $expectedVersion, got $($installedJson.version)" -ForegroundColor Red
                    return $false
                }
            } catch {
                Write-Host "Error: failed to inspect installed npm package: $($_.Exception.Message)" -ForegroundColor Red
                return $false
            }
        }

        Copy-NpmOfflineInstallToPrefix -ProjectDirectory $tempProjectDirectory -BinDir $BinDir

        Write-Host "$($PackageConfig.Name) installation completed."
        return $true
    } catch {
        Write-Host "Error: Failed to install $($PackageConfig.Name): $($_.Exception.Message)" -ForegroundColor Red
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

Export-ModuleMember -Function @(
    'Get-NpmPackageSpecs',
    'Get-NpmPackageCacheDirectory',
    'Get-NpmCacheManifestPath',
    'Get-NpmCacheStatus',
    'Save-NpmPackageCache',
    'Invoke-NpmInstallFromCache'
)
