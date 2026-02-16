# Setup-Strategies.psm1
# 抽出戦略の実装

# 注意: Setup-Common.psm1 は呼び出し元のスクリプトでインポートする必要があります
# Import-Module "$PSScriptRoot\Setup-Common.psm1" -Force

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
    elseif ($fileExtension -in @(".7z", ".zst")) {
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
        # フォルダがなく、ファイルのみの場合は TempDir を返す
        return $TempDir
    }
    elseif ($extractedFolders.Count -eq 1) {
        # フォルダが1つだけの場合はそのフォルダを返す
        return $extractedFolders[0].FullName
    }
    elseif ($extractedFolders.Count -gt 1) {
        # フォルダが複数ある場合は TempDir を返す
        return $TempDir
    }

    return $null
}

# Standard 戦略: 標準的な ZIP 展開
function Invoke-StandardExtract {
    param(
        [string]$ArchiveFile,
        [string]$BinDir,
        [string]$TempDir
    )

    Unblock-ArchiveFile $ArchiveFile
    Expand-ArchiveToTemp -ArchiveFile $ArchiveFile -TempDir $TempDir

    $sourcePath = Get-ExtractedSourcePath $TempDir
    if (-not $sourcePath) {
        throw "Extracted folder not found"
    }

    Write-Host "Extracted folder: $sourcePath"

    Get-ChildItem -Path $sourcePath -Recurse | ForEach-Object {
        if ($sourcePath -eq $TempDir) {
            $relativePath = $_.Name
        } else {
            $relativePath = $_.FullName.Substring($sourcePath.Length + 1)
        }

        # ファイルのみをコピー (空のディレクトリは作成しない)
        if (-not $_.PSIsContainer) {
            $destinationPath = Join-Path $BinDir $relativePath

            $destinationDir = Split-Path $destinationPath -Parent
            if ($destinationDir -and !(Test-Path $destinationDir)) {
                New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
            }
            Copy-Item -Path $_.FullName -Destination $destinationPath -Force
        }
    }

    return $true
}

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

# VersionNormalized 戦略: バージョン番号を正規化
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

            # ファイルのみをコピー (空のディレクトリは作成しない)
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

# TargetDirectory 戦略: ターゲットディレクトリ指定
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

        # ファイルのみをコピー (空のディレクトリは作成しない)
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

    # PostExtract: data ディレクトリの作成
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

# JarWithWrapper 戦略: JAR ファイル + ラッパー
function Invoke-JarWithWrapperExtract {
    param(
        [string]$ArchiveFile,
        [string]$BinDir,
        [hashtable]$Config
    )

    Unblock-ArchiveFile $ArchiveFile

    $jarFileName = $Config.JarName
    $jarDestination = Join-Path $BinDir $jarFileName

    Write-Host "JAR file: $(Split-Path $ArchiveFile -Leaf)"
    Copy-Item -Path $ArchiveFile -Destination $jarDestination -Force
    Write-Host "Copied to bin directory as $jarFileName"

    # ラッパースクリプトを生成
    $wrapperName = $Config.WrapperName
    if (-not $wrapperName) {
        Write-Host "Warning: WrapperName not specified in config" -ForegroundColor Yellow
        return $false
    }

    $wrapperContent = $Config.WrapperContent
    if (-not $wrapperContent) {
        Write-Host "Warning: WrapperContent not specified in config" -ForegroundColor Yellow
        return $false
    }

    $wrapperPath = Join-Path $BinDir $wrapperName
    $wrapperContent | Out-File -FilePath $wrapperPath -Encoding ASCII
    Write-Host "Created wrapper script: $wrapperName"

    return $true
}

# SingleExecutable 戦略: 単一実行ファイル
function Invoke-SingleExecutableExtract {
    param(
        [string]$ArchiveFile,
        [string]$BinDir,
        [hashtable]$Config
    )

    Unblock-ArchiveFile $ArchiveFile

    $exeFileName = Split-Path $ArchiveFile -Leaf
    $targetName = if ($Config.TargetName) { $Config.TargetName } else { $exeFileName }
    $exeDestination = Join-Path $BinDir $targetName

    Write-Host "EXE file: $exeFileName"

    try {
        Unblock-File -Path $ArchiveFile -ErrorAction SilentlyContinue
        Write-Host "Unblocked $exeFileName"
    } catch {
        # ブロック解除に失敗した場合は続行
    }

    Copy-Item -Path $ArchiveFile -Destination $exeDestination -Force
    Write-Host "Copied $exeFileName to bin directory as $targetName"

    try {
        Unblock-File -Path $exeDestination -ErrorAction SilentlyContinue
    } catch {
        # ブロック解除に失敗した場合は続行
    }

    return $true
}

