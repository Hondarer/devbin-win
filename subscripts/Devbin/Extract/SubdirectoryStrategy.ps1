# SubdirectoryStrategy.ps1
# Subdirectory / SubdirectoryToTarget 戦略: 一部のディレクトリだけを取り出す

# Subdirectory 戦略: サブディレクトリのみを抽出
function Invoke-SubdirectoryExtract {
    param(
        [string]$ArchiveFile,
        [string]$BinDir,
        [string]$TempDir,
        [string]$ExtractPath,
        [string]$FilePattern = $null,
        [hashtable]$RenameFiles = $null
    )

    Unblock-ArchiveFile $ArchiveFile
    Expand-ArchiveToTemp -ArchiveFile $ArchiveFile -TempDir $TempDir

    $sourcePath = Get-ExtractedSourcePath $TempDir
    if (-not $sourcePath) {
        throw "Extracted folder not found"
    }

    # サブディレクトリを検索
    $subDirPath = $null
    $extractPathNormalized = $ExtractPath -replace '/', '\'

    if ($sourcePath -eq $TempDir) {
        $possiblePath = Join-Path $TempDir $extractPathNormalized
        if (Test-Path $possiblePath) {
            $subDirPath = $possiblePath
        }
    } else {
        $possiblePath = Join-Path $sourcePath $extractPathNormalized
        if (Test-Path $possiblePath) {
            $subDirPath = $possiblePath
        }
    }

    if (-not $subDirPath) {
        throw "Subdirectory not found: $ExtractPath"
    }

    # 絶対パスに変換
    $subDirPath = (Resolve-Path $subDirPath).Path

    Write-Host "Extracting from subdirectory: $subDirPath"

    $allItems = Get-ChildItem -Path $subDirPath -Recurse

    # FilePattern が指定されている場合はフィルタリング
    if ($FilePattern) {
        $allItems = $allItems | Where-Object { -not $_.PSIsContainer -and $_.Name -match $FilePattern }
        Write-Host "Filtering files with pattern: $FilePattern"
    }

    foreach ($item in $allItems) {
        # 相対パスを安全に計算 (絶対パス同士で計算)
        $itemFullPath = $item.FullName
        if ($itemFullPath.StartsWith($subDirPath)) {
            $relativePath = $itemFullPath.Substring($subDirPath.Length).TrimStart('\', '/')
        } else {
            Write-Host "Warning: Item path does not start with subDirPath" -ForegroundColor Yellow
            Write-Host "  Item: $itemFullPath" -ForegroundColor Yellow
            Write-Host "  SubDir: $subDirPath" -ForegroundColor Yellow
            continue
        }

        if ([string]::IsNullOrWhiteSpace($relativePath)) {
            continue
        }

        # RenameFiles が指定されている場合、ファイル名を変更
        $fileName = Split-Path $relativePath -Leaf
        if ($RenameFiles -and $RenameFiles.ContainsKey($fileName)) {
            $newFileName = $RenameFiles[$fileName]
            $parentDir = Split-Path $relativePath -Parent
            if ($parentDir) {
                $relativePath = Join-Path $parentDir $newFileName
            } else {
                $relativePath = $newFileName
            }
            Write-Host "Renaming: $fileName -> $newFileName"
        }

        $destinationPath = Join-Path $BinDir $relativePath

        # ファイルのみをコピー (空のディレクトリは作成しない)
        if (-not $item.PSIsContainer) {
            $destinationDir = Split-Path $destinationPath -Parent
            if ($destinationDir -and !(Test-Path $destinationDir)) {
                New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
            }

            try {
                Copy-Item -Path $item.FullName -Destination $destinationPath -Force
            } catch {
                Write-Host "  Error copying $relativePath : $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }

    return $true
}

# SubdirectoryToTarget 戦略: サブディレクトリをターゲットディレクトリに抽出
function Invoke-SubdirectoryToTargetExtract {
    param(
        [string]$ArchiveFile,
        [string]$BinDir,
        [string]$TempDir,
        [string]$ExtractPath,
        [string]$TargetDirectory
    )

    Unblock-ArchiveFile $ArchiveFile
    Expand-ArchiveToTemp -ArchiveFile $ArchiveFile -TempDir $TempDir

    $sourcePath = Get-ExtractedSourcePath $TempDir
    if (-not $sourcePath) {
        throw "Extracted folder not found"
    }

    # サブディレクトリを検索
    $subDirPath = $null
    $extractPathNormalized = $ExtractPath -replace '/', '\'

    if ($sourcePath -eq $TempDir) {
        $possiblePath = Join-Path $TempDir $extractPathNormalized
        if (Test-Path $possiblePath) {
            $subDirPath = $possiblePath
        }
    } else {
        $possiblePath = Join-Path $sourcePath $extractPathNormalized
        if (Test-Path $possiblePath) {
            $subDirPath = $possiblePath
        }
    }

    if (-not $subDirPath) {
        throw "Subdirectory not found: $ExtractPath"
    }

    # 絶対パスに変換
    $subDirPath = (Resolve-Path $subDirPath).Path

    # ターゲットディレクトリを作成
    $targetPath = Join-Path $BinDir $TargetDirectory
    Write-Host "Creating target directory: $TargetDirectory"

    if (!(Test-Path $targetPath)) {
        New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
    }

    Write-Host "Extracting from subdirectory: $subDirPath"
    Write-Host "Target directory: $targetPath"

    $allItems = Get-ChildItem -Path $subDirPath -Recurse

    foreach ($item in $allItems) {
        # 相対パスを安全に計算 (絶対パス同士で計算)
        $itemFullPath = $item.FullName
        if ($itemFullPath.StartsWith($subDirPath)) {
            $relativePath = $itemFullPath.Substring($subDirPath.Length).TrimStart('\', '/')
        } else {
            Write-Host "Warning: Item path does not start with subDirPath" -ForegroundColor Yellow
            Write-Host "  Item: $itemFullPath" -ForegroundColor Yellow
            Write-Host "  SubDir: $subDirPath" -ForegroundColor Yellow
            continue
        }

        if ([string]::IsNullOrWhiteSpace($relativePath)) {
            continue
        }

        $destinationPath = Join-Path $targetPath $relativePath

        # ファイルのみをコピー (空のディレクトリは作成しない)
        if (-not $item.PSIsContainer) {
            $destinationDir = Split-Path $destinationPath -Parent
            if ($destinationDir -and !(Test-Path $destinationDir)) {
                New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
            }

            try {
                Copy-Item -Path $item.FullName -Destination $destinationPath -Force
            } catch {
                Write-Host "  Error copying $relativePath : $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }

    Write-Host "Installed to: $targetPath"
    return $true
}
