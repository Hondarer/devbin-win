# ComponentPath.ps1
# コンポーネント関連ディレクトリのユーザー環境変数 PATH への反映および同期

# 複数のディレクトリをユーザー環境変数 PATH に追加します。
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

# パッケージ定義に基づいて PATH ディレクトリを追加します (SkipIfCommand によるスキップ判定を含む)。
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

# パッケージ定義に基づいて PATH ディレクトリを削除します。
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

# インストール先ルートディレクトリ (bin ディレクトリ) をユーザー環境変数 PATH に追加します。
function Add-BasePathDir {
    param([string]$InstallDir)

    $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if ($currentPath -and ($currentPath -split ';' | Where-Object { $_ -eq $InstallDir })) {
        return
    }
    Add-MultiplePathDirs -Directories @($InstallDir)
}

# インストール先ルートディレクトリ (bin ディレクトリ) をユーザー環境変数 PATH から削除します。
function Remove-BasePathDir {
    param([string]$InstallDir)
    Remove-FromUserPath -Directories @($InstallDir)
}

# コンポーネントのインストール状態に基づいてユーザー環境変数 PATH を再構成します。
function Sync-ComponentManagerPath {
    param(
        [string]$InstallDir,
        [array]$Packages,
        [hashtable]$Manifest
    )

    $installedShortNames = if ($Manifest -and $Manifest.components) {
        @($Manifest.components.Keys)
    } else {
        @()
    }

    $includeBaseDir = $false
    if ($Manifest -and $Manifest.components -and $Manifest.components.Count -gt 0) {
        $includeBaseDir = $true
    }

    Sync-ManagedUserPath `
        -InstallDir $InstallDir `
        -Packages $Packages `
        -InstalledShortNames $installedShortNames `
        -IncludeBaseDir:$includeBaseDir
}
