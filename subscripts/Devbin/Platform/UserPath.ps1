# UserPath.ps1
# ユーザー PATH 環境変数へのディレクトリ追加・削除、および管理下パスの再構成

# ユーザー PATH 環境変数に複数のディレクトリを追加
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
    }
}

# ユーザー PATH 環境変数から指定されたディレクトリ群を除去
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
            # ディレクトリが存在しない場合は GetFullPath による正規化パスでフォールバック
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

# 単一ディレクトリをユーザー PATH 環境変数に追加するヘルパー関数
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

# 単一ディレクトリをユーザー PATH 環境変数から除去するヘルパー関数
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

# パッケージ定義 (packages.psd1) の PathPosition プロパティを解析 (既定値: Prepend)
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

# 管理下パッケージの定義順序に基づいて再構成したユーザー PATH 文字列を生成 (環境変数は未変更)
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
        # 外部に同じコマンドがある場合は PATH へ追加しません (通常の判定結果のため出力しません)。
        if (-not [string]::IsNullOrWhiteSpace($skipCommand) -and (Test-ExternalCommandExists -CommandName $skipCommand -InstallDir $InstallDir)) {
            continue
        }

        $pathPosition = Get-PackagePathPosition -PackageConfig $package
        foreach ($relativeDir in $pathDirs) {
            $fullPath = Join-Path $InstallDir $relativeDir
            if (-not (Test-Path $fullPath)) {
                Write-Host "    Directory not found: $relativeDir"
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

# 管理下パッケージの定義順序に基づいてユーザー PATH を再構成し、ユーザー環境変数へ反映
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
        Write-Host "    User PATH updated successfully."
        Write-Host "    Note: Restart your terminal for PATH changes to take effect."
    }
}
