# PackageCatalog.ps1
# パッケージ定義 (カタログ) の読み込みおよび整合性検証

$script:DevbinRequiredPackageKeys = @(
    "Name", "ShortName", "Version", "ArchivePattern",
    "ExtractStrategy", "DependsOn", "PathDirs", "EnvVars", "DetectFiles"
)

# 指定された ShortName に一致するパッケージ設定を取得
function Get-PackageByShortName {
    param(
        [string]$ShortName,
        [array]$Packages
    )

    foreach ($package in $Packages) {
        if ($package.ShortName -eq $ShortName) {
            return $package
        }
    }
    return $null
}

# パッケージ定義群の整合性を検証し、検出されたエラー一覧を返却
# 検証項目: 必須プロパティの有無、ShortName の重複、未定義の依存パッケージ、循環依存
function Test-PackageCatalog {
    param([array]$Packages)

    $errors = @()
    $seen = @{}

    foreach ($package in $Packages) {
        $shortName = if ($package.ContainsKey("ShortName")) { [string]$package.ShortName } else { "" }
        if ([string]::IsNullOrWhiteSpace($shortName)) {
            $errors += "ShortName が指定されていないパッケージ定義があります"
            continue
        }

        foreach ($key in $script:DevbinRequiredPackageKeys) {
            if (-not $package.ContainsKey($key)) {
                $errors += "必須プロパティが存在しません: $shortName の $key"
            }
        }

        if ($seen.ContainsKey($shortName)) {
            $errors += "ShortName が重複しています: $shortName"
        }
        $seen[$shortName] = $true
    }

    $shortNames = @($Packages | ForEach-Object { [string]$_.ShortName } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $resolution = Resolve-DependencyOrder -ShortNames $shortNames -Packages $Packages
    if (-not $resolution.Success) {
        $errors += $resolution.Errors
    }

    return @($errors)
}

# パッケージ定義ファイルを読み込み、整合性検証結果とあわせて返却
# 戻り値: Success (ブール値) / Packages (配列) / Errors (エラーメッセージ配列) を含むオブジェクト
function Import-PackageCatalog {
    param(
        [string]$Path,
        [switch]$SkipValidation
    )

    try {
        $data = Import-DevbinDataFile -Path $Path
    } catch {
        return [PSCustomObject]@{
            Success  = $false
            Packages = @()
            Errors   = @($_.Exception.Message)
        }
    }

    if (-not ($data -is [hashtable]) -or -not $data.ContainsKey("Packages")) {
        return [PSCustomObject]@{
            Success  = $false
            Packages = @()
            Errors   = @("パッケージ定義に Packages が存在しません: $Path")
        }
    }

    $packages = @($data.Packages)
    $errors = if ($SkipValidation) { @() } else { @(Test-PackageCatalog -Packages $packages) }

    return [PSCustomObject]@{
        Success  = ($errors.Count -eq 0)
        Packages = $packages
        Errors   = @($errors)
    }
}

# パッケージの展開先ディレクトリ名を取得 (TargetDirectory が未定義の場合は ShortName を適用)
function Get-PackageTargetDirectory {
    param([hashtable]$PackageConfig)

    if ($PackageConfig.ContainsKey("TargetDirectory") -and -not [string]::IsNullOrWhiteSpace([string]$PackageConfig.TargetDirectory)) {
        return [string]$PackageConfig.TargetDirectory
    }
    return [string]$PackageConfig.ShortName
}

# Python の展開先ディレクトリを InstallDir 配下の絶対パスとして取得
# パッケージ定義の TargetDirectory を参照することで、バージョン更新時の修正箇所を集約
function Get-PythonDirectory {
    param(
        [array]$Packages,
        [string]$InstallDir,
        [string]$ShortName = "python"
    )

    $package = Get-PackageByShortName -ShortName $ShortName -Packages $Packages
    if (-not $package) {
        return ""
    }

    return (Join-Path $InstallDir (Get-PackageTargetDirectory -PackageConfig $package))
}
