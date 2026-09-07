# VsBuildToolsDownload.ps1
# Visual Studio Build Tools の定義解析と取得の入口

# VSBuildTools 戦略のパッケージ定義から Setup-VSBT.ps1 へ渡す引数を組み立てる
function Get-VsBuildToolsParameters {
    param([hashtable]$PackageConfig)

    if (-not $PackageConfig.ContainsKey("VSBTConfig")) {
        throw "VSBTConfig が定義されていません: $($PackageConfig.ShortName)"
    }

    $config = $PackageConfig.VSBTConfig
    return @{
        MSVCVersion = $config.MSVCVersion
        SDKVersion  = $config.SDKVersion
        Target      = $config.Target
        HostArch    = $config.HostArch
    }
}

# Setup-VSBT.ps1 を取得のみのモードで実行する
# 戻り値: Success / Skipped / Message
function Invoke-VsBuildToolsDownload {
    param(
        [hashtable]$PackageConfig,
        [string]$SubscriptsDir
    )

    if (-not $PackageConfig) {
        return [PSCustomObject]@{
            Success = $true
            Skipped = $true
            Message = "VSBuildTools の対象がありません"
        }
    }

    $vsbtScript = Join-Path $SubscriptsDir "Setup-VSBT.ps1"
    if (-not (Test-Path $vsbtScript)) {
        return [PSCustomObject]@{
            Success = $false
            Skipped = $false
            Message = "Setup-VSBT.ps1 が見つかりません: $vsbtScript"
        }
    }

    try {
        $parameters = Get-VsBuildToolsParameters -PackageConfig $PackageConfig
    } catch {
        return [PSCustomObject]@{
            Success = $false
            Skipped = $false
            Message = $_.Exception.Message
        }
    }

    $parameters.DownloadOnly = $true
    $parameters.AcceptLicense = $true

    Write-Host "Executing Setup-VSBT.ps1 with parameters:"
    Write-Host "  MSVCVersion: $($parameters.MSVCVersion)"
    Write-Host "  SDKVersion: $($parameters.SDKVersion)"
    Write-Host "  Target: $($parameters.Target)"
    Write-Host "  HostArch: $($parameters.HostArch)"
    Write-Host ""

    & $vsbtScript @parameters
    # 外部スクリプトの終了コードは実行直後に確認する
    $exitCode = $LASTEXITCODE

    if ($null -ne $exitCode -and $exitCode -ne 0) {
        return [PSCustomObject]@{
            Success = $false
            Skipped = $false
            Message = "Setup-VSBT.ps1 が終了コード $exitCode で終了しました"
        }
    }

    return [PSCustomObject]@{
        Success = $true
        Skipped = $false
        Message = "Visual Studio Build Tools を取得しました"
    }
}
