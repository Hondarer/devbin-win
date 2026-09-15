# PipCache.ps1
# pip wheel キャッシュのダウンロードおよび整合性検証

# pip download コマンドを実行してバイナリ wheel を取得
# 戻り値: pip プロセスの終了コード
function Save-PipWheelPackages {
    param(
        [string]$PythonCommandPath,
        [string]$DestinationDir,
        [string]$TargetPythonVersion = "",
        [string[]]$DownloadSpecs = @()
    )

    if (-not (Test-Path $DestinationDir)) {
        New-Item -ItemType Directory -Path $DestinationDir -Force | Out-Null
    }

    $specs = @($DownloadSpecs | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($specs.Count -eq 0) {
        return 0
    }

    $pipArgs = @("-m", "pip", "download", "--only-binary=:all:")
    if (-not [string]::IsNullOrWhiteSpace($TargetPythonVersion)) {
        $pipArgs += @("--python-version", $TargetPythonVersion, "--implementation", "cp", "--platform", "win_amd64")
    }
    $pipArgs += $specs
    $pipArgs += @("--dest", $DestinationDir)

    & $PythonCommandPath @pipArgs | Out-Host
    # 外部プロセスの終了コード ($LASTEXITCODE) を直ちに返却
    return $LASTEXITCODE
}

# packages.psd1 の python 定義から対象 Python バージョン (メジャー.マイナー) を抽出
function Get-TargetPythonVersion {
    param([array]$Packages)

    $pythonPackage = Get-PackageByShortName -ShortName "python" -Packages $Packages
    if (-not $pythonPackage -or -not $pythonPackage.Version) {
        return ""
    }

    $versionParts = ([string]$pythonPackage.Version) -split '\.'
    if ($versionParts.Count -lt 2) {
        return ""
    }
    return "$($versionParts[0]).$($versionParts[1])"
}

# wheel キャッシュの取得および存在検証を実行
# IncludeCorePackages 指定時は Python 初期セットアップ用コア wheel を取得対象に追加
# 戻り値: Success / Skipped / Missing / Message を持つ結果オブジェクト
function Invoke-PipWheelDownload {
    param(
        [array]$Packages,
        [array]$PipInstallPackages = @(),
        [string]$DestinationDir,
        [switch]$IncludeCorePackages
    )

    $pythonCommand = Get-Command python.exe -ErrorAction SilentlyContinue
    if (-not $pythonCommand) {
        return [PSCustomObject]@{
            Success = $true
            Skipped = $true
            Missing = @()
            Message = "Python が見つからないため wheel の取得を省略しました"
        }
    }

    $requiredNames = @(Get-PipWheelPackageNames -PackageConfigs $PipInstallPackages -IncludeCorePackages:$IncludeCorePackages)
    $downloadSpecs = @(Get-PipWheelDownloadSpecs -PackageConfigs $PipInstallPackages -IncludeCorePackages:$IncludeCorePackages)

    try {
        $exitCode = Save-PipWheelPackages `
            -PythonCommandPath $pythonCommand.Source `
            -DestinationDir $DestinationDir `
            -TargetPythonVersion (Get-TargetPythonVersion -Packages $Packages) `
            -DownloadSpecs $downloadSpecs
    } catch {
        return [PSCustomObject]@{
            Success = $false
            Skipped = $false
            Missing = @()
            Message = "wheel の取得に失敗しました: $($_.Exception.Message)"
        }
    }

    $missing = @(Test-PipWheelPackages -DirectoryPath $DestinationDir -PackageNames $requiredNames)

    if ($exitCode -ne 0) {
        return [PSCustomObject]@{
            Success = $false
            Skipped = $false
            Missing = $missing
            Message = "wheel の取得に失敗しました (終了コード: $exitCode)"
        }
    }

    if ($missing.Count -gt 0) {
        return [PSCustomObject]@{
            Success = $false
            Skipped = $false
            Missing = $missing
            Message = "wheel キャッシュに不足があります: $($missing -join ', ')"
        }
    }

    return [PSCustomObject]@{
        Success = $true
        Skipped = $false
        Missing = @()
        Message = "wheel を $DestinationDir に取得しました"
    }
}
