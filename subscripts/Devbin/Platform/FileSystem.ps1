# FileSystem.ps1
# 長いパス (MAX_PATH 超過) に対応したファイル操作およびディレクトリツリーの削除

# 長いパスを拡張長パス形式 (\\?\) に変換
function Convert-ToLongPath {
    param([string]$Path)

    if ($Path.StartsWith("\\?\")) {
        return $Path
    }

    if (-not [System.IO.Path]::IsPathRooted($Path)) {
        $Path = (Resolve-Path $Path -ErrorAction SilentlyContinue).Path
        if (-not $Path) {
            return $null
        }
    }

    # UNC パス (\\server\share) は \\?\UNC\server\share の形式に変換
    if ($Path.StartsWith("\\")) {
        return "\\?\UNC\" + $Path.Substring(2)
    }

    return "\\?\$Path"
}

# 長いパスに対応したディレクトリ作成
function New-LongPathDirectory {
    param([string]$Path)

    $longPath = Convert-ToLongPath $Path
    if ($longPath -and !(Test-Path $longPath)) {
        try {
            New-Item -ItemType Directory -Path $longPath -Force | Out-Null
            return $true
        } catch {
            Write-Host "  Warning: Failed to create directory: $Path"
            Write-Host "  Error: $($_.Exception.Message)"
            return $false
        }
    }
    return $true
}

# 長いパスに対応したファイルコピー
function Copy-LongPathFile {
    param(
        [string]$SourcePath,
        [string]$DestinationPath
    )

    $longSourcePath = Convert-ToLongPath $SourcePath
    $longDestinationPath = Convert-ToLongPath $DestinationPath

    if ($longSourcePath -and $longDestinationPath) {
        try {
            Copy-Item -Path $longSourcePath -Destination $longDestinationPath -Force
            return $true
        } catch {
            Write-Host "  Warning: Failed to copy file: $(Split-Path $SourcePath -Leaf)"
            Write-Host "  Error: $($_.Exception.Message)"
            return $false
        }
    }
    return $false
}

# ディレクトリツリーの削除 (MAX_PATH 超過時は robocopy による空同期へフォールバック)
function Remove-DirectoryTree {
    param(
        [string]$Path
    )

    $lastError = $null

    try {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        return [PSCustomObject]@{ Success = $true; ErrorMessage = $null }
    } catch {
        $lastError = $_.Exception.Message
    }

    if (-not (Get-Command robocopy.exe -ErrorAction SilentlyContinue)) {
        return [PSCustomObject]@{ Success = $false; ErrorMessage = $lastError }
    }

    # robocopy は長いパスを処理可能なため、空ディレクトリとの /MIR 同期により配下を消去した後に本体を削除
    $emptyDir = Join-Path ([System.IO.Path]::GetTempPath()) ("devbin-empty-" + [System.Guid]::NewGuid().ToString("N"))
    try {
        New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null
        & robocopy.exe $emptyDir $Path /MIR /NFL /NDL /NJH /NJS /NP /R:0 /W:0 | Out-Null
        if ($LASTEXITCODE -ge 8) {
            return [PSCustomObject]@{ Success = $false; ErrorMessage = $lastError }
        }

        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        return [PSCustomObject]@{ Success = $true; ErrorMessage = $null }
    } catch {
        return [PSCustomObject]@{ Success = $false; ErrorMessage = $_.Exception.Message }
    } finally {
        if (Test-Path -LiteralPath $emptyDir) {
            Remove-Item -LiteralPath $emptyDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