# SelfExtractingArchive 戦略: 自己解凍アーカイブ
function Invoke-SelfExtractingArchiveExtract {
    param(
        [string]$ArchiveFile,
        [string]$BinDir,
        [hashtable]$Config
    )

    Unblock-ArchiveFile $ArchiveFile

    $targetDirectory = $Config.TargetDirectory
    $targetPath = Join-Path $BinDir $targetDirectory

    Write-Host "Creating target directory: $targetDirectory"

    if (!(Test-Path $targetPath)) {
        New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
    }

    Write-Host "Extracting (this may take a moment)..."

    $resolvedTargetPath = (Resolve-Path $targetPath).Path
    $extractArgs = @()

    foreach ($arg in $Config.ExtractArgs) {
        $processedArg = $arg -replace '\{TargetPath\}', $resolvedTargetPath
        $extractArgs += $processedArg
    }

    $process = Start-Process -FilePath $ArchiveFile -ArgumentList $extractArgs -Wait -PassThru

    if ($process.ExitCode -eq 0) {
        Write-Host "Extracted successfully to: $targetPath"

        # PostExtract: ファイルのコピー
        if ($Config.PostExtract -and $Config.PostExtract.CopyFiles) {
            Write-Host "Copying additional files..."
            foreach ($fileEntry in $Config.PostExtract.CopyFiles) {
                $sourcePath = $fileEntry.Source
                $destPath = Join-Path $BinDir $fileEntry.Destination

                if (Test-Path $sourcePath) {
                    Copy-Item -Path $sourcePath -Destination $destPath -Force
                    Write-Host "  Copied: $($fileEntry.Destination)"
                } else {
                    Write-Host "  Warning: File not found: $sourcePath" -ForegroundColor Yellow
                }
            }
        }

        return $targetPath
    } else {
        throw "Extraction failed with exit code: $($process.ExitCode)"
    }
}

