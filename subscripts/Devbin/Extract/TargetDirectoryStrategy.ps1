# TargetDirectoryStrategy.ps1
# VersionNormalized および TargetDirectory 戦略: 指定ターゲットディレクトリへの展開

# VersionNormalized 戦略: フォルダ名からバージョン番号を抽出し、正規化名ターゲットディレクトリへ展開
function Invoke-VersionNormalizedExtract {
    param(
        [string]$ArchiveFile,
        [string]$BinDir,
        [string]$TempDir,
        [string]$VersionPattern,
        [string]$TargetDirectory
    )

    Unblock-ArchiveFile $ArchiveFile
    Expand-ArchiveToTemp -ArchiveFile $ArchiveFile -TempDir $TempDir

    $sourcePath = Get-ExtractedSourcePath $TempDir
    if (-not $sourcePath) {
        throw "Extracted folder not found"
    }

    $sourceFolder = $null

    if ((Split-Path $sourcePath -Leaf) -match $VersionPattern) {
        $sourceFolder = Get-Item $sourcePath
        Write-Host "Source path matches pattern: $($sourceFolder.Name)"
    } else {
        $sourceFolder = Get-ChildItem -Path $sourcePath -Directory | Where-Object { $_.Name -match $VersionPattern } | Select-Object -First 1
        if ($sourceFolder) {
            Write-Host "Found folder matching pattern: $($sourceFolder.Name)"
        }
    }

    if (-not $sourceFolder) {
        throw "Source folder matching pattern not found: $VersionPattern"
    }

    if ($sourceFolder.Name -match $VersionPattern) {
        $versionPart = $matches[1]
        $targetFolderName = $TargetDirectory -replace '\{0\}', $versionPart
        $targetPath = Join-Path $BinDir $targetFolderName

        Write-Host "Creating target directory: $targetFolderName"

        if (!(Test-Path $targetPath)) {
            New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
        }

        Get-ChildItem -Path $sourceFolder.FullName -Recurse | ForEach-Object {
            $relativePath = $_.FullName.Substring($sourceFolder.FullName.Length + 1)

            # ファイルのみをコピー (空ディレクトリの不要な生成を防止)
            if (-not $_.PSIsContainer) {
                $destinationPath = Join-Path $targetPath $relativePath
                $destinationDir = Split-Path $destinationPath -Parent
                if ($destinationDir -and !(Test-Path $destinationDir)) {
                    New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
                }
                Copy-Item -Path $_.FullName -Destination $destinationPath -Force
            }
        }

        Write-Host "Installed to: $targetPath"
        return $targetPath
    }

    throw "Failed to extract version from folder name"
}

# TargetDirectory 戦略: 一時展開された全ファイルを指定ターゲットディレクトリへ配置 (長いパス対応および事後ディレクトリ作成に対応)
function Invoke-TargetDirectoryExtract {
    param(
        [string]$ArchiveFile,
        [string]$BinDir,
        [string]$TempDir,
        [hashtable]$Config
    )

    Unblock-ArchiveFile $ArchiveFile
    Expand-ArchiveToTemp -ArchiveFile $ArchiveFile -TempDir $TempDir

    $targetFolderName = $Config.TargetDirectory
    $targetPath = Join-Path $BinDir $targetFolderName
    $useLongPath = $Config.UseLongPathSupport

    Write-Host "Creating target directory: $targetFolderName"

    if (!(Test-Path $targetPath)) {
        New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
    }

    $absoluteTempDir = (Resolve-Path $TempDir).Path
    Write-Host "Copying files from temp directory: $absoluteTempDir"

    Get-ChildItem -Path $absoluteTempDir -Recurse | ForEach-Object {
        $relativePath = $_.FullName.Substring($absoluteTempDir.Length + 1)
        $destinationPath = Join-Path $targetPath $relativePath

        # ファイルのみをコピー (空ディレクトリの不要な生成を防止)
        if (-not $_.PSIsContainer) {
            $destinationDir = Split-Path $destinationPath -Parent
            if ($destinationDir) {
                if ($useLongPath) {
                    New-LongPathDirectory -Path $destinationDir | Out-Null
                } else {
                    if (!(Test-Path $destinationDir)) {
                        New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
                    }
                }
            }

            if ($useLongPath) {
                $copyResult = Copy-LongPathFile -SourcePath $_.FullName -DestinationPath $destinationPath
                if (-not $copyResult) {
                    Write-Host "  Skipped: $relativePath"
                }
            } else {
                Copy-Item -Path $_.FullName -Destination $destinationPath -Force
            }
        }
    }

    Write-Host "Installed to: $targetPath"

    # 抽出後処理 (PostExtract): 追加ディレクトリの作成
    if ($Config.PostExtract -and $Config.PostExtract.CreateDirectories) {
        foreach ($dir in $Config.PostExtract.CreateDirectories) {
            $dirPath = Join-Path $targetPath $dir
            if (!(Test-Path $dirPath)) {
                New-Item -ItemType Directory -Path $dirPath -Force | Out-Null
                Write-Host "Created directory: $dir"
            }
        }
    }

    return $targetPath
}
