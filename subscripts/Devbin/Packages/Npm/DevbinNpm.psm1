# DevbinNpm.psm1
# npm オフラインキャッシュの子モジュール
#
# StrictMode をこのモジュール内に閉じ込め、他の処理へ波及させない。
# キャッシュのレイアウト、検証、作成、オフライン導入をファイルで分ける。

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
