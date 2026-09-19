# ComponentFileRemoval.ps1
# アンインストール時におけるインストール済みファイルの削除処理

# 対象コンポーネント以外のコンポーネントがマニフェストに記録しているファイルを収集します。
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

# コンポーネント自身が実行時に生成するファイル (自己更新時のバックアップ等) を CleanupPatterns に基づいて削除します。
# パターンは $InstallDir からの相対パスで、ファイル名部分にのみワイルドカードを使用できます。
# 他コンポーネントがマニフェストに記録しているファイルは削除しません。
function Remove-ComponentCleanupFiles {
    param(
        [string]$ShortName,
        [hashtable]$PackageConfig,
        [string]$InstallDir,
        [hashtable]$Manifest
    )

    $patterns = if ($PackageConfig.ContainsKey("CleanupPatterns")) {
        @($PackageConfig.CleanupPatterns) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    } else {
        @()
    }
    if (@($patterns).Count -eq 0) { return }

    $allOtherFiles = Get-OtherComponentFiles -Manifest $Manifest -ShortName $ShortName

    foreach ($pattern in $patterns) {
        $relativeDir = Split-Path $pattern -Parent
        $leafPattern = Split-Path $pattern -Leaf
        $searchDir = if ($relativeDir) { Join-Path $InstallDir $relativeDir } else { $InstallDir }
        if (-not (Test-Path $searchDir -PathType Container)) { continue }

        foreach ($item in @(Get-ChildItem -LiteralPath $searchDir -Filter $leafPattern -File -Force -ErrorAction SilentlyContinue)) {
            $relativePath = if ($relativeDir) { Join-Path $relativeDir $item.Name } else { $item.Name }
            if ($allOtherFiles.ContainsKey($relativePath)) {
                Write-Host "  Skipped (shared): $relativePath"
                continue
            }
            try {
                Remove-Item -LiteralPath $item.FullName -Force -ErrorAction Stop
                Write-Host "  Removed: $relativePath"
            } catch {
                # 実行中のプロセスが使用しているファイルは削除できないため、警告にとどめます。
                Write-Host "Warning: Failed to remove '$relativePath': $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
    }
}

# 相対パス一覧から、ルートディレクトリ名を重複なく抽出します。
function Get-ComponentRootDirectories {
    param([string[]]$Paths)

    return @($Paths |
        Where-Object { $_ } |
        ForEach-Object { ($_ -split '[\\\/]')[0] } |
        Where-Object { $_ } |
        Sort-Object -Unique)
}

# マニフェストのファイル一覧または DetectFiles に基づいてインストール成果物を削除します。
# 他のコンポーネントから参照されている共有ファイルおよびディレクトリは保持します。
function Remove-ComponentInstalledFiles {
    param(
        [string]$ShortName,
        [hashtable]$PackageConfig,
        [string]$InstallDir,
        [hashtable]$Manifest,
        [string[]]$Files = @()
    )

    $targetDir = if ($PackageConfig.ContainsKey("TargetDirectory")) { $PackageConfig.TargetDirectory } else { $null }

    # マニフェストに記録されない実行時の生成ファイルを先に削除します。
    Remove-ComponentCleanupFiles -ShortName $ShortName -PackageConfig $PackageConfig -InstallDir $InstallDir -Manifest $Manifest

    $targetDirRemoved = $false
    if ($targetDir) {
        # TargetDirectory 設定時: 対象ディレクトリを一括削除します。
        # テンプレート未解決 (例: "jdk-{0}") 等によりパスが存在しない場合はフォールスルーします。
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
        # 参照整合性の維持およびルートディレクトリ保護のため、他コンポーネントの管理対象ファイルを収集します。
        $allOtherFiles = Get-OtherComponentFiles -Manifest $Manifest -ShortName $ShortName

        if ($Files.Count -gt 0) {
            # マニフェストのファイル一覧に基づく削除 (他コンポーネントとの共有判定を含む)
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
            # ファイル一覧が存在しない場合: DetectFiles の定義に基づいて削除対象を特定します。
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

        # ファイル削除後、残存したルートディレクトリのうち他コンポーネントから参照されていない空ディレクトリを削除します。
        # (VersionNormalized テンプレート未解決時や DetectFiles にファイルパスが指定されている場合に対応)
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
