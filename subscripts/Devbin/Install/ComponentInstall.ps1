# ComponentInstall.ps1
# コンポーネントの導入と再導入

# コンポーネントをインストールする
function Install-Component {
    param(
        [string]$ShortName,
        [array]$Packages,
        [string]$InstallDir,
        [string]$ScriptDir,
        [hashtable]$Manifest,
        [switch]$SkipDeps,
        [hashtable]$InProgress = @{}
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
        # 自分自身を解決中として記録し、循環依存で再帰が止まらなくなるのを防ぐ
        $InProgress[$ShortName] = $true
        foreach ($dep in $deps) {
            if ($InProgress.ContainsKey($dep)) {
                Write-Host "Error: 循環依存を検出しました: $ShortName -> $dep" -ForegroundColor Red
                return $false
            }
            if (-not (Test-ComponentInstalled -Manifest $Manifest -ShortName $dep)) {
                Write-Host ""
                Write-Host "  依存コンポーネントをインストール: $dep" -ForegroundColor Cyan
                $depResult = Install-Component `
                    -ShortName $dep `
                    -Packages $Packages `
                    -InstallDir $InstallDir `
                    -ScriptDir $ScriptDir `
                    -Manifest $Manifest `
                    -InProgress $InProgress
                if (-not $depResult) {
                    Write-Host "Error: Failed to install dependency '$dep'" -ForegroundColor Red
                    return $false
                }
            }
        }
        $InProgress.Remove($ShortName)
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
        $packagesDir = Get-PackagesDirectory -ScriptDir $ScriptDir
        $version = if (Get-Command Resolve-PackageVersion -ErrorAction SilentlyContinue) {
            Resolve-PackageVersion -PackageConfig $pkg -PackagesDir $packagesDir
        } else {
            if ($pkg.ContainsKey("Version")) { $pkg.Version } else { "" }
        }
        Add-ComponentToManifest `
            -Manifest $Manifest `
            -ShortName $ShortName `
            -Version $version `
            -ArchiveFile "(no-extract)" `
            -Files @() `
            -PathDirs $pathDirs
        return $true
    }

    # 導入に必要なファイルを用意する (不足していれば取得を試みる)
    $packagesDir = Get-PackagesDirectory -ScriptDir $ScriptDir
    $source = Resolve-ComponentSource `
        -ShortName $ShortName `
        -PackageConfig $pkg `
        -Packages $Packages `
        -InstallDir $InstallDir `
        -ScriptDir $ScriptDir `
        -PackagesDir $packagesDir

    if (-not $source.Success) {
        return $false
    }
    $archiveFile = $source.ArchiveFile

    # インストール前スナップショット
    $snapshotBefore = Get-DirectorySnapshot -InstallDir $InstallDir

    # 抽出実行
    $result = Invoke-ExtractStrategy `
        -PackageConfig $pkg `
        -ArchiveFile $(if ($archiveFile) { $archiveFile } else { "" }) `
        -BinDir $InstallDir `
        -ScriptDir $ScriptDir `
        -PackagesDir $packagesDir `
        -Packages $Packages

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

    $pathDirs = if ($pkg.ContainsKey("PathDirs")) { @($pkg.PathDirs) } else { @() }

    # 環境変数設定
    $envVarsConfig = if ($pkg.ContainsKey("EnvVars")) { $pkg.EnvVars } else { @{} }
    $appliedEnvVars = @{}
    $hasBrowserConfig = Test-ComponentUsesEdge -PackageConfig $pkg
    if ($envVarsConfig.Count -gt 0 -or $hasBrowserConfig) {
        Write-Host ""
        Write-Host "  環境変数を設定中..."
        try {
            $appliedEnvVars = Set-ComponentEnvVars -InstallDir $InstallDir -PackageConfig $pkg
        } catch {
            Write-Host "Error: Failed to configure runtime environment: $($_.Exception.Message)" -ForegroundColor Red
            return $false
        }
    }

    # マニフェストに記録
    $version = if (Get-Command Resolve-PackageVersion -ErrorAction SilentlyContinue) {
        Resolve-PackageVersion -PackageConfig $pkg -PackagesDir $packagesDir -ArchiveFile $(if ($archiveFile) { $archiveFile } else { "" })
    } else {
        if ($pkg.ContainsKey("Version")) { $pkg.Version } else { "" }
    }
    Add-ComponentToManifest `
        -Manifest $Manifest `
        -ShortName $ShortName `
        -Version $version `
        -ArchiveFile (Split-Path $(if ($archiveFile) { $archiveFile } else { "(no-archive)" }) -Leaf) `
        -Files $installedFiles `
        -PathDirs $pathDirs `
        -EnvVars $appliedEnvVars

    Write-Host ""
    Write-Host "  PATH を更新中..."
    Sync-ComponentManagerPath -InstallDir $InstallDir -Packages $Packages -Manifest $Manifest

    Invoke-PackageLifecycleScripts `
        -PackageConfig $pkg `
        -Phase "Install" `
        -InstallDir $InstallDir `
        -ScriptDir $ScriptDir

    Write-Host ""
    Write-Host "  $($pkg.Name) のインストールが完了しました"

    return $true
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
    Write-Host "  PATH を更新中..."
    Sync-ComponentManagerPath -InstallDir $InstallDir -Packages $Packages -Manifest $Manifest

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
