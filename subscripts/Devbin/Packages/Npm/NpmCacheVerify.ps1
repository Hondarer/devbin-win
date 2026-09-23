# NpmCacheVerify.ps1
# npm オフラインキャッシュの判定 (マニフェストと定義の一致、npm キャッシュの有無)

# tarball の整合性は npm が内容アドレス (SHA-512) で読み出し時に検証するため、ここでは確認しません。
# see: https://github.com/npm/cacache
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
    $contentDirectory = Get-NpmCacheContentDirectory -CacheDirectory $cacheDirectory
    $status = [ordered]@{
        IsValid          = $false
        CacheDirectory   = $cacheDirectory
        ManifestPath     = $manifestPath
        ContentDirectory = $contentDirectory
        Manifest         = $null
        Missing          = @()
        Invalid          = @()
    }

    if (-not (Test-Path $manifestPath -PathType Leaf)) {
        $status.Missing += $script:NpmCacheManifestName
        return [pscustomobject]$status
    }

    try {
        $manifest = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $status.Manifest = $manifest
        $names = @($manifest.PSObject.Properties.Name)
        $valueOf = {
            param($name)
            if ($names -contains $name) { $manifest.$name } else { $null }
        }

        if ((& $valueOf 'schemaVersion') -ne $script:NpmCacheSchemaVersion) {
            $status.Invalid += "unsupported schema version: $(& $valueOf 'schemaVersion')"
        }
        if ([string](& $valueOf 'shortName') -ne [string]$PackageConfig.ShortName) {
            $status.Invalid += "manifest shortName mismatch"
        }

        $expectedPackage = if ($PackageConfig.ContainsKey("NpmPackage")) { [string]$PackageConfig.NpmPackage } else { "" }
        $expectedVersion = if ($PackageConfig.ContainsKey("Version")) { [string]$PackageConfig.Version } else { "" }
        if ([string](& $valueOf 'rootPackage') -ne $expectedPackage) {
            $status.Invalid += "root package mismatch"
        }
        if (-not [string]::IsNullOrWhiteSpace($expectedVersion) -and [string](& $valueOf 'rootVersion') -ne $expectedVersion) {
            $status.Invalid += "root version mismatch"
        }

        # NpmDependencies の変更も、キャッシュの作り直しが必要な変更として扱います。
        $expectedSpecs = @(Get-NpmPackageSpecs -PackageConfig $PackageConfig | Sort-Object)
        $cachedSpecs = @(@(& $valueOf 'requestedPackages') | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ } | Sort-Object)
        if (($expectedSpecs -join "`n") -ne ($cachedSpecs -join "`n")) {
            $status.Invalid += "requested packages mismatch"
        }
    } catch {
        $status.Invalid += "manifest read failed: $($_.Exception.Message)"
    }

    # npm のキャッシュは、メタデータの索引 (index-v5) と内容 (content-v2) で構成されます。
    foreach ($entry in @("index-v5", "content-v2")) {
        if (-not (Test-Path (Join-Path $contentDirectory (Join-Path "_cacache" $entry)) -PathType Container)) {
            $status.Missing += "$($script:NpmCacheContentDirectoryName)/_cacache/$entry"
        }
    }

    $status.Missing = @($status.Missing | Select-Object -Unique)
    $status.Invalid = @($status.Invalid | Select-Object -Unique)
    $status.IsValid = ($status.Missing.Count -eq 0 -and $status.Invalid.Count -eq 0)
    return [pscustomobject]$status
}
