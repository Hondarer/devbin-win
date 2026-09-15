# DevbinNpm.psm1
# npm オフラインキャッシュ管理サブモジュール
#
# Set-StrictMode を本モジュールスコープに局所化し、外部スクリプトへの副作用を防止します。
# キャッシュレイアウト解決、整合性検証、キャッシュ作成、オフラインインストールの責務を各ファイルへ分離して構成します。

Set-StrictMode -Version Latest

$script:DevbinNpmSourceFiles = @(
    "NpmCacheLayout.ps1"
    "NpmCacheVerify.ps1"
    "NpmCacheBuild.ps1"
    "NpmOfflineInstall.ps1"
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
    'Invoke-NpmInstallFromCache'
)
