# NpmCacheDownload.ps1
# npm オフラインキャッシュの作成
#
# キャッシュの作成・検証・オフライン導入の実装は Packages/Npm の子モジュールにあり、
# ここでは取得側から呼ぶための入口だけを持つ。

# NpmInstall 戦略のパッケージについて、オフラインキャッシュを作る
# 戻り値: Success / Skipped / FailedShortNames / Message
function Invoke-NpmCacheDownload {
    param(
        [array]$NpmInstallPackages,
        [string]$PackagesDir,
        [switch]$Force
    )

    if (@($NpmInstallPackages).Count -eq 0) {
        return [PSCustomObject]@{
            Success          = $true
            Skipped          = $true
            FailedShortNames = @()
            Message          = "npm キャッシュの対象がありません"
        }
    }

    $npmCommand = Get-Command npm.cmd -ErrorAction SilentlyContinue
    if (-not $npmCommand) {
        return [PSCustomObject]@{
            Success          = $false
            Skipped          = $false
            FailedShortNames = @($NpmInstallPackages | ForEach-Object { [string]$_.ShortName })
            Message          = "npm が見つかりません。準備環境に Node.js/npm を入れてから再実行してください"
        }
    }

    $failedShortNames = @()
    foreach ($package in $NpmInstallPackages) {
        Write-Host "  Preparing npm offline cache: $($package.ShortName)"
        try {
            $exitCode = Save-NpmPackageCache `
                -NpmCommandPath $npmCommand.Source `
                -PackagesDir $PackagesDir `
                -PackageConfig $package `
                -Force:$Force
            if ($exitCode -ne 0 -and $null -ne $exitCode) {
                $failedShortNames += [string]$package.ShortName
            }
        } catch {
            Write-Host "  Warning: $($package.ShortName): $($_.Exception.Message)" -ForegroundColor Yellow
            $failedShortNames += [string]$package.ShortName
        }
    }

    if ($failedShortNames.Count -gt 0) {
        return [PSCustomObject]@{
            Success          = $false
            Skipped          = $false
            FailedShortNames = @($failedShortNames)
            Message          = "npm キャッシュの作成に失敗しました: $($failedShortNames -join ', ')"
        }
    }

    return [PSCustomObject]@{
        Success          = $true
        Skipped          = $false
        FailedShortNames = @()
        Message          = "npm オフラインキャッシュを $PackagesDir に作成しました"
    }
}
