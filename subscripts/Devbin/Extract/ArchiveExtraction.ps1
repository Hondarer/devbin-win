# ArchiveExtraction.ps1
# 戦略が共有するアーカイブ展開の下請け

# アーカイブファイルをブロック解除する共通関数
function Unblock-ArchiveFile {
    param([string]$ArchiveFile)

    try {
        Unblock-File -Path $ArchiveFile -ErrorAction SilentlyContinue
    } catch {
        # ブロック解除に失敗した場合は続行
    }
}

# アーカイブを一時ディレクトリに展開する共通関数
function Expand-ArchiveToTemp {
    param(
        [string]$ArchiveFile,
        [string]$TempDir
    )

    if (Test-Path $TempDir) {
        Remove-Item -Path $TempDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $TempDir | Out-Null

    $fileExtension = [System.IO.Path]::GetExtension($ArchiveFile).ToLower()

    if ($fileExtension -eq ".zip") {
        Expand-Archive -Path $ArchiveFile -DestinationPath $TempDir -Force
    }
    elseif ($fileExtension -in @(".7z", ".zst", ".xz")) {
        $tarPath = "$env:WINDIR\System32\tar.exe"
        if (Test-Path $tarPath) {
            Write-Host "Using Windows built-in tar.exe (libarchive) for $fileExtension extraction..."

            $absoluteArchive = (Resolve-Path $ArchiveFile).Path
            $absoluteTempDir = (Resolve-Path $TempDir).Path

            & $tarPath -xf $absoluteArchive -C $absoluteTempDir

            if ($LASTEXITCODE -ne 0) {
                throw "tar.exe extraction failed with exit code: $LASTEXITCODE"
            }

            Write-Host "Successfully extracted $fileExtension file using tar.exe"
        } else {
            throw "tar.exe not found at expected location: $tarPath"
        }
    }
    else {
        throw "Unsupported file type: $fileExtension"
    }
}

# 展開されたソースパスを取得する共通関数
function Get-ExtractedSourcePath {
    param([string]$TempDir)

    $extractedItems = Get-ChildItem -Path $TempDir
    $extractedFolders = $extractedItems | Where-Object { $_.PSIsContainer }

    if (-not $extractedFolders -and ($extractedItems | Where-Object { -not $_.PSIsContainer })) {
        # フォルダーがなく、ファイルのみの場合は TempDir を返す
        return $TempDir
    }
    elseif ($extractedFolders.Count -eq 1) {
        # フォルダーが1つだけの場合はそのフォルダーを返す
        return $extractedFolders[0].FullName
    }
    elseif ($extractedFolders.Count -gt 1) {
        # フォルダーが複数ある場合は TempDir を返す
        return $TempDir
    }

    return $null
}

# PostExtract の追加ファイルを解決する
function Resolve-PostExtractSourcePath {
    param(
        [string]$SourcePath,
        [string]$ScriptDir = ""
    )

    if ([string]::IsNullOrWhiteSpace($SourcePath)) {
        return $SourcePath
    }

    if ([System.IO.Path]::IsPathRooted($SourcePath)) {
        return $SourcePath
    }

    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($ScriptDir)) {
        $repositoryRoot = Split-Path -Parent $ScriptDir
        if (-not [string]::IsNullOrWhiteSpace($repositoryRoot)) {
            $candidates += Join-Path $repositoryRoot $SourcePath
        }
    }
    $candidates += $SourcePath

    foreach ($candidate in @($candidates | Select-Object -Unique)) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }

    return $candidates[0]
}
