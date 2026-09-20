# PackageLayout.ps1
# packages ディレクトリの現行資材許可リストと、未参照ファイルの削除

$script:DevbinNpmPackagesDirectoryName = "npm-packages"
$script:DevbinPipPackagesDirectoryName = "pip-packages"
$script:DevbinVsbtDirectoryName = "vsbt"

# packages 配下の絶対パスを、packages ルートからの相対パスへ変換する
# packages の外を指す場合は $null を返す
function ConvertTo-PackagesRelativePath {
    param(
        [string]$PackagesDir,
        [string]$PathValue
    )

    if ([string]::IsNullOrWhiteSpace($PackagesDir) -or [string]::IsNullOrWhiteSpace($PathValue)) {
        return $null
    }

    try {
        $root = [System.IO.Path]::GetFullPath($PackagesDir).TrimEnd('\', '/')
        $full = [System.IO.Path]::GetFullPath($PathValue)
    } catch {
        return $null
    }

    $prefix = $root + [System.IO.Path]::DirectorySeparatorChar
    if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        return $null
    }

    return $full.Substring($prefix.Length)
}

# 指定ディレクトリ配下のファイルを許可リストへ追加する
function Add-ManagedTreeKeepPaths {
    param(
        [string]$PackagesDir,
        [string]$TreeDir,
        [System.Collections.Generic.List[string]]$KeepPaths
    )

    if ([string]::IsNullOrWhiteSpace($TreeDir) -or -not (Test-Path -LiteralPath $TreeDir -PathType Container)) {
        return
    }

    $files = @(Get-ChildItem -LiteralPath $TreeDir -Recurse -File -Force -ErrorAction SilentlyContinue)
    foreach ($file in $files) {
        $relativePath = ConvertTo-PackagesRelativePath -PackagesDir $PackagesDir -PathValue $file.FullName
        if (-not [string]::IsNullOrWhiteSpace($relativePath)) {
            $KeepPaths.Add($relativePath)
        }
    }
}

# 現行カタログが必要とする packages 配下の相対パス一覧を返す
# アーカイブは保存ファイル名、npm / pip / VSBT は取得後に残っている管理ツリーの実ファイルを列挙する
function Get-ManagedPackageKeepRelativePaths {
    param(
        [array]$Packages,
        [string]$PackagesDir
    )

    $keepPaths = New-Object System.Collections.Generic.List[string]

    $offlineName = if (-not [string]::IsNullOrWhiteSpace($script:DevbinOfflineMarkerName)) {
        $script:DevbinOfflineMarkerName
    } else {
        "OFFLINE"
    }
    $keepPaths.Add($offlineName)

    $keepPipTree = $false
    $keepVsbtTree = $false

    foreach ($package in @($Packages)) {
        if ($null -eq $package) {
            continue
        }

        $strategy = if ($package.ContainsKey("ExtractStrategy")) { [string]$package.ExtractStrategy } else { "" }
        $shortName = if ($package.ContainsKey("ShortName")) { [string]$package.ShortName } else { "" }

        if ($package.ContainsKey("DownloadUrl") -and -not [string]::IsNullOrWhiteSpace([string]$package.DownloadUrl)) {
            $fileName = Get-PackageDownloadFileName -Package $package
            if (-not [string]::IsNullOrWhiteSpace($fileName)) {
                $keepPaths.Add($fileName)
            }
        }

        if ($strategy -eq "NpmInstall") {
            $cacheDirectory = Get-NpmPackageCacheDirectory -PackagesDir $PackagesDir -PackageConfig $package
            Add-ManagedTreeKeepPaths -PackagesDir $PackagesDir -TreeDir $cacheDirectory -KeepPaths $keepPaths
        }

        if ($strategy -eq "PipInstall" -or $strategy -eq "CopyToPackages" -or $shortName -eq "python" -or $shortName -eq "get-pip") {
            $keepPipTree = $true
        }

        if ($strategy -eq "VSBuildTools") {
            $keepVsbtTree = $true
        }
    }

    if ($keepPipTree) {
        Add-ManagedTreeKeepPaths `
            -PackagesDir $PackagesDir `
            -TreeDir (Join-Path $PackagesDir $script:DevbinPipPackagesDirectoryName) `
            -KeepPaths $keepPaths
    }

    if ($keepVsbtTree) {
        Add-ManagedTreeKeepPaths `
            -PackagesDir $PackagesDir `
            -TreeDir (Join-Path $PackagesDir $script:DevbinVsbtDirectoryName) `
            -KeepPaths $keepPaths
    }

    return @($keepPaths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
}

# 許可リストに無い packages 配下のファイルを削除し、空ディレクトリを取り除く
# 戻り値: RemovedCount / RemovedPaths を持つ結果オブジェクト
function Remove-UnreferencedPackageFiles {
    param(
        [string]$PackagesDir,
        [string[]]$KeepRelativePaths = @()
    )

    $removedPaths = @()
    if ([string]::IsNullOrWhiteSpace($PackagesDir) -or -not (Test-Path -LiteralPath $PackagesDir -PathType Container)) {
        return [PSCustomObject]@{
            RemovedCount = 0
            RemovedPaths = @()
        }
    }

    $keep = @{}
    foreach ($relativePath in @($KeepRelativePaths)) {
        if ([string]::IsNullOrWhiteSpace($relativePath)) {
            continue
        }
        $normalized = ([string]$relativePath).Replace('/', '\').TrimStart('\')
        if (-not [string]::IsNullOrWhiteSpace($normalized)) {
            $keep[$normalized] = $true
        }
    }

    $files = @(Get-ChildItem -LiteralPath $PackagesDir -Recurse -File -Force -ErrorAction SilentlyContinue)
    foreach ($file in $files) {
        $relativePath = ConvertTo-PackagesRelativePath -PackagesDir $PackagesDir -PathValue $file.FullName
        if ([string]::IsNullOrWhiteSpace($relativePath)) {
            continue
        }
        if ($keep.ContainsKey($relativePath)) {
            continue
        }

        try {
            Write-Host "  Removed: $relativePath"
            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
            $removedPaths += $relativePath
        } catch {
            Write-Host "  Warning: Failed to remove unreferenced package file ${relativePath}: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    $directories = @(Get-ChildItem -LiteralPath $PackagesDir -Recurse -Directory -Force -ErrorAction SilentlyContinue |
        Sort-Object -Property FullName -Descending)
    foreach ($directory in $directories) {
        $entries = @(Get-ChildItem -LiteralPath $directory.FullName -Force -ErrorAction SilentlyContinue)
        if ($entries.Count -eq 0) {
            Remove-Item -LiteralPath $directory.FullName -Force -ErrorAction SilentlyContinue
        }
    }

    if ($removedPaths.Count -gt 0) {
        Write-Host "Removed $($removedPaths.Count) unreferenced file(s)"
    } else {
        Write-Host "No unreferenced files found"
    }

    return [PSCustomObject]@{
        RemovedCount = @($removedPaths).Count
        RemovedPaths = @($removedPaths)
    }
}
