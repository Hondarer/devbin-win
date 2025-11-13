# Setup-Common.psm1
# 共通関数モジュール

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
                    $null = Start-Process -FilePath $commandPath -ArgumentList "--version" -NoNewWindow -Wait -PassThru -RedirectStandardError "stderr_temp.txt" -RedirectStandardOutput "stdout_temp.txt"

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
                if ($currentPath) {
                    $currentPath = "$dirPath;$currentPath"
                } else {
                    $currentPath = $dirPath
                }
                Write-Host "  Added: $dirPath"
                $pathChanged = $true

                if ($dirPath -like "*dotnet8sdk") {
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

                if ($pathDirs -and $pathDirs.Count -gt 0) {
                    Remove-FromUserPath -Directories $pathDirs -Silent:$Silent
                }
            } catch {
                if (-not $Silent) {
                    Write-Host "Warning: Failed to load package configuration: $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
        }

        # DOTNET_HOME 環境変数を削除
        $currentDotnetHome = [Environment]::GetEnvironmentVariable("DOTNET_HOME", "User")
        $dotnetSdkPath = Join-Path $InstallDirectory "dotnet8sdk"
        if ($currentDotnetHome -and ($currentDotnetHome -eq $dotnetSdkPath)) {
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

        # インストールディレクトリを削除
        if (Test-Path $InstallDirectory) {
            if (-not $Silent) {
                Write-Host "Removing installation directory: $InstallDirectory"
            }

            try {
                Remove-Item -Path $InstallDirectory -Recurse -Force -ErrorAction Stop
                if (-not $Silent) {
                    Write-Host "Installation directory removed."
                }
            } catch {
                if (-not $Silent) {
                    Write-Host "Warning: Failed to remove installation directory: $($_.Exception.Message)" -ForegroundColor Yellow
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

Export-ModuleMember -Function @(
    'Test-CommandExists',
    'Add-ToUserPath',
    'Remove-FromUserPath',
    'Convert-ToLongPath',
    'New-LongPathDirectory',
    'Copy-LongPathFile',
    'Sync-EnvironmentVariable',
    'Sync-EnvironmentVariables',
    'Backup-VSCodeData',
    'Restore-VSCodeData',
    'Invoke-CompleteUninstall'
)
