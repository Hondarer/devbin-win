# Setup-Manifest.psm1
# インストールマニフェスト管理モジュール

$script:ManifestFileName = ".devbin-manifest.json"
$script:ManifestVersion = 1

# マニフェストファイルのパスを取得する
function Get-ManifestPath {
    param([string]$InstallDir)
    return Join-Path $InstallDir $script:ManifestFileName
}

# マニフェストを読み込む。存在しなければ空のマニフェストを返す
function Read-Manifest {
    param([string]$InstallDir)

    $manifestPath = Get-ManifestPath $InstallDir

    if (-not (Test-Path $manifestPath)) {
        return @{
            version = $script:ManifestVersion
            components = @{}
        }
    }

    try {
        $json = Get-Content $manifestPath -Raw -Encoding UTF8
        $obj = $json | ConvertFrom-Json

        # PSCustomObject をハッシュテーブルに変換
        $manifest = @{
            version = $obj.version
            components = @{}
        }

        foreach ($prop in $obj.components.PSObject.Properties) {
            $comp = $prop.Value
            $manifest.components[$prop.Name] = @{
                installedAt = $comp.installedAt
                archiveFile = $comp.archiveFile
                files = @($comp.files)
                pathDirs = @($comp.pathDirs)
                envVars = @{}
            }
            if ($comp.envVars) {
                foreach ($envProp in $comp.envVars.PSObject.Properties) {
                    $manifest.components[$prop.Name].envVars[$envProp.Name] = $envProp.Value
                }
            }
        }

        return $manifest
    } catch {
        Write-Host "Warning: Failed to read manifest: $($_.Exception.Message)" -ForegroundColor Yellow
        return @{
            version = $script:ManifestVersion
            components = @{}
        }
    }
}

# マニフェストを保存する (擬似アトミック: .tmp に書いてからリネーム)
function Write-Manifest {
    param(
        [string]$InstallDir,
        [hashtable]$Manifest
    )

    $manifestPath = Get-ManifestPath $InstallDir
    $tmpPath = "$manifestPath.tmp"

    try {
        $json = $Manifest | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($tmpPath, $json, [System.Text.Encoding]::UTF8)

        if (Test-Path $manifestPath) {
            Remove-Item $manifestPath -Force
        }
        Move-Item $tmpPath $manifestPath -Force
    } catch {
        Write-Host "Warning: Failed to write manifest: $($_.Exception.Message)" -ForegroundColor Yellow
        if (Test-Path $tmpPath) {
            Remove-Item $tmpPath -Force -ErrorAction SilentlyContinue
        }
    }
}

# コンポーネントをマニフェストに追加/更新する
function Add-ComponentToManifest {
    param(
        [hashtable]$Manifest,
        [string]$ShortName,
        [string]$ArchiveFile,
        [string[]]$Files,
        [string[]]$PathDirs,
        [hashtable]$EnvVars = @{}
    )

    $Manifest.components[$ShortName] = @{
        installedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        archiveFile = $ArchiveFile
        files = $Files
        pathDirs = $PathDirs
        envVars = $EnvVars
    }
}

# コンポーネントをマニフェストから削除する
function Remove-ComponentFromManifest {
    param(
        [hashtable]$Manifest,
        [string]$ShortName
    )

    if ($Manifest.components.ContainsKey($ShortName)) {
        $Manifest.components.Remove($ShortName)
    }
}

# マニフェスト上でコンポーネントがインストール済みかを確認する
function Test-ComponentInstalled {
    param(
        [hashtable]$Manifest,
        [string]$ShortName
    )

    return $Manifest.components.ContainsKey($ShortName)
}

# ファイルシステム上でコンポーネントのファイルが実在するかを確認する
function Test-ComponentFiles {
    param(
        [string]$InstallDir,
        [string[]]$DetectFiles
    )

    if (-not $DetectFiles -or $DetectFiles.Count -eq 0) {
        return $false
    }

    foreach ($file in $DetectFiles) {
        $fullPath = Join-Path $InstallDir $file
        if (Test-Path $fullPath) {
            return $true
        }
    }
    return $false
}

