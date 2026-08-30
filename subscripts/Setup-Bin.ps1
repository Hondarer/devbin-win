# 開発ツール セットアップ スクリプト
# 開発ツールの抽出、インストール、またはアンインストールを行う

param(
    [string]$InstallDir = ".\bin",
    [switch]$Extract,
    [switch]$Install,
    [switch]$Uninstall,
    [switch]$Manage
)

# スクリプトのディレクトリを取得
$ScriptDir = if ($PSScriptRoot) {
    $PSScriptRoot
} elseif ($MyInvocation.MyCommand.Path) {
    Split-Path -Parent $MyInvocation.MyCommand.Path
} else {
    # フォールバック: 現在の実行ディレクトリを使用
    Get-Location | Select-Object -ExpandProperty Path
}

# モジュールをインポート
$commonModulePath = "$ScriptDir\Setup-Common.psm1"
$strategiesModulePath = "$ScriptDir\Setup-Strategies.psm1"

if (-not (Test-Path $commonModulePath)) {
    Write-Host "Error: Setup-Common.psm1 not found at: $commonModulePath" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $strategiesModulePath)) {
    Write-Host "Error: Setup-Strategies.psm1 not found at: $strategiesModulePath" -ForegroundColor Red
    exit 1
}

try {
    Import-Module $commonModulePath -Force -ErrorAction Stop
} catch {
    Write-Host "Error importing Setup-Common: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

try {
    Import-Module $strategiesModulePath -Force -ErrorAction Stop
} catch {
    Write-Host "Error importing Setup-Strategies: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$npmCacheModulePath = "$ScriptDir\Setup-NpmCache.psm1"
if (Test-Path $npmCacheModulePath) {
    try {
        Import-Module $npmCacheModulePath -Force -ErrorAction Stop
    } catch {
        Write-Host "Error importing Setup-NpmCache: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "Error: Setup-NpmCache.psm1 not found at: $npmCacheModulePath" -ForegroundColor Red
    exit 1
}

$manifestModulePath = "$ScriptDir\Setup-Manifest.psm1"
$componentsModulePath = "$ScriptDir\Setup-Components.psm1"

if (Test-Path $manifestModulePath) {
    try {
        Import-Module $manifestModulePath -Force -ErrorAction Stop
    } catch {
        Write-Host "Warning: Failed to import Setup-Manifest: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

if (Test-Path $componentsModulePath) {
    try {
        Import-Module $componentsModulePath -Force -ErrorAction Stop
    } catch {
        Write-Host "Warning: Failed to import Setup-Components: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# パッケージ設定を読み込む
$PackagesConfigPath = Join-Path $ScriptDir "config\packages.psd1"
$PackagesConfig = Invoke-Expression (Get-Content $PackagesConfigPath -Raw)
$Packages = $PackagesConfig.Packages

# オプションが指定されていない場合は使用方法を表示
if (-not ($Extract -or $Install -or $Uninstall -or $Manage)) {
    Write-Host "Development Tools Setup Script"
    Write-Host "================================"
    Write-Host ""
    Write-Host "Usage:"
    Write-Host "  .\Setup-Bin.ps1 -Extract [-InstallDir <path>]    # Extract tools only"
    Write-Host "  .\Setup-Bin.ps1 -Install [-InstallDir <path>]    # Extract tools and add to PATH"
    Write-Host "  .\Setup-Bin.ps1 -Uninstall [-InstallDir <path>]  # Remove tools and clean PATH"
    Write-Host "  .\Setup-Bin.ps1 -Manage [-InstallDir <path>]     # Interactive component manager"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -InstallDir <path>  Installation directory (default: .\bin)"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\Setup-Bin.ps1 -Extract                         # Extract to .\bin"
    Write-Host "  .\Setup-Bin.ps1 -Install -InstallDir C:\Tools    # Install to C:\Tools"
    Write-Host "  .\Setup-Bin.ps1 -Uninstall                       # Uninstall from .\bin"
    Write-Host "  .\Setup-Bin.ps1 -Manage                          # Open component manager"
    exit 0
}

# 昇格された管理者権限での実行を検出する (本スクリプトは非昇格ユーザーでの実行を想定)
$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
if ($currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Warning: This script is not intended to be run with elevated administrator privileges." -ForegroundColor Yellow
    Write-Host "Please run it from a non-elevated (standard user) shell." -ForegroundColor Yellow
    exit 1
}

# 追加 / 削除すべき PATH ディレクトリを取得する
function Get-PathDirectories {
    param(
        [string]$BaseDir,
        [array]$PackageList = @()
    )

    # packages.psd1 の PathDirs から動的に生成する
    if ($PackageList -and $PackageList.Count -gt 0) {
        $pathDirs = @($BaseDir)
        foreach ($pkg in $PackageList) {
            if ($pkg.ContainsKey("PathDirs") -and $pkg.PathDirs) {
                foreach ($rel in $pkg.PathDirs) {
                    if ($rel) {
                        $pathDirs += Join-Path $BaseDir $rel
                    }
                }
            }
        }
        # 重複を除去して返す
        return $pathDirs | Select-Object -Unique
    }

    # フォールバック: ハードコードリスト (PackageList が空の場合)
    return @(
        $BaseDir,
        "$BaseDir\jdk-25\bin",
        "$BaseDir\graphviz",
        "$BaseDir\python-3.13",
        "$BaseDir\python-3.13\Scripts",
        "$BaseDir\dotnet10sdk",
        "$BaseDir\git",
        "$BaseDir\git\bin",
        "$BaseDir\git\cmd",
        "$BaseDir\vscode\bin",
        "$BaseDir\OpenCppCoverage",
        "$BaseDir\ReportGenerator"
    )
}

# Manage モード: 対話型コンポーネントマネージャー
if ($Manage) {
    $menuModulePath = "$ScriptDir\Setup-Menu.psm1"
    if (-not (Test-Path $menuModulePath)) {
        Write-Host "Error: Setup-Menu.psm1 not found at: $menuModulePath" -ForegroundColor Red
        exit 1
    }
    try {
        Import-Module $menuModulePath -Force -ErrorAction Stop
    } catch {
        Write-Host "Error importing Setup-Menu: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }

    # InstallDir を絶対パスに変換
    $absoluteInstallDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($InstallDir)

    # 環境変数をレジストリから同期
    Sync-EnvironmentVariables -VariableNames @("PATH", "DOTNET_HOME", "DOTNET_CLI_TELEMETRY_OPTOUT", "PLANTUML_HOME", "BROWSER_PATH", "PUPPETEER_EXECUTABLE_PATH") -Silent | Out-Null

    Invoke-MenuLoop -Packages $Packages -InstallDir $absoluteInstallDir -ScriptDir $ScriptDir
    exit 0
}

# アンインストール処理
if ($Uninstall) {
    Write-Host "=== Development Tools Uninstallation ==="
    Write-Host ""

    # 絶対パスに変換
    $absoluteInstallDir = (Resolve-Path $InstallDir -ErrorAction SilentlyContinue)
    if ($absoluteInstallDir) {
        $InstallDir = $absoluteInstallDir.Path
    }

    Write-Host "Installation directory: $InstallDir"
    Write-Host ""

    # VS Code data フォルダのバックアップ
    $vscodePath = Join-Path $InstallDir "vscode"
    if (Test-Path $vscodePath) {
        Backup-VSCodeData -InstallDirectory $InstallDir | Out-Null
    }

    # ユーザー PATH から開発ツールのディレクトリを削除
    $pathDirs = Get-PathDirectories -BaseDir $InstallDir -PackageList $Packages
    Remove-FromUserPath -Directories $pathDirs

    # パッケージ定義と manifest に基づいて環境変数を削除
    $uninstallEnvironmentNames = @("PATH")
    $uninstallManifest = if (Get-Command Read-Manifest -ErrorAction SilentlyContinue) {
        Read-Manifest -InstallDir $InstallDir
    } else {
        $null
    }
    foreach ($packageConfig in $Packages) {
        $hasEnvConfig = $packageConfig.ContainsKey("EnvVars") -and $packageConfig.EnvVars.Count -gt 0
        $hasBrowserConfig = $packageConfig.ContainsKey("Browser") -and [string]$packageConfig.Browser -eq "Edge"
        if (-not ($hasEnvConfig -or $hasBrowserConfig)) {
            continue
        }

        $appliedEnvVars = @{}
        if ($uninstallManifest -and $uninstallManifest.components.ContainsKey($packageConfig.ShortName)) {
            $componentData = $uninstallManifest.components[$packageConfig.ShortName]
            if ($componentData.ContainsKey("envVars") -and $componentData.envVars) {
                $appliedEnvVars = $componentData.envVars
            }
        }
        Remove-ComponentEnvVars -InstallDir $InstallDir -PackageConfig $packageConfig -AppliedEnvVars $appliedEnvVars
        $uninstallEnvironmentNames += @($appliedEnvVars.Keys)
    }
    Sync-EnvironmentVariables -VariableNames ($uninstallEnvironmentNames | Select-Object -Unique) | Out-Null

    # 完全アンインストールの確認
    try {
        Invoke-CompleteUninstall -InstallDirectory $InstallDir -PackagesConfigPath $PackagesConfigPath | Out-Null
        Write-Host ""
        Write-Host "Uninstallation completed." -ForegroundColor Green
        Write-Host "Note: To apply PATH changes, restart your terminal."
        exit 0
    } catch {
        Write-Host ""
        Write-Host "Error: Uninstallation failed." -ForegroundColor Red
        Write-Host "$($_.Exception.Message)" -ForegroundColor Yellow
        exit 1
    }
}

# Extract または Install 処理
Write-Host "=== Development Tools Setup ==="
Write-Host ""

# 環境変数をレジストリからカレントプロセスに同期
Write-Host "Synchronizing environment variables..."
Sync-EnvironmentVariables -VariableNames @("PATH", "PYTHONHOME", "PYTHONPATH", "DOTNET_HOME", "DOTNET_CLI_TELEMETRY_OPTOUT", "PLANTUML_HOME", "BROWSER_PATH", "PUPPETEER_EXECUTABLE_PATH") | Out-Null
Write-Host ""

# インストール処理中、スリープ/スクリーンセーバーが働かないよう Busy シグナルを開始する
Start-BusySignal

try {

# 絶対パスに変換
$absoluteInstallDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($InstallDir)
$InstallDir = $absoluteInstallDir

Write-Host "Installation directory: $InstallDir"
Write-Host ""

function Get-NormalizedPipPackageName {
    param([string]$Name)

    return (([string]$Name).Trim().ToLowerInvariant() -replace '[-_.]+', '-')
}

function Get-PipWheelPackageNames {
    param([hashtable]$PackageConfig)

    $packageNames = @()
    if ($PackageConfig.ContainsKey("PipPackage") -and -not [string]::IsNullOrWhiteSpace([string]$PackageConfig.PipPackage)) {
        $pipPackage = [string]$PackageConfig.PipPackage
        $version = if ($PackageConfig.ContainsKey("Version")) { [string]$PackageConfig.Version } else { "" }
        if (-not [string]::IsNullOrWhiteSpace($version)) {
            $packageNames += "$pipPackage==$version"
        } else {
            $packageNames += $pipPackage
        }
    }

    if ($PackageConfig.ContainsKey("PipDependencies")) {
        $packageNames += @($PackageConfig.PipDependencies)
    }

    $seen = @{}
    $result = @()
    foreach ($packageName in $packageNames) {
        $packageNameOnly = ([string]$packageName -split '==', 2)[0]
        $normalizedName = Get-NormalizedPipPackageName -Name $packageNameOnly
        if ([string]::IsNullOrWhiteSpace($normalizedName) -or $seen.ContainsKey($normalizedName)) {
            continue
        }

        $seen[$normalizedName] = $true
        $result += [string]$packageName
    }

    return @($result)
}

function Test-PipWheelPackages {
    param(
        [string]$DirectoryPath,
        [string[]]$PackageNames
    )

    $missing = @()
    $wheelFiles = if (Test-Path $DirectoryPath) {
        @(Get-ChildItem -Path $DirectoryPath -Filter "*.whl" -File -ErrorAction SilentlyContinue)
    } else {
        @()
    }

    foreach ($packageName in $PackageNames) {
        if ([string]::IsNullOrWhiteSpace($packageName)) {
            continue
        }

        $packageSpecParts = ([string]$packageName -split '==', 2)
        $packageNameOnly = $packageSpecParts[0]
        $requiredVersion = if ($packageSpecParts.Count -gt 1) { $packageSpecParts[1] } else { "" }
        $normalizedName = Get-NormalizedPipPackageName -Name $packageNameOnly
        $found = $false
        foreach ($wheelFile in $wheelFiles) {
            $wheelNameParts = $wheelFile.Name -split '-', 3
            $distributionName = $wheelNameParts[0]
            $wheelVersion = if ($wheelNameParts.Count -gt 1) { $wheelNameParts[1] } else { "" }
            if ((Get-NormalizedPipPackageName -Name $distributionName) -eq $normalizedName -and ([string]::IsNullOrWhiteSpace($requiredVersion) -or $wheelVersion -eq $requiredVersion)) {
                $found = $true
                break
            }
        }

        if (-not $found) {
            $missing += if ([string]::IsNullOrWhiteSpace($requiredVersion)) { "$packageNameOnly-*.whl" } else { "$packageNameOnly==$requiredVersion" }
        }
    }

    return @($missing)
}

function Invoke-GetPackagesForPipInstall {
    param(
        [string]$ShortName,
        [string]$InstallDir,
        [string]$ScriptDir
    )

    $getPackagesScript = Join-Path $ScriptDir "Get-Packages.ps1"
    if (-not (Test-Path $getPackagesScript)) {
        Write-Host "Error: Get-Packages.ps1 not found at: $getPackagesScript" -ForegroundColor Red
        return
    }

    $originalPath = $env:PATH
    $pythonDir = Join-Path $InstallDir "python-3.13"
    $pythonScriptsDir = Join-Path $pythonDir "Scripts"

    try {
        if (Test-Path (Join-Path $pythonDir "python.exe")) {
            $pathEntries = @($pythonDir, $pythonScriptsDir) | Where-Object { Test-Path $_ }
            if ($pathEntries.Count -gt 0) {
                $env:PATH = ($pathEntries -join ';') + ";" + $env:PATH
            }
        }

        Write-Host "  ダウンロード対象: $ShortName"
        & $getPackagesScript -PackageShortNames @($ShortName)
    } finally {
        $env:PATH = $originalPath
    }
}

# packages ディレクトリをチェック
$packagesDir = Join-Path (Split-Path $ScriptDir -Parent) "packages"
if (!(Test-Path $packagesDir)) {
    New-Item -ItemType Directory -Path $packagesDir | Out-Null
    Write-Host "Created packages directory."
}

# 必要なパッケージファイルが存在するかチェック
$missingPackages = @()
foreach ($packageConfig in $Packages) {
    # VSBuildTools は archive ファイルを使わないためスキップ
    if ($packageConfig.ExtractStrategy -eq "VSBuildTools") {
        continue
    }

    if ($packageConfig.ExtractStrategy -eq "PipInstall") {
        $pipPackagesDir = Join-Path $packagesDir "pip-packages"
        $requiredPipWheels = Get-PipWheelPackageNames -PackageConfig $packageConfig
        $missingPipWheels = @(Test-PipWheelPackages -DirectoryPath $pipPackagesDir -PackageNames $requiredPipWheels)
        if ($missingPipWheels.Count -gt 0) {
            $missingPackages += $packageConfig
        }

        continue
    }

    if ($packageConfig.ExtractStrategy -eq "NpmInstall") {
        $npmCacheStatus = Get-NpmCacheStatus -PackageConfig $packageConfig -PackagesDir $packagesDir
        if (-not $npmCacheStatus.IsValid) {
            $missingPackages += $packageConfig
        }

        continue
    }

    $archivePattern = $packageConfig.ArchivePattern
    $archiveFiles = Get-ChildItem -Path $packagesDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $archivePattern }

    if ($archiveFiles.Count -eq 0 -and $packageConfig.DownloadUrl) {
        $missingPackages += $packageConfig
    }
}

# 不足しているパッケージがある場合はダウンロードを試みる
if ($missingPackages.Count -gt 0) {
    Write-Host "Missing $($missingPackages.Count) package(s). Attempting to download..."
    Write-Host ""

    $getPackagesScript = Join-Path $ScriptDir "Get-Packages.ps1"
    if (Test-Path $getPackagesScript) {
        $downloadTargets = @($missingPackages | ForEach-Object { $_.ShortName } | Select-Object -Unique)
        & $getPackagesScript -PackageShortNames $downloadTargets
        if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) {
            Write-Host "Warning: Package download completed with errors." -ForegroundColor Yellow
        }
        Write-Host ""

        $stillMissing = @()
        foreach ($packageConfig in $missingPackages) {
            if ($packageConfig.ExtractStrategy -eq "NpmInstall") {
                $cacheStatus = Get-NpmCacheStatus -PackageConfig $packageConfig -PackagesDir $packagesDir
                if (-not $cacheStatus.IsValid) {
                    $stillMissing += "$($packageConfig.ShortName): $($cacheStatus.Invalid + $cacheStatus.Missing -join ', ')"
                }
            } elseif ($packageConfig.ExtractStrategy -eq "PipInstall") {
                $requiredPipWheels = Get-PipWheelPackageNames -PackageConfig $packageConfig
                $missingPipWheels = @(Test-PipWheelPackages -DirectoryPath (Join-Path $packagesDir "pip-packages") -PackageNames $requiredPipWheels)
                if ($missingPipWheels.Count -gt 0) {
                    $stillMissing += "$($packageConfig.ShortName): $($missingPipWheels -join ', ')"
                }
            } else {
                $archiveFiles = Get-ChildItem -Path $packagesDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $packageConfig.ArchivePattern }
                if ($archiveFiles.Count -eq 0 -and $packageConfig.DownloadUrl) {
                    $stillMissing += "$($packageConfig.ShortName): archive"
                }
            }
        }
        if ($stillMissing.Count -gt 0) {
            Write-Host "Error: Required package caches are still missing after download:" -ForegroundColor Red
            $stillMissing | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
            exit 1
        }
    } else {
        Write-Host "Error: Get-Packages.ps1 not found at: $getPackagesScript" -ForegroundColor Red
        Write-Host "Please download required packages manually." -ForegroundColor Red
        exit 1
    }
}

# インストール前にクリーンアップを実行
Write-Host "Performing pre-installation cleanup..."
try {
    # ディレクトリ削除前に PATH から削除する (Invoke-CompleteUninstall より先に実行)
    $pathDirsToClean = Get-PathDirectories -BaseDir $InstallDir -PackageList $Packages
    Remove-FromUserPath -Directories $pathDirsToClean

    $cleanupResult = Invoke-CompleteUninstall `
        -InstallDirectory $InstallDir `
        -PreserveVSCodeData `
        -PackagesConfigPath $PackagesConfigPath

    if ($cleanupResult) {
        Write-Host "Previous installation cleaned up successfully."
    } else {
        Write-Host "Cleanup completed with some warnings (this is normal for first-time installation)."
    }
    Write-Host ""
} catch {
    Write-Host ""
    Write-Host "Error: Pre-installation cleanup failed." -ForegroundColor Red
    Write-Host "$($_.Exception.Message)" -ForegroundColor Yellow
    exit 1
}

# bin ディレクトリを作成
if (!(Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir | Out-Null
    Write-Host "Created installation directory."
}
Write-Host ""

# 各パッケージを処理
Write-Host "Processing packages..."
Write-Host ""

$successCount = 0
$totalCount = 0
$successfulPackages = @()

foreach ($packageConfig in $Packages) {
    $packageName = $packageConfig.Name
    $archivePattern = $packageConfig.ArchivePattern
    $strategy = $packageConfig.ExtractStrategy

    # VSBuildTools 戦略の場合は Setup-VSBT.ps1 に処理を委譲
    if ($strategy -eq "VSBuildTools") {
        $totalCount++

        # パッケージを抽出 (ArchiveFile パラメーターはダミー)
        $result = Invoke-ExtractStrategy `
            -PackageConfig $packageConfig `
            -ArchiveFile "" `
            -BinDir $InstallDir `
            -ScriptDir $ScriptDir `
            -PackagesDir $packagesDir

        if ($result) {
            $successCount++
            $successfulPackages += $packageConfig
        }

        Write-Host ""
        continue
    }

    # PipInstall / NpmInstall 戦略の場合は各パッケージマネージャーに処理を委譲
    if ($strategy -eq "PipInstall" -or $strategy -eq "NpmInstall") {
        $totalCount++

        if ($strategy -eq "PipInstall") {
            $pipPackagesDir = Join-Path $packagesDir "pip-packages"
            $requiredPipWheels = Get-PipWheelPackageNames -PackageConfig $packageConfig
            $missingPipWheels = @(Test-PipWheelPackages -DirectoryPath $pipPackagesDir -PackageNames $requiredPipWheels)

            if ($missingPipWheels.Count -gt 0) {
                Write-Host "  pip wheel ファイルが見つかりません。ダウンロードを試みます..." -ForegroundColor Yellow
                Write-Host "  不足: $($missingPipWheels -join ', ')"

                Invoke-GetPackagesForPipInstall -ShortName $packageConfig.ShortName -InstallDir $InstallDir -ScriptDir $ScriptDir

                $missingPipWheels = @(Test-PipWheelPackages -DirectoryPath $pipPackagesDir -PackageNames $requiredPipWheels)
                if ($missingPipWheels.Count -gt 0) {
                    Write-Host "Error: pip wheel files not found for '$($packageConfig.ShortName)': $($missingPipWheels -join ', ')" -ForegroundColor Red
                    Write-Host "Please run: .\subscripts\Get-Packages.ps1 -PackageShortNames $($packageConfig.ShortName)" -ForegroundColor Yellow
                    Write-Host ""
                    continue
                }
            }
        }

        $result = Invoke-ExtractStrategy `
            -PackageConfig $packageConfig `
            -ArchiveFile "" `
            -BinDir $InstallDir `
            -ScriptDir $ScriptDir `
            -PackagesDir $packagesDir

        if ($result) {
            $successCount++
            $successfulPackages += $packageConfig
        }

        Write-Host ""
        continue
    }

    # packages フォルダ内でアーカイブファイルを検索
    $archiveFiles = Get-ChildItem -Path $packagesDir -File | Where-Object { $_.Name -match $archivePattern }

    if ($archiveFiles.Count -eq 0) {
        Write-Host "Warning: Archive for $packageName not found (pattern: $archivePattern)" -ForegroundColor Yellow
        $totalCount++
        continue
    }

    # 最初にマッチしたファイルを使用
    $archiveFile = $archiveFiles[0].FullName
    $totalCount++

    # CopyToPackages 戦略の場合は、抽出処理は対象外
    if ($strategy -eq "CopyToPackages") {
        $successCount++
        $successfulPackages += $packageConfig
        continue
    }

    # パッケージを抽出
    $result = Invoke-ExtractStrategy `
        -PackageConfig $packageConfig `
        -ArchiveFile $archiveFile `
        -BinDir $InstallDir `
        -ScriptDir $ScriptDir `
        -PackagesDir $packagesDir

    if ($result) {
        $successCount++
        $successfulPackages += $packageConfig
    }

    Write-Host ""
}


Write-Host "Extraction Summary:"
Write-Host "Success: $successCount / $totalCount"

if ($successCount -ne $totalCount) {
    Write-Host ""
    Write-Host "Some packages failed to extract." -ForegroundColor Yellow
    Write-Host "Please check the error messages above."
}

$batchEnvironmentFailed = $false
$batchAppliedEnvVars = @{}
$batchEnvironmentFailedShortNames = @()
if ($Install -and (Get-Command Set-ComponentEnvVars -ErrorAction SilentlyContinue)) {
    foreach ($packageConfig in $successfulPackages) {
        $hasEnvConfig = $packageConfig.ContainsKey("EnvVars") -and $packageConfig.EnvVars.Count -gt 0
        $hasBrowserConfig = $packageConfig.ContainsKey("Browser") -and [string]$packageConfig.Browser -eq "Edge"
        if (-not ($hasEnvConfig -or $hasBrowserConfig)) {
            continue
        }

        try {
            $applied = Set-ComponentEnvVars -InstallDir $InstallDir -PackageConfig $packageConfig
            $batchAppliedEnvVars[$packageConfig.ShortName] = $applied
        } catch {
            $batchEnvironmentFailed = $true
            $batchEnvironmentFailedShortNames += $packageConfig.ShortName
            Write-Host "Error: Failed to configure environment for '$($packageConfig.ShortName)': $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

# Install オプションが指定されている場合
if ($Install) {
    Write-Host ""
    Write-Host "=== PATH Configuration ==="
    Write-Host ""

    # Python が正しくインストールされているかチェック
    $pythonExe = "$InstallDir\python-3.13\python.exe"
    if (Test-CommandExists "python") {
        Write-Host "Python is already available in PATH."
    } elseif (Test-Path $pythonExe) {
        Write-Host "Python executable found: $pythonExe"
    } else {
        Write-Host "Warning: Python executable not found at expected location: $pythonExe" -ForegroundColor Yellow
    }

    # ユーザー PATH に開発ツールのディレクトリを追加
    Sync-ManagedUserPath `
        -InstallDir $InstallDir `
        -Packages $Packages `
        -InstalledShortNames @($Packages | ForEach-Object { $_.ShortName }) `
        -IncludeBaseDir

    # パッケージ定義から環境変数を設定し、現在のプロセスへ同期
    $environmentNames = @("PATH")
    foreach ($packageEnvVars in $batchAppliedEnvVars.Values) {
        $environmentNames += @($packageEnvVars.Keys)
    }
    Sync-EnvironmentVariables -VariableNames ($environmentNames | Select-Object -Unique) | Out-Null

    if (Get-Command Invoke-PackageLifecycleScripts -ErrorAction SilentlyContinue) {
        foreach ($packageConfig in ($successfulPackages | Where-Object { $_.ContainsKey("RunPostInstallInBatch") -and $_.RunPostInstallInBatch -eq $true })) {
            Invoke-PackageLifecycleScripts `
                -PackageConfig $packageConfig `
                -Phase "Install" `
                -InstallDir $InstallDir `
                -ScriptDir $ScriptDir
        }
    }

    # マニフェストを生成/更新 (コンポーネントマネージャーへの移行用)
    if (Get-Command Read-Manifest -ErrorAction SilentlyContinue) {
        Write-Host ""
        Write-Host "Generating component manifest..."
        try {
            $manifest = Read-Manifest -InstallDir $InstallDir
            $processedShortNames = @($Packages | ForEach-Object { $_.ShortName })
            foreach ($processedShortName in $processedShortNames) {
                if ($manifest.components.ContainsKey($processedShortName)) {
                    $manifest.components.Remove($processedShortName)
                }
            }

            foreach ($pkg in $successfulPackages) {
                if ($batchEnvironmentFailedShortNames -contains $pkg.ShortName) {
                    continue
                }
                $detectFiles = if ($pkg.ContainsKey("DetectFiles")) { @($pkg.DetectFiles) } else { @() }
                $filesExist = if ($detectFiles.Count -gt 0) {
                    Test-ComponentFiles -InstallDir $InstallDir -DetectFiles $detectFiles
                } else { $true }

                if ($filesExist -or $pkg.ExtractStrategy -eq "CopyToPackages" -or $pkg.ExtractStrategy -eq "PipInstall" -or $pkg.ExtractStrategy -eq "NpmInstall") {
                    $pathDirsForPkg = if ($pkg.ContainsKey("PathDirs")) { @($pkg.PathDirs) } else { @() }
                    $envVarsForPkg = if ($batchAppliedEnvVars.ContainsKey($pkg.ShortName)) { $batchAppliedEnvVars[$pkg.ShortName] } elseif ($pkg.ContainsKey("EnvVars")) { $pkg.EnvVars } else { @{} }
                    $versionForPkg = if (Get-Command Resolve-PackageVersion -ErrorAction SilentlyContinue) {
                        Resolve-PackageVersion -PackageConfig $pkg -PackagesDir $packagesDir
                    } else {
                        if ($pkg.ContainsKey("Version")) { $pkg.Version } else { "" }
                    }
                    Add-ComponentToManifest `
                        -Manifest $manifest `
                        -ShortName $pkg.ShortName `
                        -Version $versionForPkg `
                        -ArchiveFile "(batch-install)" `
                        -Files @() `
                        -PathDirs $pathDirsForPkg `
                        -EnvVars $envVarsForPkg
                }
            }
            Write-Manifest -InstallDir $InstallDir -Manifest $manifest
            Write-Host "Component manifest saved."
        } catch {
            Write-Host "Warning: Failed to generate manifest: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    Write-Host ""
    if ($successCount -eq $totalCount -and -not $batchEnvironmentFailed) {
        Write-Host "Installation completed successfully!" -ForegroundColor Green
    } else {
        Write-Host "Installation completed with errors." -ForegroundColor Red
    }
    Write-Host "Note: To apply PATH changes to new terminals, restart your terminal."
    Write-Host ""
    Write-Host "Quick test commands:"
    Write-Host "  node --version"
    Write-Host "  python --version"
    Write-Host "  dotnet --version"
    Write-Host "  git --version"
    if ($successCount -ne $totalCount -or $batchEnvironmentFailed) {
        exit 1
    }
} else {
    Write-Host ""
    Write-Host "Extraction completed." -ForegroundColor Green
    Write-Host ""
    Write-Host "To add tools to PATH, run:"
    Write-Host "  .\Setup-Bin.ps1 -Install"
}

} finally {
    Stop-BusySignal
}
