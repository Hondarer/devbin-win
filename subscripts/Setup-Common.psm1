# Setup-Common.psm1
# 共通関数モジュール

# コマンド情報から実体パスを取得する
function Get-CommandSourcePath {
    param(
        [System.Management.Automation.CommandInfo]$CommandInfo
    )

    if ($null -eq $CommandInfo) {
        return $null
    }

    if (-not [string]::IsNullOrWhiteSpace($CommandInfo.Source)) {
        return [string]$CommandInfo.Source
    }

    if ($CommandInfo.PSObject.Properties.Match("Path").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($CommandInfo.Path)) {
        return [string]$CommandInfo.Path
    }

    return $null
}

# PATH 比較用にディレクトリ文字列を正規化する
function Get-NormalizedPathString {
    param(
        [string]$PathValue
    )

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return $null
    }

    $normalized = $null
    try {
        if (Test-Path $PathValue) {
            $normalized = (Resolve-Path $PathValue -ErrorAction Stop).Path
        } else {
            $normalized = [System.IO.Path]::GetFullPath($PathValue)
        }
    } catch {
        $normalized = $PathValue.Trim()
    }

    if ($normalized.Length -gt 3) {
        return $normalized.TrimEnd('\')
    }

    return $normalized
}

# Python コマンド候補が実体を持つかどうかを判定する
function Test-PythonCommandCandidate {
    param(
        [string]$CommandPath
    )

    if ([string]::IsNullOrWhiteSpace($CommandPath)) {
        return $true
    }

    if ($CommandPath -notmatch "\\WindowsApps\\") {
        return $true
    }

    Write-Host "  Detected Windows Store Python proxy: $CommandPath"
    Write-Host "  Testing if Python is actually installed..."

    try {
        $null = Start-Process -FilePath $CommandPath -ArgumentList "--version" -NoNewWindow -Wait -PassThru -RedirectStandardError "stderr_temp.txt" -RedirectStandardOutput "stdout_temp.txt"

        $stderrContent = ""
        if (Test-Path "stderr_temp.txt") {
            $stderrContent = Get-Content "stderr_temp.txt" -Raw -ErrorAction SilentlyContinue
            Remove-Item "stderr_temp.txt" -ErrorAction SilentlyContinue
        }

        $stdoutContent = ""
        if (Test-Path "stdout_temp.txt") {
            $stdoutContent = Get-Content "stdout_temp.txt" -Raw -ErrorAction SilentlyContinue
            Remove-Item "stdout_temp.txt" -ErrorAction SilentlyContinue
        }

        if ($stderrContent -match "^Python\s*$" -or ($stderrContent -match "Python" -and -not ($stderrContent -match "\d+\.\d+" -or $stdoutContent -match "\d+\.\d+"))) {
            Write-Host "  Windows Store Python proxy detected - Python not actually installed"
            return $false
        }

        if ($stdoutContent -match "\d+\.\d+" -or $stderrContent -match "\d+\.\d+") {
            Write-Host "  Valid Python installation detected"
            return $true
        }

        Write-Host "  Python proxy test failed - treating as not installed"
        return $false

    } catch {
        Write-Host "  Failed to test Python proxy: $($_.Exception.Message)"
        return $false
    } finally {
        Remove-Item "stderr_temp.txt" -ErrorAction SilentlyContinue
        Remove-Item "stdout_temp.txt" -ErrorAction SilentlyContinue
    }
}

# コマンド候補が有効かどうかを判定する
function Test-CommandCandidate {
    param(
        [string]$CommandName,
        [System.Management.Automation.CommandInfo]$CommandInfo
    )

    if ($null -eq $CommandInfo) {
        return $false
    }

    if ($CommandName -match "^python3?$") {
        return Test-PythonCommandCandidate -CommandPath (Get-CommandSourcePath -CommandInfo $CommandInfo)
    }

    return $true
}

# PATH 上の有効なコマンド候補を列挙する
function Get-ValidCommandCandidates {
    param(
        [string]$CommandName
    )

    try {
        return @(Get-Command $CommandName -All -ErrorAction Stop)
    } catch {
        return @()
    }
}

# コマンドが PATH で既に利用可能かどうかをチェックする
function Test-CommandExists {
    param([string]$CommandName)

    foreach ($command in Get-ValidCommandCandidates -CommandName $CommandName) {
        if (Test-CommandCandidate -CommandName $CommandName -CommandInfo $command) {
            return $true
        }
    }

    return $false
}