# コンポーネントの総合ステータスを返す: Installed / NotInstalled / Broken
function Get-ComponentStatus {
    param(
        [hashtable]$Manifest,
        [string]$InstallDir,
        [hashtable]$PackageConfig
    )

    $shortName = $PackageConfig.ShortName
    $inManifest = Test-ComponentInstalled -Manifest $Manifest -ShortName $shortName

    # DetectFiles が未指定の場合はマニフェストのみで判断
    $detectFiles = if ($PackageConfig.ContainsKey("DetectFiles")) { @($PackageConfig.DetectFiles) } else { @() }

    if ($inManifest) {
        if ($detectFiles.Count -eq 0) {
            return "Installed"
        }
        $filesExist = Test-ComponentFiles -InstallDir $InstallDir -DetectFiles $detectFiles
        if ($filesExist) {
            return "Installed"
        } else {
            return "Broken"
        }
    } else {
        # マニフェストにないがファイルが存在する = レガシーインストール
        if ($detectFiles.Count -gt 0) {
            $filesExist = Test-ComponentFiles -InstallDir $InstallDir -DetectFiles $detectFiles
            if ($filesExist) {
                return "Legacy"
            }
        }
        return "NotInstalled"
    }
}

# インストール前後のファイルスナップショット差分を取得する
function Get-FileSnapshotDiff {
    param(
        [string]$InstallDir,
        [hashtable]$Before
    )

    $after = Get-DirectorySnapshot -InstallDir $InstallDir
    $newFiles = @()

    foreach ($key in $after.Keys) {
        if (-not $Before.ContainsKey($key)) {
            $newFiles += $key
        }
    }

    return $newFiles
}

# ディレクトリのファイルスナップショット(相対パス → 最終更新時刻)を取得する
function Get-DirectorySnapshot {
    param([string]$InstallDir)

    $snapshot = @{}

    if (-not (Test-Path $InstallDir)) {
        return $snapshot
    }

    try {
        $items = Get-ChildItem -Path $InstallDir -Recurse -File -ErrorAction SilentlyContinue
        foreach ($item in $items) {
            # マニフェストファイル自体は除外
            if ($item.Name -eq $script:ManifestFileName) {
                continue
            }
            $relativePath = $item.FullName.Substring($InstallDir.Length).TrimStart('\', '/')
            $snapshot[$relativePath] = $item.LastWriteTimeUtc
        }
    } catch {
        # スナップショット取得失敗は無視
    }

    return $snapshot
}

# レガシーインストール(マニフェストなし)をスキャンしてマニフェストを生成する
function Initialize-LegacyManifest {
    param(
        [string]$InstallDir,
        [array]$Packages
    )

    $manifest = @{
        version = $script:ManifestVersion
        components = @{}
    }

    Write-Host "既存インストールを検出しました。マニフェストを生成します..." -ForegroundColor Cyan

    foreach ($pkg in $Packages) {
        $shortName = $pkg.ShortName
        $detectFiles = if ($pkg.ContainsKey("DetectFiles")) { @($pkg.DetectFiles) } else { @() }

        if ($detectFiles.Count -eq 0) {
            continue
        }

        $filesExist = Test-ComponentFiles -InstallDir $InstallDir -DetectFiles $detectFiles
        if ($filesExist) {
            $pathDirs = if ($pkg.ContainsKey("PathDirs")) { @($pkg.PathDirs) } else { @() }
            $envVars = if ($pkg.ContainsKey("EnvVars")) { $pkg.EnvVars } else { @{} }

            Add-ComponentToManifest `
                -Manifest $manifest `
                -ShortName $shortName `
                -ArchiveFile "(legacy)" `
                -Files @() `
                -PathDirs $pathDirs `
                -EnvVars $envVars

            Write-Host "  検出: $($pkg.Name)" -ForegroundColor Cyan
        }
    }

    return $manifest
}

Export-ModuleMember -Function @(
    'Get-ManifestPath',
    'Read-Manifest',
    'Write-Manifest',
    'Add-ComponentToManifest',
    'Remove-ComponentFromManifest',
    'Test-ComponentInstalled',
    'Test-ComponentFiles',
    'Get-ComponentStatus',
    'Get-FileSnapshotDiff',
    'Get-DirectorySnapshot',
    'Initialize-LegacyManifest'
)
