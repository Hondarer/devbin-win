# ComponentFileRemoval.ps1
# アンインストール時のファイル削除を扱う

# 対象コンポーネント以外がマニフェストに記録しているファイルを集める
function Get-OtherComponentFiles {
    param(
        [hashtable]$Manifest,
        [string]$ShortName
    )

    $result = @{}
    foreach ($otherShortName in $Manifest.components.Keys) {
        if ($otherShortName -eq $ShortName) { continue }
        $otherData = $Manifest.components[$otherShortName]
        foreach ($file in @($otherData.files) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) {
            $result[$file] = $true
        }
    }

    return $result
}

# 相対パスの一覧から、先頭のディレクトリ名を重複なく取り出す
function Get-ComponentRootDirectories {
    param([string[]]$Paths)

    return @($Paths |
        Where-Object { $_ } |
        ForEach-Object { ($_ -split '[\\\/]')[0] } |
        Where-Object { $_ } |
        Sort-Object -Unique)
}

# マニフェストのファイル一覧、または DetectFiles に基づいて実体を削除する
# 他コンポーネントが参照しているファイルとディレクトリは残す
function Remove-ComponentInstalledFiles {
    param(
        [string]$ShortName,
        [hashtable]$PackageConfig,
        [string]$InstallDir,
        [hashtable]$Manifest,
        [string[]]$Files = @()
    )

    $targetDir = if ($PackageConfig.ContainsKey("TargetDirectory")) { $PackageConfig.TargetDirectory } else { $null }

    $targetDirRemoved = $false
    if ($targetDir) {
        # TargetDirectory 系: ディレクトリごと削除
        # テンプレート未解決 (例: "jdk-{0}") でパスが存在しない場合はフォールスルー
        $targetPath = Join-Path $InstallDir $targetDir
        if (Test-Path $targetPath) {
            try {
                Remove-Item -Path $targetPath -Recurse -Force -ErrorAction Stop
                Write-Host "  Removed: $targetDir"
                $targetDirRemoved = $true
            } catch {
                Write-Host "Warning: Failed to remove '$targetDir': $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
    }

    if (-not $targetDirRemoved) {
        # 参照カウントとルートディレクトリ保護のため、他コンポーネントのファイルを集める
        $allOtherFiles = Get-OtherComponentFiles -Manifest $Manifest -ShortName $ShortName

        if ($Files.Count -gt 0) {
            # ファイルリスト削除 (参照カウント確認)
            foreach ($file in $Files) {
                if ($allOtherFiles.ContainsKey($file)) {
                    Write-Host "  Skipped (shared): $file"
                    continue
                }
                $fullPath = Join-Path $InstallDir $file
                if (Test-Path $fullPath) {
                    try {
                        Remove-Item -Path $fullPath -Force -ErrorAction Stop
                        Write-Host "  Removed: $file"
                    } catch {
                        Write-Host "Warning: Failed to remove '$file': $($_.Exception.Message)" -ForegroundColor Yellow
                    }
                }
            }
        } else {
            # ファイル一覧なし: DetectFiles で削除対象を特定
            $detectFiles = if ($PackageConfig.ContainsKey("DetectFiles")) { @($PackageConfig.DetectFiles) } else { @() }
            foreach ($df in $detectFiles) {
                $fullPath = Join-Path $InstallDir $df
                if (Test-Path $fullPath) {
                    try {
                        $dfItem = Get-Item $fullPath -ErrorAction SilentlyContinue
                        if ($dfItem -and $dfItem.PSIsContainer) {
                            Remove-Item -Path $fullPath -Recurse -Force -ErrorAction Stop
                        } else {
                            Remove-Item -Path $fullPath -Force -ErrorAction Stop
                        }
                        Write-Host "  Removed: $df"
                    } catch {
                        Write-Host "Warning: Failed to remove '$df': $($_.Exception.Message)" -ForegroundColor Yellow
                    }
                }
            }
        }

        # ファイル削除後、孤立したルートディレクトリを削除
        # (VersionNormalized のテンプレート未解決や DetectFiles がファイルパスの場合に対応)
        $sourcePaths = if ($Files.Count -gt 0) { $Files } else {
            if ($PackageConfig.ContainsKey("DetectFiles")) { @($PackageConfig.DetectFiles) } else { @() }
        }
        $rootDirs = Get-ComponentRootDirectories -Paths $sourcePaths
        foreach ($rd in $rootDirs) {
            $rdPath = Join-Path $InstallDir $rd
            if (Test-Path $rdPath) {
                $rdItem = Get-Item $rdPath -ErrorAction SilentlyContinue
                if ($rdItem -and $rdItem.PSIsContainer) {
                    $hasOtherRefs = ($allOtherFiles.Keys |
                        Where-Object { $_ -and $_ -match "^$([regex]::Escape($rd))[\\\/]" } |
                        Measure-Object).Count -gt 0
                    if (-not $hasOtherRefs) {
                        try {
                            Remove-Item -Path $rdPath -Recurse -Force -ErrorAction SilentlyContinue
                            Write-Host "  Removed directory: $rd"
                        } catch {
                            Write-Host "Warning: Failed to remove directory '$rd': $($_.Exception.Message)" -ForegroundColor Yellow
                        }
                    }
                }
            }
        }
    }
}
