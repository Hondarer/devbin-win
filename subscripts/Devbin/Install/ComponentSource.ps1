# ComponentSource.ps1
# 導入に必要なファイルの配置場所と、不足時の取得を扱う

function Get-PackagesDirectory {
    param([string]$ScriptDir)

    if (-not [string]::IsNullOrWhiteSpace($ScriptDir)) {
        $repoDir = Split-Path -Parent $ScriptDir
        $candidate = Join-Path $repoDir "packages"
        return $candidate
    }

    return "packages"
}

# 導入中に不足したキャッシュを取得する
# 取得スクリプトと同じ Invoke-PackageAcquisition を通す
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
    # Python の配置先はパッケージ定義の TargetDirectory から取得する
    $pythonDir = Get-PythonDirectory -Packages $Packages -InstallDir $InstallDir
    $pythonScriptsDir = if ([string]::IsNullOrWhiteSpace($pythonDir)) { "" } else { Join-Path $pythonDir "Scripts" }

    try {
        # 導入済みの Python を使用して wheel を取得できるよう PATH の先頭へ配置する
        if ($WithInstalledPython -and -not [string]::IsNullOrWhiteSpace($pythonDir) -and (Test-Path (Join-Path $pythonDir "python.exe"))) {
            $pathEntries = @($pythonDir, $pythonScriptsDir) | Where-Object { Test-Path $_ }
            if ($pathEntries.Count -gt 0) {
                $env:PATH = ($pathEntries -join ';') + ";" + $env:PATH
            }
        }

        Write-Host "  ダウンロード対象: $($ShortNames -join ', ')"
        $result = Invoke-PackageAcquisition -Packages $Packages -Context $context -ShortNames $ShortNames
        if (-not $result.Success) {
            foreach ($message in $result.Messages) {
                Write-Host "  $message" -ForegroundColor Yellow
            }
        }
        return $result.Success
    } finally {
        $env:PATH = $originalPath
    }
}

