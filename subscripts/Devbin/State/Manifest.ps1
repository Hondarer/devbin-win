# Manifest.ps1
# インストールマニフェストの入出力とファイル一覧

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
                version     = if ($comp.PSObject.Properties["version"]) { $comp.version } else { "" }
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

# マニフェストを保存する (.tmp に書いてから置換。失敗時は旧ファイルを保持)
# 戻り値: 保存に成功したかどうか
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
            [System.IO.File]::Replace($tmpPath, $manifestPath, [System.Management.Automation.Language.NullString]::Value)
        } else {
            [System.IO.File]::Move($tmpPath, $manifestPath)
        }
        return $true
    } catch {
        Write-Host "Error: Failed to write manifest: $($_.Exception.Message)" -ForegroundColor Red
        if (Test-Path $tmpPath) {
            Remove-Item $tmpPath -Force -ErrorAction SilentlyContinue
        }
        return $false
    }
}

# コンポーネントをマニフェストに追加/更新する
function Add-ComponentToManifest {
    param(
        [hashtable]$Manifest,
        [string]$ShortName,
        [string]$Version = "",
        [string]$ArchiveFile,
        [string[]]$Files,
        [string[]]$PathDirs,
        [hashtable]$EnvVars = @{}
    )

    $Manifest.components[$ShortName] = @{
        installedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        version     = $Version
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
            $version = if ($pkg.ContainsKey("Version")) { $pkg.Version } else { "" }

            Add-ComponentToManifest `
                -Manifest $manifest `
                -ShortName $shortName `
                -Version $version `
                -ArchiveFile "(legacy)" `
                -Files @() `
                -PathDirs $pathDirs `
                -EnvVars $envVars

            Write-Host "  検出: $($pkg.Name)" -ForegroundColor Cyan
        }
    }

    return $manifest
}

# 導入先とマニフェストを使える状態にする
# マニフェストが無く既存ファイルがある場合は Legacy として生成し、保存まで行う
# 戻り値: Manifest / LegacyDetected / Saved
function Initialize-ComponentManifest {
    param(
        [string]$InstallDir,
        [array]$Packages
    )

    if (-not (Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }

    $manifest = Read-Manifest -InstallDir $InstallDir
    $manifestPath = Get-ManifestPath -InstallDir $InstallDir
    $legacyDetected = $false
    $saved = $true

    if (-not (Test-Path $manifestPath)) {
        $existingFiles = Get-ChildItem -Path $InstallDir -File -ErrorAction SilentlyContinue
        if ($existingFiles -and $existingFiles.Count -gt 0) {
            $legacyDetected = $true
            $manifest = Initialize-LegacyManifest -InstallDir $InstallDir -Packages $Packages
            $saved = Write-Manifest -InstallDir $InstallDir -Manifest $manifest
        }
    }

    return [PSCustomObject]@{
        Manifest       = $manifest
        LegacyDetected = $legacyDetected
        Saved          = $saved
    }
}
