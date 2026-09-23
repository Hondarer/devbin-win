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
        # 再インストールの一部として呼ばれた場合は見出しを出さず、完了メッセージを再インストール向けにします。
        [switch]$Reinstall,
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
    if (-not $Reinstall) {
        Write-Host "=== $($pkg.Name) をインストール中 ==="
        Write-Host ""
    }

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
        Write-Host "  Error: Extraction failed for '$ShortName'" -ForegroundColor Red
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
            Write-Host "    Error: Failed to configure runtime environment: $($_.Exception.Message)" -ForegroundColor Red
            return $false
        }
    }

    # ユーザー設定・キャッシュの保存先 (data 配下) を用意し、未設定の環境変数だけを設定します。
    try {
        $storageEnvNames = @(Initialize-DevbinComponentStorage -ShortName $ShortName)
        if ($storageEnvNames.Count -gt 0) {
            Write-Host "  ユーザー データの保存先を設定しました: $($storageEnvNames -join ', ')"
            Sync-EnvironmentVariables -VariableNames $storageEnvNames -Indent 4 | Out-Null
        }
    } catch {
        Write-Host "    Warning: ユーザー データの保存先を設定できません: $($_.Exception.Message)" -ForegroundColor Yellow
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
    if ($Reinstall) {
        Write-Host "  $($pkg.Name) の再インストールが完了しました"
    } else {
        Write-Host "  $($pkg.Name) のインストールが完了しました"
    }

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
    Write-Host ""

    # 削除対象はマニフェスト解除前に確保します。解除後は PATH から外します。
    $componentData = $null
    if ($Manifest.components.ContainsKey($ShortName)) {
        $componentData = $Manifest.components[$ShortName]
    }
    $previousFiles = @()
    if ($componentData -and $componentData.ContainsKey("files")) {
        $previousFiles = @($componentData.files) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    }

    Remove-ComponentFromManifest -Manifest $Manifest -ShortName $ShortName
    Write-Host "  PATH を更新中..."
    Sync-ComponentManagerPath -InstallDir $InstallDir -Packages $Packages -Manifest $Manifest

    # 上書き展開だと Node 付属 npm と既存 node_modules が混ざり、直後の npm cache add が失敗します。
    $hasCleanupPatterns = $pkg.ContainsKey("CleanupPatterns")
    $hasTargetDirectory = $pkg.ContainsKey("TargetDirectory")
    if ($hasCleanupPatterns -or $hasTargetDirectory -or $previousFiles.Count -gt 0) {
        Write-Host ""
        Write-Host "  既存のファイルを削除中..."
    }
    Remove-ComponentInstalledFiles `
        -ShortName $ShortName `
        -PackageConfig $pkg `
        -InstallDir $InstallDir `
        -Manifest $Manifest `
        -Files $previousFiles

    # コンポーネントを再インストールします。
    $result = Install-Component `
        -ShortName $ShortName `
        -Packages $Packages `
        -InstallDir $InstallDir `
        -ScriptDir $ScriptDir `
        -Manifest $Manifest `
        -SkipDeps `
        -Reinstall

    return $result
}
