# ComponentSource.ps1
# インストール対象ソースファイルの配置確認および不足時の取得処理

function Get-PackagesDirectory {
    param([string]$ScriptDir)

    if (-not [string]::IsNullOrWhiteSpace($ScriptDir)) {
        $repoDir = Split-Path -Parent $ScriptDir
        $candidate = Join-Path $repoDir "packages"
        return $candidate
    }

    return "packages"
}

function Find-ComponentArchiveFile {
    param(
        [hashtable]$PackageConfig,
        [string]$PackagesDir
    )

    if ([string]::IsNullOrWhiteSpace($PackagesDir) -or -not (Test-Path -LiteralPath $PackagesDir -PathType Container)) {
        return $null
    }

    $archivePattern = if ($PackageConfig.ContainsKey("ArchivePattern")) { [string]$PackageConfig.ArchivePattern } else { "" }
    if (-not [string]::IsNullOrWhiteSpace($archivePattern)) {
        $archiveFiles = @(Get-ChildItem -Path $PackagesDir -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match $archivePattern })
        if ($archiveFiles.Count -gt 0) {
            return $archiveFiles[0].FullName
        }
    }

    $baseFileName = Get-PackageBaseFileName -Package $PackageConfig
    $downloadFileName = ""
    if (-not [string]::IsNullOrWhiteSpace($baseFileName)) {
        $downloadFileName = Get-PackageDownloadFileName -Package $PackageConfig
    }

    if (-not [string]::IsNullOrWhiteSpace($baseFileName) -and $baseFileName -ne $downloadFileName) {
        $candidatePath = Join-Path $PackagesDir $baseFileName
        if (Test-Path -LiteralPath $candidatePath -PathType Leaf) {
            return $candidatePath
        }
    }

    return $null
}

function Test-VsBuildToolsSourceAvailable {
    param(
        [hashtable]$PackageConfig,
        [string]$PackagesDir
    )

    $downloadsPath = Join-Path $PackagesDir "vsbt"
    $channelPath = Join-Path $downloadsPath "channel_release.json"
    $manifestPath = Join-Path $downloadsPath "manifest_release.json"
    if (-not (Test-Path -LiteralPath $channelPath -PathType Leaf)) {
        return $false
    }
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        return $false
    }

    $target = "x64"
    if ($PackageConfig.ContainsKey("VSBTConfig") -and $PackageConfig.VSBTConfig -and $PackageConfig.VSBTConfig.ContainsKey("Target")) {
        $targetValue = [string]$PackageConfig.VSBTConfig.Target
        if (-not [string]::IsNullOrWhiteSpace($targetValue)) {
            $target = $targetValue
        }
    }

    $payloadDir = Join-Path $downloadsPath $target
    if (-not (Test-Path -LiteralPath $payloadDir -PathType Container)) {
        return $false
    }

    $payloadFiles = @(Get-ChildItem -LiteralPath $payloadDir -Recurse -File -ErrorAction SilentlyContinue)
    return ($payloadFiles.Count -gt 0)
}

function Test-ComponentSourceAvailable {
    param(
        [hashtable]$PackageConfig,
        [string]$PackagesDir
    )

    if ($null -eq $PackageConfig) {
        return $false
    }

    $strategy = if ($PackageConfig.ContainsKey("ExtractStrategy")) { [string]$PackageConfig.ExtractStrategy } else { "" }

    if ($strategy -eq "NpmInstall") {
        $npmCacheStatus = Get-NpmCacheStatus -PackageConfig $PackageConfig -PackagesDir $PackagesDir
        return [bool]$npmCacheStatus.IsValid
    }

    if ($strategy -eq "PipInstall") {
        $pipPackagesDir = Join-Path $PackagesDir "pip-packages"
        $requiredPipWheels = Get-PipWheelPackageNames -PackageConfigs @($PackageConfig)
        $missingPipWheels = @(Test-PipWheelPackages -DirectoryPath $pipPackagesDir -PackageNames $requiredPipWheels)
        return ($missingPipWheels.Count -eq 0)
    }

    if ($strategy -eq "VSBuildTools") {
        return (Test-VsBuildToolsSourceAvailable -PackageConfig $PackageConfig -PackagesDir $PackagesDir)
    }

    $archiveFile = Find-ComponentArchiveFile -PackageConfig $PackageConfig -PackagesDir $PackagesDir
    if ([string]::IsNullOrWhiteSpace($archiveFile)) {
        return $false
    }

    $shortName = if ($PackageConfig.ContainsKey("ShortName")) { [string]$PackageConfig.ShortName } else { "" }
    if ($strategy -eq "CopyToPackages" -or $shortName -eq "get-pip") {
        $pipPackagesDir = Join-Path $PackagesDir "pip-packages"
        $corePackages = @(Get-PipWheelPackageNames -IncludeCorePackages)
        $missingCoreWheels = @(Test-PipWheelPackages -DirectoryPath $pipPackagesDir -PackageNames $corePackages)
        if ($missingCoreWheels.Count -gt 0) {
            return $false
        }
    }

    return $true
}

