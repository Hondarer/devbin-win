# Manifest.ps1
# インストールマニフェスト (.devbin-manifest.json) の入出力およびファイルスナップショット管理

$script:ManifestFileName = ".devbin-manifest.json"
$script:ManifestVersion = 1

# マニフェストファイルの絶対パスを取得
function Get-ManifestPath {
    param([string]$InstallDir)
    return Join-Path $InstallDir $script:ManifestFileName
}

# マニフェストファイルを読み込み (ファイルが存在しない場合は初期構造のハッシュテーブルを返却)
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

        # JSON からデシリアライズされた PSCustomObject をハッシュテーブルへ変換
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

# マニフェストをアトミックに保存 (一時ファイル書き込み後に置換、失敗時は既存ファイルを保持)
# 戻り値: 保存成功時は $true、失敗時は $false
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

# コンポーネント情報をマニフェストに追加または更新
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

# コンポーネント情報をマニフェストから削除
function Remove-ComponentFromManifest {
    param(
        [hashtable]$Manifest,
        [string]$ShortName
    )

    if ($Manifest.components.ContainsKey($ShortName)) {
        $Manifest.components.Remove($ShortName)
    }
}

# 該当コンポーネントがインストールされているかを検証
# マニフェストは devbin が最後に操作した結果です。NpmInstall コンポーネントは利用者が npm -g で追加・削除できるため、
# Packages と InstallDir を渡した場合は、マニフェストではなく npm のグローバル ツリーの実物で判定します。
function Test-ComponentInstalled {
    param(
        [hashtable]$Manifest,
        [string]$ShortName,
        [array]$Packages = @(),
        [string]$InstallDir = ""
    )

    if (-not [string]::IsNullOrWhiteSpace($InstallDir) -and @($Packages).Count -gt 0) {
        $pkg = Get-PackageByShortName -ShortName $ShortName -Packages $Packages
        if ($pkg -and [string]$pkg.ExtractStrategy -eq "NpmInstall" -and $pkg.ContainsKey("NpmPackage")) {
            return -not [string]::IsNullOrWhiteSpace((Get-NpmGlobalPackageVersion -BinDir $InstallDir -PackageName ([string]$pkg.NpmPackage)))
        }
    }

    return $Manifest.components.ContainsKey($ShortName)
}

# 検出対象ファイル (DetectFiles) がファイルシステム上に実在するかを検証
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

# インストール前後のファイルスナップショットを比較し、新規追加された相対パス一覧を取得
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

# 対象ディレクトリ内のファイルスナップショット (相対パスから最終更新日時へのマッピング) を取得
function Get-DirectorySnapshot {
    param([string]$InstallDir)

    $snapshot = @{}

    if (-not (Test-Path $InstallDir)) {
        return $snapshot
    }

    try {
        $items = Get-ChildItem -Path $InstallDir -Recurse -File -ErrorAction SilentlyContinue
        foreach ($item in $items) {
            # マニフェストファイル自身はスナップショットから除外
            if ($item.Name -eq $script:ManifestFileName) {
                continue
            }
            $relativePath = $item.FullName.Substring($InstallDir.Length).TrimStart('\', '/')
            $snapshot[$relativePath] = $item.LastWriteTimeUtc
        }
    } catch {
        # スナップショット取得時の例外は無視
    }

    return $snapshot
}

# レガシーインストール (マニフェスト不在) のディレクトリを走査し、検出されたコンポーネント情報から初期マニフェストを生成
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

# インストール先ディレクトリおよびマニフェストを初期化
# マニフェストが存在せず既存ファイルが検出された場合は、レガシーマニフェストを自動生成して保存
# 戻り値: Manifest (ハッシュテーブル) / LegacyDetected (ブール値) / Saved (ブール値) を含むオブジェクト
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
