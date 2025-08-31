# 開発ツール セットアップ スクリプト
# 開発ツールの抽出、インストール、またはアンインストールを行う

param(
    [string]$InstallDir = ".\bin",
    [switch]$Extract,
    [switch]$Install,
    [switch]$Uninstall
)

# オプションが指定されていない場合は使用方法を表示
if (-not ($Extract -or $Install -or $Uninstall)) {
    Write-Host "Development Tools Setup Script"
    Write-Host "================================"
    Write-Host ""
    Write-Host "Usage:"
    Write-Host "  .\setup.ps1 -Extract [-InstallDir <path>]    # Extract tools only"
    Write-Host "  .\setup.ps1 -Install [-InstallDir <path>]    # Extract tools and add to PATH"
    Write-Host "  .\setup.ps1 -Uninstall [-InstallDir <path>]  # Remove tools and clean PATH"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -InstallDir <path>  Installation directory (default: .\bin)"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\setup.ps1 -Extract                         # Extract to .\bin"
    Write-Host "  .\setup.ps1 -Install -InstallDir C:\Tools    # Install to C:\Tools"
    Write-Host "  .\setup.ps1 -Uninstall                       # Uninstall from .\bin"
    exit 0
}

# 追加 / 削除すべき PATH ディレクトリを取得する
function Get-PathDirectories {
    param([string]$BaseDir)
    
    $pathDirs = @(
        $BaseDir,
        "$BaseDir\jdk-21\bin",
        "$BaseDir\python-3.13",
        "$BaseDir\git",
        "$BaseDir\git\bin",
        "$BaseDir\git\cmd",
        "$BaseDir\git\mingw64\bin",
        "$BaseDir\git\usr\bin"
    )
    
    return $pathDirs
}

# コマンドが PATH で既に利用可能かどうかをチェックする
function Test-CommandExists {
    param([string]$CommandName)
    try {
        Get-Command $CommandName -ErrorAction Stop | Out-Null
        return $true
    } catch {
        return $false
    }
}

# ユーザー PATH にディレクトリを追加する関数
function Add-ToUserPath {
    param([string[]]$Directories)
    
    Write-Host "Adding directories to user PATH..."
    
    $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if (-not $currentPath) {
        $currentPath = ""
    }
    
    $pathChanged = $false
    foreach ($dir in $Directories) {
        $absolutePath = (Resolve-Path $dir -ErrorAction SilentlyContinue)
        if ($absolutePath -and (Test-Path $absolutePath)) {
            $dirPath = $absolutePath.Path
            $shouldSkip = $false
            
            # 既存のコマンドをチェックして特定のパスをスキップ
            if ($dirPath -like "*jdk-*\bin") {
                if (Test-CommandExists "java") {
                    Write-Host "  Skipped (java.exe already available): $dirPath"
                    $shouldSkip = $true
                }
            }
            elseif ($dirPath -like "*python-*") {
                if (Test-CommandExists "python") {
                    Write-Host "  Skipped (python.exe already available): $dirPath"
                    $shouldSkip = $true
                }
            }
            elseif ($dirPath -like "*git" -or $dirPath -like "*git\bin" -or $dirPath -like "*git\mingw64\bin" -or $dirPath -like "*git\usr\bin" -or $dirPath -like "*git\cmd") {
                if (Test-CommandExists "git") {
                    Write-Host "  Skipped (git.exe already available): $dirPath"
                    $shouldSkip = $true
                }
            }
            
            if (-not $shouldSkip) {
                # エントリを事前削除しているため、重複チェックなしで直接追加
                if ($currentPath) {
                    $currentPath = "$dirPath;$currentPath"
                } else {
                    $currentPath = $dirPath
                }
                Write-Host "  Added: $dirPath"
                $pathChanged = $true
            }
        } else {
            Write-Host "  Directory not found: $dir"
        }
    }
    
    if ($pathChanged) {
        [Environment]::SetEnvironmentVariable("PATH", $currentPath, "User")
        Write-Host "User PATH updated successfully."
        Write-Host "Note: Restart your terminal for PATH changes to take effect."
    } else {
        Write-Host "No PATH changes needed."
    }
}

