# PipPackage.ps1
# pip パッケージ名の正規化と wheel の検証
#
# Python の初期設定に必要な wheel (pip / setuptools / wheel / packaging) と、
# 追加パッケージに必要な wheel の違いは -IncludeCorePackages で表す。

# Python 初期設定に必要なコアパッケージ
$script:DevbinPipCorePackages = @("pip", "setuptools", "wheel", "packaging")

# PEP 503 に従って pip パッケージ名を正規化する
function Get-NormalizedPipPackageName {
    param([string]$Name)

    return (([string]$Name).Trim().ToLowerInvariant() -replace '[-_.]+', '-')
}

# パッケージ定義から、必要な pip パッケージ名 (版指定込み) を重複なく返す
# 重複判定は正規化後の名前で行う
function Get-PipWheelPackageNames {
    param(
        [array]$PackageConfigs = @(),
        [switch]$IncludeCorePackages
    )

    $packageNames = @()
    if ($IncludeCorePackages) {
        $packageNames += $script:DevbinPipCorePackages
    }

    foreach ($packageConfig in @($PackageConfigs)) {
        if ($null -eq $packageConfig) {
            continue
        }

        if ($packageConfig.ContainsKey("PipPackage") -and -not [string]::IsNullOrWhiteSpace([string]$packageConfig.PipPackage)) {
            $pipPackage = [string]$packageConfig.PipPackage
            $version = if ($packageConfig.ContainsKey("Version")) { [string]$packageConfig.Version } else { "" }
            if (-not [string]::IsNullOrWhiteSpace($version)) {
                $packageNames += "$pipPackage==$version"
            } else {
                $packageNames += $pipPackage
            }
        }

        if ($packageConfig.ContainsKey("PipDependencies")) {
            $packageNames += @($packageConfig.PipDependencies)
        }
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

# pip download に渡す仕様を返す
# 検証側 (Get-PipWheelPackageNames) と同じ正規化で重複排除するため、
# ruamel.yaml と ruamel-yaml のような表記ゆれを別物として扱わない
function Get-PipWheelDownloadSpecs {
    param(
        [array]$PackageConfigs = @(),
        [switch]$IncludeCorePackages
    )

    return (Get-PipWheelPackageNames -PackageConfigs $PackageConfigs -IncludeCorePackages:$IncludeCorePackages)
}

# 指定ディレクトリに必要な wheel が揃っているかを確認し、不足分を返す
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

    foreach ($packageName in @($PackageNames)) {
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
