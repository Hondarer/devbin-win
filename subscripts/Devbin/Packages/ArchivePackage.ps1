# ArchivePackage.ps1
# アーカイブパッケージの取得対象絞り込み、ダウンロード実行、および旧世代資材のクリーンアップ

# ShortName に基づいて取得対象パッケージを絞り込み
# 引数未指定時は全件を返却。未定義の ShortName が指定された場合は例外を送出
function Select-TargetPackages {
    param(
        [array]$Packages,
        [string[]]$ShortNames = @()
    )

    if (-not $ShortNames -or @($ShortNames).Count -eq 0) {
        return @($Packages)
    }

    $targets = @()
    $seen = @{}

    # cmd 経由の powershell.exe -File 実行時にカンマ区切りが単一文字列として渡されるケースに対応
    foreach ($shortName in @($ShortNames | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() })) {
        if ([string]::IsNullOrWhiteSpace($shortName)) { continue }
        if ($seen.ContainsKey($shortName)) { continue }

        $package = Get-PackageByShortName -ShortName $shortName -Packages $Packages
        if (-not $package) {
            throw "Package not found: $shortName"
        }

        $targets += $package
        $seen[$shortName] = $true
    }

    return @($targets)
}

# DownloadUrl が定義されたパッケージからダウンロード対象オブジェクト配列を生成
function Get-ArchiveDownloadTargets {
    param([array]$Packages)

    $targets = @()
    foreach ($package in $Packages) {
        if (-not $package.DownloadUrl) { continue }

        $targets += [PSCustomObject]@{
            Package  = $package
            Url      = [string]$package.DownloadUrl
            FileName = Get-PackageDownloadFileName -Package $package
            Headers  = if ($package.ContainsKey("DownloadHeaders")) { $package.DownloadHeaders } else { @{} }
        }
    }
    return @($targets)
}

# 過去バージョンのアーカイブファイルおよび不要になったベースファイル名を削除
function Remove-OldPackageFiles {
    param(
        [hashtable]$Package,
        [string]$CurrentFileName,
        [string]$PackagesDir
    )

    if (-not (Test-Path $PackagesDir)) {
        return
    }

    $oldFiles = Get-ChildItem -Path $PackagesDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match $Package.ArchivePattern -and $_.Name -ne $CurrentFileName }

    if ($oldFiles) {
        Write-Host "  Old package cleanup for $($Package.ShortName): $($oldFiles.Count) file(s)"
        Write-Host "    Current package file: $CurrentFileName"
    }

    foreach ($oldFile in $oldFiles) {
        try {
            Write-Host "    Removing old package file: $($oldFile.Name)"
            Remove-Item -LiteralPath $oldFile.FullName -Force -ErrorAction Stop
        } catch {
            Write-Host "  Warning: Failed to remove old package file $($oldFile.Name): $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    $baseFileName = Get-PackageBaseFileName -Package $Package
    if ([string]::IsNullOrWhiteSpace($baseFileName) -or $baseFileName -eq $CurrentFileName) {
        return
    }

    $baseFilePath = Join-Path $PackagesDir $baseFileName
    if (-not (Test-Path $baseFilePath -PathType Leaf)) {
        return
    }

    try {
        Write-Host "  Original package file cleanup for $($Package.ShortName): $baseFileName"
        Remove-Item -LiteralPath $baseFilePath -Force -ErrorAction Stop
    } catch {
        Write-Host "  Warning: Failed to remove base package file ${baseFileName}: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# アーカイブパッケージのダウンロードを実行
# ダウンロード成功時のみ旧世代ファイルを削除 (失敗時は既存資材を保持)
# 戻り値: Success / SuccessCount / TotalCount / FailedShortNames を持つ結果オブジェクト
function Invoke-ArchiveDownload {
    param(
        [array]$Targets,
        [string]$PackagesDir,
        [switch]$Force
    )

    $successCount = 0
    $failedShortNames = @()

    foreach ($target in $Targets) {
        $outputPath = Join-Path $PackagesDir $target.FileName

        if (Save-DownloadedFile -Url $target.Url -OutputPath $outputPath -Headers $target.Headers -Force:$Force) {
            $successCount++
            Remove-OldPackageFiles -Package $target.Package -CurrentFileName $target.FileName -PackagesDir $PackagesDir
        } else {
            $failedShortNames += [string]$target.Package.ShortName
        }

        Start-Sleep -Milliseconds 500
    }

    $total = @($Targets).Count
    return [PSCustomObject]@{
        Success          = ($successCount -eq $total)
        SuccessCount     = $successCount
        TotalCount       = $total
        FailedShortNames = @($failedShortNames)
    }
}
