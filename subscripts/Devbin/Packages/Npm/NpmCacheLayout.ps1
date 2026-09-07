# NpmCacheLayout.ps1
# npm キャッシュのパス・名前・整合値などの共通部品

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
                        $packageJson = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
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
                $json = Get-Content $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
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
