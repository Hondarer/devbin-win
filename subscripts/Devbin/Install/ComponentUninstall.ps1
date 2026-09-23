# ComponentUninstall.ps1
# コンポーネントのアンインストールおよび孤立した依存コンポーネントのクリーンアップ

# 単一のコンポーネントをアンインストールします。
function Uninstall-Component {
    param(
        [string]$ShortName,
        [array]$Packages,
        [string]$InstallDir,
        [hashtable]$Manifest,
        [string]$ScriptDir = "",
        [switch]$Force
    )

    $pkg = Get-PackageByShortName -ShortName $ShortName -Packages $Packages
    if (-not $pkg) {
        Write-Host "Error: Package '$ShortName' not found" -ForegroundColor Red
        return $false
    }

    if (-not (Test-ComponentInstalled -Manifest $Manifest -ShortName $ShortName)) {
        Write-Host "  '$ShortName' はインストールされていません" -ForegroundColor Cyan
        return $true
    }

    # 当該コンポーネントに依存している他のコンポーネントを確認します。
    if (-not $Force) {
        $dependents = Get-Dependents -ShortName $ShortName -Packages $Packages -Manifest $Manifest
        if ($dependents.Count -gt 0) {
            $depNames = $dependents | ForEach-Object {
                $d = Get-PackageByShortName -ShortName $_ -Packages $Packages
                if ($d) { $d.Name } else { $_ }
            }
            Write-Host ""
            Write-Host "警告: 次のコンポーネントが '$($pkg.Name)' に依存しています:" -ForegroundColor Yellow
            foreach ($dn in $depNames) {
                Write-Host "  - $dn" -ForegroundColor Yellow
            }
            if (-not (Read-ConfirmationKey -Prompt "アンインストールを続行しますか? [y/N/Esc] ")) {
                Write-Host "キャンセルしました"
                return $false
            }
        }
    }

    Write-Host ""
    Write-Host "=== $($pkg.Name) をアンインストール中 ==="
    Write-Host ""

    if ($pkg.ExtractStrategy -eq "NpmInstall") {
        $npmPackage = if ($pkg.ContainsKey("NpmPackage")) { [string]$pkg.NpmPackage } else { "" }
        $npmCmd = Join-Path $InstallDir "npm.cmd"

        if (-not [string]::IsNullOrWhiteSpace($npmPackage) -and (Test-Path $npmCmd)) {
            Write-Host "  npm uninstall を実行中: $npmPackage"
            & $npmCmd uninstall -g --prefix $InstallDir $npmPackage
            if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) {
                Write-Host "    Warning: npm uninstall exited with code $LASTEXITCODE" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  npm uninstall をスキップしました (npm または NpmPackage が見つかりません)" -ForegroundColor Yellow
        }
    }

    # 見出し直後の最初の手順には空行を入れません。
    if ($pkg.ExtractStrategy -eq "NpmInstall") {
        Write-Host ""
    }
    Write-Host "  ファイルを削除中..."

    # マニフェストに記録されたファイル一覧に基づいて配置ファイルを削除します。
    $componentData = $Manifest.components[$ShortName]
    $files = if ($componentData -and $componentData.ContainsKey("files")) {
        @($componentData.files) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    } else {
        @()
    }
    Remove-ComponentInstalledFiles `
        -ShortName $ShortName `
        -PackageConfig $pkg `
        -InstallDir $InstallDir `
        -Manifest $Manifest `
        -Files $files

    # コンポーネントに関連する環境変数を削除します。
    $envVarsConfig = if ($pkg.ContainsKey("EnvVars")) { $pkg.EnvVars } else { @{} }
    $hasBrowserConfig = Test-ComponentUsesEdge -PackageConfig $pkg
    if ($envVarsConfig.Count -gt 0 -or $hasBrowserConfig) {
        Write-Host ""
        Write-Host "  環境変数を削除中..."
        $componentEnvVars = @{}
        if ($componentData -and $componentData.ContainsKey("envVars") -and $componentData.envVars) {
            $componentEnvVars = $componentData.envVars
        }
        $skipEnvironmentKeys = @()
        if ($hasBrowserConfig) {
            foreach ($otherShortName in $Manifest.components.Keys) {
                if ($otherShortName -eq $ShortName) {
                    continue
                }
                $otherPackage = Get-PackageByShortName -ShortName $otherShortName -Packages $Packages
                if ($otherPackage -and $otherPackage.ContainsKey("Browser") -and [string]$otherPackage.Browser -eq "Edge") {
                    $skipEnvironmentKeys += @("BROWSER_PATH", "PUPPETEER_EXECUTABLE_PATH")
                    break
                }
            }
        }
        Remove-ComponentEnvVars -InstallDir $InstallDir -PackageConfig $pkg -AppliedEnvVars $componentEnvVars -SkipKeys $skipEnvironmentKeys
    }

    # マニフェストからコンポーネントの登録を解除します。
    Remove-ComponentFromManifest -Manifest $Manifest -ShortName $ShortName

    # data 配下の保存先を指す環境変数を解除します。data 自体は完全アンインストールまで残します。
    try {
        $storageEnvNames = @(Remove-DevbinComponentStorage -ShortName $ShortName -InstalledShortNames @($Manifest.components.Keys))
        if ($ShortName -eq "vscode" -and (Remove-DevbinVSCodeData)) {
            $storageEnvNames += "VSCODE_PORTABLE"
        }
        if ($storageEnvNames.Count -gt 0) {
            Write-Host "  ユーザー データの保存先の設定を解除しました: $($storageEnvNames -join ', ')"
            Sync-EnvironmentVariables -VariableNames $storageEnvNames -Indent 4 | Out-Null
        }
    } catch {
        Write-Host "    Warning: ユーザー データの保存先を解除できません: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # 参照元が存在しなくなった非表示の依存コンポーネントを自動的にアンインストールします。
    Remove-OrphanDependencies -UninstalledShortName $ShortName -Packages $Packages -InstallDir $InstallDir -Manifest $Manifest

    Write-Host ""
    Write-Host "  PATH を更新中..."
    Sync-ComponentManagerPath -InstallDir $InstallDir -Packages $Packages -Manifest $Manifest

    if ($ScriptDir) {
        Invoke-PackageLifecycleScripts `
            -PackageConfig $pkg `
            -Phase "Uninstall" `
            -InstallDir $InstallDir `
            -ScriptDir $ScriptDir
    }

    Write-Host ""
    Write-Host "  $($pkg.Name) のアンインストールが完了しました"

    return $true
}

# 参照元が存在しなくなった非表示の依存パッケージを削除します。
# [CmdletBinding()] により、引数名の不一致を実行時エラーとして検出します。
function Remove-OrphanDependencies {
    [CmdletBinding()]
    param(
        [string]$UninstalledShortName,
        [array]$Packages,
        [string]$InstallDir,
        [hashtable]$Manifest
    )

    # アンインストール対象パッケージの依存先を確認します。
    $pkg = Get-PackageByShortName -ShortName $UninstalledShortName -Packages $Packages
    if (-not $pkg) { return }

    $deps = if ($pkg.ContainsKey("DependsOn")) { @($pkg.DependsOn) } else { @() }

    foreach ($dep in $deps) {
        $depPkg = Get-PackageByShortName -ShortName $dep -Packages $Packages
        if (-not $depPkg) { continue }

        # 非表示 (Hidden) パッケージのみを自動削除の対象とします。
        $isHidden = $depPkg.ContainsKey("Hidden") -and $depPkg.Hidden
        if (-not $isHidden) { continue }

        # 依存先パッケージがインストール済みであるか確認します。
        if (-not (Test-ComponentInstalled -Manifest $Manifest -ShortName $dep)) { continue }

        # 当該依存先を参照している他のコンポーネントが存在しないか確認します。
        $remainingDependents = Get-Dependents -ShortName $dep -Packages $Packages -Manifest $Manifest
        if ($remainingDependents.Count -eq 0) {
            Write-Host ""
            Write-Host "  孤立した依存パッケージを削除: $($depPkg.Name)" -ForegroundColor Cyan
            Uninstall-Component `
                -ShortName $dep `
                -Packages $Packages `
                -InstallDir $InstallDir `
                -ScriptDir "" `
                -Manifest $Manifest `
                -Force | Out-Null
        }
    }
}
