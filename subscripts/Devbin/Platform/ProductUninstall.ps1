# ProductUninstall.ps1
# 再インストール前のクリーンアップ処理および製品の完全アンインストール

# 1 キー入力による確認プロンプト (Y/N/Esc)。Enter キーは既定値に従います。
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

# インストールディレクトリ配下の削除および環境設定の解除を実行
function Invoke-CompleteUninstall {
    param(
        [string]$InstallDirectory,
        [switch]$Silent = $false,
        [string]$PackagesConfigPath
    )

    if (-not $Silent) {
        Write-Host "Starting cleanup process..."
    }

    try {
        # ユーザー PATH 環境変数から対象ディレクトリを除去
        if ($PackagesConfigPath -and (Test-Path $PackagesConfigPath)) {
            try {
                # PowerShell 5.0 以降では Import-PowerShellDataFile を使用
                if (Get-Command Import-PowerShellDataFile -ErrorAction SilentlyContinue) {
                    $packagesConfig = Import-PowerShellDataFile $PackagesConfigPath
                } else {
                    # フォールバック: Invoke-Expression によるデータファイル読み込み
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

                # 後方互換対応: dotnet8sdk が存在する場合は削除対象に追加
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

        # DOTNET_HOME 環境変数を削除 (dotnet10sdk および dotnet8sdk の後方互換対応)
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

        # vswhere インスタンス登録を解除
        if (-not $Silent) {
            Write-Host "Removing vswhere instance registration..."
        }
        Unregister-VswhereInstance

        # インストールディレクトリの削除
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
                # ファイルが他プロセスで使用中 (ビジー状態) であるかを検証
                $isBusy = [string]$removeResult.ErrorMessage -match "(使用中|being used|in use|access.*denied|cannot access|プロセスで使用|別のプロセス)"

                if ($isBusy) {
                    Write-Host ""
                    Write-Host "Error: 使用中のファイルがあるため削除できません。" -ForegroundColor Red
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

        return $true
    } catch {
        if (-not $Silent) {
            Write-Host "Warning: Some cleanup operations failed: $($_.Exception.Message)" -ForegroundColor Yellow
        }

        return $false
    }
}

# vswhere インスタンス ID (固定値: 8 文字ハッシュ形式)
$script:VSBT_INSTANCE_ID = "8f3e5d42"

function Invoke-ProductUninstall {
    param(
        [string]$InstallDir,
        [switch]$Force,
        [switch]$RemoveData,
        [switch]$RemoveLogs
    )

    $productRoot = Get-DevbinProductRoot -InstallDir $InstallDir

    Write-Host "=== 開発ツールの完全アンインストール ==="
    Write-Host ""
    Write-Host "製品ルート: $productRoot"
    Write-Host ""

    # 標準インストール先以外への削除要求を拒否 (リポジトリや作業ディレクトリの誤削除を防止)
    if (-not (Test-DevbinProductRootAllowed -ProductRoot $productRoot)) {
        Write-Host "Error: 完全アンインストールは標準の導入先だけを対象にします。" -ForegroundColor Red
        Write-Host "  想定: $(Get-DevbinExpectedProductRoot)"
        Write-Host "  実際: $productRoot"
        Write-Host "何も削除していません。他の場所は手動で削除してください。" -ForegroundColor Yellow
        return [PSCustomObject]@{ Status = "Refused" }
    }

    Write-Host "導入状態にかかわらず、このフォルダーの痕跡を次のとおり削除します。"
    Write-Host "  - 製品フォルダーとその中身のすべて"
    Write-Host "  - このフォルダーを指すユーザー PATH のエントリ"
    Write-Host "  - このフォルダーを指すユーザー環境変数"
    Write-Host "  - このフォルダーを指すフォント登録"
    Write-Host "  - このフォルダーを指す Windows Terminal のプロファイル"
    Write-Host "  - このフォルダーを指す vswhere の登録"
    Write-Host ""
    if (-not $Force) {
        if (-not $PSBoundParameters.ContainsKey('RemoveData')) {
            $RemoveData = Read-ConfirmationKey -Prompt "data (設定・キャッシュ) を削除しますか? $(Get-DevbinDataDirectory) [y/N/Esc] "
        }
        if (-not $PSBoundParameters.ContainsKey('RemoveLogs')) {
            $RemoveLogs = Read-ConfirmationKey -Prompt "過去のログを削除しますか? $(Get-DevbinLogDirectory) [y/N/Esc] "
        }
    }
    Write-Host "data の削除: $([bool]$RemoveData) - $(Get-DevbinDataDirectory)"
    Write-Host "log の削除: $([bool]$RemoveLogs) - $(Get-DevbinLogDirectory) (記録中のログは残します)"
    Write-Host "data の外にある HOME / XDG は削除しません。"
    Write-Host ""

    if (-not $Force) {
        if (-not (Read-ConfirmationKey -Prompt "続行しますか? [y/N/Esc] ")) {
            Write-Host "中止しました。"
            return [PSCustomObject]@{ Status = "Cancelled" }
        }
        Write-Host ""
    }

    try {
        if ($RemoveData) { Assert-DevbinStorageTreeSafe -Path (Get-DevbinDataDirectory) }
        if ($RemoveLogs) { Assert-DevbinStorageTreeSafe -Path (Get-DevbinLogDirectory) }
    } catch {
        Write-Host "削除を中止しました: $($_.Exception.Message)" -ForegroundColor Red
        return [PSCustomObject]@{ Status = "Refused" }
    }

    $removedEnvNames = @("PATH")
    Write-Host "製品フォルダーを指す設定を削除しています..."
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
        Write-Host "製品フォルダーを削除しています: $productRoot"
        $removeResult = Remove-DirectoryTree -Path $productRoot
        if ($removeResult.Success) {
            Write-Host "製品フォルダーを削除しました。"
        } else {
            $dirFailed = $true
            $isBusy = [string]$removeResult.ErrorMessage -match "(使用中|being used|in use|access.*denied|cannot access|プロセスで使用|別のプロセス)"
            if ($isBusy) {
                Write-Host ""
                Write-Host "Error: Some files are currently in use and cannot be removed." -ForegroundColor Red
                Write-Host "環境設定は解除しました。PC を再起動してから、もう一度実行してフォルダーを削除してください。" -ForegroundColor Yellow
                Write-Host ""
            } else {
                Write-Host "Warning: 製品フォルダーを削除できません: $($removeResult.ErrorMessage)" -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host "製品フォルダーが見つかりません: $productRoot"
    }

    try {
        Remove-DevbinUserStorage -RemoveData:$RemoveData -RemoveLogs:$RemoveLogs
    } catch {
        $dirFailed = $true
        Write-Host "data / log の削除に失敗しました: $($_.Exception.Message)" -ForegroundColor Red
    }
    # log の削除に失敗しても、削除済み data を参照する変数は残しません。
    if ($RemoveData -and -not (Test-Path -LiteralPath (Get-DevbinDataDirectory))) {
        try {
            $removedEnvNames += @(Remove-UserEnvVarsPointingToRoot -Root (Get-DevbinDataDirectory))
            Remove-UserPathEntriesPointingToRoot -Root (Get-DevbinDataDirectory)
        } catch {
            $dirFailed = $true
            Write-Host "data を指す環境設定の解除に失敗しました: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    Sync-EnvironmentVariables -VariableNames ($removedEnvNames | Select-Object -Unique) | Out-Null

    if ($dirFailed) {
        return [PSCustomObject]@{ Status = "Failed" }
    }

    Write-Host ""
    Write-Host "完全アンインストールが完了しました。" -ForegroundColor Green
    Write-Host "Note: 環境変数の変更を反映するには、ターミナルを開き直してください。"
    return [PSCustomObject]@{ Status = "Success" }
}
