# PackageAcquisition.ps1
# 取得処理の入口
#
# 対象選択、取得、検証、旧ファイル整理をまとめる。
# 取得スクリプト (Get-Packages.ps1) と、導入中にキャッシュが不足したときの
# 自動取得は、どちらもこの関数を通る。

# pip wheel を取得すべきかどうかを判定する
# 対象を絞り込んだ場合は、Python 関連が含まれるときだけ取得する
function Test-ShouldAcquirePipWheels {
    param(
        [array]$TargetPackages,
        [string[]]$RequestedShortNames = @()
    )

    if (-not $RequestedShortNames -or @($RequestedShortNames).Count -eq 0) {
        return $true
    }

    $pipRelated = @("python", "get-pip")
    $targetShortNames = @($TargetPackages | ForEach-Object { [string]$_.ShortName })

    foreach ($shortName in $targetShortNames) {
        if ($pipRelated -contains $shortName) {
            return $true
        }
    }

    # PipInstall 戦略のパッケージが対象に含まれていれば取得する
    foreach ($package in $TargetPackages) {
        if ([string]$package.ExtractStrategy -eq "PipInstall") {
            return $true
        }
    }

    return $false
}

# パッケージを取得する
# 戻り値: Success / Messages / FailedShortNames
function Invoke-PackageAcquisition {
    param(
        [array]$Packages,
        [PSCustomObject]$Context,
        [string[]]$ShortNames = @(),
        [switch]$Force
    )

    $messages = @()
    $failedShortNames = @()
    $success = $true

    try {
        $targetPackages = Select-TargetPackages -Packages $Packages -ShortNames $ShortNames
    } catch {
        return [PSCustomObject]@{
            Success          = $false
            Messages         = @($_.Exception.Message)
            FailedShortNames = @()
        }
    }

    if (-not (Test-Path $Context.PackagesDir)) {
        Write-Host "Creating packages directory..."
        New-Item -ItemType Directory -Path $Context.PackagesDir -Force | Out-Null
    }

    $vsbtPackage = $targetPackages | Where-Object { $_.ExtractStrategy -eq "VSBuildTools" } | Select-Object -First 1
    $npmInstallPackages = @($targetPackages | Where-Object { $_.ExtractStrategy -eq "NpmInstall" })
    $pipInstallPackages = @($targetPackages | Where-Object { $_.ExtractStrategy -eq "PipInstall" })
    $archiveTargets = @(Get-ArchiveDownloadTargets -Packages $targetPackages)

    if ($archiveTargets.Count -eq 0 -and -not $vsbtPackage -and
        $npmInstallPackages.Count -eq 0 -and $pipInstallPackages.Count -eq 0) {
        return [PSCustomObject]@{
            Success          = $false
            Messages         = @("取得対象が見つかりません")
            FailedShortNames = @()
        }
    }

    # Visual Studio Build Tools
    if ($vsbtPackage) {
        Write-Host ""
        Write-Host "=== Visual Studio Build Tools Download ===" -ForegroundColor Cyan
        Write-Host ""

        $vsbtResult = Invoke-VsBuildToolsDownload -PackageConfig $vsbtPackage -SubscriptsDir $Context.SubscriptsDir
        $messages += $vsbtResult.Message
        if (-not $vsbtResult.Success) {
            $success = $false
            $failedShortNames += [string]$vsbtPackage.ShortName
        }
        Write-Host ""
    }

    # アーカイブ
    if ($archiveTargets.Count -gt 0) {
        Write-Host "=== File Download Started ==="
        Write-Host "Downloading files to packages directory."
        if ($ShortNames -and @($ShortNames).Count -gt 0) {
            Write-Host "Selected packages: $((@($targetPackages | ForEach-Object { $_.ShortName })) -join ', ')"
        }
        Write-Host "Total packages: $($archiveTargets.Count)"
        if ($Force) {
            Write-Host "Force download mode: overwriting existing files." -ForegroundColor Yellow
        }

        $archiveResult = Invoke-ArchiveDownload -Targets $archiveTargets -PackagesDir $Context.PackagesDir -Force:$Force

        Write-Host ""
        Write-Host "Download Summary:"
        Write-Host "Success: $($archiveResult.SuccessCount) / $($archiveResult.TotalCount)"

        if ($archiveResult.Success) {
            Write-Host ""
            Write-Host "All files downloaded successfully." -ForegroundColor Green
            Write-Host ""
            Write-Host "Unblocking downloaded files..."
            Unblock-PackageFiles -PackagesDir $Context.PackagesDir
            $messages += "アーカイブを $($archiveResult.SuccessCount) 件取得しました"
        } else {
            $success = $false
            $failedShortNames += $archiveResult.FailedShortNames
            $messages += "アーカイブの取得に失敗しました: $($archiveResult.FailedShortNames -join ', ')"
            Write-Host ""
            Write-Host "$($archiveResult.TotalCount - $archiveResult.SuccessCount) file(s) failed to download." -ForegroundColor Yellow
            Write-Host "既存の資材はそのまま残しています。ネットワークを確認して再実行してください。"
        }
    }

    # npm
    if ($npmInstallPackages.Count -gt 0) {
        Write-Host ""
        Write-Host "=== npm Cache Download ===" -ForegroundColor Cyan
        Write-Host ""

        $npmResult = Invoke-NpmCacheDownload -NpmInstallPackages $npmInstallPackages -PackagesDir $Context.PackagesDir -Force:$Force
        $messages += $npmResult.Message
        if (-not $npmResult.Success) {
            $success = $false
            $failedShortNames += $npmResult.FailedShortNames
            Write-Host $npmResult.Message -ForegroundColor Yellow
        } else {
            Write-Host $npmResult.Message
        }
    }

    # pip wheel
    if (Test-ShouldAcquirePipWheels -TargetPackages $targetPackages -RequestedShortNames $ShortNames) {
        Write-Host ""
        Write-Host "=== Pip Wheel Download ===" -ForegroundColor Cyan
        Write-Host ""

        $pipResult = Invoke-PipWheelDownload `
            -Packages $Packages `
            -PipInstallPackages $pipInstallPackages `
            -DestinationDir $Context.PipPackagesDir `
            -IncludeCorePackages

        $messages += $pipResult.Message
        if ($pipResult.Skipped) {
            Write-Host $pipResult.Message
            Write-Host "Wheel files will be downloaded during installation."
        } elseif ($pipResult.Success) {
            Write-Host $pipResult.Message
        } else {
            $success = $false
            Write-Host $pipResult.Message -ForegroundColor Yellow
        }
    }

    return [PSCustomObject]@{
        Success          = $success
        Messages         = @($messages)
        FailedShortNames = @($failedShortNames | Select-Object -Unique)
    }
}
