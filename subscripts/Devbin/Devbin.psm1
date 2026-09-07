# Devbin.psm1
# devbin-win の内部モジュールの読み込み窓口
#
# 読み込み順は下から上への依存関係を崩さないよう、ここで明示する。
# 呼び出し元の Import 順や Get-Command による存在確認には依存しない。

$script:DevbinModuleRoot = $PSScriptRoot
$script:DevbinSubscriptsDir = Split-Path -Parent $PSScriptRoot
$script:DevbinRepositoryRoot = Split-Path -Parent $script:DevbinSubscriptsDir

# npm は StrictMode を使うため子モジュールとして分離し、他の処理へ波及させない
$script:DevbinNpmModulePath = Join-Path $script:DevbinModuleRoot "Packages\Npm\DevbinNpm.psm1"
if (-not (Test-Path $script:DevbinNpmModulePath -PathType Leaf)) {
    throw "Devbin npm module not found: $($script:DevbinNpmModulePath)"
}
Import-Module $script:DevbinNpmModulePath -Force -ErrorAction Stop

$script:DevbinSourceFiles = @(
    "Context\DevbinContext.ps1"
    "Catalog\PackageDataFile.ps1"
    "Catalog\PackageCatalog.ps1"
    "Catalog\PackageDependency.ps1"
    "Catalog\PackageVersion.ps1"
    "Catalog\PackageFileName.ps1"
    "Catalog\PipPackage.ps1"
    "State\Manifest.ps1"
    "State\ComponentStatus.ps1"
    "Packages\FileDownload.ps1"
    "Packages\ArchivePackage.ps1"
    "Packages\PipCache.ps1"
    "Packages\NpmCacheDownload.ps1"
    "Packages\VsBuildToolsDownload.ps1"
    "Packages\PackageAcquisition.ps1"
    "Install\ComponentChangePlan.ps1"
)

foreach ($relativePath in $script:DevbinSourceFiles) {
    $sourcePath = Join-Path $script:DevbinModuleRoot $relativePath
    if (-not (Test-Path $sourcePath -PathType Leaf)) {
        throw "Devbin module source not found: $sourcePath"
    }
    . $sourcePath
}

Export-ModuleMember -Function @(
    # Context
    'New-DevbinContext',
    # Catalog
    'Import-DevbinDataFile',
    'Import-PackageCatalog',
    'Test-PackageCatalog',
    'Get-PackageByShortName',
    'Get-PackageTargetDirectory',
    'Get-PythonDirectory',
    'Resolve-Dependencies',
    'Resolve-DependencyOrder',
    'Get-Dependents',
    'Get-UninstallOrder',
    'Resolve-PackageVersion',
    'Get-PackageBaseFileName',
    'Test-FileNameContainsVersion',
    'Get-PackageDownloadFileName',
    'Get-NormalizedPipPackageName',
    'Get-PipWheelPackageNames',
    'Get-PipWheelDownloadSpecs',
    'Test-PipWheelPackages',
    # State
    'Get-ManifestPath',
    'Read-Manifest',
    'Write-Manifest',
    'Add-ComponentToManifest',
    'Remove-ComponentFromManifest',
    'Test-ComponentInstalled',
    'Test-ComponentFiles',
    'Initialize-LegacyManifest',
    'Initialize-ComponentManifest',
    'Compare-PackageVersion',
    'Test-ComponentUpdateable',
    'Get-ComponentStatus',
    'Get-DirectorySnapshot',
    'Get-FileSnapshotDiff',
    # Packages
    'Save-DownloadedFile',
    'Unblock-PackageFiles',
    'Select-TargetPackages',
    'Get-ArchiveDownloadTargets',
    'Remove-OldPackageFiles',
    'Invoke-ArchiveDownload',
    'Save-PipWheelPackages',
    'Invoke-PipWheelDownload',
    'Invoke-NpmCacheDownload',
    'Invoke-VsBuildToolsDownload',
    'Invoke-PackageAcquisition',
    # Packages/Npm (子モジュールからの再公開)
    'Get-NpmPackageSpecs',
    'Get-NpmPackageCacheDirectory',
    'Get-NpmCacheManifestPath',
    'Get-NpmCacheStatus',
    'Save-NpmPackageCache',
    'Invoke-NpmInstallFromCache',
    # Install
    'New-ComponentChangePlan',
    'Invoke-ComponentChangePlan'
)
