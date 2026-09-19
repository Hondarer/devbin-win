# ComponentInstall.ps1
# コンポーネントのインストールおよび再インストール (更新)

# 単一のコンポーネントをインストールします。
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

    # インストール済みの場合は処理をスキップします。
    if (Test-ComponentInstalled -Manifest $Manifest -ShortName $ShortName) {
        Write-Host "  '$ShortName' は既にインストール済みです" -ForegroundColor Cyan
        return $true
    }

    # 依存コンポーネントを先行してインストールします。
    if (-not $SkipDeps) {
        $deps = if ($pkg.ContainsKey("DependsOn")) { @($pkg.DependsOn) } else { @() }
        # 循環依存による無限再帰を防止するため、処理中のコンポーネントを追跡します。
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

    # CopyToPackages 戦略の場合は展開をスキップします (ファイルは packages ディレクトリ内に保持)。
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

    # インストールに必要なファイルを取得・検証します。
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

    # インストール前のディレクトリスナップショットを取得します。
    $snapshotBefore = Get-DirectorySnapshot -InstallDir $InstallDir

    # 抽出戦略を実行します。
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

    # インストール前後のスナップショット差分から配置されたファイル一覧を算出します。
    $installedFiles = Get-FileSnapshotDiff -InstallDir $InstallDir -Before $snapshotBefore

    # TargetDirectory 指定時はディレクトリ名を代表エントリとして記録します。
    $targetDir = if ($pkg.ContainsKey("TargetDirectory")) { $pkg.TargetDirectory } else { $null }
    if ($targetDir -and (Test-Path (Join-Path $InstallDir $targetDir))) {
        $installedFiles = @($targetDir)
    }

    $pathDirs = if ($pkg.ContainsKey("PathDirs")) { @($pkg.PathDirs) } else { @() }

    # コンポーネント固有の環境変数を設定します。
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

    # インストール情報をマニフェストに記録します。
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

# コンポーネントの再インストール (更新) を実行します。
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

    # マニフェストから登録を解除し、PATH を更新します。
    Remove-ComponentFromManifest -Manifest $Manifest -ShortName $ShortName
    Write-Host "  PATH を更新中..."
    Sync-ComponentManagerPath -InstallDir $InstallDir -Packages $Packages -Manifest $Manifest

    # 自己更新時のバックアップ等、マニフェストに記録されない実行時の生成ファイルを削除します。
    Remove-ComponentCleanupFiles -ShortName $ShortName -PackageConfig $pkg -InstallDir $InstallDir -Manifest $Manifest

    # TargetDirectory 指定時はディレクトリをクリーンアップします。
    $targetDir = if ($pkg.ContainsKey("TargetDirectory")) { $pkg.TargetDirectory } else { $null }
    if ($targetDir) {
        $targetPath = Join-Path $InstallDir $targetDir
        if (Test-Path $targetPath) {
            # VS Code のポータブルデータ (data ディレクトリ) を退避します。
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

    # コンポーネントを再インストールします。
    $result = Install-Component `
        -ShortName $ShortName `
        -Packages $Packages `
        -InstallDir $InstallDir `
        -ScriptDir $ScriptDir `
        -Manifest $Manifest `
        -SkipDeps

    return $result
}
