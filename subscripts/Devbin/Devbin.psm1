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
    "Platform\CommandLookup.ps1"
    "Platform\TempDirectory.ps1"
    "Platform\FileSystem.ps1"
    "Platform\EnvironmentVariable.ps1"
    "Platform\UserPath.ps1"
    "Platform\VSCodeData.ps1"
    "Platform\Vswhere.ps1"
    "Platform\ProductRoot.ps1"
    "Platform\FontRegistration.ps1"
    "Platform\WindowsTerminal.ps1"
    "Platform\WindowsTerminalProfile.ps1"
    "Platform\ProductUninstall.ps1"
    "Platform\HomeDirectory.ps1"
    "Platform\BusySignal.ps1"
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
    "Extract\ArchiveExtraction.ps1"
    "Extract\StandardStrategy.ps1"
    "Extract\SubdirectoryStrategy.ps1"
    "Extract\TargetDirectoryStrategy.ps1"
    "Extract\ExecutableStrategy.ps1"
    "Extract\InstallerStrategy.ps1"
    "Extract\PackageManagerStrategy.ps1"
    "Extract\ExtractStrategy.ps1"
    "Install\ComponentEnvironment.ps1"
    "Install\ComponentPath.ps1"
    "Install\LifecycleScript.ps1"
    "Install\ComponentSource.ps1"
    "Install\ComponentInstall.ps1"
    "Install\ComponentFileRemoval.ps1"
    "Install\ComponentUninstall.ps1"
    "Install\ComponentChangePlan.ps1"
    "Menu\ConsoleInput.ps1"
    "Menu\MenuState.ps1"
    "Menu\MenuNavigation.ps1"
    "Menu\MenuRender.ps1"
    "Menu\MenuActions.ps1"
    "Menu\MenuLoop.ps1"
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
    # Platform
    'Test-CommandExists',
    'New-DevbinTempDirectory',
    'Remove-DevbinTempDirectory',
    'Convert-ToLongPath',
    'New-LongPathDirectory',
    'Copy-LongPathFile',
    'Remove-DirectoryTree',
    'Sync-EnvironmentVariable',
    'Sync-EnvironmentVariables',
    'Add-ToUserPath',
    'Remove-FromUserPath',
    'Add-SinglePathDir',
    'Remove-SinglePathDir',
    'Get-ManagedUserPathValue',
    'Sync-ManagedUserPath',
    'Backup-VSCodeData',
    'Restore-VSCodeData',
    'Register-VswhereInstance',
    'Unregister-VswhereInstance',
    'Get-DevbinProductRoot',
    'Get-DevbinExpectedProductRoot',
    'Test-DevbinProductRootAllowed',
    'Test-PathUnderRoot',
    'Split-RootEntriesFromValue',
    'ConvertFrom-JsonWithComments',
    'Get-WindowsTerminalSettingsPath',
    'New-SettingsBackup',
    'Get-TerminalSettings',
    'Save-TerminalSettings',
    'Invoke-CompleteUninstall',
    'Invoke-ProductUninstall',
    'Get-DevbinHomeLayout',
    'Get-DevbinHomePlan',
    'Invoke-DevbinHomePlan',
    'Start-BusySignal',
    'Stop-BusySignal',
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
    # Extract
    'Unblock-ArchiveFile',
    'Expand-ArchiveToTemp',
    'Get-ExtractedSourcePath',
    'Resolve-PostExtractSourcePath',
    'Invoke-ExtractStrategy',
    'Invoke-PipInstallStrategy',
    'Invoke-NpmInstallStrategy',
    # Install
    'Get-ComponentEnvVarValues',
    'Test-ComponentUsesEdge',
    'Resolve-ComponentSource',
    'Set-ComponentEnvVars',
    'Remove-ComponentEnvVars',
    'Add-ComponentPathDirs',
    'Remove-ComponentPathDirs',
    'Add-BasePathDir',
    'Remove-BasePathDir',
    'Sync-ComponentManagerPath',
    'Invoke-PackageLifecycleScripts',
    'Install-Component',
    'Get-OtherComponentFiles',
    'Get-ComponentRootDirectories',
    'Remove-ComponentInstalledFiles',
    'Uninstall-Component',
    'Update-Component',
    'Remove-OrphanDependencies',
    'New-ComponentChangePlan',
    'Invoke-ComponentChangePlan',
    # Menu
    'Get-MenuItems',
    'Invoke-MenuLoop'
)
