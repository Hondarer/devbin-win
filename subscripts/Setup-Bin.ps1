# 開発ツール セットアップ スクリプト
# 開発ツールの抽出、インストール、またはアンインストールを行う

param(
    [string]$InstallDir = ".\bin",
    [switch]$Extract,
    [switch]$Install,
    [switch]$Uninstall
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

# パッケージ設定を読み込む
$PackagesConfigPath = Join-Path $ScriptDir "config\packages.psd1"
$PackagesConfig = Invoke-Expression (Get-Content $PackagesConfigPath -Raw)
$Packages = $PackagesConfig.Packages

# オプションが指定されていない場合は使用方法を表示
if (-not ($Extract -or $Install -or $Uninstall)) {
    Write-Host "Development Tools Setup Script"
    Write-Host "================================"
    Write-Host ""
    Write-Host "Usage:"
    Write-Host "  .\Setup-Bin.ps1 -Extract [-InstallDir <path>]    # Extract tools only"
    Write-Host "  .\Setup-Bin.ps1 -Install [-InstallDir <path>]    # Extract tools and add to PATH"
    Write-Host "  .\Setup-Bin.ps1 -Uninstall [-InstallDir <path>]  # Remove tools and clean PATH"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -InstallDir <path>  Installation directory (default: .\bin)"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\Setup-Bin.ps1 -Extract                         # Extract to .\bin"
    Write-Host "  .\Setup-Bin.ps1 -Install -InstallDir C:\Tools    # Install to C:\Tools"
    Write-Host "  .\Setup-Bin.ps1 -Uninstall                       # Uninstall from .\bin"
    exit 0
}

# 追加 / 削除すべき PATH ディレクトリを取得する
function Get-PathDirectories {
    param([string]$BaseDir)

    $pathDirs = @(
        $BaseDir,
        "$BaseDir\jdk-21\bin",
        "$BaseDir\graphviz",
        "$BaseDir\python-3.13",
        "$BaseDir\dotnet10sdk",
        "$BaseDir\git",
        "$BaseDir\git\bin",
        "$BaseDir\git\cmd",
        "$BaseDir\vscode\bin",
        "$BaseDir\OpenCppCoverage",
        "$BaseDir\ReportGenerator"
    )

    return $pathDirs
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
    $pathDirs = Get-PathDirectories -BaseDir $InstallDir
    Remove-FromUserPath -Directories $pathDirs

    # DOTNET 環境変数を削除
    Write-Host ""
    Write-Host "Removing .NET environment variables..."

    [Environment]::SetEnvironmentVariable("DOTNET_HOME", $null, "User")
    Write-Host "  Removed DOTNET_HOME"

    [Environment]::SetEnvironmentVariable("DOTNET_CLI_TELEMETRY_OPTOUT", $null, "User")
    Write-Host "  Removed DOTNET_CLI_TELEMETRY_OPTOUT"

    # PlantUML 環境変数を削除
    Write-Host ""
    Write-Host "Removing PlantUML environment variables..."

    [Environment]::SetEnvironmentVariable("PLANTUML_HOME", $null, "User")
    Write-Host "  Removed PLANTUML_HOME"

    # 環境変数を現在のプロセスに同期
    Sync-EnvironmentVariables -VariableNames @("PATH", "DOTNET_HOME", "DOTNET_CLI_TELEMETRY_OPTOUT", "PLANTUML_HOME") | Out-Null

    # 完全アンインストールの確認
    try {
        Invoke-CompleteUninstall -InstallDirectory $InstallDir | Out-Null
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
Sync-EnvironmentVariables -VariableNames @("PATH", "PYTHONHOME", "PYTHONPATH", "DOTNET_HOME", "DOTNET_CLI_TELEMETRY_OPTOUT", "PLANTUML_HOME") | Out-Null
Write-Host ""

# 絶対パスに変換
$absoluteInstallDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($InstallDir)
$InstallDir = $absoluteInstallDir

Write-Host "Installation directory: $InstallDir"
Write-Host ""

# packages ディレクトリをチェック
$packagesDir = "packages"
if (!(Test-Path $packagesDir)) {
    New-Item -ItemType Directory -Path $packagesDir | Out-Null
    Write-Host "Created packages directory."
}

# 必要なパッケージファイルが存在するかチェック
$missingPackages = @()
foreach ($packageConfig in $Packages) {
    # VSBuildTools は戦略内でダウンロードされるためスキップ
    if ($packageConfig.ExtractStrategy -eq "VSBuildTools") {
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
        & $getPackagesScript
        if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) {
            Write-Host "Warning: Package download completed with errors." -ForegroundColor Yellow
        }
        Write-Host ""
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
    $pathDirsToClean = Get-PathDirectories -BaseDir $InstallDir
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
            -ScriptDir $ScriptDir

        if ($result) {
            $successCount++
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
        continue
    }

    # パッケージを抽出
    $result = Invoke-ExtractStrategy `
        -PackageConfig $packageConfig `
        -ArchiveFile $archiveFile `
        -BinDir $InstallDir `
        -ScriptDir $ScriptDir

    if ($result) {
        $successCount++
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
    $pathDirs = Get-PathDirectories -BaseDir $InstallDir
    Add-ToUserPath -Directories $pathDirs

    # .NET 環境変数を設定
    Write-Host ""
    Write-Host "Setting .NET environment variables..."

    $dotnetHome = Join-Path $InstallDir "dotnet10sdk"
    [Environment]::SetEnvironmentVariable("DOTNET_HOME", $dotnetHome, "User")
    Write-Host "  Set DOTNET_HOME=$dotnetHome"

    [Environment]::SetEnvironmentVariable("DOTNET_CLI_TELEMETRY_OPTOUT", "1", "User")
    Write-Host "  Set DOTNET_CLI_TELEMETRY_OPTOUT=1"

    # PlantUML 環境変数を設定
    Write-Host ""
    Write-Host "Setting PlantUML environment variables..."

    $plantumlHome = $InstallDir
    [Environment]::SetEnvironmentVariable("PLANTUML_HOME", $plantumlHome, "User")
    Write-Host "  Set PLANTUML_HOME=$plantumlHome"

    # 環境変数を現在のプロセスに同期
    Sync-EnvironmentVariables -VariableNames @("PATH", "DOTNET_HOME", "DOTNET_CLI_TELEMETRY_OPTOUT", "PLANTUML_HOME") | Out-Null

    Write-Host ""
    Write-Host "Installation completed successfully!" -ForegroundColor Green
    Write-Host "Note: To apply PATH changes to new terminals, restart your terminal."
    Write-Host ""
    Write-Host "Quick test commands:"
    Write-Host "  node --version"
    Write-Host "  python --version"
    Write-Host "  dotnet --version"
    Write-Host "  git --version"
} else {
    Write-Host ""
    Write-Host "Extraction completed." -ForegroundColor Green
    Write-Host ""
    Write-Host "To add tools to PATH, run:"
    Write-Host "  .\Setup-Bin.ps1 -Install"
}