# devbin-win 外部のコマンドが利用可能かどうかをチェックする
function Test-ExternalCommandExists {
    param(
        [string]$CommandName,
        [string]$InstallDir
    )

    $normalizedInstallDir = Get-NormalizedPathString -PathValue $InstallDir

    foreach ($command in Get-ValidCommandCandidates -CommandName $CommandName) {
        if (-not (Test-CommandCandidate -CommandName $CommandName -CommandInfo $command)) {
            continue
        }

        $commandPath = Get-CommandSourcePath -CommandInfo $command
        if ([string]::IsNullOrWhiteSpace($commandPath)) {
            return $true
        }

        $normalizedCommandPath = Get-NormalizedPathString -PathValue $commandPath
        if ([string]::IsNullOrWhiteSpace($normalizedInstallDir) -or [string]::IsNullOrWhiteSpace($normalizedCommandPath)) {
            return $true
        }

        if ($normalizedCommandPath -eq $normalizedInstallDir) {
            continue
        }

        if ($normalizedCommandPath.StartsWith("$normalizedInstallDir\", [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        return $true
    }

    return $false
}

function Get-PackageBaseFileName {
    param(
        [hashtable]$Package
    )

    $url = if ($Package.ContainsKey("DownloadUrl")) { [string]$Package.DownloadUrl } else { "" }
    if ([string]::IsNullOrWhiteSpace($url)) {
        return ""
    }

    $uri = [Uri]$url
    $fileName = if ($Package.ContainsKey("DownloadFileName")) { [string]$Package.DownloadFileName } else { "" }

    if ([string]::IsNullOrWhiteSpace($fileName)) {
        $fileName = [System.IO.Path]::GetFileName($uri.AbsolutePath)
    }

    if ($fileName -eq "download" -and $uri.Host -like "*sourceforge.net*") {
        $pathSegments = $uri.AbsolutePath.Split('/', [StringSplitOptions]::RemoveEmptyEntries)
        $fileName = $pathSegments[-2]
    }
    elseif ($uri.Host -eq "github.com" -and $uri.AbsolutePath -match '/([^/]+)/([^/]+)/archive/refs/tags/(.+)$') {
        $repoName = $matches[2]
        $tagName = [System.IO.Path]::GetFileNameWithoutExtension($matches[3])
        $extension = [System.IO.Path]::GetExtension($matches[3])
        $tagName = $tagName -replace '^v', ''
        $fileName = "$repoName-$tagName$extension"
    }

    return $fileName
}

function Resolve-PackageVersionFromZipEntry {
    param(
        [string]$ArchiveFile,
        [hashtable]$VersionSource
    )

    if ([string]::IsNullOrWhiteSpace($ArchiveFile) -or -not (Test-Path $ArchiveFile -PathType Leaf)) {
        return ""
    }

    $entryPath = if ($VersionSource.ContainsKey("Path")) { [string]$VersionSource.Path } else { "" }
    if ([string]::IsNullOrWhiteSpace($entryPath)) {
        return ""
    }

    $pattern = if ($VersionSource.ContainsKey("Pattern")) { [string]$VersionSource.Pattern } else { "" }

    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        $zip = [System.IO.Compression.ZipFile]::OpenRead($ArchiveFile)
        try {
            $normalizedEntryPath = $entryPath -replace '\\', '/'
            $entry = $zip.Entries | Where-Object {
                ($_.FullName -replace '\\', '/') -ieq $normalizedEntryPath
            } | Select-Object -First 1

            if (-not $entry) {
                return ""
            }

            $reader = [System.IO.StreamReader]::new($entry.Open())
            try {
                $content = $reader.ReadToEnd()
            } finally {
                $reader.Dispose()
            }

            if ([string]::IsNullOrWhiteSpace($content)) {
                return ""
            }

            if (-not [string]::IsNullOrWhiteSpace($pattern)) {
                $match = [regex]::Match($content, $pattern)
                if ($match.Success) {
                    return $match.Value
                }
                return ""
            }

            $firstLine = ($content -split "\r?\n") | Where-Object {
                -not [string]::IsNullOrWhiteSpace($_)
            } | Select-Object -First 1

            if ($null -eq $firstLine) {
                return ""
            }

            return $firstLine.Trim()
        } finally {
            $zip.Dispose()
        }
    } catch {
        Write-Host "Warning: Failed to read version from archive '$ArchiveFile': $($_.Exception.Message)" -ForegroundColor Yellow
        return ""
    }
}

function Resolve-PackageVersion {
    param(
        [hashtable]$PackageConfig,
        [string]$PackagesDir = "packages",
        [string]$ArchiveFile = ""
    )

    $fallbackVersion = if ($PackageConfig.ContainsKey("Version")) { [string]$PackageConfig.Version } else { "" }

    if (-not $PackageConfig.ContainsKey("VersionSource")) {
        return $fallbackVersion
    }

    $versionSource = $PackageConfig.VersionSource
    if (-not ($versionSource -is [hashtable])) {
        return $fallbackVersion
    }

    $sourceType = if ($versionSource.ContainsKey("Type")) { [string]$versionSource.Type } else { "" }
    if ($sourceType -ne "ZipEntry") {
        return $fallbackVersion
    }

    $candidateArchive = ""
    if (-not [string]::IsNullOrWhiteSpace($ArchiveFile) -and (Test-Path $ArchiveFile -PathType Leaf)) {
        $candidateArchive = $ArchiveFile
    } else {
        $archivePattern = if ($PackageConfig.ContainsKey("ArchivePattern")) { [string]$PackageConfig.ArchivePattern } else { "" }
        if (-not [string]::IsNullOrWhiteSpace($archivePattern) -and (Test-Path $PackagesDir)) {
            $candidate = Get-ChildItem -Path $PackagesDir -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match $archivePattern } |
                Sort-Object Name -Descending |
                Select-Object -First 1
            if ($candidate) {
                $candidateArchive = $candidate.FullName
            }
        }
    }

    $resolvedVersion = Resolve-PackageVersionFromZipEntry -ArchiveFile $candidateArchive -VersionSource $versionSource
    if (-not [string]::IsNullOrWhiteSpace($resolvedVersion)) {
        return $resolvedVersion
    }

    return $fallbackVersion
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
            elseif ($dirPath -like "*dotnet10sdk") {
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
            elseif ($dirPath -like "*vscode\bin") {
                if (Test-CommandExists "code") {
                    Write-Host "  Skipped (code.cmd already available): $dirPath"
                    $shouldSkip = $true
                }
            }

            if (-not $shouldSkip) {
                if ($currentPath) {
                    $currentPath = "$dirPath;$currentPath"
                } else {
                    $currentPath = $dirPath
                }
                Write-Host "  Added: $dirPath"
                $pathChanged = $true

                if ($dirPath -like "*dotnet10sdk") {
                    $currentDotnetHome = [Environment]::GetEnvironmentVariable("DOTNET_HOME", "User")
                    if (-not $currentDotnetHome) {
                        [Environment]::SetEnvironmentVariable("DOTNET_HOME", $dirPath, "User")
                        Write-Host "  Set DOTNET_HOME: $dirPath"
                    } else {
                        Write-Host "  DOTNET_HOME already set: $currentDotnetHome"
                    }

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
            # ディレクトリが存在しない場合は GetFullPath でノーマライズしてフォールバック
            $normalizedDir = if ($absolutePath) {
                $absolutePath.Path
            } else {
                [System.IO.Path]::GetFullPath($dir)
            }
            if ($entry -eq $normalizedDir) {
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

# 環境変数をレジストリからカレントプロセスに同期するヘルパー関数
function Sync-EnvironmentVariable {
    param(
        [string]$VariableName,
        [switch]$Silent = $false
    )

    try {
        if ($VariableName -eq "PATH") {
            $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
            $machinePath = [Environment]::GetEnvironmentVariable("PATH", "Machine")

            if (-not $userPath) { $userPath = "" }
            if (-not $machinePath) { $machinePath = "" }

            $combinedPath = if ($userPath -and $machinePath) {
                "$userPath;$machinePath"
            } elseif ($userPath) {
                $userPath
            } elseif ($machinePath) {
                $machinePath
            } else {
                ""
            }

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
                $env:PATH = $cleanPath

                if (-not $Silent) {
                    Write-Host "Synchronized PATH environment variable to current process"
                }
            }
        } else {
            $userValue = [Environment]::GetEnvironmentVariable($VariableName, "User")
            $machineValue = [Environment]::GetEnvironmentVariable($VariableName, "Machine")

            $finalValue = if ($userValue) { $userValue } else { $machineValue }

            if ($finalValue) {
                Set-Item -Path "Env:$VariableName" -Value $finalValue
                if (-not $Silent) {
                    Write-Host "Synchronized $VariableName environment variable to current process"
                }
            } else {
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

    # Data フォルダ内にファイルが存在するかチェック
    $filesInData = Get-ChildItem -Path $vscodeDataPath -Recurse -File -ErrorAction SilentlyContinue
    if (-not $filesInData -or $filesInData.Count -eq 0) {
        if (-not $Silent) {
            Write-Host "VS Code data folder is empty, skipping backup: $vscodeDataPath"
        }
        return $null
    }

    $tempBackupDir = Join-Path ([System.IO.Path]::GetTempPath()) "vscode_data_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"

    try {
        if (-not $Silent) {
            Write-Host "Backing up VS Code data folder to: $tempBackupDir"
        }

        Copy-Item -Path $vscodeDataPath -Destination $tempBackupDir -Recurse -Force

        if (-not $Silent) {
            Write-Host "VS Code data backup completed successfully"
        }

        return $tempBackupDir
    } catch {
        if (-not $Silent) {
            Write-Host "Warning: Failed to backup VS Code data: $($_.Exception.Message)" -ForegroundColor Yellow
        }

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

        if (Test-Path $vscodeDataPath) {
            Remove-Item -Path $vscodeDataPath -Recurse -Force
        }

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
        [switch]$PreserveVSCodeData = $false,
        [string]$PackagesConfigPath
    )

    if (-not $Silent) {
        Write-Host "Starting cleanup process..."
    }

    $vscodeDataBackup = $null
    if ($PreserveVSCodeData) {
        $vscodeDataBackup = Backup-VSCodeData -InstallDirectory $InstallDirectory -Silent:$Silent
        if (-not $vscodeDataBackup) {
            $PreserveVSCodeData = $false
        }
    }

    try {
        # PATH から削除
        if ($PackagesConfigPath -and (Test-Path $PackagesConfigPath)) {
            try {
                # PowerShell 5.0+ の Import-PowerShellDataFile を試行
                if (Get-Command Import-PowerShellDataFile -ErrorAction SilentlyContinue) {
                    $packagesConfig = Import-PowerShellDataFile $PackagesConfigPath
                } else {
                    # フォールバック: Invoke-Expression を使用
                    $packagesConfig = Invoke-Expression (Get-Content $PackagesConfigPath -Raw)
                }

                $pathDirs = @($InstallDirectory)

                foreach ($package in $packagesConfig.Packages) {
                    if ($package.PathsToAdd) {
                        foreach ($path in $package.PathsToAdd) {
                            $fullPath = Join-Path $InstallDirectory $path
                            $pathDirs += $fullPath
                        }
                    }
                }

                # 後方互換: dotnet8sdk が存在する場合は削除対象に追加
                $dotnet8SdkPath = Join-Path $InstallDirectory "dotnet8sdk"
                if (Test-Path $dotnet8SdkPath) {
                    $pathDirs += $dotnet8SdkPath
                }

                if ($pathDirs -and $pathDirs.Count -gt 0) {
                    Remove-FromUserPath -Directories $pathDirs -Silent:$Silent
                }
            } catch {
                if (-not $Silent) {
                    Write-Host "Warning: Failed to load package configuration: $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
        }

        # DOTNET_HOME 環境変数を削除 (dotnet10sdk および dotnet8sdk の後方互換)
        $currentDotnetHome = [Environment]::GetEnvironmentVariable("DOTNET_HOME", "User")
        $dotnet10SdkPath = Join-Path $InstallDirectory "dotnet10sdk"
        $dotnet8SdkPath = Join-Path $InstallDirectory "dotnet8sdk"

        if ($currentDotnetHome -and (($currentDotnetHome -eq $dotnet10SdkPath) -or ($currentDotnetHome -eq $dotnet8SdkPath))) {
            [Environment]::SetEnvironmentVariable("DOTNET_HOME", $null, "User")
            if (-not $Silent) {
                Write-Host "Removed DOTNET_HOME environment variable: $currentDotnetHome"
            }

            $currentTelemetryOptout = [Environment]::GetEnvironmentVariable("DOTNET_CLI_TELEMETRY_OPTOUT", "User")
            if ($currentTelemetryOptout -eq "1") {
                [Environment]::SetEnvironmentVariable("DOTNET_CLI_TELEMETRY_OPTOUT", $null, "User")
                if (-not $Silent) {
                    Write-Host "Removed DOTNET_CLI_TELEMETRY_OPTOUT environment variable"
                }
            }
        }

        # PLANTUML_HOME 環境変数を削除
        $currentPlantumlHome = [Environment]::GetEnvironmentVariable("PLANTUML_HOME", "User")
        if ($currentPlantumlHome -and ($currentPlantumlHome -eq $InstallDirectory)) {
            [Environment]::SetEnvironmentVariable("PLANTUML_HOME", $null, "User")
            if (-not $Silent) {
                Write-Host "Removed PLANTUML_HOME environment variable: $currentPlantumlHome"
            }
        }

        # vswhere インスタンスを削除
        if (-not $Silent) {
            Write-Host "Removing vswhere instance registration..."
        }
        Unregister-VswhereInstance

        # インストールディレクトリを削除
        if (Test-Path $InstallDirectory) {
            if (-not $Silent) {
                Write-Host "Removing installation directory: $InstallDirectory"
            }

            $removeResult = Remove-DirectoryTree -Path $InstallDirectory
            if ($removeResult.Success) {
                if (-not $Silent) {
                    Write-Host "Installation directory removed."
                }
            } else {
                # ファイルが使用中 (busy) かどうかをチェック
                $isBusy = [string]$removeResult.ErrorMessage -match "(使用中|being used|in use|access.*denied|cannot access|プロセスで使用|別のプロセス)"

                if ($isBusy) {
                    Write-Host ""
                    Write-Host "Error: Some files are currently in use and cannot be removed." -ForegroundColor Red
                    Write-Host "Please restart your PC and run this operation again." -ForegroundColor Yellow
                    Write-Host ""
                    throw "Installation directory cleanup failed: Files are in use"
                } else {
                    if (-not $Silent) {
                        Write-Host "Warning: Failed to remove installation directory: $($removeResult.ErrorMessage)" -ForegroundColor Yellow
                    }
                }
            }
        } else {
            if (-not $Silent) {
                Write-Host "Installation directory not found: $InstallDirectory"
            }
        }

        # VS Code data の復元
        if ($vscodeDataBackup) {
            if (-not $Silent) {
                Write-Host "Restoring VS Code data from backup..."
            }

            # bin ディレクトリを作成 (削除されている場合)
            if (!(Test-Path $InstallDirectory)) {
                New-Item -ItemType Directory -Path $InstallDirectory -Force | Out-Null
            }

            # vscode ディレクトリを作成
            $vscodeDir = Join-Path $InstallDirectory "vscode"
            if (!(Test-Path $vscodeDir)) {
                New-Item -ItemType Directory -Path $vscodeDir -Force | Out-Null
            }

            # data フォルダを復元
            $vscodeDataPath = Join-Path $vscodeDir "data"
            Copy-Item -Path $vscodeDataBackup -Destination $vscodeDataPath -Recurse -Force

            if (-not $Silent) {
                Write-Host "VS Code data restored successfully"
            }

            # バックアップを削除
            Remove-Item -Path $vscodeDataBackup -Recurse -Force -ErrorAction SilentlyContinue
        }

        return $true
    } catch {
        if (-not $Silent) {
            Write-Host "Warning: Some cleanup operations failed: $($_.Exception.Message)" -ForegroundColor Yellow
        }

        if ($vscodeDataBackup -and (Test-Path $vscodeDataBackup)) {
            Remove-Item -Path $vscodeDataBackup -Recurse -Force -ErrorAction SilentlyContinue
            if (-not $Silent) {
                Write-Host "Cleaned up VS Code data backup due to error"
            }
        }

        return $false
    }
}

# vswhere インスタンス ID (固定値、8文字ハッシュ形式)
$script:VSBT_INSTANCE_ID = "8f3e5d42"

# vswhere インスタンスを登録する関数
function Register-VswhereInstance {
    param(
        [string]$InstallPath,
        [string]$MsvcVersion,
        [string]$SdkVersion,
        [string[]]$Targets
    )

    try {
        $instancesPath = Join-Path $env:ProgramData "Microsoft\VisualStudio\Packages\_Instances"
        $instancePath = Join-Path $instancesPath $script:VSBT_INSTANCE_ID

        # インスタンスディレクトリを作成
        if (-not (Test-Path $instancePath)) {
            New-Item -ItemType Directory -Path $instancePath -Force -ErrorAction Stop | Out-Null
        }

        # 絶対パスを取得
        $absolutePath = (Resolve-Path $InstallPath -ErrorAction Stop).Path

        # ターゲットに基づいてパッケージ配列を構築
        $packagesArray = @(
            @{
                id = "Microsoft.VisualStudio.Component.VC.Tools.x86.x64"
                version = $MsvcVersion
            }
        )

        foreach ($target in $Targets) {
            $packagesArray += @{
                id = "Microsoft.VisualStudio.Component.VC.Tools.$target"
                version = $MsvcVersion
            }
        }

        # state.json を作成
        $stateJson = @{
            installationPath = $absolutePath
            installationVersion = $MsvcVersion
            installDate = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            displayName = "Visual Studio Build Tools (devbin-win)"
            description = "Portable MSVC and Windows SDK"
            channelId = "VisualStudio.17.Release"
            channelUri = "https://aka.ms/vs/17/release/channel"
            enginePath = $absolutePath
            installChannelUri = "https://aka.ms/vs/17/release/channel"
            releaseNotes = "https://docs.microsoft.com/en-us/visualstudio/releases/2022/release-notes"
            thirdPartyNotices = "https://go.microsoft.com/fwlink/?LinkId=660909"
            product = @{
                id = "Microsoft.VisualStudio.Product.BuildTools"
                version = $MsvcVersion
                localizedResources = @(
                    @{
                        language = "en-US"
                        title = "Visual Studio Build Tools (devbin-win)"
                        description = "Portable MSVC and Windows SDK"
                    }
                )
            }
            packages = $packagesArray
        } | ConvertTo-Json -Depth 10

        $stateJsonPath = Join-Path $instancePath "state.json"
        [System.IO.File]::WriteAllText($stateJsonPath, $stateJson, [System.Text.Encoding]::UTF8)

        Write-Host "Registered to vswhere: $instancePath" -ForegroundColor Green
    }
    catch {
        $isAccessDenied = $_.Exception.Message -match "(アクセスが拒否|Access.*denied|UnauthorizedAccess)"

        if ($isAccessDenied) {
            Write-Host "Skip to register vswhere instance: You are normal user."
        } else {
            Write-Host "Skip to register vswhere instance: $_"
        }

        Write-Host "Continuing without vswhere registration..."
    }
}

# vswhere インスタンスを削除する関数
function Unregister-VswhereInstance {
    try {
        $instancesPath = Join-Path $env:ProgramData "Microsoft\VisualStudio\Packages\_Instances"
        $instancePath = Join-Path $instancesPath $script:VSBT_INSTANCE_ID

        if (Test-Path $instancePath) {
            Remove-Item -Path $instancePath -Recurse -Force -ErrorAction Stop
            Write-Host "Unregistered from vswhere: $instancePath" -ForegroundColor Green
        } else {
            Write-Host "vswhere instance not found (already unregistered or never registered)" -ForegroundColor Cyan
        }
    }
    catch {
        $isAccessDenied = $_.Exception.Message -match "(アクセスが拒否|Access.*denied|UnauthorizedAccess)"

        if ($isAccessDenied) {
            Write-Warning "Failed to unregister vswhere instance: Access denied"
            Write-Host "Note: vswhere unregistration requires administrator privileges." -ForegroundColor Yellow
        } else {
            Write-Warning "Failed to unregister vswhere instance: $_"
        }

        Write-Host "Continuing anyway..." -ForegroundColor Yellow
    }
}

function Get-DevbinProductRoot {
    param(
        [string]$InstallDir
    )

    if ([string]::IsNullOrWhiteSpace($InstallDir)) {
        throw "InstallDir is required"
    }

    $fullPath = $null
    try {
        $fullPath = [System.IO.Path]::GetFullPath($InstallDir)
    } catch {
        $fullPath = $InstallDir.Trim()
    }

    $leaf = Split-Path -Path $fullPath -Leaf
    $parent = Split-Path -Path $fullPath -Parent
    if ($parent -and $leaf -eq "bin") {
        $parentLeaf = Split-Path -Path $parent -Leaf
        if ($parentLeaf -eq "devbin-win") {
            $normalizedParent = Get-NormalizedPathString -PathValue $parent
            if ($normalizedParent) {
                return $normalizedParent
            }
            return $parent.TrimEnd('\')
        }
    }

    $normalized = Get-NormalizedPathString -PathValue $fullPath
    if ($normalized) {
        return $normalized
    }
    return $fullPath.TrimEnd('\')
}

# 完全アンインストールが許可される唯一の対象ルートを返す
function Get-DevbinExpectedProductRoot {
    $expected = Join-Path $env:ProgramData "$env:USERNAME\devbin-win"
    $normalized = Get-NormalizedPathString -PathValue $expected
    if ($normalized) {
        return $normalized
    }
    return $expected.TrimEnd('\')
}

# 対象ルートが完全アンインストールの許可範囲かどうかを判定する
function Test-DevbinProductRootAllowed {
    param(
        [string]$ProductRoot
    )

    $normalized = Get-NormalizedPathString -PathValue $ProductRoot
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return $false
    }

    return [string]::Equals($normalized, (Get-DevbinExpectedProductRoot), [StringComparison]::OrdinalIgnoreCase)
}

function Test-PathUnderRoot {
    param(
        [string]$PathValue,
        [string]$Root
    )

    if ([string]::IsNullOrWhiteSpace($PathValue) -or [string]::IsNullOrWhiteSpace($Root)) {
        return $false
    }

    $normalizedRoot = Get-NormalizedPathString -PathValue $Root
    if ([string]::IsNullOrWhiteSpace($normalizedRoot)) {
        $normalizedRoot = $Root.Trim().TrimEnd('\')
    }

    $candidates = New-Object System.Collections.Generic.List[string]
    $raw = $PathValue.Trim()
    if ($raw.StartsWith('"') -and $raw.EndsWith('"') -and $raw.Length -ge 2) {
        $raw = $raw.Substring(1, $raw.Length - 2)
    }
    $candidates.Add($raw) | Out-Null
    try {
        $expanded = [Environment]::ExpandEnvironmentVariables($raw)
        if (-not [string]::IsNullOrWhiteSpace($expanded)) {
            $candidates.Add($expanded) | Out-Null
        }
    } catch {
    }

    if ($PathValue -match '^\s*"([^"]+)"') {
        $candidates.Add($Matches[1]) | Out-Null
    } elseif ($raw -match '^([^\s]+)') {
        $candidates.Add($Matches[1]) | Out-Null
    }

    foreach ($candidate in @($candidates | Select-Object -Unique)) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }

        $normalized = Get-NormalizedPathString -PathValue $candidate
        if ([string]::IsNullOrWhiteSpace($normalized)) {
            continue
        }

        if ([string]::Equals($normalized, $normalizedRoot, [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }

        $rootPrefix = $normalizedRoot.TrimEnd('\') + '\'
        if ($normalized.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    $searchText = $PathValue
    try {
        $searchText = [Environment]::ExpandEnvironmentVariables($PathValue)
    } catch {
        $searchText = $PathValue
    }

    $rootToken = $normalizedRoot.TrimEnd('\')
    $index = $searchText.IndexOf($rootToken, [StringComparison]::OrdinalIgnoreCase)
    if ($index -lt 0) {
        return $false
    }

    $after = $index + $rootToken.Length
    if ($after -ge $searchText.Length) {
        return $true
    }

    $nextChar = $searchText[$after]
    return ($nextChar -eq '\' -or $nextChar -eq '/' -or $nextChar -eq '"' -or $nextChar -eq "'" -or [char]::IsWhiteSpace($nextChar))
}

# ";" 区切りの値を、対象ルート配下のエントリとそれ以外に分ける
function Split-RootEntriesFromValue {
    param(
        [string]$Value,
        [string]$Root
    )

    $kept = @()
    $removed = @()

    if (-not [string]::IsNullOrWhiteSpace($Value)) {
        foreach ($entry in ($Value -split ';')) {
            if ([string]::IsNullOrWhiteSpace($entry)) {
                continue
            }

            $trimmed = $entry.Trim()
            if (Test-PathUnderRoot -PathValue $trimmed -Root $Root) {
                $removed += $trimmed
            } else {
                $kept += $trimmed
            }
        }
    }

    return [PSCustomObject]@{
        Kept    = @($kept)
        Removed = @($removed)
    }
}

function Remove-UserEnvVarsPointingToRoot {
    param(
        [string]$Root
    )

    $changed = @()
    try {
        $userVars = [Environment]::GetEnvironmentVariables("User")
        foreach ($key in @($userVars.Keys)) {
            if ([string]::Equals([string]$key, "PATH", [StringComparison]::OrdinalIgnoreCase)) {
                continue
            }

            $value = [string]$userVars[$key]
            $split = Split-RootEntriesFromValue -Value $value -Root $Root
            if ($split.Removed.Count -eq 0) {
                continue
            }

            # 対象ルート配下のエントリだけを取り除き、他のエントリが残る場合は変数自体は残す
            if ($split.Kept.Count -eq 0) {
                [Environment]::SetEnvironmentVariable([string]$key, $null, "User")
                Write-Host "  Removed environment variable: $key"
            } else {
                [Environment]::SetEnvironmentVariable([string]$key, ($split.Kept -join ';'), "User")
                Write-Host "  Updated environment variable: $key"
                foreach ($removedEntry in $split.Removed) {
                    Write-Host "    Removed entry: $removedEntry"
                }
            }

            $changed += [string]$key
        }
    } catch {
        Write-Host "Warning: Failed to scan user environment variables: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    return @($changed)
}

function Remove-UserPathEntriesPointingToRoot {
    param(
        [string]$Root
    )

    try {
        $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
        if ([string]::IsNullOrWhiteSpace($currentPath)) {
            return
        }

        $split = Split-RootEntriesFromValue -Value $currentPath -Root $Root
        if ($split.Removed.Count -eq 0) {
            return
        }

        [Environment]::SetEnvironmentVariable("PATH", ($split.Kept -join ';'), "User")
        foreach ($removedEntry in $split.Removed) {
            Write-Host "  Removed PATH entry: $removedEntry"
        }
    } catch {
        Write-Host "Warning: Failed to clean user PATH: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

function Remove-FontRegistrationsPointingToRoot {
    param(
        [string]$Root
    )

    $regPath = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
    if (-not (Test-Path $regPath)) {
        return
    }

    try {
        $fontProps = Get-ItemProperty -Path $regPath -ErrorAction Stop
        $skipNames = @("PSPath", "PSParentPath", "PSChildName", "PSDrive", "PSProvider")
        foreach ($prop in $fontProps.PSObject.Properties) {
            if ($skipNames -contains $prop.Name) {
                continue
            }

            $value = [string]$prop.Value
            if (Test-PathUnderRoot -PathValue $value -Root $Root) {
                Remove-ItemProperty -Path $regPath -Name $prop.Name -ErrorAction SilentlyContinue
                Write-Host "  Removed font registration: $($prop.Name)"
            }
        }
    } catch {
        Write-Host "Warning: Failed to scan font registrations: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# コメント (// と /* */) を含む JSON を読み込む
function ConvertFrom-JsonWithComments {
    param(
        [string]$JsonText
    )

    if ([string]::IsNullOrWhiteSpace($JsonText)) {
        return $null
    }

    # Windows Terminal の settings.json は既定でコメント付きのため、事前に取り除く
    $builder = New-Object System.Text.StringBuilder
    $inString = $false
    $escaped = $false
    $index = 0
    $length = $JsonText.Length

    while ($index -lt $length) {
        $ch = $JsonText[$index]

        if ($inString) {
            [void]$builder.Append($ch)
            if ($escaped) {
                $escaped = $false
            } elseif ($ch -eq [char]92) {
                $escaped = $true
            } elseif ($ch -eq '"') {
                $inString = $false
            }
            $index++
            continue
        }

        if ($ch -eq '"') {
            $inString = $true
            [void]$builder.Append($ch)
            $index++
            continue
        }

        if ($ch -eq '/' -and ($index + 1) -lt $length) {
            $next = $JsonText[$index + 1]
            if ($next -eq '/') {
                while ($index -lt $length -and $JsonText[$index] -ne "`n") {
                    $index++
                }
                continue
            }
            if ($next -eq '*') {
                $index += 2
                while (($index + 1) -lt $length -and -not ($JsonText[$index] -eq '*' -and $JsonText[$index + 1] -eq '/')) {
                    $index++
                }
                $index += 2
                continue
            }
        }

        [void]$builder.Append($ch)
        $index++
    }

    return ($builder.ToString() | ConvertFrom-Json)
}

function Get-WindowsTerminalSettingsPaths {
    return @(
        (Join-Path $env:LOCALAPPDATA "Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"),
        (Join-Path $env:LOCALAPPDATA "Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json"),
        (Join-Path $env:APPDATA "Microsoft\Windows Terminal\settings.json")
    )
}

function Test-DevbinWindowsTerminalProfileGuid {
    param([string]$GuidValue)

    if ([string]::IsNullOrWhiteSpace($GuidValue)) {
        return $false
    }

    $normalized = $GuidValue.Trim().Trim("{}")
    $known = @(
        "b2e42366-5d93-4fb7-be22-177d0a5850d1",
        "d48c104b-44a7-4180-be8d-b542db93a384"
    )
    foreach ($guid in $known) {
        if ([string]::Equals($normalized, $guid, [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

function Remove-WindowsTerminalProfilesForRoot {
    param(
        [string]$Root
    )

    $settingsPaths = @(Get-WindowsTerminalSettingsPaths | Where-Object { $_ -and (Test-Path $_) })
    if ($settingsPaths.Count -eq 0) {
        Write-Host "  Windows Terminal settings.json not found, skipping profile cleanup"
        return
    }

    foreach ($settingsPath in $settingsPaths) {
        $backupPath = $null
        try {
            $jsonContent = Get-Content -Path $settingsPath -Raw -Encoding UTF8
            $settings = ConvertFrom-JsonWithComments -JsonText $jsonContent
            if (-not $settings -or -not $settings.profiles -or -not $settings.profiles.list) {
                continue
            }

            $originalProfiles = @($settings.profiles.list)
            $removedNames = @()
            $removedGuids = @()
            $kept = @()
            # $profile は PowerShell の自動変数のため、ループ変数には使わない
            foreach ($wtProfile in $originalProfiles) {
                $guid = if ($wtProfile.PSObject.Properties.Match("guid").Count -gt 0) { [string]$wtProfile.guid } else { "" }
                $commandline = if ($wtProfile.PSObject.Properties.Match("commandline").Count -gt 0) { [string]$wtProfile.commandline } else { "" }
                $icon = if ($wtProfile.PSObject.Properties.Match("icon").Count -gt 0) { [string]$wtProfile.icon } else { "" }
                $startingDirectory = if ($wtProfile.PSObject.Properties.Match("startingDirectory").Count -gt 0) { [string]$wtProfile.startingDirectory } else { "" }

                $matchesRoot = (Test-PathUnderRoot -PathValue $commandline -Root $Root) -or
                    (Test-PathUnderRoot -PathValue $icon -Root $Root) -or
                    (Test-PathUnderRoot -PathValue $startingDirectory -Root $Root)
                $matchesKnownGuid = Test-DevbinWindowsTerminalProfileGuid -GuidValue $guid

                if ($matchesRoot -or $matchesKnownGuid) {
                    $profileName = if ($wtProfile.PSObject.Properties.Match("name").Count -gt 0) { [string]$wtProfile.name } else { $guid }
                    $removedNames += $profileName
                    if ($guid) {
                        $removedGuids += $guid
                    }
                } else {
                    $kept += $wtProfile
                }
            }

            if ($removedNames.Count -eq 0) {
                continue
            }

            $settings.profiles.list = [object[]]$kept
            if ($settings.PSObject.Properties.Match("defaultProfile").Count -gt 0) {
                $defaultProfile = [string]$settings.defaultProfile
                $defaultRemoved = $false
                foreach ($removedGuid in $removedGuids) {
                    if ([string]::Equals($defaultProfile, $removedGuid, [StringComparison]::OrdinalIgnoreCase)) {
                        $defaultRemoved = $true
                        break
                    }
                }
                if ($defaultRemoved) {
                    if ($kept.Count -gt 0 -and $kept[0].PSObject.Properties.Match("guid").Count -gt 0) {
                        $settings.defaultProfile = [string]$kept[0].guid
                    }
                }
            }

            # 書き込み直前にバックアップを作成する (無変更時や解析失敗時に残さない)
            $backupPath = $settingsPath + "." + (Get-Date -Format "yyMMddHHmmss")
            Copy-Item -Path $settingsPath -Destination $backupPath -Force

            $jsonOutput = $settings | ConvertTo-Json -Depth 20
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText($settingsPath, $jsonOutput, $utf8NoBom)
            foreach ($name in $removedNames) {
                Write-Host "  Removed Windows Terminal profile: $name"
            }
            Write-Host "  Backup: $backupPath"
        } catch {
            Write-Host "Warning: Failed to clean Windows Terminal profiles ($settingsPath): $($_.Exception.Message)" -ForegroundColor Yellow
            if ($backupPath -and (Test-Path $backupPath)) {
                Write-Host "  To restore: Copy-Item -Path '$backupPath' -Destination '$settingsPath' -Force" -ForegroundColor Yellow
            }
        }
    }
}

function Unregister-VswhereInstanceIfPointingToRoot {
    param(
        [string]$Root
    )

    try {
        $instancesPath = Join-Path $env:ProgramData "Microsoft\VisualStudio\Packages\_Instances"
        $instancePath = Join-Path $instancesPath $script:VSBT_INSTANCE_ID
        if (-not (Test-Path $instancePath)) {
            Write-Host "  vswhere instance not found (already unregistered or never registered)"
            return
        }

        $stateJsonPath = Join-Path $instancePath "state.json"
        $shouldRemove = $false
        if (-not (Test-Path $stateJsonPath)) {
            $shouldRemove = $true
        } else {
            try {
                $state = Get-Content -Path $stateJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
                $installationPath = if ($state.PSObject.Properties.Match("installationPath").Count -gt 0) {
                    [string]$state.installationPath
                } else {
                    ""
                }
                if ([string]::IsNullOrWhiteSpace($installationPath) -or (Test-PathUnderRoot -PathValue $installationPath -Root $Root)) {
                    $shouldRemove = $true
                } else {
                    Write-Host "  vswhere instance installationPath is outside product root, leaving it: $installationPath"
                }
            } catch {
                $shouldRemove = $true
            }
        }

        if ($shouldRemove) {
            Remove-Item -Path $instancePath -Recurse -Force -ErrorAction Stop
            Write-Host "  Unregistered vswhere instance: $instancePath"
        }
    } catch {
        $isAccessDenied = $_.Exception.Message -match "(アクセスが拒否|Access.*denied|UnauthorizedAccess)"
        if ($isAccessDenied) {
            Write-Host "Warning: Failed to unregister vswhere instance: Access denied" -ForegroundColor Yellow
        } else {
            Write-Host "Warning: Failed to unregister vswhere instance: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
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

function Invoke-ProductUninstall {
    param(
        [string]$InstallDir,
        [switch]$Force
    )

    $productRoot = Get-DevbinProductRoot -InstallDir $InstallDir

    Write-Host "=== Development Tools Complete Uninstallation ==="
    Write-Host ""
    Write-Host "Product root: $productRoot"
    Write-Host ""

    # 標準のインストール先以外を対象にした削除は行わない (リポジトリや配布フォルダの誤削除を防ぐ)
    if (-not (Test-DevbinProductRootAllowed -ProductRoot $productRoot)) {
        Write-Host "Error: Complete uninstallation is limited to the standard install location." -ForegroundColor Red
        Write-Host "  Expected: $(Get-DevbinExpectedProductRoot)"
        Write-Host "  Actual:   $productRoot"
        Write-Host "Nothing was removed. Remove other locations manually." -ForegroundColor Yellow
        return [PSCustomObject]@{ Status = "Refused" }
    }

    Write-Host "This removes traces of this folder regardless of install state:"
    Write-Host "  - The product folder and all contents, including VS Code data"
    Write-Host "  - User PATH entries pointing at this folder"
    Write-Host "  - User environment variables pointing at this folder"
    Write-Host "  - Font registrations pointing at this folder"
    Write-Host "  - Windows Terminal profiles pointing at this folder"
    Write-Host "  - vswhere registration if it points at this folder"
    Write-Host ""
    Write-Host "HOME / XDG are not removed."
    Write-Host ""

    if (-not $Force) {
        $confirmation = Read-Host "Continue? [y/N]"
        if ($confirmation -notmatch '^[yY]$') {
            Write-Host "Cancelled."
            return [PSCustomObject]@{ Status = "Cancelled" }
        }
        Write-Host ""
    }

    $removedEnvNames = @("PATH")
    Write-Host "Removing references that point at the product folder..."
    $envRemoved = @(Remove-UserEnvVarsPointingToRoot -Root $productRoot)
    if ($envRemoved.Count -gt 0) {
        $removedEnvNames += $envRemoved
    }
    Remove-UserPathEntriesPointingToRoot -Root $productRoot
    Remove-FontRegistrationsPointingToRoot -Root $productRoot
    Remove-WindowsTerminalProfilesForRoot -Root $productRoot
    Unregister-VswhereInstanceIfPointingToRoot -Root $productRoot

    $dirFailed = $false
    if (Test-Path -LiteralPath $productRoot) {
        Write-Host "Removing product folder: $productRoot"
        $removeResult = Remove-DirectoryTree -Path $productRoot
        if ($removeResult.Success) {
            Write-Host "Product folder removed."
        } else {
            $dirFailed = $true
            $isBusy = [string]$removeResult.ErrorMessage -match "(使用中|being used|in use|access.*denied|cannot access|プロセスで使用|別のプロセス)"
            if ($isBusy) {
                Write-Host ""
                Write-Host "Error: Some files are currently in use and cannot be removed." -ForegroundColor Red
                Write-Host "Environment references were cleaned. Restart the PC and run this again to delete the folder." -ForegroundColor Yellow
                Write-Host ""
            } else {
                Write-Host "Warning: Failed to remove product folder: $($removeResult.ErrorMessage)" -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host "Product folder not found: $productRoot"
    }

    Sync-EnvironmentVariables -VariableNames ($removedEnvNames | Select-Object -Unique) | Out-Null

    if ($dirFailed) {
        return [PSCustomObject]@{ Status = "Failed" }
    }

    Write-Host ""
    Write-Host "Complete uninstallation finished." -ForegroundColor Green
    Write-Host "Note: To apply environment changes, restart your terminal."
    return [PSCustomObject]@{ Status = "Success" }
}

# 単一ディレクトリをユーザー PATH に追加するヘルパー
function Add-SinglePathDir {
    param([string]$Directory)

    if (-not (Test-Path $Directory)) {
        Write-Host "  Directory not found: $Directory" -ForegroundColor Yellow
        return
    }

    $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if (-not $currentPath) { $currentPath = "" }

    $entries = $currentPath -split ';' | Where-Object { $_.Trim() -ne "" }
    if ($entries -contains $Directory) {
        Write-Host "  Already in PATH: $Directory"
        return
    }

    $newPath = if ($currentPath) { "$Directory;$currentPath" } else { $Directory }
    [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
    Write-Host "  Added: $Directory"
}

# 単一ディレクトリをユーザー PATH から削除するヘルパー
function Remove-SinglePathDir {
    param([string]$Directory)

    $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if (-not $currentPath) { return }

    $normalizedDir = if (Test-Path $Directory) {
        (Resolve-Path $Directory).Path
    } else {
        [System.IO.Path]::GetFullPath($Directory)
    }

    $entries = $currentPath -split ';' | Where-Object { $_.Trim() -ne "" }
    $newEntries = $entries | Where-Object { $_ -ne $normalizedDir }

    if ($newEntries.Count -lt $entries.Count) {
        $newPath = $newEntries -join ';'
        [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
        Write-Host "  Removed: $Directory"
    }
}

# packages.psd1 の PathPosition を解釈する
function Get-PackagePathPosition {
    param(
        [hashtable]$PackageConfig
    )

    $position = if ($PackageConfig.ContainsKey("PathPosition")) { [string]$PackageConfig.PathPosition } else { "" }
    if ([string]::IsNullOrWhiteSpace($position)) {
        return "Prepend"
    }

    if ($position -in @("Prepend", "Append")) {
        return $position
    }

    Write-Warning "Unknown PathPosition '$position' for package '$($PackageConfig.ShortName)'. Falling back to Prepend."
    return "Prepend"
}

# devbin-win 管理下の PATH を宣言順で再構成した文字列を返す (環境変数は変更しない)
function Get-ManagedUserPathValue {
    param(
        [string]$CurrentPath = "",
        [string]$InstallDir,
        [array]$Packages,
        [string[]]$InstalledShortNames = @(),
        [switch]$IncludeBaseDir
    )

    $currentPath = if ($null -eq $CurrentPath) { "" } else { $CurrentPath }

    $managedEntries = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $normalizedBaseDir = Get-NormalizedPathString -PathValue $InstallDir
    if (-not [string]::IsNullOrWhiteSpace($normalizedBaseDir)) {
        $null = $managedEntries.Add($normalizedBaseDir)
    }

    foreach ($package in $Packages) {
        $pathDirs = if ($package.ContainsKey("PathDirs")) { @($package.PathDirs) } else { @() }
        foreach ($relativeDir in $pathDirs) {
            $fullPath = Join-Path $InstallDir $relativeDir
            $normalizedPath = Get-NormalizedPathString -PathValue $fullPath
            if (-not [string]::IsNullOrWhiteSpace($normalizedPath)) {
                $null = $managedEntries.Add($normalizedPath)
            }
        }
    }

    $installedLookup = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($shortName in $InstalledShortNames) {
        if (-not [string]::IsNullOrWhiteSpace($shortName)) {
            $null = $installedLookup.Add($shortName)
        }
    }

    $externalEntries = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in ($currentPath -split ';')) {
        $trimmedEntry = $entry.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmedEntry)) {
            continue
        }

        $normalizedEntry = Get-NormalizedPathString -PathValue $trimmedEntry
        if (-not [string]::IsNullOrWhiteSpace($normalizedEntry) -and $managedEntries.Contains($normalizedEntry)) {
            continue
        }

        $externalEntries.Add($trimmedEntry)
    }

    $prependEntries = [System.Collections.Generic.List[string]]::new()
    $appendEntries = [System.Collections.Generic.List[string]]::new()

    if ($IncludeBaseDir -and (Test-Path $InstallDir)) {
        $prependEntries.Add((Resolve-Path $InstallDir -ErrorAction Stop).Path)
    }

    foreach ($package in $Packages) {
        $shortName = if ($package.ContainsKey("ShortName")) { [string]$package.ShortName } else { "" }
        if ([string]::IsNullOrWhiteSpace($shortName) -or -not $installedLookup.Contains($shortName)) {
            continue
        }

        $pathDirs = if ($package.ContainsKey("PathDirs")) { @($package.PathDirs) } else { @() }
        if ($pathDirs.Count -eq 0) {
            continue
        }

        $skipCommand = if ($package.ContainsKey("SkipIfCommand")) { [string]$package.SkipIfCommand } else { "" }
        if (-not [string]::IsNullOrWhiteSpace($skipCommand) -and (Test-ExternalCommandExists -CommandName $skipCommand -InstallDir $InstallDir)) {
            Write-Host "  Skipped (external '$skipCommand' already available): $shortName"
            continue
        }

        $pathPosition = Get-PackagePathPosition -PackageConfig $package
        foreach ($relativeDir in $pathDirs) {
            $fullPath = Join-Path $InstallDir $relativeDir
            if (-not (Test-Path $fullPath)) {
                Write-Host "  Directory not found: $relativeDir"
                continue
            }

            $resolvedPath = (Resolve-Path $fullPath -ErrorAction Stop).Path
            if ($pathPosition -eq "Append") {
                $appendEntries.Add($resolvedPath)
            } else {
                $prependEntries.Add($resolvedPath)
            }
        }
    }

    $finalEntries = [System.Collections.Generic.List[string]]::new()
    $seenEntries = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($entry in $prependEntries) {
        $trimmedEntry = $entry.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmedEntry)) {
            continue
        }

        $normalizedEntry = Get-NormalizedPathString -PathValue $trimmedEntry
        if ([string]::IsNullOrWhiteSpace($normalizedEntry)) {
            $normalizedEntry = $trimmedEntry
        }

        if ($seenEntries.Add($normalizedEntry)) {
            $finalEntries.Add($trimmedEntry)
        }
    }

    foreach ($entry in $externalEntries) {
        $trimmedEntry = $entry.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmedEntry)) {
            continue
        }

        $normalizedEntry = Get-NormalizedPathString -PathValue $trimmedEntry
        if ([string]::IsNullOrWhiteSpace($normalizedEntry)) {
            $normalizedEntry = $trimmedEntry
        }

        if ($seenEntries.Add($normalizedEntry)) {
            $finalEntries.Add($trimmedEntry)
        }
    }

    foreach ($entry in $appendEntries) {
        $trimmedEntry = $entry.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmedEntry)) {
            continue
        }

        $normalizedEntry = Get-NormalizedPathString -PathValue $trimmedEntry
        if ([string]::IsNullOrWhiteSpace($normalizedEntry)) {
            $normalizedEntry = $trimmedEntry
        }

        if ($seenEntries.Add($normalizedEntry)) {
            $finalEntries.Add($trimmedEntry)
        }
    }

    return ($finalEntries -join ';')
}

# devbin-win 管理下の PATH を宣言順で再構成し、ユーザー環境変数へ反映する
function Sync-ManagedUserPath {
    param(
        [string]$InstallDir,
        [array]$Packages,
        [string[]]$InstalledShortNames = @(),
        [switch]$IncludeBaseDir
    )

    $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if (-not $currentPath) {
        $currentPath = ""
    }

    $newPath = Get-ManagedUserPathValue `
        -CurrentPath $currentPath `
        -InstallDir $InstallDir `
        -Packages $Packages `
        -InstalledShortNames $InstalledShortNames `
        -IncludeBaseDir:$IncludeBaseDir

    if ($newPath -ne $currentPath) {
        [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
        Write-Host "User PATH updated successfully."
        Write-Host "Note: Restart your terminal for PATH changes to take effect."
    } else {
        Write-Host "No PATH changes needed."
    }
}

# スリープ/スクリーンセーバーを抑止する Busy シグナルを開始する
function Start-BusySignal {
    if (-not ("Devbin.PowerNative" -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

namespace Devbin
{
    public static class PowerNative
    {
        [DllImport("kernel32.dll")]
        public static extern uint SetThreadExecutionState(uint esFlags);
    }
}
"@
    }

    # ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED
    $busySignalFlags = [Convert]::ToUInt32("80000003", 16)

    [Devbin.PowerNative]::SetThreadExecutionState($busySignalFlags) | Out-Null

    $script:BusySignalTimer = New-Object System.Timers.Timer
    $script:BusySignalTimer.Interval = 10000
    $script:BusySignalTimer.AutoReset = $true

    # Register-ObjectEvent の -Action はモジュールの $script: スコープを参照できないため、
    # -MessageData 経由でフラグ値を渡す
    $script:BusySignalEventJob = Register-ObjectEvent `
        -InputObject $script:BusySignalTimer `
        -EventName Elapsed `
        -MessageData $busySignalFlags `
        -Action { [Devbin.PowerNative]::SetThreadExecutionState($Event.MessageData) | Out-Null }

    $script:BusySignalTimer.Start()
}

# Busy シグナルを停止し、スリープ抑止状態を解除する
function Stop-BusySignal {
    if ($null -ne $script:BusySignalTimer) {
        $script:BusySignalTimer.Stop()
        $script:BusySignalTimer.Dispose()
        $script:BusySignalTimer = $null
    }

    if ($null -ne $script:BusySignalEventJob) {
        Unregister-Event -SourceIdentifier $script:BusySignalEventJob.Name -ErrorAction SilentlyContinue
        $script:BusySignalEventJob = $null
    }

    if ("Devbin.PowerNative" -as [type]) {
        [Devbin.PowerNative]::SetThreadExecutionState([Convert]::ToUInt32("80000000", 16)) | Out-Null
    }
}

Export-ModuleMember -Function @(
    'Test-CommandExists',
    'Sync-ManagedUserPath',
    'Get-ManagedUserPathValue',
    'Get-PackageBaseFileName',
    'Resolve-PackageVersion',
    'Add-ToUserPath',
    'Remove-FromUserPath',
    'Add-SinglePathDir',
    'Remove-SinglePathDir',
    'Convert-ToLongPath',
    'New-LongPathDirectory',
    'Copy-LongPathFile',
    'Sync-EnvironmentVariable',
    'Sync-EnvironmentVariables',
    'Backup-VSCodeData',
    'Restore-VSCodeData',
    'Invoke-CompleteUninstall',
    'Get-DevbinProductRoot',
    'Get-DevbinExpectedProductRoot',
    'Test-DevbinProductRootAllowed',
    'Test-PathUnderRoot',
    'Split-RootEntriesFromValue',
    'Remove-DirectoryTree',
    'ConvertFrom-JsonWithComments',
    'Invoke-ProductUninstall',
    'Register-VswhereInstance',
    'Unregister-VswhereInstance',
    'Start-BusySignal',
    'Stop-BusySignal'
)