function Test-ComponentTreeSourceAvailable {
    param(
        [string]$ShortName,
        [array]$Packages,
        [string]$PackagesDir
    )

    $order = @(Resolve-Dependencies -ShortName $ShortName -Packages $Packages)
    if ($order.Count -eq 0) {
        return $false
    }

    foreach ($name in $order) {
        $package = Get-PackageByShortName -ShortName $name -Packages $Packages
        if ($null -eq $package) {
            return $false
        }
        if (-not (Test-ComponentSourceAvailable -PackageConfig $package -PackagesDir $PackagesDir)) {
            return $false
        }
    }

    return $true
}

function Write-ComponentSourceMissing {
    param(
        [string]$ShortName,
        [string]$PackagesDir,
        [string]$Detail = ""
    )

    if (-not [string]::IsNullOrWhiteSpace($Detail)) {
        Write-Host "    Error: $Detail" -ForegroundColor Red
    }

    if (Test-DevbinOfflineMode -PackagesDir $PackagesDir) {
        Write-Host "    packages\OFFLINE があるため、不足資材の取得はしません。" -ForegroundColor Yellow
        Write-Host "    不足している資材を packages に置いてから再実行してください。" -ForegroundColor Yellow
        return
    }

    Write-Host "    Please run: .\subscripts\Get-Packages.ps1 -PackageShortNames $ShortName" -ForegroundColor Yellow
}

# 不足しているパッケージアーカイブやキャッシュを取得します。
# パッケージ取得スクリプトと共通の Invoke-PackageAcquisition を経由して取得します。
function Invoke-PackageAcquisitionForShortNames {
    param(
        [string[]]$ShortNames,
        [string]$InstallDir,
        [string]$ScriptDir,
        [array]$Packages = @(),
        [switch]$WithInstalledPython
    )

    $context = New-DevbinContext -InstallDir $InstallDir -SubscriptsDir $ScriptDir
    $originalPath = $env:PATH
    # Python のインストール先ディレクトリはパッケージ定義の TargetDirectory から取得します。
    $pythonDir = Get-PythonDirectory -Packages $Packages -InstallDir $InstallDir
    $pythonScriptsDir = if ([string]::IsNullOrWhiteSpace($pythonDir)) { "" } else { Join-Path $pythonDir "Scripts" }

    try {
        # インストール済みの Python を使用して wheel を取得できるよう、環境変数 PATH の先頭に追加します。
        if ($WithInstalledPython -and -not [string]::IsNullOrWhiteSpace($pythonDir) -and (Test-Path (Join-Path $pythonDir "python.exe"))) {
            $pathEntries = @($pythonDir, $pythonScriptsDir) | Where-Object { Test-Path $_ }
            if ($pathEntries.Count -gt 0) {
                $env:PATH = ($pathEntries -join ';') + ";" + $env:PATH
            }
        }

        Write-Host "    ダウンロード対象: $($ShortNames -join ', ')"
        $result = Invoke-PackageAcquisition -Packages $Packages -Context $context -ShortNames $ShortNames
        if (-not $result.Success) {
            foreach ($message in $result.Messages) {
                Write-Host "    $message" -ForegroundColor Yellow
            }
        }
        return $result.Success
    } finally {
        $env:PATH = $originalPath
    }
}

