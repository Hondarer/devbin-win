# PipPackage.ps1
# pip パッケージ名の正規化およびオフライン wheel ファイルの検証
#
# Python の初期セットアップに必要な基本パッケージ (pip / setuptools / wheel / packaging / pytest) と、
# 各種追加パッケージに必要な wheel の切り替えは -IncludeCorePackages スイッチで制御します。

# Python 初期セットアップ用の基本コアパッケージ一覧
$script:DevbinPipCorePackages = @("pip", "setuptools", "wheel", "packaging", "pytest")

# PEP 503 に準拠した pip パッケージ名の正規化
function Get-NormalizedPipPackageName {
    param([string]$Name)

    return (([string]$Name).Trim().ToLowerInvariant() -replace '[-_.]+', '-')
}

# パッケージ定義群から必要な pip パッケージ仕様 (バージョン指定を含む) を重複なく抽出
# 重複判定は正規化名に基づいて実行
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

# pip download コマンドに渡すパッケージ仕様一覧を取得
# 検証処理と同一の正規化ロジックで重複を排除し、表記揺れ (ruamel.yaml と ruamel-yaml 等) を同一パッケージとして処理
function Get-PipWheelDownloadSpecs {
    param(
        [array]$PackageConfigs = @(),
        [switch]$IncludeCorePackages
    )

    return (Get-PipWheelPackageNames -PackageConfigs $PackageConfigs -IncludeCorePackages:$IncludeCorePackages)
}

# 指定ディレクトリ内に必要な wheel ファイルが存在するかを照合し、不足しているパッケージ一覧を返却
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
