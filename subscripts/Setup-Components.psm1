# Setup-Components.psm1
# コンポーネント単位のインストール/アンインストール/更新操作モジュール

# ShortName でパッケージ設定を取得する
function Get-PackageByShortName {
    param(
        [string]$ShortName,
        [array]$Packages
    )

    foreach ($pkg in $Packages) {
        if ($pkg.ShortName -eq $ShortName) {
            return $pkg
        }
    }
    return $null
}

# 依存を再帰的に解決し、トポロジカルソート順で返す
# 戻り値: ShortName の配列 (依存→依存先の順)
function Resolve-Dependencies {
    param(
        [string]$ShortName,
        [array]$Packages,
        [hashtable]$Visited = @{},
        [hashtable]$InStack = @{}
    )

    if ($InStack.ContainsKey($ShortName)) {
        Write-Host "Warning: Circular dependency detected for '$ShortName'" -ForegroundColor Yellow
        return @()
    }

    if ($Visited.ContainsKey($ShortName)) {
        return @()
    }

    $InStack[$ShortName] = $true

    $pkg = Get-PackageByShortName -ShortName $ShortName -Packages $Packages
    if (-not $pkg) {
        Write-Host "Warning: Package '$ShortName' not found" -ForegroundColor Yellow
        $InStack.Remove($ShortName)
        return @()
    }

    $result = @()
    $deps = if ($pkg.ContainsKey("DependsOn")) { @($pkg.DependsOn) } else { @() }

    foreach ($dep in $deps) {
        $subDeps = Resolve-Dependencies -ShortName $dep -Packages $Packages -Visited $Visited -InStack $InStack
        $result += $subDeps
    }

    $result += $ShortName
    $Visited[$ShortName] = $true
    $InStack.Remove($ShortName)

    return $result
}

# 指定コンポーネントに依存しているインストール済みコンポーネントの一覧を返す
function Get-Dependents {
    param(
        [string]$ShortName,
        [array]$Packages,
        [hashtable]$Manifest
    )

    $dependents = @()

    foreach ($pkg in $Packages) {
        # 自分自身はスキップ
        if ($pkg.ShortName -eq $ShortName) {
            continue
        }
        # インストール済みのみ対象
        if (-not (Test-ComponentInstalled -Manifest $Manifest -ShortName $pkg.ShortName)) {
            continue
        }

        $deps = if ($pkg.ContainsKey("DependsOn")) { @($pkg.DependsOn) } else { @() }
        if ($deps -contains $ShortName) {
            $dependents += $pkg.ShortName
        }
    }

    return $dependents
}

# 環境変数を設定する (EnvVars/EnvVarIsLiteral に基づく)
function Set-ComponentEnvVars {
    param(
        [string]$InstallDir,
        [hashtable]$PackageConfig
    )

    $envVars = if ($PackageConfig.ContainsKey("EnvVars")) { $PackageConfig.EnvVars } else { @{} }
    if (-not $envVars -or $envVars.Count -eq 0) { return @{} }

    $literalKeys = if ($PackageConfig.ContainsKey("EnvVarIsLiteral")) { @($PackageConfig.EnvVarIsLiteral) } else { @() }
    $appliedVars = @{}

    foreach ($key in $envVars.Keys) {
        $rawValue = $envVars[$key]
        $value = if ($literalKeys -contains $key) {
            $rawValue
        } elseif ($rawValue -eq "") {
            $InstallDir
        } else {
            Join-Path $InstallDir $rawValue
        }

        [Environment]::SetEnvironmentVariable($key, $value, "User")
        Write-Host "  Set $key=$value"
        $appliedVars[$key] = $value
    }

    return $appliedVars
}