# InnoSetup 戦略: innoextract を使用して Inno Setup インストーラを解凍
function Invoke-InnoSetupExtract {
    param(
        [string]$ArchiveFile,
        [string]$BinDir,
        [string]$TempDir,
        [hashtable]$Config
    )

    # innoextract.exe のパスを確認
    $innoextractPath = Join-Path $BinDir "innoextract.exe"
    if (-not (Test-Path $innoextractPath)) {
        throw "innoextract.exe not found at: $innoextractPath. Please ensure innoextract is extracted first."
    }

    # 一時ディレクトリを作成
    if (Test-Path $TempDir) {
        Remove-Item $TempDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

    # innoextract で解凍
    Write-Host "  Extracting with innoextract..."
    $process = Start-Process -FilePath $innoextractPath -ArgumentList "-d", $TempDir, $ArchiveFile -Wait -PassThru -NoNewWindow

    if ($process.ExitCode -ne 0) {
        throw "innoextract failed with exit code: $($process.ExitCode)"
    }

    # ExtractPath で指定されたサブディレクトリを TargetDirectory に配置
    $sourcePath = Join-Path $TempDir $Config.ExtractPath
    if (-not (Test-Path $sourcePath)) {
        throw "Source path not found: $sourcePath"
    }

    $targetPath = Join-Path $BinDir $Config.TargetDirectory

    # ターゲットディレクトリが存在する場合は削除
    if (Test-Path $targetPath) {
        Remove-Item $targetPath -Recurse -Force
    }

    # サブディレクトリを移動
    Move-Item -Path $sourcePath -Destination $targetPath -Force
    Write-Host "  Extracted to: $targetPath"

    # 一時ディレクトリを削除
    if (Test-Path $TempDir) {
        Remove-Item $TempDir -Recurse -Force
    }

    return $targetPath
}

# VSBuildTools 戦略: Setup-VSBT.ps1 を実行
function Invoke-VSBuildToolsExtract {
    param(
        [string]$BinDir,
        [string]$ScriptDir,
        [hashtable]$Config
    )

    Write-Host "Processing: $($Config.DisplayName)"

    $vsbtScript = Join-Path $ScriptDir "Setup-VSBT.ps1"

    if (-not (Test-Path $vsbtScript)) {
        Write-Host "  Error: Setup-VSBT.ps1 not found at: $vsbtScript" -ForegroundColor Red
        return $false
    }

    $vsbtConfig = $Config.VSBTConfig
    $outputPath = Join-Path $BinDir $Config.ExtractedName

    $params = @{
        MSVCVersion = $vsbtConfig.MSVCVersion
        SDKVersion = $vsbtConfig.SDKVersion
        Target = $vsbtConfig.Target
        HostArch = $vsbtConfig.HostArch
        OutputPath = $outputPath
        AcceptLicense = $true
    }

    Write-Host "  Executing Setup-VSBT.ps1..."
    Write-Host "    MSVC: $($params.MSVCVersion)"
    Write-Host "    SDK: $($params.SDKVersion)"
    Write-Host "    Target: $($params.Target)"
    Write-Host "    Output: $outputPath`n"

    try {
        & $vsbtScript @params

        if ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE) {
            Write-Host "  $($Config.DisplayName) setup completed" -ForegroundColor Green
            return $true
        } else {
            Write-Host "  Setup-VSBT.ps1 exited with code $LASTEXITCODE" -ForegroundColor Yellow
            return $false
        }
    } catch {
        Write-Host "  Error executing Setup-VSBT.ps1: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# メイン関数: 抽出戦略を実行
function Invoke-ExtractStrategy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$PackageConfig,

        [Parameter(Mandatory=$false)]
        [string]$ArchiveFile = "",

        [Parameter(Mandatory)]
        [string]$BinDir,

        [Parameter(Mandatory)]
        [string]$ScriptDir,

        [string]$TempDir = "temp_extract"
    )

    # TempDir を絶対パスに変換 (スクリプト実行ディレクトリ基準)
    if (-not [System.IO.Path]::IsPathRooted($TempDir)) {
        $TempDir = Join-Path (Get-Location).Path $TempDir
    }

    $strategy = $PackageConfig.ExtractStrategy

    Write-Host "Extracting $($PackageConfig.Name) using $strategy strategy..."

    $targetPath = $null

    try {
        switch ($strategy) {
            "Standard" {
                Invoke-StandardExtract -ArchiveFile $ArchiveFile -BinDir $BinDir -TempDir $TempDir
            }
            "Subdirectory" {
                Invoke-SubdirectoryExtract -ArchiveFile $ArchiveFile -BinDir $BinDir -TempDir $TempDir -ExtractPath $PackageConfig.ExtractPath -FilePattern $PackageConfig.FilePattern -RenameFiles $PackageConfig.RenameFiles
            }
            "SubdirectoryToTarget" {
                Invoke-SubdirectoryToTargetExtract -ArchiveFile $ArchiveFile -BinDir $BinDir -TempDir $TempDir -ExtractPath $PackageConfig.ExtractPath -TargetDirectory $PackageConfig.TargetDirectory
            }
            "VersionNormalized" {
                $targetPath = Invoke-VersionNormalizedExtract -ArchiveFile $ArchiveFile -BinDir $BinDir -TempDir $TempDir -VersionPattern $PackageConfig.VersionPattern -TargetDirectory $PackageConfig.TargetDirectory
            }
            "TargetDirectory" {
                $targetPath = Invoke-TargetDirectoryExtract -ArchiveFile $ArchiveFile -BinDir $BinDir -TempDir $TempDir -Config $PackageConfig
            }
            "JarWithWrapper" {
                Invoke-JarWithWrapperExtract -ArchiveFile $ArchiveFile -BinDir $BinDir -Config $PackageConfig
            }
            "SingleExecutable" {
                Invoke-SingleExecutableExtract -ArchiveFile $ArchiveFile -BinDir $BinDir -Config $PackageConfig
            }
            "SelfExtractingArchive" {
                $targetPath = Invoke-SelfExtractingArchiveExtract -ArchiveFile $ArchiveFile -BinDir $BinDir -Config $PackageConfig
            }
            "InnoSetup" {
                $targetPath = Invoke-InnoSetupExtract -ArchiveFile $ArchiveFile -BinDir $BinDir -TempDir $TempDir -Config $PackageConfig
            }
            "VSBuildTools" {
                return Invoke-VSBuildToolsExtract -BinDir $BinDir -ScriptDir $ScriptDir -Config $PackageConfig
            }
            default {
                Write-Host "Unknown strategy: $strategy" -ForegroundColor Red
                return $false
            }
        }

        # PostSetupScript 実行
        if ($PackageConfig.PostSetupScript) {
            if (-not $targetPath) {
                Write-Host "Warning: targetPath is not set for PostSetupScript" -ForegroundColor Yellow
            } else {
                $scriptPath = Join-Path $ScriptDir "config\templates\$($PackageConfig.PostSetupScript)"
                if (Test-Path $scriptPath) {
                    Write-Host "Running post-setup script: $($PackageConfig.PostSetupScript)"
                    & $scriptPath -TargetPath $targetPath
                } else {
                    Write-Host "Warning: Post-setup script not found: $scriptPath" -ForegroundColor Yellow
                }
            }
        }

        Write-Host "$($PackageConfig.Name) extraction completed."
        return $true
    }
    catch {
        Write-Host "Error: Failed to extract $($PackageConfig.Name)" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        return $false
    }
    finally {
        # 一時ディレクトリをクリーンアップ
        if ((Test-Path $TempDir) -and ($strategy -ne "JarWithWrapper") -and ($strategy -ne "SingleExecutable") -and ($strategy -ne "SelfExtractingArchive")) {
            Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "Temporary directory cleaned up."
        }
    }
}

Export-ModuleMember -Function 'Invoke-ExtractStrategy'