# インストールに必要なソースファイル (アーカイブ、npm キャッシュ、pip wheel) を検証・準備します。
# ファイルが存在しない場合は自動取得を試行し、取得できない場合は Success = $false を返します。
function Resolve-ComponentSource {
    param(
        [string]$ShortName,
        [hashtable]$PackageConfig,
        [array]$Packages,
        [string]$InstallDir,
        [string]$ScriptDir,
        [string]$PackagesDir
    )

    $archiveFile = $null
    $result = [PSCustomObject]@{
        Success     = $false
        ArchiveFile = $null
    }
    $offline = Test-DevbinOfflineMode -PackagesDir $PackagesDir
    $strategy = if ($PackageConfig.ContainsKey("ExtractStrategy")) { [string]$PackageConfig.ExtractStrategy } else { "" }

    if ($strategy -eq "NpmInstall") {
        $npmCacheStatus = Get-NpmCacheStatus -PackageConfig $PackageConfig -PackagesDir $PackagesDir
        if (-not $npmCacheStatus.IsValid) {
            Write-Host "  npm パッケージアーカイブが見つかりません。" -ForegroundColor Yellow
            Write-Host "    不足: $($npmCacheStatus.Missing -join ', ')"
            if ($npmCacheStatus.Invalid.Count -gt 0) {
                Write-Host "    不正: $($npmCacheStatus.Invalid -join ', ')"
            }

            if ($offline) {
                Write-ComponentSourceMissing -ShortName $ShortName -PackagesDir $PackagesDir
                return $result
            }

            Write-Host "  ダウンロードを試みます..." -ForegroundColor Yellow
            Invoke-PackageAcquisitionForShortNames -ShortNames @($ShortName) -InstallDir $InstallDir -ScriptDir $ScriptDir -Packages $Packages | Out-Null

            $npmCacheStatus = Get-NpmCacheStatus -PackageConfig $PackageConfig -PackagesDir $PackagesDir
            if (-not $npmCacheStatus.IsValid) {
                Write-Host "      Missing: $($npmCacheStatus.Missing -join ', ')" -ForegroundColor Red
                Write-Host "      Invalid: $($npmCacheStatus.Invalid -join ', ')" -ForegroundColor Red
                Write-ComponentSourceMissing -ShortName $ShortName -PackagesDir $PackagesDir -Detail "npm package cache is not valid for '$ShortName'"
                return $result
            }
        }
    }
    elseif ($strategy -eq "PipInstall") {
        $pipPackagesDir = Join-Path $PackagesDir "pip-packages"
        $requiredPipWheels = Get-PipWheelPackageNames -PackageConfigs @($PackageConfig)
        $missingPipWheels = @(Test-PipWheelPackages -DirectoryPath $pipPackagesDir -PackageNames $requiredPipWheels)

        if ($missingPipWheels.Count -gt 0) {
            Write-Host "  pip wheel ファイルが見つかりません。" -ForegroundColor Yellow
            Write-Host "    不足: $($missingPipWheels -join ', ')"

            if ($offline) {
                Write-ComponentSourceMissing -ShortName $ShortName -PackagesDir $PackagesDir
                return $result
            }

            Write-Host "  ダウンロードを試みます..." -ForegroundColor Yellow
            Invoke-PackageAcquisitionForShortNames -ShortNames @($ShortName) -InstallDir $InstallDir -ScriptDir $ScriptDir -Packages $Packages -WithInstalledPython | Out-Null

            $missingPipWheels = @(Test-PipWheelPackages -DirectoryPath $pipPackagesDir -PackageNames $requiredPipWheels)
            if ($missingPipWheels.Count -gt 0) {
                Write-ComponentSourceMissing -ShortName $ShortName -PackagesDir $PackagesDir -Detail "pip wheel files not found for '$ShortName': $($missingPipWheels -join ', ')"
                return $result
            }
        }
    }
    elseif ($strategy -eq "VSBuildTools") {
        if ($offline -and -not (Test-VsBuildToolsSourceAvailable -PackageConfig $PackageConfig -PackagesDir $PackagesDir)) {
            Write-ComponentSourceMissing -ShortName $ShortName -PackagesDir $PackagesDir -Detail "VS Build Tools cache not found for '$ShortName'"
            return $result
        }
    }
    else {
        $archiveFile = Find-ComponentArchiveFile -PackageConfig $PackageConfig -PackagesDir $PackagesDir
        if (-not [string]::IsNullOrWhiteSpace($archiveFile)) {
            $archivePattern = if ($PackageConfig.ContainsKey("ArchivePattern")) { [string]$PackageConfig.ArchivePattern } else { "" }
            $leafName = Split-Path $archiveFile -Leaf
            if (-not [string]::IsNullOrWhiteSpace($archivePattern) -and $leafName -notmatch $archivePattern) {
                Write-Host "    Warning: ArchivePattern に一致しないため元ファイル名へフォールバックします: $leafName" -ForegroundColor Yellow
            }
        } else {
            if ($offline) {
                Write-ComponentSourceMissing -ShortName $ShortName -PackagesDir $PackagesDir -Detail "Archive not found for '$ShortName' (pattern: $($PackageConfig.ArchivePattern))"
                return $result
            }

            Write-Host "  アーカイブが見つかりません。ダウンロードを試みます..."
            $resolution = Resolve-DependencyOrder -ShortNames @($ShortName) -Packages $Packages
            if (-not $resolution.Success) {
                foreach ($message in $resolution.Errors) {
                    Write-Host "    Error: $message" -ForegroundColor Red
                }
                return $result
            }
            $downloadTargets = @($resolution.Order | Select-Object -Unique)
            if (-not $downloadTargets -or $downloadTargets.Count -eq 0) {
                $downloadTargets = @($ShortName)
            }

            Invoke-PackageAcquisitionForShortNames -ShortNames $downloadTargets -InstallDir $InstallDir -ScriptDir $ScriptDir -Packages $Packages | Out-Null

            $archiveFile = Find-ComponentArchiveFile -PackageConfig $PackageConfig -PackagesDir $PackagesDir
            if ([string]::IsNullOrWhiteSpace($archiveFile)) {
                Write-ComponentSourceMissing -ShortName $ShortName -PackagesDir $PackagesDir -Detail "Archive not found for '$ShortName' (pattern: $($PackageConfig.ArchivePattern))"
                return $result
            }
        }
    }

    $result.Success = $true
    $result.ArchiveFile = $archiveFile
    return $result
}
