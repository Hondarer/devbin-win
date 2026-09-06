# Get-Packages.ps1
# packages ディレクトリにダウンロードするスクリプト

param(
    [switch]$Force = $false,
    [string[]]$PackageShortNames = @()
)

# スクリプトのディレクトリを取得
$ScriptDir = if ($PSScriptRoot) {
    $PSScriptRoot
} elseif ($MyInvocation.MyCommand.Path) {
    Split-Path -Parent $MyInvocation.MyCommand.Path
} else {
    Get-Location | Select-Object -ExpandProperty Path
}

$RepositoryRoot = Split-Path $ScriptDir -Parent
$PackagesRoot = Join-Path $RepositoryRoot "packages"

# Devbin モジュールを読み込む
$devbinModulePath = Join-Path $ScriptDir "Devbin"
try {
    Import-Module $devbinModulePath -Force -ErrorAction Stop
} catch {
    Write-Host "Error importing Devbin: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# パッケージ設定を読み込む
$DevbinContext = New-DevbinContext -SubscriptsDir $ScriptDir
$catalog = Import-PackageCatalog -Path $DevbinContext.ConfigPath
if (-not $catalog.Success) {
    Write-Host "Error: パッケージ定義に問題があります" -ForegroundColor Red
    foreach ($message in $catalog.Errors) {
        Write-Host "  $message" -ForegroundColor Red
    }
    exit 1
}
$Packages = $catalog.Packages

$npmCacheModulePath = Join-Path $ScriptDir "Setup-NpmCache.psm1"
if (-not (Test-Path $npmCacheModulePath)) {
    Write-Host "Error: Setup-NpmCache.psm1 not found at: $npmCacheModulePath" -ForegroundColor Red
    exit 1
}
try {
    Import-Module $npmCacheModulePath -Force -ErrorAction Stop
} catch {
    Write-Host "Error importing Setup-NpmCache: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

function Get-TargetPackages {
    param(
        [array]$AllPackages,
        [string[]]$RequestedShortNames
    )

    if (-not $RequestedShortNames -or $RequestedShortNames.Count -eq 0) {
        return @($AllPackages)
    }

    $targets = @()
    $seen = @{}

    foreach ($shortName in $RequestedShortNames) {
        if ([string]::IsNullOrWhiteSpace($shortName)) {
            continue
        }

        if ($seen.ContainsKey($shortName)) {
            continue
        }

        $package = $AllPackages | Where-Object { $_.ShortName -eq $shortName } | Select-Object -First 1
        if (-not $package) {
            throw "Package not found: $shortName"
        }

        $targets += $package
        $seen[$shortName] = $true
    }

    return $targets
}

try {
    $TargetPackages = Get-TargetPackages -AllPackages $Packages -RequestedShortNames $PackageShortNames
} catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# packages ディレクトリが存在しない場合は作成
if (-not (Test-Path $PackagesRoot)) {
    Write-Host "Creating packages directory..."
    New-Item -ItemType Directory -Path $PackagesRoot | Out-Null
}

# SourceForge の実際のダウンロード URL を取得
function Get-SourceForgeDownloadUrl {
    param([string]$Url)

    try {
        $ProgressPreference = 'SilentlyContinue'
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -ErrorAction Stop

        # meta refresh タグから実際のダウンロード URL を抽出
        if ($response.Content -match '<meta[^>]+http-equiv="refresh"[^>]+content="\d+;\s*url=([^"]+)"') {
            $downloadUrl = $matches[1]
            # HTML エンティティをデコード (&amp; -> &)
            $downloadUrl = $downloadUrl -replace '&amp;', '&'
            return $downloadUrl
        }

        # ダイレクトダウンロード URL を構築
        if ($Url -match 'sourceforge\.net/projects/([^/]+)/files/(.+)/download') {
            $project = $matches[1]
            $filePath = $matches[2]
            return "https://downloads.sourceforge.net/project/$project/$filePath"
        }

        return $Url
    }
    catch {
        return $Url
    }
}

# 共通のダウンロード関数
function Get-File {
    param(
        [string]$Url,
        [string]$OutputPath,
        [hashtable]$Headers = @{}
    )

    $fileName = Split-Path $OutputPath -Leaf

    # ファイルが既に存在する場合はスキップ (-Force オプションが指定されていない場合)
    if ((Test-Path $OutputPath) -and -not $Force) {
        Write-Host "  $fileName already exists. Skipping."
        return $true
    }

    # 現在の設定を保存
    $originalProgressPreference = $ProgressPreference
    try {
        Write-Host "  Downloading $fileName..."

        # プログレスバーを無効化
        # Invoke-WebRequest のプログレスバーは性能に問題あり
        $ProgressPreference = 'SilentlyContinue'

        # SourceForge の URL の場合は実際のダウンロード URL を取得
        $downloadUrl = $Url
        if ($Url -match 'sourceforge\.net/projects/.+/files/.+/download') {
            $downloadUrl = Get-SourceForgeDownloadUrl -Url $Url
            Write-Host "    Resolved to: $downloadUrl"
        }

        $requestArgs = @{
            Uri = $downloadUrl
            OutFile = $OutputPath
            UseBasicParsing = $true
            ErrorAction = 'Stop'
        }

        if ($Headers -and $Headers.Count -gt 0) {
            $requestArgs.Headers = $Headers
        }

        Invoke-WebRequest @requestArgs

        if (Test-Path $OutputPath) {
            $fileSize = (Get-Item $OutputPath).Length
            $fileSizeMB = [math]::Round($fileSize / 1MB, 2)
            Write-Host "  $fileName download completed. (${fileSizeMB} MB)"
            return $true
        } else {
            throw "Download failed"
        }
    }
    catch {
        Write-Host "  $fileName download failed: $($_.Exception.Message)" -ForegroundColor Red

        # 失敗した場合は部分的にダウンロードされたファイルを削除
        if (Test-Path $OutputPath) {
            Remove-Item $OutputPath -Force
        }

        return $false
    }
    finally {
        # 設定を復元
        $ProgressPreference = $originalProgressPreference
    }
}

function Remove-OldPackageFiles {
    param(
        [hashtable]$Package,
        [string]$CurrentFileName,
        [string]$PackagesDir = "packages"
    )

    if (-not (Test-Path $PackagesDir)) {
        return
    }

    $oldFiles = Get-ChildItem -Path $PackagesDir -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -match $Package.ArchivePattern -and $_.Name -ne $CurrentFileName
        }

    if ($oldFiles) {
        Write-Host "  Old package cleanup for $($Package.ShortName): $($oldFiles.Count) file(s)"
        Write-Host "    Current package file: $CurrentFileName"
    }

    foreach ($oldFile in $oldFiles) {
        try {
            Write-Host "    Removing old package file: $($oldFile.Name)"
            Remove-Item -LiteralPath $oldFile.FullName -Force -ErrorAction Stop
            Write-Host "  Removed old package file: $($oldFile.Name)"
        } catch {
            Write-Host "  Warning: Failed to remove old package file $($oldFile.Name): $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    $baseFileName = Get-PackageBaseFileName -Package $Package
    if (-not [string]::IsNullOrWhiteSpace($baseFileName) -and $baseFileName -ne $CurrentFileName) {
        $baseFilePath = Join-Path $PackagesDir $baseFileName
        if (Test-Path $baseFilePath -PathType Leaf) {
            try {
                Write-Host "  Original package file cleanup for $($Package.ShortName): $baseFileName"
                Remove-Item -LiteralPath $baseFilePath -Force -ErrorAction Stop
                Write-Host "  Removed base package file: $baseFileName"
            } catch {
                Write-Host "  Warning: Failed to remove base package file ${baseFileName}: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
    }
}

function Save-PipWheelPackages {
    param(
        [string]$PythonCommandPath,
        [string]$DestinationDir,
        [string]$TargetPythonVersion = "",
        [string[]]$PackageNames = @()
    )

    if (!(Test-Path $DestinationDir)) {
        New-Item -ItemType Directory -Path $DestinationDir -Force | Out-Null
    }

    $downloadPackages = @($PackageNames | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    if ($downloadPackages.Count -eq 0) {
        $downloadPackages = @("pip", "setuptools", "wheel", "packaging")
    }

    $args = @("-m", "pip", "download", "--only-binary=:all:")
    if (-not [string]::IsNullOrWhiteSpace($TargetPythonVersion)) {
        $args += @("--python-version", $TargetPythonVersion, "--implementation", "cp", "--platform", "win_amd64")
    }

    $args += $downloadPackages
    $args += @("--dest", $DestinationDir)

    & $PythonCommandPath @args | Out-Host
    return $LASTEXITCODE
}

function Save-NpmPackageArchives {
    param(
        [string]$NpmCommandPath,
        [string]$DestinationDir,
        [array]$PackagesToPack
    )

    if (-not $PackagesToPack -or $PackagesToPack.Count -eq 0) {
        return 0
    }

    $exitCode = 0
    foreach ($pkg in $PackagesToPack) {
        Write-Host "  Preparing npm offline cache: $($pkg.ShortName)"
        $cacheExitCode = Save-NpmPackageCache `
            -NpmCommandPath $NpmCommandPath `
            -PackagesDir (Split-Path $DestinationDir -Parent) `
            -PackageConfig $pkg `
            -Force:$Force
        if ($cacheExitCode -ne 0) {
            $exitCode = $cacheExitCode
        }
    }

    return $exitCode
}

# Visual Studio Build Tools のダウンロード処理
$vsbtPackage = $TargetPackages | Where-Object { $_.ExtractStrategy -eq "VSBuildTools" } | Select-Object -First 1
if ($vsbtPackage) {
    Write-Host ""
    Write-Host "=== Visual Studio Build Tools Download ===" -ForegroundColor Cyan
    Write-Host ""

    $vsbtScript = Join-Path $ScriptDir "Setup-VSBT.ps1"
    if (-not (Test-Path $vsbtScript)) {
        Write-Host "Error: Setup-VSBT.ps1 not found at: $vsbtScript" -ForegroundColor Red
        exit 1
    }

    $vsbtConfig = $vsbtPackage.VSBTConfig
    $params = @{
        MSVCVersion = $vsbtConfig.MSVCVersion
        SDKVersion = $vsbtConfig.SDKVersion
        Target = $vsbtConfig.Target
        HostArch = $vsbtConfig.HostArch
        DownloadOnly = $true
        AcceptLicense = $true
    }

    Write-Host "Executing Setup-VSBT.ps1 with parameters:"
    Write-Host "  MSVCVersion: $($params.MSVCVersion)"
    Write-Host "  SDKVersion: $($params.SDKVersion)"
    Write-Host "  Target: $($params.Target)"
    Write-Host "  HostArch: $($params.HostArch)"
    Write-Host ""

    & $vsbtScript @params

    if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) {
        Write-Host "Warning: Setup-VSBT.ps1 exited with code $LASTEXITCODE" -ForegroundColor Yellow
    }

    Write-Host ""
}

# npm / pip キャッシュ対象を packages.psd1 から取得
$npmInstallPackages = @($TargetPackages | Where-Object { $_.ExtractStrategy -eq "NpmInstall" })
$pipInstallPackages = @($TargetPackages | Where-Object { $_.ExtractStrategy -eq "PipInstall" })

# ダウンロード対象ファイルを packages.psd1 から取得
$downloads = @()
foreach ($package in $TargetPackages) {
    if ($package.DownloadUrl) {
        $downloads += [PSCustomObject]@{
            Package = $package
            Url = $package.DownloadUrl
            FileName = Get-PackageDownloadFileName -Package $package
        }
    }
}

if ($downloads.Count -eq 0 -and -not $vsbtPackage -and $npmInstallPackages.Count -eq 0 -and $pipInstallPackages.Count -eq 0) {
    Write-Host "Error: No download URLs found in package configuration." -ForegroundColor Red
    exit 1
}

# ダウンロード実行
Write-Host "=== File Download Started ==="
Write-Host "Downloading files to packages directory."
if ($PackageShortNames -and $PackageShortNames.Count -gt 0) {
    Write-Host "Selected packages: $((@($TargetPackages | ForEach-Object { $_.ShortName })) -join ', ')"
}
Write-Host "Total packages: $($downloads.Count)"

if ($Force) {
    Write-Host "Force download mode: overwriting existing files." -ForegroundColor Yellow
}

$successCount = 0
$totalCount = $downloads.Count
$overallExitCode = 0

foreach ($download in $downloads) {
    $url = $download.Url
    $fileName = $download.FileName
    $outputPath = Join-Path $PackagesRoot $fileName
    $headers = if ($download.Package.ContainsKey("DownloadHeaders")) { $download.Package.DownloadHeaders } else { @{} }

    if (Get-File -Url $url -OutputPath $outputPath -Headers $headers) {
        $successCount++
        Remove-OldPackageFiles -Package $download.Package -CurrentFileName $fileName -PackagesDir $PackagesRoot
    }

    Start-Sleep -Milliseconds 500
}

Write-Host "`nDownload Summary:"
Write-Host "Success: $successCount / $totalCount"

if ($successCount -eq $totalCount) {
    Write-Host "`nAll files downloaded successfully." -ForegroundColor Green

    # packages フォルダ内のすべてのファイルのブロック解除
    Write-Host "`nUnblocking downloaded files..."
    try {
        $allFiles = Get-ChildItem -Path $PackagesRoot -File -Recurse -ErrorAction SilentlyContinue
        if ($allFiles) {
            $allFiles | Unblock-File -ErrorAction SilentlyContinue
            Write-Host "Unblocked $($allFiles.Count) file(s)."
        }
    } catch {
        Write-Host "  Warning: Failed to unblock some files: $($_.Exception.Message)" -ForegroundColor Yellow
    }
} else {
    $failedCount = $totalCount - $successCount
    $overallExitCode = 1
    Write-Host "`n$failedCount file(s) failed to download." -ForegroundColor Yellow
    Write-Host "Please check your network connection and try again."
    Write-Host "Use the -Force option to forcefully re-download existing files."
}

# npm キャッシュの自動ダウンロード
if ($npmInstallPackages.Count -gt 0) {
    Write-Host ""
    Write-Host "=== npm Cache Download ===" -ForegroundColor Cyan
    Write-Host ""

    $npmCmd = Get-Command npm.cmd -ErrorAction SilentlyContinue
    if (-not $npmCmd) {
        $overallExitCode = 1
        Write-Host "Error: npm not found. npm cache preparation cannot be completed." -ForegroundColor Red
        Write-Host "Install Node.js/npm in the preparation environment and run Get-Packages.ps1 again."
    } else {
        $npmPackagesDir = Join-Path $PackagesRoot "npm-packages"
        $npmNames = @($npmInstallPackages | ForEach-Object { $_.ShortName })
        Write-Host "npm found. Preparing npm offline caches for: $($npmNames -join ', ')"

        try {
            $packExitCode = Save-NpmPackageArchives -NpmCommandPath $npmCmd.Source -DestinationDir $npmPackagesDir -PackagesToPack $npmInstallPackages
            if ($packExitCode -eq 0 -or $null -eq $packExitCode) {
                Write-Host "Successfully prepared npm offline caches at $npmPackagesDir"
            } else {
                $overallExitCode = 1
                Write-Host "Warning: Failed to prepare some npm package archives (exit code: $packExitCode)" -ForegroundColor Yellow
            }
        } catch {
            $overallExitCode = 1
            Write-Host "Warning: Failed to prepare npm package archives: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

# pip wheel ファイルの自動ダウンロード
$shouldDownloadPipWheels = $true
if ($PackageShortNames -and $PackageShortNames.Count -gt 0) {
    $targetShortNames = @($TargetPackages | ForEach-Object { $_.ShortName })
    $shouldDownloadPipWheels = ($targetShortNames -contains "python") -or ($targetShortNames -contains "get-pip") -or ($targetShortNames -contains "yamllint")
}

if (-not $shouldDownloadPipWheels) {
    exit $overallExitCode
}

Write-Host ""
Write-Host "=== Pip Wheel Download ===" -ForegroundColor Cyan
Write-Host ""

$pythonExe = Get-Command python.exe -ErrorAction SilentlyContinue
if (-not $pythonExe) {
    Write-Host "Python not found. Skipping wheel download."
    Write-Host "Wheel files will be downloaded during Setup-Bin.ps1 execution."
} else {
    Write-Host "Python found. Downloading pip wheel files..."

    $pipPackagesDir = Join-Path $PackagesRoot "pip-packages"

    try {
        # devbin の Python バージョンを packages.psd1 から取得
        $pythonPkg = $Packages | Where-Object { $_.ShortName -eq "python" } | Select-Object -First 1
        $targetPythonVersion = ""
        if ($pythonPkg -and $pythonPkg.Version) {
            $versionParts = ([string]$pythonPkg.Version) -split '\.'
            $targetPythonVersion = "$($versionParts[0]).$($versionParts[1])"
        }

        # pip download で依存を含む wheel ファイルを取得
        $pipWheelPackageNames = Get-PipWheelPackageNames -PackageConfigs $pipInstallPackages -IncludeCorePackages
        $pipWheelDownloadSpecs = Get-PipWheelDownloadSpecs -PackageConfigs $pipInstallPackages -IncludeCorePackages
        $downloadExitCode = Save-PipWheelPackages -PythonCommandPath $pythonExe.Source -DestinationDir $pipPackagesDir -TargetPythonVersion $targetPythonVersion -PackageNames $pipWheelDownloadSpecs
        $missingWheels = Test-PipWheelPackages -DirectoryPath $pipPackagesDir -PackageNames $pipWheelPackageNames

        if ($downloadExitCode -eq 0 -and $missingWheels.Count -eq 0) {
            Write-Host "Successfully downloaded wheel files to $pipPackagesDir"
        } elseif ($downloadExitCode -eq 0) {
            Write-Host "Warning: Wheel cache is missing required files: $($missingWheels -join ', ')" -ForegroundColor Yellow
            $overallExitCode = 1
        } else {
            Write-Host "Warning: Failed to download some wheel files (exit code: $downloadExitCode)" -ForegroundColor Yellow
            $overallExitCode = 1
        }
    } catch {
        $overallExitCode = 1
        Write-Host "Warning: Failed to download wheel files: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

exit $overallExitCode
