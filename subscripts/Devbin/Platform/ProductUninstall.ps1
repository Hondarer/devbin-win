# ProductUninstall.ps1
# 再インストール前のクリーンアップと、製品の完全アンインストール

# Y/N/Esc を 1 キーで決定する。Enter は既定の可否に従う。
function Read-ConfirmationKey {
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,

        [switch]$DefaultYes
    )

    Write-Host $Prompt -NoNewline
    while ($true) {
        $key = [Console]::ReadKey($true)
        if ($key.Key -eq "Escape" -or $key.KeyChar -eq 'n' -or $key.KeyChar -eq 'N') {
            Write-Host "n"
            return $false
        }
        if ($key.KeyChar -eq 'y' -or $key.KeyChar -eq 'Y') {
            Write-Host "y"
            return $true
        }
        if ($key.Key -eq "Enter") {
            if ($DefaultYes) {
                Write-Host "y"
                return $true
            }
            Write-Host "n"
            return $false
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
        if (-not (Read-ConfirmationKey -Prompt "Continue? [y/N/Esc] ")) {
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