# 環境変数を削除する
function Remove-ComponentEnvVars {
    param(
        [string]$InstallDir,
        [hashtable]$PackageConfig
    )

    $envVars = if ($PackageConfig.ContainsKey("EnvVars")) { $PackageConfig.EnvVars } else { @{} }
    if (-not $envVars -or $envVars.Count -eq 0) { return }

    $literalKeys = if ($PackageConfig.ContainsKey("EnvVarIsLiteral")) { @($PackageConfig.EnvVarIsLiteral) } else { @() }

    foreach ($key in $envVars.Keys) {
        $rawValue = $envVars[$key]
        $expectedValue = if ($literalKeys -contains $key) {
            $rawValue
        } elseif ($rawValue -eq "") {
            $InstallDir
        } else {
            Join-Path $InstallDir $rawValue
        }

        $currentValue = [Environment]::GetEnvironmentVariable($key, "User")
        if ($currentValue -eq $expectedValue) {
            [Environment]::SetEnvironmentVariable($key, $null, "User")
            Write-Host "  Removed $key"
        }
    }
}

# PATH ディレクトリを追加する (SkipIfCommand 考慮)
function Add-ComponentPathDirs {
    param(
        [string]$InstallDir,
        [hashtable]$PackageConfig
    )

    $pathDirs = if ($PackageConfig.ContainsKey("PathDirs")) { @($PackageConfig.PathDirs) } else { @() }
    $skipCmd = if ($PackageConfig.ContainsKey("SkipIfCommand")) { $PackageConfig.SkipIfCommand } else { "" }

    if ($pathDirs.Count -eq 0) { return $pathDirs }

    if ($skipCmd -and (Test-CommandExists $skipCmd)) {
        Write-Host "  Skipped PATH (${skipCmd} already available)"
        return $pathDirs
    }

    $dirsToAdd = @()
    foreach ($rel in $pathDirs) {
        $abs = Join-Path $InstallDir $rel
        $dirsToAdd += $abs
    }

    if ($dirsToAdd.Count -gt 0) {
        Add-MultiplePathDirs -Directories $dirsToAdd
    }

    return $pathDirs
}

# PATH ディレクトリを削除する
function Remove-ComponentPathDirs {
    param(
        [string]$InstallDir,
        [hashtable]$PackageConfig
    )

    $pathDirs = if ($PackageConfig.ContainsKey("PathDirs")) { @($PackageConfig.PathDirs) } else { @() }
    if ($pathDirs.Count -eq 0) { return }

    $dirsToRemove = @()
    foreach ($rel in $pathDirs) {
        $dirsToRemove += Join-Path $InstallDir $rel
    }

    Remove-FromUserPath -Directories $dirsToRemove
}

# ベース PATH (bin/ ルート) を追加する
function Add-BasePathDir {
    param([string]$InstallDir)

    $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if ($currentPath -and ($currentPath -split ';' | Where-Object { $_ -eq $InstallDir })) {
        return
    }
    Add-MultiplePathDirs -Directories @($InstallDir)
}

# ベース PATH (bin/ ルート) を削除する
function Remove-BasePathDir {
    param([string]$InstallDir)
    Remove-FromUserPath -Directories @($InstallDir)
}