# 導入に必要なファイル (アーカイブ、npm キャッシュ、pip wheel) を用意する
# 見つからない場合は取得を試み、それでも揃わなければ Success = $false を返す
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

    if ($PackageConfig.ExtractStrategy -eq "NpmInstall") {
        $npmCacheStatus = Get-NpmCacheStatus -PackageConfig $PackageConfig -PackagesDir $PackagesDir
        if (-not $npmCacheStatus.IsValid) {
            Write-Host "  npm パッケージアーカイブが見つかりません。ダウンロードを試みます..." -ForegroundColor Yellow
            Write-Host "  不足: $($npmCacheStatus.Missing -join ', ')"
            if ($npmCacheStatus.Invalid.Count -gt 0) {
                Write-Host "  不正: $($npmCacheStatus.Invalid -join ', ')"
            }

            Invoke-PackageAcquisitionForShortNames -ShortNames @($ShortName) -InstallDir $InstallDir -ScriptDir $ScriptDir -Packages $Packages | Out-Null

            $npmCacheStatus = Get-NpmCacheStatus -PackageConfig $PackageConfig -PackagesDir $PackagesDir
            if (-not $npmCacheStatus.IsValid) {
                Write-Host "Error: npm package cache is not valid for '$ShortName'" -ForegroundColor Red
                Write-Host "  Missing: $($npmCacheStatus.Missing -join ', ')" -ForegroundColor Red
                Write-Host "  Invalid: $($npmCacheStatus.Invalid -join ', ')" -ForegroundColor Red
                Write-Host "Please run: .\subscripts\Get-Packages.ps1 -PackageShortNames $ShortName" -ForegroundColor Yellow
                return $result
            }
        }
    }
    elseif ($PackageConfig.ExtractStrategy -eq "PipInstall") {
        $pipPackagesDir = Join-Path $PackagesDir "pip-packages"
        $requiredPipWheels = Get-PipWheelPackageNames -PackageConfigs @($PackageConfig)
        $missingPipWheels = @(Test-PipWheelPackages -DirectoryPath $pipPackagesDir -PackageNames $requiredPipWheels)

        if ($missingPipWheels.Count -gt 0) {
            Write-Host "  pip wheel ファイルが見つかりません。ダウンロードを試みます..." -ForegroundColor Yellow
            Write-Host "  不足: $($missingPipWheels -join ', ')"

            Invoke-PackageAcquisitionForShortNames -ShortNames @($ShortName) -InstallDir $InstallDir -ScriptDir $ScriptDir -Packages $Packages -WithInstalledPython | Out-Null

            $missingPipWheels = @(Test-PipWheelPackages -DirectoryPath $pipPackagesDir -PackageNames $requiredPipWheels)
            if ($missingPipWheels.Count -gt 0) {
                Write-Host "Error: pip wheel files not found for '$ShortName': $($missingPipWheels -join ', ')" -ForegroundColor Red
                Write-Host "Please run: .\subscripts\Get-Packages.ps1 -PackageShortNames $ShortName" -ForegroundColor Yellow
                return $result
            }
        }
    }
    elseif ($PackageConfig.ExtractStrategy -ne "VSBuildTools" -and $PackageConfig.ExtractStrategy -ne "PipInstall") {
        # 保存ファイル名の判定は取得側 (Get-Packages) と同じ実装を使用する
        $baseFileName = Get-PackageBaseFileName -Package $PackageConfig
        $downloadFileName = ""
        if (-not [string]::IsNullOrWhiteSpace($baseFileName)) {
            $downloadFileName = Get-PackageDownloadFileName -Package $PackageConfig
        }

        $archiveFiles = Get-ChildItem -Path $PackagesDir -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match $PackageConfig.ArchivePattern }

        if ($archiveFiles -and $archiveFiles.Count -gt 0) {
            $archiveFile = $archiveFiles[0].FullName
        } else {
            $fallbackPath = $null
            if (-not [string]::IsNullOrWhiteSpace($baseFileName) -and $baseFileName -ne $downloadFileName) {
                $candidatePath = Join-Path $PackagesDir $baseFileName
                if (Test-Path $candidatePath -PathType Leaf) {
                    $fallbackPath = $candidatePath
                }
            }

            if ($fallbackPath) {
                $archiveFile = $fallbackPath
                Write-Host "  Warning: ArchivePattern に一致しないため元ファイル名へフォールバックします: $(Split-Path $fallbackPath -Leaf)" -ForegroundColor Yellow
            } else {
                # アーカイブが見つからない場合はダウンロードを試みる
                Write-Host "  アーカイブが見つかりません。ダウンロードを試みます..."
                $resolution = Resolve-DependencyOrder -ShortNames @($ShortName) -Packages $Packages
                if (-not $resolution.Success) {
                    foreach ($message in $resolution.Errors) {
                        Write-Host "Error: $message" -ForegroundColor Red
                    }
                    return $result
                }
                $downloadTargets = @($resolution.Order | Select-Object -Unique)
                if (-not $downloadTargets -or $downloadTargets.Count -eq 0) {
                    $downloadTargets = @($ShortName)
                }

                Invoke-PackageAcquisitionForShortNames -ShortNames $downloadTargets -InstallDir $InstallDir -ScriptDir $ScriptDir -Packages $Packages | Out-Null

                $archiveFiles = Get-ChildItem -Path $PackagesDir -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -match $PackageConfig.ArchivePattern }

                if ($archiveFiles -and $archiveFiles.Count -gt 0) {
                    $archiveFile = $archiveFiles[0].FullName
                } else {
                    Write-Host "Error: Archive not found for '$ShortName' (pattern: $($PackageConfig.ArchivePattern))" -ForegroundColor Red
                    return $result
                }
            }
        }
    }

    $result.Success = $true
    $result.ArchiveFile = $archiveFile
    return $result
}
