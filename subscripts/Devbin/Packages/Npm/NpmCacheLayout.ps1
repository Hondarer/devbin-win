# NpmCacheLayout.ps1
# npm キャッシュのパス解決と、パッケージ指定の解釈

# 3: npm install -g の実行結果として、npm 自身のキャッシュ (メタデータと tarball) を保存します。
# 導入は npm install -g --offline をそのまま実行するため、配置と依存関係の解決は npm に委ねます。
# 2 以前は devbin が独自に組み立てた依存ツリーの記録であり、npm -g と配置が異なるため無効とします。
$script:NpmCacheSchemaVersion = 3
$script:NpmCacheManifestName = "npm-cache-manifest.json"
$script:NpmCacheContentDirectoryName = "cache"

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

# コンポーネントが npm install -g で明示的に要求するパッケージ名 (本体と NpmDependencies) を返します。
function Get-NpmRequestedPackageNames {
    param(
        [Parameter(Mandatory)]
        [hashtable]$PackageConfig
    )

    return @(Get-NpmPackageSpecs -PackageConfig $PackageConfig |
        ForEach-Object { Get-NpmPackageNameFromSpec -PackageSpec $_ } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -Unique)
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

# npm の --cache に渡すディレクトリです。npm はこの配下に _cacache を作成します。
function Get-NpmCacheContentDirectory {
    param([Parameter(Mandatory)][string]$CacheDirectory)

    return (Join-Path $CacheDirectory $script:NpmCacheContentDirectoryName)
}
