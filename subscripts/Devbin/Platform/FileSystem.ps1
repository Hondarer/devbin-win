# FileSystem.ps1
# 長いパスに対応したファイル操作と、ディレクトリツリーの削除

# 長いパスを UNC 形式に変換する関数
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

    return "\\?\$Path"
}

# 長いパス対応のディレクトリ作成関数
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

# 長いパス対応のファイルコピー関数
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

# ディレクトリツリーを削除する (260 文字を超えるパス向けに robocopy へフォールバック)
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

    # robocopy はロングパスを扱えるため、空ディレクトリとの /MIR で中身を空にしてから削除する
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
