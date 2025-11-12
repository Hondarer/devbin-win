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
        "$BaseDir\dotnet8sdk",
        "$BaseDir\git",
        "$BaseDir\git\bin",
        "$BaseDir\git\cmd",
        "$BaseDir\vscode\bin"
    )
    
    return $pathDirs
}

# コマンドが PATH で既に利用可能かどうかをチェックする
function Test-CommandExists {
    param([string]$CommandName)
    try {
        $command = Get-Command $CommandName -ErrorAction Stop

        # Python/Python3 の場合、Windows Store アプリのプロキシかどうかをチェック
        if ($CommandName -match "^python3?$") {
            $commandPath = $command.Source

            # WindowsApps パスの場合、実際に実行可能かテスト
            if ($commandPath -match "\\WindowsApps\\") {
                Write-Host "  Detected Windows Store Python proxy: $commandPath"
                Write-Host "  Testing if Python is actually installed..."

                try {
                    # --version オプションでテスト実行
                    $null = Start-Process -FilePath $commandPath -ArgumentList "--version" -NoNewWindow -Wait -PassThru -RedirectStandardError "stderr_temp.txt" -RedirectStandardOutput "stdout_temp.txt"

                    # 標準エラー出力をチェック
                    $stderrContent = ""
                    if (Test-Path "stderr_temp.txt") {
                        $stderrContent = Get-Content "stderr_temp.txt" -Raw -ErrorAction SilentlyContinue
                        Remove-Item "stderr_temp.txt" -ErrorAction SilentlyContinue
                    }

                    # 標準出力をチェック
                    $stdoutContent = ""
                    if (Test-Path "stdout_temp.txt") {
                        $stdoutContent = Get-Content "stdout_temp.txt" -Raw -ErrorAction SilentlyContinue
                        Remove-Item "stdout_temp.txt" -ErrorAction SilentlyContinue
                    }

                    # ストアアプリのプロキシの場合、stderr に "Python" とだけ出力される
                    if ($stderrContent -match "^Python\s*$" -or ($stderrContent -match "Python" -and -not ($stderrContent -match "\d+\.\d+" -or $stdoutContent -match "\d+\.\d+"))) {
                        Write-Host "  Windows Store Python proxy detected - Python not actually installed"
                        return $false
                    }

                    # 正常なバージョン情報が出力された場合は有効
                    if ($stdoutContent -match "\d+\.\d+" -or $stderrContent -match "\d+\.\d+") {
                        Write-Host "  Valid Python installation detected"
                        return $true
                    }

                    # その他のエラーの場合は無効とみなす
                    Write-Host "  Python proxy test failed - treating as not installed"
                    return $false

                } catch {
                    Write-Host "  Failed to test Python proxy: $($_.Exception.Message)"
                    return $false
                } finally {
                    # 一時ファイルのクリーンアップ
                    Remove-Item "stderr_temp.txt" -ErrorAction SilentlyContinue
                    Remove-Item "stdout_temp.txt" -ErrorAction SilentlyContinue
                }
            }
        }

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
            elseif ($dirPath -like "*dotnet8sdk") {
                if (Test-CommandExists "dotnet") {
                    Write-Host "  Skipped (dotnet.exe already available): $dirPath"
                    $shouldSkip = $true
                }
            }
            elseif ($dirPath -like "*git" -or $dirPath -like "*git\bin" -or $dirPath -like "*git\cmd") {
                if (Test-CommandExists "git") {
                    Write-Host "  Skipped (git.exe already available): $dirPath"
                    $shouldSkip = $true
                }
            }
            elseif ($dirPath -like "*vscode") {
                if (Test-CommandExists "code") {
                    Write-Host "  Skipped (code.cmd already available): $dirPath"
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

                # dotnet8sdk パスの場合、DOTNET_HOME 環境変数を設定
                if ($dirPath -like "*dotnet8sdk") {
                    $currentDotnetHome = [Environment]::GetEnvironmentVariable("DOTNET_HOME", "User")
                    if (-not $currentDotnetHome) {
                        [Environment]::SetEnvironmentVariable("DOTNET_HOME", $dirPath, "User")
                        Write-Host "  Set DOTNET_HOME: $dirPath"
                    } else {
                        Write-Host "  DOTNET_HOME already set: $currentDotnetHome"
                    }

                    # DOTNET_CLI_TELEMETRY_OPTOUT を設定してテレメトリを無効化
                    $currentTelemetryOptout = [Environment]::GetEnvironmentVariable("DOTNET_CLI_TELEMETRY_OPTOUT", "User")
                    if (-not $currentTelemetryOptout) {
                        [Environment]::SetEnvironmentVariable("DOTNET_CLI_TELEMETRY_OPTOUT", "1", "User")
                        Write-Host "  Set DOTNET_CLI_TELEMETRY_OPTOUT: 1"
                    } else {
                        Write-Host "  DOTNET_CLI_TELEMETRY_OPTOUT already set: $currentTelemetryOptout"
                    }
                }
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
    param(
        [string[]]$Directories,
        [switch]$Silent = $false
    )

    if (-not $Silent) {
        Write-Host "Removing directories from user PATH..."
    }
    
    $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if (-not $currentPath) {
        if (-not $Silent) {
            Write-Host "User PATH is empty."
        }
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
                if (-not $Silent) {
                    Write-Host "  Removed: $entry"
                }
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
        if (-not $Silent) {
            Write-Host "User PATH updated successfully."
        }
    } else {
        if (-not $Silent) {
            Write-Host "No matching directories found in PATH."
        }
    }
}

# 重複ファイル追跡用のグローバル キャッシュ
$global:DuplicateFiles = @{}
$global:PackageFileMapping = @{}

# 長いパスを UNC 形式に変換する関数
function Convert-ToLongPath {
    param([string]$Path)

    # 既に UNC 形式の場合はそのまま返す
    if ($Path.StartsWith("\\?\")) {
        return $Path
    }

    # 相対パスの場合は絶対パスに変換
    if (-not [System.IO.Path]::IsPathRooted($Path)) {
        $Path = (Resolve-Path $Path -ErrorAction SilentlyContinue).Path
        if (-not $Path) {
            return $null
        }
    }

    # UNC 形式に変換
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

# 環境変数をレジストリからカレントプロセスに同期するヘルパー関数
function Sync-EnvironmentVariable {
    param(
        [string]$VariableName,
        [switch]$Silent = $false
    )

    try {
        if ($VariableName -eq "PATH") {
            # PATH の特別処理: User と Machine を結合
            $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
            $machinePath = [Environment]::GetEnvironmentVariable("PATH", "Machine")

            # 空の値を空文字列として扱う
            if (-not $userPath) { $userPath = "" }
            if (-not $machinePath) { $machinePath = "" }

            # User PATH を優先して結合
            $combinedPath = if ($userPath -and $machinePath) {
                "$userPath;$machinePath"
            } elseif ($userPath) {
                $userPath
            } elseif ($machinePath) {
                $machinePath
            } else {
                ""
            }

            # 重複エントリと空エントリを除去 (順序を保持)
            if ($combinedPath) {
                $pathEntries = $combinedPath -split ';' | Where-Object { $_.Trim() -ne "" }
                $uniqueEntries = @()
                $seenEntries = @{}

                foreach ($entry in $pathEntries) {
                    $trimmedEntry = $entry.Trim()
                    if ($trimmedEntry -and -not $seenEntries.ContainsKey($trimmedEntry.ToLower())) {
                        $uniqueEntries += $trimmedEntry
                        $seenEntries[$trimmedEntry.ToLower()] = $true
                    }
                }

                $cleanPath = $uniqueEntries -join ';'

                # カレントプロセスに設定
                $env:PATH = $cleanPath

                if (-not $Silent) {
                    Write-Host "Synchronized PATH environment variable to current process"
                }
            }
        } else {
            # その他の環境変数: User を優先、なければ Machine
            $userValue = [Environment]::GetEnvironmentVariable($VariableName, "User")
            $machineValue = [Environment]::GetEnvironmentVariable($VariableName, "Machine")

            $finalValue = if ($userValue) { $userValue } else { $machineValue }

            if ($finalValue) {
                Set-Item -Path "Env:$VariableName" -Value $finalValue
                if (-not $Silent) {
                    Write-Host "Synchronized $VariableName environment variable to current process"
                }
            } else {
                # 値が存在しない場合はカレントプロセスからも削除
                if (Test-Path "Env:$VariableName") {
                    Remove-Item -Path "Env:$VariableName" -ErrorAction SilentlyContinue
                    if (-not $Silent) {
                        Write-Host "Removed $VariableName from current process (not set in registry)"
                    }
                }
            }
        }

        return $true
    } catch {
        if (-not $Silent) {
            Write-Host "Warning: Failed to sync $VariableName environment variable: $($_.Exception.Message)" -ForegroundColor Yellow
        }
        return $false
    }
}

# 複数の環境変数を一括同期する関数
function Sync-EnvironmentVariables {
    param(
        [string[]]$VariableNames = @("PATH", "DOTNET_HOME", "DOTNET_CLI_TELEMETRY_OPTOUT"),
        [switch]$Silent = $false
    )

    if (-not $Silent) {
        Write-Host "Synchronizing environment variables with current process..."
    }

    $syncCount = 0
    foreach ($varName in $VariableNames) {
        if (Sync-EnvironmentVariable -VariableName $varName -Silent:$Silent) {
            $syncCount++
        }
    }

    if (-not $Silent) {
        Write-Host "Successfully synchronized $syncCount/$($VariableNames.Count) environment variables"
    }

    return $syncCount -eq $VariableNames.Count
}

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
    if ($PackageName -match "\.NET SDK") { return "dotnet8sdk" }
    if ($PackageName -match "VS Code") { return "vscode" }
    if ($PackageName -match "GNU Make") { return "make" }
    if ($PackageName -match "CMake") { return "cmake" }
    if ($PackageName -match "NuGet") { return "nuget" }
    if ($PackageName -match "nkf") { return "nkf" }

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
    if ($PackageName -match "\.NET SDK") {
        return $true
    }
    if ($PackageName -match "VS Code") {
        return $true
    }
    if ($PackageName -match "GNU Make") {
        return $true
    }
    if ($PackageName -match "CMake") {
        return $true
    }
    if ($PackageName -match "NuGet") {
        return $true
    }
    if ($PackageName -match "nkf") {
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

function Expand-Package {
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

    # NuGet EXE ファイルの特別処理
    if ($PackageName -match "NuGet" -and $ArchiveFile -match "\.exe$") {
        Write-Host "Detected NuGet EXE file, applying special handling..."

        # bin ディレクトリが存在しない場合は作成
        if (!(Test-Path $BinDir)) {
            New-Item -ItemType Directory -Path $BinDir
            Write-Host "Created bin directory."
        }

        # EXE ファイル名を抽出
        $exeFileName = Split-Path $ArchiveFile -Leaf
        Write-Host "NuGet EXE file: $exeFileName"

        # EXE ファイルを bin ディレクトリにコピー
        $exeDestination = Join-Path $BinDir "nuget.exe"

        # ファイルのブロックを解除
        try {
            Unblock-File -Path $ArchiveFile -ErrorAction SilentlyContinue
            Write-Host "Unblocked $exeFileName"
        } catch {
            # ブロック解除に失敗した場合は続行
        }

        Copy-Item -Path $ArchiveFile -Destination $exeDestination -Force
        Write-Host "Copied $exeFileName to bin directory as nuget.exe"

        # コピー後もブロック解除
        try {
            Unblock-File -Path $exeDestination -ErrorAction SilentlyContinue
        } catch {
            # ブロック解除に失敗した場合は続行
        }

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

                # python.exe のコピーを python3.exe として作成
                $pythonExe = Join-Path $targetPath "python.exe"
                $python3Exe = Join-Path $targetPath "python3.exe"

                if ((Test-Path $pythonExe) -and !(Test-Path $python3Exe)) {
                    try {
                        Copy-Item -Path $pythonExe -Destination $python3Exe -Force
                        Write-Host "Created python3.exe copy for compatibility"
                    } catch {
                        Write-Host "Warning: Failed to create python3.exe: $($_.Exception.Message)"
                    }
                }

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
            }
            elseif ($isSpecialPackage -and $PackageName -match "\.NET SDK") {
                # .NET SDK の特別処理
                Write-Host "Applying special .NET SDK handling..."

                $targetFolderName = "dotnet8sdk"
                $targetPath = Join-Path $BinDir $targetFolderName

                Write-Host "Creating target directory: $targetFolderName"

                # ターゲットディレクトリを作成
                if (!(Test-Path $targetPath)) {
                    New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
                }

                # .NET SDK の場合、一時ディレクトリ全体の内容をコピー
                # .NET SDK アーカイブは直下にファイルとフォルダが展開される
                $absoluteTempDir = (Resolve-Path $TempDir).Path
                Write-Host "Copying .NET SDK files from temp directory: $absoluteTempDir"
                Get-ChildItem -Path $absoluteTempDir -Recurse | ForEach-Object {
                    $relativePath = $_.FullName.Substring($absoluteTempDir.Length + 1)
                    $destinationPath = Join-Path $targetPath $relativePath

                    if ($_.PSIsContainer) {
                        # 長いパス対応のディレクトリ作成
                        New-LongPathDirectory -Path $destinationPath | Out-Null
                    } else {
                        $destinationDir = Split-Path $destinationPath -Parent
                        if ($destinationDir) {
                            # 長いパス対応のディレクトリ作成
                            New-LongPathDirectory -Path $destinationDir | Out-Null
                        }

                        # 長いパス対応のファイルコピー
                        $copyResult = Copy-LongPathFile -SourcePath $_.FullName -DestinationPath $destinationPath
                        if (-not $copyResult) {
                            Write-Host "  Skipped: $relativePath"
                        }
                    }
                }

                Write-Host ".NET SDK installed to: $targetPath"
            }
            elseif ($isSpecialPackage -and $PackageName -match "VS Code") {
                # VS Code の特別処理
                Write-Host "Applying special VS Code handling..."

                $targetFolderName = "vscode"
                $targetPath = Join-Path $BinDir $targetFolderName

                Write-Host "Creating target directory: $targetFolderName"

                # ターゲットディレクトリを作成
                if (!(Test-Path $targetPath)) {
                    New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
                }

                # VS Code の場合、zip ファイルは直下に Code.exe やその他のファイルを含む
                # sourcePath が一時ディレクトリの場合、直下のファイルをコピー
                Write-Host "Copying VS Code files from: $sourcePath"

                if ($sourcePath -eq $TempDir) {
                    # ファイルが一時ディレクトリに直接ある
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
                } else {
                    # ファイルがサブディレクトリにある場合
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

                # 存在しない場合、data フォルダを作成
                $dataPath = Join-Path $targetPath "data"
                if (!(Test-Path $dataPath)) {
                    New-Item -ItemType Directory -Path $dataPath -Force | Out-Null
                    Write-Host "Created data folder: $dataPath"
                }

                Write-Host "VS Code installed to: $targetPath"
            }
            elseif ($isSpecialPackage -and $PackageName -match "GNU Make") {
                # GNU Make の特別処理
                Write-Host "Applying special GNU Make handling..."

                # GNU Make の場合、bin/ ディレクトリの内容だけをコピー
                # アーカイブには bin/, contrib/, manifest/, share/ などが含まれるが、bin/ のみが必要

                # bin ディレクトリを検索または特定
                $binFolder = $null

                # sourcePath 自体が bin フォルダかチェック
                $sourcePathName = Split-Path $sourcePath -Leaf
                if ($sourcePathName -eq "bin") {
                    $binFolder = Get-Item $sourcePath
                }
                elseif ($sourcePath -eq $TempDir) {
                    # 一時ディレクトリに直接展開された場合
                    $possibleBinFolder = Join-Path $TempDir "bin"
                    if (Test-Path $possibleBinFolder) {
                        $binFolder = Get-Item $possibleBinFolder
                    }
                } else {
                    # サブディレクトリに展開された場合
                    $possibleBinFolder = Join-Path $sourcePath "bin"
                    if (Test-Path $possibleBinFolder) {
                        $binFolder = Get-Item $possibleBinFolder
                    }
                }

                if ($binFolder) {
                    # bin/ ディレクトリの内容を BinDir に直接コピー
                    $allItems = Get-ChildItem -Path $binFolder.FullName -Recurse

                    foreach ($item in $allItems) {
                        # 相対パスを安全に計算
                        $relativePath = $item.FullName.Substring($binFolder.FullName.Length).TrimStart('\', '/')

                        # 相対パスが空の場合はスキップ (bin フォルダ自体)
                        if ([string]::IsNullOrWhiteSpace($relativePath)) {
                            continue
                        }

                        $destinationPath = Join-Path $BinDir $relativePath

                        if ($item.PSIsContainer) {
                            if (!(Test-Path $destinationPath)) {
                                New-Item -ItemType Directory -Path $destinationPath -Force | Out-Null
                            }
                        } else {
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

                    Write-Host "GNU Make installed to: $BinDir"
                } else {
                    Write-Host "Warning: bin folder not found in GNU Make archive" -ForegroundColor Yellow
                }
            }
            elseif ($isSpecialPackage -and $PackageName -match "CMake") {
                # CMake の特別処理
                Write-Host "Applying special CMake handling..."

                # CMake の場合、bin/ ディレクトリの内容だけをコピー
                # アーカイブには bin/, doc/, man/, share/ などが含まれるが、bin/ のみが必要

                # bin ディレクトリを検索または特定
                $binFolder = $null

                # sourcePath 自体が bin フォルダかチェック
                $sourcePathName = Split-Path $sourcePath -Leaf
                if ($sourcePathName -eq "bin") {
                    $binFolder = Get-Item $sourcePath
                }
                elseif ($sourcePath -eq $TempDir) {
                    # 一時ディレクトリに直接展開された場合
                    $possibleBinFolder = Join-Path $TempDir "bin"
                    if (Test-Path $possibleBinFolder) {
                        $binFolder = Get-Item $possibleBinFolder
                    }
                } else {
                    # サブディレクトリに展開された場合 (通常は cmake-x.x.x-windows-x86_64/bin)
                    $possibleBinFolder = Join-Path $sourcePath "bin"
                    if (Test-Path $possibleBinFolder) {
                        $binFolder = Get-Item $possibleBinFolder
                    }
                }

                if ($binFolder) {
                    # bin/ ディレクトリの内容を BinDir に直接コピー
                    $allItems = Get-ChildItem -Path $binFolder.FullName -Recurse

                    foreach ($item in $allItems) {
                        # 相対パスを安全に計算
                        $relativePath = $item.FullName.Substring($binFolder.FullName.Length).TrimStart('\', '/')

                        # 相対パスが空の場合はスキップ (bin フォルダ自体)
                        if ([string]::IsNullOrWhiteSpace($relativePath)) {
                            continue
                        }

                        $destinationPath = Join-Path $BinDir $relativePath

                        if ($item.PSIsContainer) {
                            if (!(Test-Path $destinationPath)) {
                                New-Item -ItemType Directory -Path $destinationPath -Force | Out-Null
                            }
                        } else {
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

                    Write-Host "CMake installed to: $BinDir"
                } else {
                    Write-Host "Warning: bin folder not found in CMake archive" -ForegroundColor Yellow
                }
            }
            elseif ($isSpecialPackage -and $PackageName -match "nkf") {
                # nkf の特別処理
                Write-Host "Applying special nkf handling..."

                # nkf の場合、bin/mingw64/ ディレクトリの内容だけをコピー
                # アーカイブには bin/mingw64/ が含まれる

                # bin/mingw64 ディレクトリを検索
                $nkfBinFolder = $null

                # sourcePath 以下で bin/mingw64 を探す
                if ($sourcePath -eq $TempDir) {
                    # 一時ディレクトリに直接展開された場合
                    $possibleBinFolder = Join-Path $TempDir "bin\mingw64"
                    if (Test-Path $possibleBinFolder) {
                        $nkfBinFolder = Get-Item $possibleBinFolder
                    }
                } else {
                    # サブディレクトリに展開された場合 (通常は nkf-bin-2.1.5-96c3371/bin/mingw64)
                    $possibleBinFolder = Join-Path $sourcePath "bin\mingw64"
                    if (Test-Path $possibleBinFolder) {
                        $nkfBinFolder = Get-Item $possibleBinFolder
                    }
                }

                if ($nkfBinFolder) {
                    # bin/mingw64/ ディレクトリの内容を BinDir に直接コピー
                    $allItems = Get-ChildItem -Path $nkfBinFolder.FullName -Recurse

                    foreach ($item in $allItems) {
                        # 相対パスを安全に計算
                        $relativePath = $item.FullName.Substring($nkfBinFolder.FullName.Length).TrimStart('\', '/')

                        # 相対パスが空の場合はスキップ (bin/mingw64 フォルダ自体)
                        if ([string]::IsNullOrWhiteSpace($relativePath)) {
                            continue
                        }

                        $destinationPath = Join-Path $BinDir $relativePath

                        if ($item.PSIsContainer) {
                            if (!(Test-Path $destinationPath)) {
                                New-Item -ItemType Directory -Path $destinationPath -Force | Out-Null
                            }
                        } else {
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

                    Write-Host "nkf installed to: $BinDir"
                } else {
                    Write-Host "Warning: bin/mingw64 folder not found in nkf archive" -ForegroundColor Yellow
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

# VS Code data フォルダをバックアップする
function Backup-VSCodeData {
    param(
        [string]$InstallDirectory,
        [switch]$Silent = $false
    )

    $vscodeDataPath = Join-Path $InstallDirectory "vscode\data"
    if (!(Test-Path $vscodeDataPath)) {
        if (-not $Silent) {
            Write-Host "VS Code data folder not found, skipping backup: $vscodeDataPath"
        }
        return $null
    }

    # 一時バックアップディレクトリを作成
    $tempBackupDir = Join-Path ([System.IO.Path]::GetTempPath()) "vscode_data_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"

    try {
        if (-not $Silent) {
            Write-Host "Backing up VS Code data folder to: $tempBackupDir"
        }

        # data フォルダを一時ディレクトリにコピー
        Copy-Item -Path $vscodeDataPath -Destination $tempBackupDir -Recurse -Force

        if (-not $Silent) {
            Write-Host "VS Code data backup completed successfully"
        }

        return $tempBackupDir
    } catch {
        if (-not $Silent) {
            Write-Host "Warning: Failed to backup VS Code data: $($_.Exception.Message)" -ForegroundColor Yellow
        }

        # バックアップに失敗した場合、作成した一時ディレクトリをクリーンアップ
        if (Test-Path $tempBackupDir) {
            Remove-Item -Path $tempBackupDir -Recurse -Force -ErrorAction SilentlyContinue
        }

        return $null
    }
}

# VS Code data フォルダを復元する関数
function Restore-VSCodeData {
    param(
        [string]$InstallDirectory,
        [string]$BackupPath,
        [switch]$Silent = $false
    )

    if (-not $BackupPath -or !(Test-Path $BackupPath)) {
        if (-not $Silent) {
            Write-Host "VS Code data backup not found, skipping restore: $BackupPath"
        }
        return $false
    }

    $vscodeDir = Join-Path $InstallDirectory "vscode"
    if (!(Test-Path $vscodeDir)) {
        if (-not $Silent) {
            Write-Host "VS Code installation directory not found, skipping restore: $vscodeDir"
        }
        return $false
    }

    $vscodeDataPath = Join-Path $vscodeDir "data"

    try {
        if (-not $Silent) {
            Write-Host "Restoring VS Code data folder from backup: $BackupPath"
        }

        # 既存の data フォルダが存在する場合は削除
        if (Test-Path $vscodeDataPath) {
            Remove-Item -Path $vscodeDataPath -Recurse -Force
        }

        # バックアップから data フォルダを復元
        Copy-Item -Path $BackupPath -Destination $vscodeDataPath -Recurse -Force

        if (-not $Silent) {
            Write-Host "VS Code data restoration completed successfully"
        }

        return $true
    } catch {
        if (-not $Silent) {
            Write-Host "Warning: Failed to restore VS Code data: $($_.Exception.Message)" -ForegroundColor Yellow
        }
        return $false
    } finally {
        # バックアップディレクトリをクリーンアップ
        if (Test-Path $BackupPath) {
            Remove-Item -Path $BackupPath -Recurse -Force -ErrorAction SilentlyContinue
            if (-not $Silent) {
                Write-Host "Cleaned up temporary backup directory"
            }
        }
    }
}

# 完全アンインストール処理を実行する関数
function Invoke-CompleteUninstall {
    param(
        [string]$InstallDirectory,
        [switch]$Silent = $false,
        [switch]$PreserveVSCodeData = $false
    )

    if (-not $Silent) {
        Write-Host "Starting cleanup process..."
    }

    # VS Code data フォルダのバックアップ
    $vscodeDataBackup = $null
    if ($PreserveVSCodeData) {
        $vscodeDataBackup = Backup-VSCodeData -InstallDirectory $InstallDirectory -Silent:$Silent
    }

    try {
        # PATH から削除
        $pathDirs = Get-PathDirectories -BaseDir $InstallDirectory
        if ($pathDirs -and $pathDirs.Count -gt 0) {
            Remove-FromUserPath -Directories $pathDirs -Silent:$Silent
        }

        # DOTNET_HOME 環境変数を削除 (dotnet8sdk インストールディレクトリと一致する場合)
        $currentDotnetHome = [Environment]::GetEnvironmentVariable("DOTNET_HOME", "User")
        $dotnetSdkPath = Join-Path $InstallDirectory "dotnet8sdk"
        if ($currentDotnetHome -and ($currentDotnetHome -eq $dotnetSdkPath)) {
            [Environment]::SetEnvironmentVariable("DOTNET_HOME", $null, "User")
            if (-not $Silent) {
                Write-Host "Removed DOTNET_HOME environment variable: $currentDotnetHome"
            }

            # DOTNET_CLI_TELEMETRY_OPTOUT も削除 (このスクリプトで設定したと推定される場合)
            $currentTelemetryOptout = [Environment]::GetEnvironmentVariable("DOTNET_CLI_TELEMETRY_OPTOUT", "User")
            if ($currentTelemetryOptout -eq "1") {
                [Environment]::SetEnvironmentVariable("DOTNET_CLI_TELEMETRY_OPTOUT", $null, "User")
                if (-not $Silent) {
                    Write-Host "Removed DOTNET_CLI_TELEMETRY_OPTOUT environment variable"
                }
            }
        }

        # インストールディレクトリを削除
        if (Test-Path $InstallDirectory) {
            if (-not $Silent) {
                Write-Host "Removing installation directory: $InstallDirectory"
            }

            if ($PreserveVSCodeData) {
                # VS Code data フォルダを保持しながら他のファイルを削除
                Get-ChildItem -Path $InstallDirectory | Where-Object {
                    -not ($_.Name -eq "vscode" -and $_.PSIsContainer)
                } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

                # VS Code ディレクトリ内で data フォルダ以外を削除
                $vscodeDir = Join-Path $InstallDirectory "vscode"
                if (Test-Path $vscodeDir) {
                    Get-ChildItem -Path $vscodeDir | Where-Object {
                        -not ($_.Name -eq "data" -and $_.PSIsContainer)
                    } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

                    if (-not $Silent) {
                        Write-Host "Installation directory removed (VS Code data folder preserved)"
                    }
                } else {
                    # vscode ディレクトリが存在しない場合は通常の削除
                    Remove-Item -Path $InstallDirectory -Recurse -Force -ErrorAction SilentlyContinue
                    if (-not $Silent) {
                        Write-Host "Installation directory removed."
                    }
                }
            } else {
                # 通常の完全削除
                Remove-Item -Path $InstallDirectory -Recurse -Force -ErrorAction SilentlyContinue
                if (-not $Silent) {
                    Write-Host "Installation directory removed."
                }
            }
        } else {
            if (-not $Silent) {
                Write-Host "Installation directory not found: $InstallDirectory"
            }
        }

        return $true
    } catch {
        if (-not $Silent) {
            Write-Host "Warning: Some cleanup operations failed: $($_.Exception.Message)" -ForegroundColor Yellow
        }

        # エラーが発生した場合もバックアップをクリーンアップ
        if ($vscodeDataBackup -and (Test-Path $vscodeDataBackup)) {
            Remove-Item -Path $vscodeDataBackup -Recurse -Force -ErrorAction SilentlyContinue
            if (-not $Silent) {
                Write-Host "Cleaned up VS Code data backup due to error"
            }
        }

        return $false
    }
}

# オプションに基づくメイン実行

if ($Uninstall) {
    # アンインストール: ディレクトリを削除して PATH をクリーンアップ
    $uninstallResult = Invoke-CompleteUninstall -InstallDirectory $InstallDir -PreserveVSCodeData

    if ($uninstallResult) {
        Write-Host "Uninstall completed." -ForegroundColor Green
    } else {
        Write-Host "Uninstall completed with warnings." -ForegroundColor Yellow
    }
    exit 0
}

# Extract または Install の場合、抽出を実行
if ($Extract -or $Install) {
    # インストール前にクリーンアップを実行
    Write-Host "Performing pre-installation cleanup..."
    $cleanupResult = Invoke-CompleteUninstall -InstallDirectory $InstallDir -Silent -PreserveVSCodeData

    if ($cleanupResult) {
        Write-Host "Previous installation cleaned up successfully."
    } else {
        Write-Host "Cleanup completed with some warnings (this is normal for first-time installation)."
    }

    # 環境変数をカレントプロセスに同期
    Write-Host "Synchronizing environment variables..."
    Sync-EnvironmentVariables -Silent | Out-Null
    
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
    $nodeOutput = Expand-Package -ArchiveFile "packages\node-v22.18.0-win-x64.zip" -PackageName "Node.js v22.18.0" -BinDir $InstallDir
    $extractionResults += @($nodeOutput[-1])

    # Pandoc を抽出
    $pandocOutput = Expand-Package -ArchiveFile "packages\pandoc-3.8-windows-x86_64.zip" -PackageName "Pandoc 3.8" -BinDir $InstallDir
    $extractionResults += @($pandocOutput[-1])

    # pandoc-crossref を抽出
    $crossrefOutput = Expand-Package -ArchiveFile "packages\pandoc-crossref-Windows-X64.7z" -PackageName "pandoc-crossref v0.3.21" -BinDir $InstallDir
    $extractionResults += @($crossrefOutput[-1])

    # Doxygen を抽出
    $doxygenOutput = Expand-Package -ArchiveFile "packages\doxygen-1.14.0.windows.x64.bin.zip" -PackageName "Doxygen 1.14.0" -BinDir $InstallDir
    $extractionResults += @($doxygenOutput[-1])

    # doxybook2 を抽出
    $doxybook2Output = Expand-Package -ArchiveFile "packages\doxybook2-windows-win64-v1.6.1.zip" -PackageName "doxybook2 v1.6.1" -BinDir $InstallDir
    $extractionResults += @($doxybook2Output[-1])

    # Microsoft JDK を抽出
    $jdkOutput = Expand-Package -ArchiveFile "packages\microsoft-jdk-21.0.8-windows-x64.zip" -PackageName "Microsoft JDK 21.0.8" -BinDir $InstallDir
    $extractionResults += @($jdkOutput[-1])

    # PlantUML を抽出
    $plantumlOutput = Expand-Package -ArchiveFile "packages\plantuml-1.2025.4.jar" -PackageName "PlantUML 1.2025.4" -BinDir $InstallDir
    $extractionResults += @($plantumlOutput[-1])

    # Python を抽出
    $pythonOutput = Expand-Package -ArchiveFile "packages\python-3.13.7-embed-amd64.zip" -PackageName "Python 3.13.7" -BinDir $InstallDir
    $extractionResults += @($pythonOutput[-1])

    # .NET SDK を抽出
    $dotnetOutput = Expand-Package -ArchiveFile "packages\dotnet-sdk-8.0.414-win-x64.zip" -PackageName ".NET SDK 8.0.414" -BinDir $InstallDir
    $extractionResults += @($dotnetOutput[-1])

    # VS Code を抽出
    $vscodeOutput = Expand-Package -ArchiveFile "packages\VSCode-win32-x64-1.104.2.zip" -PackageName "VS Code 1.104.2" -BinDir $InstallDir
    $extractionResults += @($vscodeOutput[-1])

    # VS Code data フォルダの状態確認
    $vscodeDataPath = Join-Path $InstallDir "vscode\data"
    if (Test-Path $vscodeDataPath) {
        $dataItems = Get-ChildItem -Path $vscodeDataPath -ErrorAction SilentlyContinue
        if ($dataItems -and $dataItems.Count -gt 0) {
            Write-Host "VS Code data folder found with existing settings and extensions"
        } else {
            Write-Host "VS Code data folder created (new installation)"
        }
    }

    # GNU Make を抽出
    $makeOutput = Expand-Package -ArchiveFile "packages\make-3.81-bin.zip" -PackageName "GNU Make 3.81" -BinDir $InstallDir
    $extractionResults += @($makeOutput[-1])

    # GNU Make Dependencies を抽出
    $makeDepOutput = Expand-Package -ArchiveFile "packages\make-3.81-dep.zip" -PackageName "GNU Make 3.81 Dependencies" -BinDir $InstallDir
    $extractionResults += @($makeDepOutput[-1])

    # CMake を抽出
    $cmakeOutput = Expand-Package -ArchiveFile "packages\cmake-4.1.2-windows-x86_64.zip" -PackageName "CMake 4.1.2" -BinDir $InstallDir
    $extractionResults += @($cmakeOutput[-1])

    # NuGet を抽出
    $nugetOutput = Expand-Package -ArchiveFile "packages\nuget.exe" -PackageName "NuGet" -BinDir $InstallDir
    $extractionResults += @($nugetOutput[-1])

    # nkf を抽出
    $nkfOutput = Expand-Package -ArchiveFile "packages\nkf-bin-2.1.5-96c3371.zip" -PackageName "nkf 2.1.5" -BinDir $InstallDir
    $extractionResults += @($nkfOutput[-1])

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

    # 最終的な結果をチェック
    $successfulExtractions = ($extractionResults | Where-Object { $_ -eq $true }).Count
    $totalPackages = $extractionResults.Count

    Write-Host "`nExtraction Summary:"
    Write-Host "Success: $successfulExtractions / $totalPackages"

    if ($successfulExtractions -eq $totalPackages) {
        Write-Host "`nAll packages extracted successfully."
        
        # MinGW PATH 管理スクリプトを bin ディレクトリにコピー
        Write-Host "`nCopying MinGW PATH management scripts to bin directory..."
        $mingwScripts = @(
            "Add-MinGW-Path.cmd",
            "Add-MinGW-Path.ps1", 
            "Remove-MinGW-Path.cmd",
            "Remove-MinGW-Path.ps1"
        )
        
        foreach ($scriptName in $mingwScripts) {
            $sourcePath = "packages\$scriptName"
            $destPath = "$InstallDir\$scriptName"
            
            if (Test-Path $sourcePath) {
                Copy-Item -Path $sourcePath -Destination $destPath -Force
                Write-Host "  Copied: $scriptName"
            } else {
                Write-Host "  Warning: $scriptName not found in packages folder"
            }
        }
        
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
