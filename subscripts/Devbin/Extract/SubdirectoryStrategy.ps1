# SubdirectoryStrategy.ps1
# Subdirectory および SubdirectoryToTarget 戦略: アーカイブ内の特定サブディレクトリを抽出

# Subdirectory 戦略: 指定サブディレクトリ配下のファイルを bin ディレクトリ直下へ抽出 (リネームおよびパターン一致対応)
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

    # アーカイブ内の指定サブディレクトリを探索
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

    # 絶対パスへ正規化
    $subDirPath = (Resolve-Path $subDirPath).Path

    Write-Host "Extracting from subdirectory: $subDirPath"

    $allItems = Get-ChildItem -Path $subDirPath -Recurse

    # FilePattern が指定されている場合はファイル名でフィルタリング
    if ($FilePattern) {
        $allItems = $allItems | Where-Object { -not $_.PSIsContainer -and $_.Name -match $FilePattern }
        Write-Host "Filtering files with pattern: $FilePattern"
    }

    foreach ($item in $allItems) {
        # 絶対パス基準で安全に相対パスを算出
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

        # RenameFiles マッピングに一致する場合、配置先ファイル名を置換
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

        # ファイルのみをコピー (空ディレクトリの不要な生成を防止)
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

# SubdirectoryToTarget 戦略: アーカイブ内の指定サブディレクトリを bin 配下のターゲットディレクトリへ展開
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

    # アーカイブ内の指定サブディレクトリを探索
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

    # 絶対パスへ正規化
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
        # 絶対パス基準で安全に相対パスを算出
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

        # ファイルのみをコピー (空ディレクトリの不要な生成を防止)
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