# コンポーネントをインストールする
function Install-Component {
    param(
        [string]$ShortName,
        [array]$Packages,
        [string]$InstallDir,
        [string]$ScriptDir,
        [hashtable]$Manifest,
        [switch]$SkipDeps
    )

    $pkg = Get-PackageByShortName -ShortName $ShortName -Packages $Packages
    if (-not $pkg) {
        Write-Host "Error: Package '$ShortName' not found" -ForegroundColor Red
        return $false
    }

    # 既にインストール済みの場合はスキップ
    if (Test-ComponentInstalled -Manifest $Manifest -ShortName $ShortName) {
        Write-Host "  '$ShortName' は既にインストール済みです" -ForegroundColor Cyan
        return $true
    }

    # 依存を先にインストール
    if (-not $SkipDeps) {
        $deps = if ($pkg.ContainsKey("DependsOn")) { @($pkg.DependsOn) } else { @() }
        foreach ($dep in $deps) {
            if (-not (Test-ComponentInstalled -Manifest $Manifest -ShortName $dep)) {
                Write-Host ""
                Write-Host "  依存コンポーネントをインストール: $dep" -ForegroundColor Cyan
                $depResult = Install-Component `
                    -ShortName $dep `
                    -Packages $Packages `
                    -InstallDir $InstallDir `
                    -ScriptDir $ScriptDir `
                    -Manifest $Manifest
                if (-not $depResult) {
                    Write-Host "Error: Failed to install dependency '$dep'" -ForegroundColor Red
                    return $false
                }
            }
        }
    }

    Write-Host ""
    Write-Host "=== $($pkg.Name) をインストール中 ==="

    # インストール先ディレクトリを作成
    if (-not (Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }

    # CopyToPackages 戦略はスキップ (ファイルは packages/ に留まる)
    if ($pkg.ExtractStrategy -eq "CopyToPackages") {
        $pathDirs = if ($pkg.ContainsKey("PathDirs")) { @($pkg.PathDirs) } else { @() }
        $version = if ($pkg.ContainsKey("Version")) { $pkg.Version } else { "" }
        Add-ComponentToManifest `
            -Manifest $Manifest `
            -ShortName $ShortName `
            -Version $version `
            -ArchiveFile "(no-extract)" `
            -Files @() `
            -PathDirs $pathDirs
        return $true
    }

    # アーカイブファイルを検索
    $packagesDir = "packages"
    $archiveFile = $null

    if ($pkg.ExtractStrategy -ne "VSBuildTools") {
        $archiveFiles = Get-ChildItem -Path $packagesDir -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match $pkg.ArchivePattern }

        if ($archiveFiles -and $archiveFiles.Count -gt 0) {
            $archiveFile = $archiveFiles[0].FullName
        } else {
            # アーカイブが見つからない場合はダウンロードを試みる
            Write-Host "  アーカイブが見つかりません。ダウンロードを試みます..."
            $getPackagesScript = Join-Path $ScriptDir "Get-Packages.ps1"
            if (Test-Path $getPackagesScript) {
                $downloadTargets = @(Resolve-Dependencies -ShortName $ShortName -Packages $Packages | Select-Object -Unique)
                if (-not $downloadTargets -or $downloadTargets.Count -eq 0) {
                    $downloadTargets = @($ShortName)
                }

                Write-Host "  ダウンロード対象: $($downloadTargets -join ', ')"
                & $getPackagesScript -PackageShortNames $downloadTargets
            }

            $archiveFiles = Get-ChildItem -Path $packagesDir -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match $pkg.ArchivePattern }

            if ($archiveFiles -and $archiveFiles.Count -gt 0) {
                $archiveFile = $archiveFiles[0].FullName
            } else {
                Write-Host "Error: Archive not found for '$ShortName' (pattern: $($pkg.ArchivePattern))" -ForegroundColor Red
                return $false
            }
        }
    }

    # インストール前スナップショット
    $snapshotBefore = Get-DirectorySnapshot -InstallDir $InstallDir

    # 抽出実行
    $result = Invoke-ExtractStrategy `
        -PackageConfig $pkg `
        -ArchiveFile $(if ($archiveFile) { $archiveFile } else { "" }) `
        -BinDir $InstallDir `
        -ScriptDir $ScriptDir

    if (-not $result) {
        Write-Host "Error: Extraction failed for '$ShortName'" -ForegroundColor Red
        return $false
    }

    # インストール後スナップショット差分からファイル一覧を取得
    $installedFiles = Get-FileSnapshotDiff -InstallDir $InstallDir -Before $snapshotBefore

    # TargetDirectory 系はディレクトリ名を代表ファイルとして記録
    $targetDir = if ($pkg.ContainsKey("TargetDirectory")) { $pkg.TargetDirectory } else { $null }
    if ($targetDir -and (Test-Path (Join-Path $InstallDir $targetDir))) {
        $installedFiles = @($targetDir)
    }

    # PATH 追加
    $pathDirs = if ($pkg.ContainsKey("PathDirs")) { @($pkg.PathDirs) } else { @() }
    if ($pathDirs.Count -gt 0) {
        Write-Host ""
        Write-Host "  PATH を更新中..."
        Add-ComponentPathDirs -InstallDir $InstallDir -PackageConfig $pkg | Out-Null
    }

    # 環境変数設定
    $envVarsConfig = if ($pkg.ContainsKey("EnvVars")) { $pkg.EnvVars } else { @{} }
    $appliedEnvVars = @{}
    if ($envVarsConfig.Count -gt 0) {
        Write-Host ""
        Write-Host "  環境変数を設定中..."
        $appliedEnvVars = Set-ComponentEnvVars -InstallDir $InstallDir -PackageConfig $pkg
    }

    # ベース PATH を追加 (最初のコンポーネントインストール時)
    Add-BasePathDir -InstallDir $InstallDir

    # マニフェストに記録
    $version = if ($pkg.ContainsKey("Version")) { $pkg.Version } else { "" }
    Add-ComponentToManifest `
        -Manifest $Manifest `
        -ShortName $ShortName `
        -Version $version `
        -ArchiveFile (Split-Path $(if ($archiveFile) { $archiveFile } else { "(no-archive)" }) -Leaf) `
        -Files $installedFiles `
        -PathDirs $pathDirs `
        -EnvVars $appliedEnvVars

    Write-Host ""
    Write-Host "  $($pkg.Name) のインストールが完了しました"

    return $true
}

# コンポーネントをアンインストールする
function Uninstall-Component {
    param(
        [string]$ShortName,
        [array]$Packages,
        [string]$InstallDir,
        [hashtable]$Manifest,
        [switch]$Force
    )

    $pkg = Get-PackageByShortName -ShortName $ShortName -Packages $Packages
    if (-not $pkg) {
        Write-Host "Error: Package '$ShortName' not found" -ForegroundColor Red
        return $false
    }

    if (-not (Test-ComponentInstalled -Manifest $Manifest -ShortName $ShortName)) {
        Write-Host "  '$ShortName' はインストールされていません" -ForegroundColor Cyan
        return $true
    }

    # 依存元コンポーネントを確認
    if (-not $Force) {
        $dependents = Get-Dependents -ShortName $ShortName -Packages $Packages -Manifest $Manifest
        if ($dependents.Count -gt 0) {
            $depNames = $dependents | ForEach-Object {
                $d = Get-PackageByShortName -ShortName $_ -Packages $Packages
                if ($d) { $d.Name } else { $_ }
            }
            Write-Host ""
            Write-Host "警告: 以下のコンポーネントが '$($pkg.Name)' に依存しています:" -ForegroundColor Yellow
            foreach ($dn in $depNames) {
                Write-Host "  - $dn" -ForegroundColor Yellow
            }
            $confirm = Read-Host "アンインストールを続行しますか? [y/N]"
            if ($confirm -notmatch "^[yY]") {
                Write-Host "キャンセルしました"
                return $false
            }
        }
    }

    Write-Host ""
    Write-Host "=== $($pkg.Name) をアンインストール中 ==="

    # VS Code: data フォルダをバックアップ
    $isVSCode = $ShortName -eq "vscode"
    $vscodeBackup = $null
    if ($isVSCode) {
        $vscodeBackup = Backup-VSCodeData -InstallDirectory $InstallDir -Silent
    }

    # マニフェストのファイル一覧に基づいて削除
    $componentData = $Manifest.components[$ShortName]
    $files = if ($componentData -and $componentData.ContainsKey("files")) {
        @($componentData.files) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    } else {
        @()
    }
    $targetDir = if ($pkg.ContainsKey("TargetDirectory")) { $pkg.TargetDirectory } else { $null }

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
        # 他コンポーネントのファイル一覧を収集 (参照カウント・ルートディレクトリ保護用)
        $allOtherFiles = @{}
        foreach ($otherShortName in $Manifest.components.Keys) {
            if ($otherShortName -eq $ShortName) { continue }
            $otherData = $Manifest.components[$otherShortName]
            foreach ($f in @($otherData.files) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) {
                $allOtherFiles[$f] = $true
            }
        }

        if ($files.Count -gt 0) {
            # ファイルリスト削除 (参照カウント確認)
            foreach ($file in $files) {
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
            $detectFiles = if ($pkg.ContainsKey("DetectFiles")) { @($pkg.DetectFiles) } else { @() }
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
        $sourcePaths = if ($files.Count -gt 0) { $files } else {
            if ($pkg.ContainsKey("DetectFiles")) { @($pkg.DetectFiles) } else { @() }
        }
        $rootDirs = $sourcePaths |
            Where-Object { $_ } |
            ForEach-Object { ($_ -split '[\\\/]')[0] } |
            Where-Object { $_ } |
            Sort-Object -Unique
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

    # VS Code: data フォルダを復元
    if ($isVSCode -and $vscodeBackup) {
        $vscodeDir = Join-Path $InstallDir "vscode"
        if (-not (Test-Path $vscodeDir)) {
            New-Item -ItemType Directory -Path $vscodeDir -Force | Out-Null
        }
        Restore-VSCodeData -InstallDirectory $InstallDir -BackupPath $vscodeBackup -Silent | Out-Null
    }

    # PATH 削除
    $pathDirs = if ($pkg.ContainsKey("PathDirs")) { @($pkg.PathDirs) } else { @() }
    if ($pathDirs.Count -gt 0) {
        Write-Host ""
        Write-Host "  PATH を更新中..."
        Remove-ComponentPathDirs -InstallDir $InstallDir -PackageConfig $pkg
    }

    # 環境変数削除
    $envVarsConfig = if ($pkg.ContainsKey("EnvVars")) { $pkg.EnvVars } else { @{} }
    if ($envVarsConfig.Count -gt 0) {
        Write-Host ""
        Write-Host "  環境変数を削除中..."
        Remove-ComponentEnvVars -InstallDir $InstallDir -PackageConfig $pkg
    }

    # マニフェストから削除
    Remove-ComponentFromManifest -Manifest $Manifest -ShortName $ShortName

    # 孤立した隠し依存パッケージを自動アンインストール
    Remove-OrphanDependencies -ShortName $ShortName -Packages $Packages -InstallDir $InstallDir -Manifest $Manifest

    # 全コンポーネントがアンインストールされたらベース PATH も削除
    $visibleInstalled = $Manifest.components.Keys | Where-Object {
        $p = Get-PackageByShortName -ShortName $_ -Packages $Packages
        $p -and -not ($p.ContainsKey("Hidden") -and $p.Hidden)
    }
    if (-not $visibleInstalled -or ($visibleInstalled | Measure-Object).Count -eq 0) {
        if ($Manifest.components.Count -eq 0) {
            Remove-BasePathDir -InstallDir $InstallDir
        }
    }

    Write-Host ""
    Write-Host "  $($pkg.Name) のアンインストールが完了しました"

    return $true
}

# 孤立した隠し依存パッケージを削除する
function Remove-OrphanDependencies {
    param(
        [string]$UninstalledShortName,
        [array]$Packages,
        [string]$InstallDir,
        [hashtable]$Manifest
    )

    # アンインストールされたパッケージの依存先を確認
    $pkg = Get-PackageByShortName -ShortName $UninstalledShortName -Packages $Packages
    if (-not $pkg) { return }

    $deps = if ($pkg.ContainsKey("DependsOn")) { @($pkg.DependsOn) } else { @() }

    foreach ($dep in $deps) {
        $depPkg = Get-PackageByShortName -ShortName $dep -Packages $Packages
        if (-not $depPkg) { continue }

        # 隠しパッケージのみ自動削除対象
        $isHidden = $depPkg.ContainsKey("Hidden") -and $depPkg.Hidden
        if (-not $isHidden) { continue }

        # インストール済みか確認
        if (-not (Test-ComponentInstalled -Manifest $Manifest -ShortName $dep)) { continue }

        # 他に依存元がないか確認
        $remainingDependents = Get-Dependents -ShortName $dep -Packages $Packages -Manifest $Manifest
        if ($remainingDependents.Count -eq 0) {
            Write-Host ""
            Write-Host "  孤立した依存パッケージを削除: $($depPkg.Name)" -ForegroundColor Cyan
            Uninstall-Component `
                -ShortName $dep `
                -Packages $Packages `
                -InstallDir $InstallDir `
                -Manifest $Manifest `
                -Force | Out-Null
        }
    }
}

# コンポーネントを再インストール(更新)する
function Update-Component {
    param(
        [string]$ShortName,
        [array]$Packages,
        [string]$InstallDir,
        [string]$ScriptDir,
        [hashtable]$Manifest
    )

    $pkg = Get-PackageByShortName -ShortName $ShortName -Packages $Packages
    if (-not $pkg) {
        Write-Host "Error: Package '$ShortName' not found" -ForegroundColor Red
        return $false
    }

    Write-Host ""
    Write-Host "=== $($pkg.Name) を再インストール中 ==="

    # アンインストール (依存元への影響を無視して強制実行)
    Remove-ComponentFromManifest -Manifest $Manifest -ShortName $ShortName

    # TargetDirectory 系はディレクトリを削除してクリーンにする
    $targetDir = if ($pkg.ContainsKey("TargetDirectory")) { $pkg.TargetDirectory } else { $null }
    if ($targetDir) {
        $targetPath = Join-Path $InstallDir $targetDir
        if (Test-Path $targetPath) {
            # VS Code data を保護
            if ($ShortName -eq "vscode") {
                $vscodeBackup = Backup-VSCodeData -InstallDirectory $InstallDir -Silent
            }
            try {
                Remove-Item -Path $targetPath -Recurse -Force -ErrorAction Stop
            } catch {
                Write-Host "Warning: Could not remove '$targetDir': $($_.Exception.Message)" -ForegroundColor Yellow
            }
            if ($ShortName -eq "vscode" -and $vscodeBackup) {
                $vscodeDir = Join-Path $InstallDir "vscode"
                if (-not (Test-Path $vscodeDir)) {
                    New-Item -ItemType Directory -Path $vscodeDir -Force | Out-Null
                }
                Restore-VSCodeData -InstallDirectory $InstallDir -BackupPath $vscodeBackup -Silent | Out-Null
            }
        }
    }

    # 再インストール
    $result = Install-Component `
        -ShortName $ShortName `
        -Packages $Packages `
        -InstallDir $InstallDir `
        -ScriptDir $ScriptDir `
        -Manifest $Manifest `
        -SkipDeps

    return $result
}

# 複数ディレクトリを PATH に追加するヘルパー
function Add-MultiplePathDirs {
    param([string[]]$Directories)

    $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if (-not $currentPath) { $currentPath = "" }

    $changed = $false
    foreach ($dir in $Directories) {
        if (-not (Test-Path $dir)) {
            Write-Host "  Directory not found: $dir" -ForegroundColor Yellow
            continue
        }
        $entries = $currentPath -split ';' | Where-Object { $_.Trim() -ne "" }
        if ($entries -contains $dir) {
            Write-Host "  Already in PATH: $dir"
            continue
        }
        $currentPath = if ($currentPath) { "$dir;$currentPath" } else { $dir }
        Write-Host "  Added: $dir"
        $changed = $true
    }

    if ($changed) {
        [Environment]::SetEnvironmentVariable("PATH", $currentPath, "User")
    }
}

Export-ModuleMember -Function @(
    'Get-PackageByShortName',
    'Resolve-Dependencies',
    'Get-Dependents',
    'Install-Component',
    'Uninstall-Component',
    'Update-Component',
    'Add-ComponentPathDirs',
    'Remove-ComponentPathDirs',
    'Set-ComponentEnvVars',
    'Remove-ComponentEnvVars',
    'Add-BasePathDir',
    'Remove-BasePathDir'
)
