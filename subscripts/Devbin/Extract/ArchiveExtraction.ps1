# ArchiveExtraction.ps1
# 各抽出戦略で共通利用されるアーカイブ展開・パス解決ヘルパー

# アーカイブファイルのゾーン識別子 (Mark-of-the-Web) を解除
function Unblock-ArchiveFile {
    param([string]$ArchiveFile)

    try {
        Unblock-File -Path $ArchiveFile -ErrorAction SilentlyContinue
    } catch {
        # ゾーン識別子の解除に失敗した場合も処理を継続
    }
}

# アーカイブを一時ディレクトリに展開 (拡張子に応じて Expand-Archive または tar.exe を使用)
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
            Write-Host "    Using Windows built-in tar.exe (libarchive) for $fileExtension extraction..."

            $absoluteArchive = (Resolve-Path $ArchiveFile).Path
            $absoluteTempDir = (Resolve-Path $TempDir).Path

            & $tarPath -xf $absoluteArchive -C $absoluteTempDir

            if ($LASTEXITCODE -ne 0) {
                throw "tar.exe extraction failed with exit code: $LASTEXITCODE"
            }

            Write-Host "    Successfully extracted $fileExtension file using tar.exe"
        } else {
            throw "tar.exe not found at expected location: $tarPath"
        }
    }
    else {
        throw "Unsupported file type: $fileExtension"
    }
}

# 展開先一時ディレクトリからソースルートパスを特定
function Get-ExtractedSourcePath {
    param([string]$TempDir)

    $extractedItems = Get-ChildItem -Path $TempDir
    $extractedFolders = $extractedItems | Where-Object { $_.PSIsContainer }

    if (-not $extractedFolders -and ($extractedItems | Where-Object { -not $_.PSIsContainer })) {
        # サブディレクトリが存在せずファイルのみの場合は TempDir を返却
        return $TempDir
    }
    elseif ($extractedFolders.Count -eq 1) {
        # 単一のルートディレクトリが存在する場合はそのフルパスを返却
        return $extractedFolders[0].FullName
    }
    elseif ($extractedFolders.Count -gt 1) {
        # 複数のディレクトリが存在する場合は TempDir を返却
        return $TempDir
    }

    return $null
}

# 抽出後処理 (PostExtract) でコピーする追加ファイルのパスを解決
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
