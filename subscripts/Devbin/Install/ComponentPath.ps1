# ComponentPath.ps1
# コンポーネントのディレクトリをユーザー PATH へ反映する

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

# コンポーネントマネージャーの現在状態から PATH を再構成する
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