# ユーザー PATH からディレクトリを削除する
function Remove-FromUserPath {
    param([string[]]$Directories)
    
    Write-Host "Removing directories from user PATH..."
    
    $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if (-not $currentPath) {
        Write-Host "User PATH is empty."
        return
    }
    
    $pathChanged = $false
    $pathEntries = $currentPath -split ';'
    $newPathEntries = @()
    
    foreach ($entry in $pathEntries) {
        $shouldRemove = $false
        foreach ($dir in $Directories) {
            $absolutePath = (Resolve-Path $dir -ErrorAction SilentlyContinue)
            if ($absolutePath -and ($entry -eq $absolutePath.Path)) {
                Write-Host "  Removed: $entry"
                $shouldRemove = $true
                $pathChanged = $true
                break
            }
        }
        if (-not $shouldRemove -and $entry.Trim() -ne "") {
            $newPathEntries += $entry
        }
    }
    
    if ($pathChanged) {
        $newPath = $newPathEntries -join ';'
        [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
        Write-Host "User PATH updated successfully."
    } else {
        Write-Host "No matching directories found in PATH."
    }
}

# 重複ファイル追跡用のグローバル キャッシュ
$global:DuplicateFiles = @{}
$global:PackageFileMapping = @{}

function Get-PackageShortName {
    param([string]$PackageName)
    
    # パッケージ名から短縮名を抽出
    if ($PackageName -match "Node\.js") { return "nodejs" }
    if ($PackageName -match "Pandoc") { return "pandoc" }
    if ($PackageName -match "pandoc-crossref") { return "pandoc-crossref" }
    if ($PackageName -match "Doxygen") { return "doxygen" }
    if ($PackageName -match "doxybook2") { return "doxybook2" }
    if ($PackageName -match "Microsoft JDK") { return "jdk" }
    if ($PackageName -match "PlantUML") { return "plantuml" }
    if ($PackageName -match "Python") { return "python" }
    
    # 必要に応じてパッケージ名マッピングを追加
    return $PackageName.ToLower() -replace '[^a-z0-9]', ''
}

# パッケージが特別な処理を必要とするかチェック
function Test-SpecialPackageHandling {
    param([string]$PackageName)
    
    if ($PackageName -match "Microsoft JDK") {
        return $true
    }
    if ($PackageName -match "PlantUML") {
        return $true
    }
    if ($PackageName -match "Python") {
        return $true
    }
    return $false
}

function Get-ResolvedFileName {
    param(
        [string]$OriginalPath,
        [string]$PackageName,
        [string]$BinDir
    )
    
    $fileName = Split-Path $OriginalPath -Leaf
    $relativePath = $OriginalPath
    $packageShortName = Get-PackageShortName $PackageName
    
    # このファイルが bin ディレクトリに既に存在するか、重複としてマークされているかチェック
    $fullDestinationPath = Join-Path $BinDir $relativePath
    
    if ($global:DuplicateFiles.ContainsKey($fileName)) {
        # このファイル名は既に重複としてマークされているため、すべてのインスタンスを名前変更
        $fileNameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
        $extension = [System.IO.Path]::GetExtension($fileName)
        
        $newFileName = "${fileNameWithoutExt}_${packageShortName}${extension}"
        $newRelativePath = $relativePath -replace [regex]::Escape($fileName), $newFileName
        
        Write-Host "  Renaming duplicate file: $fileName -> $newFileName"
        return $newRelativePath
    }
    elseif (Test-Path $fullDestinationPath) {
        # ファイルが存在するため、重複としてマークして両方の名前を変更
        Write-Host "  Duplicate file detected: $fileName"
        
        # 重複としてマーク
        $global:DuplicateFiles[$fileName] = $true
        
        # 既存ファイルがまだ名前変更されていない場合は名前変更
        $existingPackage = $global:PackageFileMapping[$fileName]
        if ($existingPackage) {
            $existingShortName = Get-PackageShortName $existingPackage
            $fileNameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
            $extension = [System.IO.Path]::GetExtension($fileName)
            
            $existingNewFileName = "${fileNameWithoutExt}_${existingShortName}${extension}"
            $existingNewPath = Join-Path $BinDir $existingNewFileName
            
            if ((Test-Path $fullDestinationPath) -and !(Test-Path $existingNewPath)) {
                Move-Item -Path $fullDestinationPath -Destination $existingNewPath
                Write-Host "  Renamed existing file: $fileName -> $existingNewFileName"
            }
        }
        
        # 現在のファイルの名前変更されたパスを返す
        $fileNameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
        $extension = [System.IO.Path]::GetExtension($fileName)
        $newFileName = "${fileNameWithoutExt}_${packageShortName}${extension}"
        $newRelativePath = $relativePath -replace [regex]::Escape($fileName), $newFileName
        
        return $newRelativePath
    }
    else {
        # 競合なし、ファイル-パッケージ マッピングを追跡
        $global:PackageFileMapping[$fileName] = $PackageName
        return $relativePath
    }
}

function Extract-Package {
    param(
        [string]$ArchiveFile,
        [string]$PackageName,
        [string]$BinDir = $InstallDir,
        [string]$TempDir = "temp_extract"
    )
    
    Write-Host "Starting $PackageName binary extraction..."
    
    # アーカイブファイルが存在するかチェック
    if (!(Test-Path $ArchiveFile)) {
        Write-Host "Error: $ArchiveFile not found."
        Write-Host "Please download $PackageName and place it in the packages folder."
        return $false
    }
    
    Write-Host "Archive file found: $ArchiveFile"
    
    # セキュリティ制限を防ぐためアーカイブファイルのブロックを解除
    try {
        Unblock-File -Path $ArchiveFile -ErrorAction SilentlyContinue
    } catch {
        # ブロック解除に失敗した場合は続行
    }
    
    # PlantUML JAR ファイルの特別処理
    if ($PackageName -match "PlantUML" -and $ArchiveFile -match "\.jar$") {
        Write-Host "Detected PlantUML JAR file, applying special handling..."
        
        # bin ディレクトリが存在しない場合は作成
        if (!(Test-Path $BinDir)) {
            New-Item -ItemType Directory -Path $BinDir
            Write-Host "Created bin directory."
        }
        
        # JAR ファイル名を抽出
        $jarFileName = Split-Path $ArchiveFile -Leaf
        Write-Host "PlantUML JAR file: $jarFileName"
        
        # JAR ファイルを汎用名で bin ディレクトリにコピー
        $jarDestination = Join-Path $BinDir "plantuml.jar"
        Copy-Item -Path $ArchiveFile -Destination $jarDestination -Force
        Write-Host "Copied $jarFileName to bin directory as plantuml.jar"
        
        # plantuml.cmd バッチファイルを作成
        $cmdContent = @"
@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "JAVA_HOME=%SCRIPT_DIR%jdk-21"
"%JAVA_HOME%\bin\java.exe" -jar "%SCRIPT_DIR%plantuml.jar" %*

endlocal
"@
        
        $cmdPath = Join-Path $BinDir "plantuml.cmd"
        $cmdContent | Out-File -FilePath $cmdPath -Encoding ASCII
        Write-Host "Created plantuml.cmd wrapper script"
        Write-Host "PlantUML can be run with: plantuml.cmd"
        
        Write-Host "$PackageName binary extraction completed."
        return $true
    }
    
    # bin ディレクトリを作成
    if (!(Test-Path $BinDir)) {
        New-Item -ItemType Directory -Path $BinDir
        Write-Host "Created bin directory."
    }
    
    # 一時ディレクトリを作成
    if (Test-Path $TempDir) {
        Remove-Item -Path $TempDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $TempDir
    
    try {
        Write-Host "Extracting archive file..."
        
        # ファイルタイプを判定して適切に抽出
        $fileExtension = [System.IO.Path]::GetExtension($ArchiveFile).ToLower()
        
        if ($fileExtension -eq ".zip") {
            # ZIP ファイルを一時ディレクトリに抽出
            Expand-Archive -Path $ArchiveFile -DestinationPath $TempDir -Force
        }
        elseif ($fileExtension -eq ".7z") {
            # Windows 組み込みの tar.exe (libarchive) を使用して 7z ファイルを抽出
            try {
                $tarPath = "$env:WINDIR\System32\tar.exe"
                if (Test-Path $tarPath) {
                    Write-Host "Using Windows built-in tar.exe (libarchive) for .7z extraction..."
                    
                    # libarchive 付き tar.exe を使用して .7z ファイルを抽出
                    $absoluteArchive = (Resolve-Path $ArchiveFile).Path
                    $absoluteTempDir = (Resolve-Path $TempDir).Path
                    
                    & $tarPath -xf $absoluteArchive -C $absoluteTempDir
                    
                    if ($LASTEXITCODE -ne 0) {
                        throw "tar.exe extraction failed with exit code: $LASTEXITCODE"
                    }
                    
                    Write-Host "Successfully extracted .7z file using tar.exe"
                } else {
                    throw "tar.exe not found at expected location: $tarPath"
                }
            }
            catch {
                Write-Host "Error: 7z extraction failed using tar.exe."
                Write-Host "Details: $($_.Exception.Message)"
                
                # フォールバック: 7z コマンドが利用可能な場合は試行
                if (Get-Command "7z" -ErrorAction SilentlyContinue) {
                    Write-Host "Trying fallback with 7z command..."
                    try {
                        & 7z x $ArchiveFile -o"$TempDir" -y | Out-Null
                        if ($LASTEXITCODE -eq 0) {
                            Write-Host "Successfully extracted using 7z fallback."
                        } else {
                            throw "7z fallback failed"
                        }
                    }
                    catch {
                        Write-Host "Error: All 7z extraction methods failed."
                        Write-Host "Please install 7-Zip: https://www.7-zip.org/"
                        return $false
                    }
                } else {
                    Write-Host "No fallback available. Please install 7-Zip: https://www.7-zip.org/"
                    return $false
                }
            }
        }
        else {
            Write-Host "Error: Unsupported file type: $fileExtension"
            return $false
        }
        
        # 抽出されたフォルダまたはファイルを検索
        $extractedItems = Get-ChildItem -Path $TempDir
        $extractedFolder = $extractedItems | Where-Object { $_.PSIsContainer } | Select-Object -First 1
        
        # フォルダが見つからない場合、一時ディレクトリに直接ファイルがあるかチェック
        if (-not $extractedFolder -and ($extractedItems | Where-Object { -not $_.PSIsContainer })) {
            # ファイルが一時ディレクトリに直接ある場合、一時ディレクトリをソースとして使用
            $sourcePath = $TempDir
            Write-Host "Files extracted directly to temp directory: $sourcePath"
        }
        elseif ($extractedFolder) {
            $sourcePath = $extractedFolder.FullName
            Write-Host "Extracted folder: $sourcePath"
        }
        
        if ($sourcePath) {
            # このパッケージが特別な処理を必要とするかチェック
            $isSpecialPackage = Test-SpecialPackageHandling -PackageName $PackageName
            
            if ($isSpecialPackage -and $PackageName -match "Microsoft JDK") {
                # Microsoft JDK の特別処理
                Write-Host "Applying special JDK handling..."
                
                # JDK フォルダを検索 (例: jdk-21.0.8+9)
                # sourcePath 自体が JDK フォルダかチェック
                if ((Split-Path $sourcePath -Leaf) -match "^jdk-\d+") {
                    # 抽出されたフォルダが JDK フォルダ自体
                    $jdkFolder = Get-Item $sourcePath
                    Write-Host "Source path is JDK folder: $($jdkFolder.Name)"
                } else {
                    # ソースパス内で JDK フォルダを検索
                    $jdkFolder = Get-ChildItem -Path $sourcePath -Directory | Where-Object { $_.Name -match "^jdk-\d+" } | Select-Object -First 1
                }
                
                if ($jdkFolder) {
                    Write-Host "Found JDK folder: $($jdkFolder.Name)"
                    
                    # メジャーバージョンを抽出してターゲットフォルダ名を作成 (例: jdk-21)
                    if ($jdkFolder.Name -match "^jdk-(\d+)") {
                        $majorVersion = $matches[1]
                        $targetFolderName = "jdk-$majorVersion"
                        $targetPath = Join-Path $BinDir $targetFolderName
                        
                        Write-Host "Creating target directory: $targetFolderName"
                        
                        # ターゲットディレクトリを作成
                        if (!(Test-Path $targetPath)) {
                            New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
                        }
                        
                        # JDK フォルダの内容をターゲットディレクトリにコピー
                        Get-ChildItem -Path $jdkFolder.FullName -Recurse | ForEach-Object {
                            $relativePath = $_.FullName.Substring($jdkFolder.FullName.Length + 1)
                            $destinationPath = Join-Path $targetPath $relativePath
                            
                            if ($_.PSIsContainer) {
                                if (!(Test-Path $destinationPath)) {
                                    New-Item -ItemType Directory -Path $destinationPath -Force | Out-Null
                                }
                            } else {
                                $destinationDir = Split-Path $destinationPath -Parent
                                if ($destinationDir -and !(Test-Path $destinationDir)) {
                                    New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
                                }
                                Copy-Item -Path $_.FullName -Destination $destinationPath -Force
                            }
                        }
                        
                        Write-Host "JDK installed to: $targetPath"
                    } else {
                        Write-Host "Warning: Could not extract major version from JDK folder name: $($jdkFolder.Name)"
                    }
                } else {
                    Write-Host "Warning: JDK folder not found in extracted archive"
                }
            }
            elseif ($isSpecialPackage -and $PackageName -match "Python") {
                # Python 埋め込みパッケージの特別処理
                Write-Host "Applying special Python embeddable package handling..."
                
                # パッケージ名またはアーカイブ名からメジャー.マイナーバージョンを抽出
                $pythonVersion = "3.13"  # デフォルトバージョン
                if ($ArchiveFile -match "python-(\d+\.\d+)") {
                    $pythonVersion = $matches[1]
                }
                
                $targetFolderName = "python-$pythonVersion"
                $targetPath = Join-Path $BinDir $targetFolderName
                
                Write-Host "Creating target directory: $targetFolderName"
                
                # ターゲットディレクトリを作成
                if (!(Test-Path $targetPath)) {
                    New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
                }
                
                # Python ファイルをターゲットディレクトリにコピー
                # Python 埋め込みパッケージの場合、ファイルは sourcePath に直接あるかサブディレクトリにある可能性があります
                if ($sourcePath -eq $TempDir) {
                    # ファイルが一時ディレクトリに直接ある
                    Get-ChildItem -Path $sourcePath -File | ForEach-Object {
                        $destinationPath = Join-Path $targetPath $_.Name
                        Copy-Item -Path $_.FullName -Destination $destinationPath -Force
                    }
                } else {
                    # ファイルがサブディレクトリにある
                    Get-ChildItem -Path $sourcePath -Recurse | ForEach-Object {
                        $relativePath = $_.FullName.Substring($sourcePath.Length + 1)
                        $destinationPath = Join-Path $targetPath $relativePath
                        
                        if ($_.PSIsContainer) {
                            if (!(Test-Path $destinationPath)) {
                                New-Item -ItemType Directory -Path $destinationPath -Force | Out-Null
                            }
                        } else {
                            $destinationDir = Split-Path $destinationPath -Parent
                            if ($destinationDir -and !(Test-Path $destinationDir)) {
                                New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
                            }
                            Copy-Item -Path $_.FullName -Destination $destinationPath -Force
                        }
                    }
                }
                
                Write-Host "Python installed to: $targetPath"
                
                # get-pip.py が存在する場合はコピー
                $getPipPath = "packages\get-pip.py"
                if (Test-Path $getPipPath) {
                    $getPipDestination = Join-Path $targetPath "get-pip.py"
                    Copy-Item -Path $getPipPath -Destination $getPipDestination -Force
                    Write-Host "Copied get-pip.py to Python directory"
                    
                    # site-packages を有効にするため pth ファイルをパッチ
                    $pthFiles = Get-ChildItem -Path $targetPath -Filter "*._pth"
                    foreach ($pthFile in $pthFiles) {
                        Write-Host "Patching pth file: $($pthFile.Name)"
                        
                        $pthContent = Get-Content $pthFile.FullName
                        $newContent = @()
                        $sitePackagesAdded = $false
                        
                        foreach ($line in $pthContent) {
                            # import site に関するコメント行をスキップ
                            if ($line -match "^#.*import.*site") {
                                continue
                            }
                            # "Uncomment to run site.main()" コメントをスキップ
                            elseif ($line -match "^#.*Uncomment.*site\.main") {
                                continue
                            }
                            # 最後に追加するため既存の import site 行をスキップ
                            elseif ($line -match "^import\s+site") {
                                continue
                            } else {
                                $newContent += $line
                            }
                            
                            # site-packages が既に存在するかチェック
                            if ($line -match "Lib\\site-packages") {
                                $sitePackagesAdded = $true
                            }
                        }
                        
                        # 標準ライブラリの zip を最初に追加
                        $zipFiles = Get-ChildItem -Path $targetPath -Filter "python*.zip"
                        if ($zipFiles) {
                            $zipFile = $zipFiles[0].Name
                            if (-not ($newContent -contains $zipFile)) {
                                $newContent = @($zipFile) + $newContent
                                Write-Host "  Added standard library: $zipFile"
                            }
                        }
                        
                        # 見つからない場合は site-packages を追加
                        if (-not $sitePackagesAdded) {
                            $newContent += "Lib\site-packages"
                            Write-Host "  Added Lib\site-packages path"
                        }
                        
                        # 最後に import site を追加 (適切なコメント付き)
                        $newContent += ""
                        $newContent += "# Uncomment to run site.main() automatically"
                        $newContent += "import site"
                        Write-Host "  Enabled 'import site'"
                        
                        # 変更された内容を書き戻し (BOM なし UTF-8)
                        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
                        [System.IO.File]::WriteAllText($pthFile.FullName, ($newContent -join "`r`n"), $utf8NoBom)
                    }
                    
                    # pip をインストール
                    Write-Host "Installing pip..."
                    $pythonExe = Join-Path $targetPath "python.exe"
                    if (Test-Path $pythonExe) {
                        try {
                            & $pythonExe $getPipDestination --no-warn-script-location
                            if ($LASTEXITCODE -eq 0) {
                                Write-Host "pip installed successfully"
                            } else {
                                Write-Host "Warning: pip installation may have issues (exit code: $LASTEXITCODE)"
                            }
                        } catch {
                            Write-Host "Warning: Failed to install pip: $($_.Exception.Message)"
                        } finally {
                            # 環境変数をクリーンアップ
                            Remove-Item Env:PYTHONHOME -ErrorAction SilentlyContinue
                            Remove-Item Env:PYTHONPATH -ErrorAction SilentlyContinue
                        }
                    } else {
                        Write-Host "Warning: python.exe not found, skipping pip installation"
                    }
                } else {
                    Write-Host "Warning: get-pip.py not found, skipping pip installation"
                }
            } else {
                # その他のパッケージの標準処理
                Get-ChildItem -Path $sourcePath -Recurse | ForEach-Object {
                    if ($sourcePath -eq $TempDir) {
                        # ファイルが一時ディレクトリに直接ある
                        $relativePath = $_.Name
                    } else {
                        # ファイルがサブディレクトリにある
                        $relativePath = $_.FullName.Substring($sourcePath.Length + 1)
                    }
                    
                    if ($_.PSIsContainer) {
                        # ディレクトリの場合 - ディレクトリの名前変更は不要
                        $destinationPath = Join-Path $BinDir $relativePath
                        if (!(Test-Path $destinationPath)) {
                            New-Item -ItemType Directory -Path $destinationPath -Force | Out-Null
                        }
                    } else {
                        # ファイルの場合 - 重複をチェックして解決
                        $resolvedPath = Get-ResolvedFileName -OriginalPath $relativePath -PackageName $PackageName -BinDir $BinDir
                        $destinationPath = Join-Path $BinDir $resolvedPath
                        
                        $destinationDir = Split-Path $destinationPath -Parent
                        if ($destinationDir -and !(Test-Path $destinationDir)) {
                            New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
                        }
                        Copy-Item -Path $_.FullName -Destination $destinationPath -Force
                    }
                }
            }
            
            Write-Host "$PackageName binary extraction completed."
            return $true
        } else {
            Write-Host "Error: Extracted folder not found."
            return $false
        }
    } catch {
        Write-Host "Error: Failed to extract archive file."
        Write-Host $_.Exception.Message
        return $false
    } finally {
        # 一時ディレクトリをクリーンアップ
        if (Test-Path $TempDir) {
            Remove-Item -Path $TempDir -Recurse -Force
            Write-Host "Temporary directory cleaned up."
        }
    }
}

# オプションに基づくメイン実行

if ($Uninstall) {
    # アンインストール: ディレクトリを削除して PATH をクリーンアップ
    Write-Host "Starting uninstall process..."
    
    # まず PATH から削除
    $pathDirs = Get-PathDirectories -BaseDir $InstallDir
    Remove-FromUserPath -Directories $pathDirs
    
    # インストールディレクトリを削除
    if (Test-Path $InstallDir) {
        Write-Host "Removing installation directory: $InstallDir"
        Remove-Item -Path $InstallDir -Recurse -Force
        Write-Host "Installation directory removed."
    } else {
        Write-Host "Installation directory not found: $InstallDir"
    }
    
    Write-Host "Uninstall completed." -ForegroundColor Green
    exit 0
}

# Extract または Install の場合、抽出を実行
if ($Extract -or $Install) {
    # 起動時に bin ディレクトリをクリーンアップ
    Write-Host "Cleaning installation directory: $InstallDir"
    if (Test-Path $InstallDir) {
        Remove-Item -Path $InstallDir -Recurse -Force
        Write-Host "Removed existing installation directory."
    }
    
    # まずすべてのパッケージファイルのブロックを解除
    Write-Host "Unblocking package files..."
    $packageFiles = Get-ChildItem -Path "packages" -File
    foreach ($packageFile in $packageFiles) {
        try {
            # ファイルを直接ブロック解除を試行 (より安全なアプローチ)
            $beforeAttribs = (Get-Item $packageFile.FullName).Attributes
            Unblock-File -Path $packageFile.FullName -ErrorAction SilentlyContinue
            $afterAttribs = (Get-Item $packageFile.FullName).Attributes
            
            # 属性が変更された場合、ファイルはブロックされていた可能性がある
            if ($beforeAttribs -ne $afterAttribs) {
                Write-Host "Unblocked: $($packageFile.Name)"
            }
        } catch {
            # ブロック解除に失敗した場合は静かに続行
        }
    }
    Write-Host "Package file unblocking completed."

    # パッケージを抽出
    Write-Host "Starting package extraction process..."

    $extractionResults = @()

    # Node.js を抽出
    $nodeOutput = Extract-Package -ArchiveFile "packages\node-v22.18.0-win-x64.zip" -PackageName "Node.js v22.18.0" -BinDir $InstallDir
    $extractionResults += @($nodeOutput[-1])

    # Pandoc を抽出  
    $pandocOutput = Extract-Package -ArchiveFile "packages\pandoc-3.7.0.2-windows-x86_64.zip" -PackageName "Pandoc 3.7.0.2" -BinDir $InstallDir
    $extractionResults += @($pandocOutput[-1])

    # pandoc-crossref を抽出
    $crossrefOutput = Extract-Package -ArchiveFile "packages\pandoc-crossref-Windows-X64.7z" -PackageName "pandoc-crossref" -BinDir $InstallDir
    $extractionResults += @($crossrefOutput[-1])

    # Doxygen を抽出
    $doxygenOutput = Extract-Package -ArchiveFile "packages\doxygen-1.14.0.windows.x64.bin.zip" -PackageName "Doxygen 1.14.0" -BinDir $InstallDir
    $extractionResults += @($doxygenOutput[-1])

    # doxybook2 を抽出
    $doxybook2Output = Extract-Package -ArchiveFile "packages\doxybook2-windows-win64-v1.6.1.zip" -PackageName "doxybook2 v1.6.1" -BinDir $InstallDir
    $extractionResults += @($doxybook2Output[-1])

    # Microsoft JDK を抽出
    $jdkOutput = Extract-Package -ArchiveFile "packages\microsoft-jdk-21.0.8-windows-x64.zip" -PackageName "Microsoft JDK 21.0.8" -BinDir $InstallDir
    $extractionResults += @($jdkOutput[-1])

    # PlantUML を抽出
    $plantumlOutput = Extract-Package -ArchiveFile "packages\plantuml-1.2025.4.jar" -PackageName "PlantUML 1.2025.4" -BinDir $InstallDir
    $extractionResults += @($plantumlOutput[-1])

    # Python を抽出
    $pythonOutput = Extract-Package -ArchiveFile "packages\python-3.13.7-embed-amd64.zip" -PackageName "Python 3.13.7" -BinDir $InstallDir
    $extractionResults += @($pythonOutput[-1])

    # Portable Git を抽出
    Write-Host "Starting Portable Git extraction..."
    $gitArchiveFile = "packages\PortableGit-2.51.0-64-bit.7z.exe"
    if (Test-Path $gitArchiveFile) {
        Write-Host "Archive file found: $gitArchiveFile"
        
        # bin フォルダに git ディレクトリを作成
        $gitBinDir = "$InstallDir\git"
        if (!(Test-Path $gitBinDir)) {
            New-Item -ItemType Directory -Path $gitBinDir -Force | Out-Null
            Write-Host "Created git directory: $gitBinDir"
        }
        
        # 自己展開実行ファイルを使用して抽出 (完了まで待機)
        Write-Host "Extracting Portable Git (this may take a moment)..."
        $process = Start-Process -FilePath $gitArchiveFile -ArgumentList "-y", "-o$(Resolve-Path $gitBinDir)" -Wait -PassThru
        
        if ($process.ExitCode -eq 0) {
            Write-Host "Portable Git extracted successfully to: $gitBinDir"
            $extractionResults += @($true)
        } else {
            Write-Host "Error: Portable Git extraction failed with exit code: $($process.ExitCode)"
            $extractionResults += @($false)
        }
    } else {
        Write-Host "Error: $gitArchiveFile not found."
        Write-Host "Please download Portable Git and place it in the packages folder."
        $extractionResults += @($false)
    }

    # 全体的な結果をチェック
    $successfulExtractions = ($extractionResults | Where-Object { $_ -eq $true }).Count
    $totalPackages = $extractionResults.Count

    Write-Host "`nExtraction Summary:"
    Write-Host "Success: $successfulExtractions / $totalPackages"

    if ($successfulExtractions -eq $totalPackages) {
        Write-Host "`nAll packages extracted successfully."
        
        # Install オプションの場合、PATH に追加
        if ($Install) {
            Write-Host "`nManaging PATH environment variables..."
            $pathDirs = Get-PathDirectories -BaseDir $InstallDir
            
            # 既存のエントリを最初に削除 (再インストールシナリオ用)
            Write-Host "Removing any existing PATH entries..."
            Remove-FromUserPath -Directories $pathDirs
            
            # 新しいエントリを追加
            Write-Host "Adding tools to PATH..."
            Add-ToUserPath -Directories $pathDirs
            Write-Host "Installation completed." -ForegroundColor Green
        } else {
            Write-Host "Extraction completed." -ForegroundColor Green
        }
    } else {
        Write-Host "`nSome packages failed to extract." -ForegroundColor Yellow
        exit 1
    }
}
