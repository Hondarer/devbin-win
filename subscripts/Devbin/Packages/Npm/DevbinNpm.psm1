# DevbinNpm.psm1
# npm オフラインキャッシュと npm グローバル パッケージの管理サブモジュール
#
# Set-StrictMode を本モジュールスコープに局所化し、外部スクリプトへの副作用を防止します。
# キャッシュレイアウト解決、キャッシュ判定、キャッシュ作成、npm install -g / uninstall -g の責務を各ファイルへ分離して構成します。

Set-StrictMode -Version Latest

$script:DevbinNpmSourceFiles = @(
    "NpmCacheLayout.ps1"
    "NpmCacheVerify.ps1"
    "NpmGlobalPackages.ps1"
    "NpmCacheBuild.ps1"
)

foreach ($relativePath in $script:DevbinNpmSourceFiles) {
    $sourcePath = Join-Path $PSScriptRoot $relativePath
    if (-not (Test-Path $sourcePath -PathType Leaf)) {
        throw "Devbin npm module source not found: $sourcePath"
    }
    . $sourcePath
}

Export-ModuleMember -Function @(
    'Get-NpmPackageSpecs',
    'Get-NpmPackageCacheDirectory',
    'Get-NpmCacheManifestPath',
    'Get-NpmCacheStatus',
    'Save-NpmPackageCache',
    'Invoke-NpmInstallFromCache',
    'Get-NpmRequestedPackageNames',
    'Get-NpmGlobalPackageVersion',
    'Get-NpmComponentOwnedPaths',
    'Uninstall-NpmGlobalPackages'
)
