# ComponentChangePlan.ps1
# 操作計画の作成と適用
#
# New-ComponentChangePlan は定義・現在状態・選択から操作順を作り、
# Invoke-ComponentChangePlan は確認画面に表示した計画をそのまま実行する。
# UI は依存解決もマニフェストの書き込みも行わない。

# 操作 1 件を表す
function New-ComponentChangeEntry {
    param(
        [string]$Action,
        [hashtable]$PackageConfig,
        [bool]$IsLegacy = $false
    )

    return [PSCustomObject]@{
        Action    = $Action
        ShortName = [string]$PackageConfig.ShortName
        Name      = [string]$PackageConfig.Name
        IsLegacy  = $IsLegacy
    }
}

# 操作結果 1 件を表す
function New-ComponentChangeResult {
    param(
        [string]$Status,
        [string]$ShortName,
        [string]$Message = "",
        [string[]]$Warnings = @()
    )

    return [PSCustomObject]@{
        Status    = $Status
        ShortName = $ShortName
        Message   = $Message
        Warnings  = @($Warnings)
    }
}

# 選択状態から操作計画を作る
# 戻り値: Success / Errors / Install / Reinstall / Uninstall / IsEmpty
#   Install   : 依存先が先に来る順序
#   Uninstall : 依存元が先に来る順序
function New-ComponentChangePlan {
    param(
        [array]$Packages,
        [array]$Items,
        [hashtable]$Checked,
        [hashtable]$Reinstall,
        [hashtable]$Statuses,
        [hashtable]$Manifest,
        [string]$InstallDir,
        [string]$PackagesDir = ""
    )

    $installedStatuses = @("Installed", "Legacy", "Updateable")

    $toInstall = @()
    $toReinstall = @()
    $toUninstall = @()

    foreach ($item in $Items) {
        $shortName = [string]$item.ShortName
        $isChecked = [bool]$Checked[$shortName]
        $status = [string]$Statuses[$shortName]

        if ($isChecked -and $status -eq "NotInstalled") {
            $toInstall += $item
        } elseif ($isChecked -and $status -eq "Broken") {
            $toReinstall += $item
        } elseif ($Reinstall[$shortName] -and ($installedStatuses -contains $status)) {
            $toReinstall += $item
        } elseif (-not $isChecked -and ($installedStatuses -contains $status)) {
            $toUninstall += $item
        }
    }

    # 依存関係の検証: チェック済みアイテムの依存先が未チェックかつ未インストールなら中断する
    $errors = @()
    foreach ($item in $Items) {
        if (-not $Checked[$item.ShortName]) { continue }
        $deps = if ($item.ContainsKey("DependsOn")) { @($item.DependsOn) } else { @() }
        foreach ($dep in $deps) {
            # Hidden パッケージは導入処理が面倒を見るため、ここでは可視のものだけを見る
            $depItem = $Items | Where-Object { $_.ShortName -eq $dep } | Select-Object -First 1
            if (-not $depItem) { continue }
            if ($Checked[$dep]) { continue }
            if ($installedStatuses -contains [string]$Statuses[$dep]) { continue }
            $errors += "$($item.Name) には $($depItem.Name) が必要です"
        }
    }

    # 残るパッケージが必要としている依存先は削除しない
    $uninstallShortNames = @($toUninstall | ForEach-Object { [string]$_.ShortName })
    foreach ($item in $toUninstall) {
        $dependents = @(Get-Dependents -ShortName $item.ShortName -Packages $Packages -Manifest $Manifest)
        $stillNeededBy = @($dependents | Where-Object { $uninstallShortNames -notcontains $_ })
        foreach ($dependent in $stillNeededBy) {
            $dependentPackage = Get-PackageByShortName -ShortName $dependent -Packages $Packages
            $dependentName = if ($dependentPackage) { [string]$dependentPackage.Name } else { $dependent }
            $errors += "$($item.Name) は $dependentName が必要としているため削除できません"
        }
    }

    # 導入順: 依存先から
    $installEntries = @()
    if ($toInstall.Count -gt 0) {
        $resolution = Resolve-DependencyOrder -ShortNames @($toInstall | ForEach-Object { $_.ShortName }) -Packages $Packages
        if (-not $resolution.Success) {
            $errors += $resolution.Errors
        } else {
            $seen = @{}
            foreach ($shortName in $resolution.Order) {
                if ($seen.ContainsKey($shortName)) { continue }
                $seen[$shortName] = $true

                $package = Get-PackageByShortName -ShortName $shortName -Packages $Packages
                if (-not $package) { continue }

                $status = Get-ComponentStatus `
                    -Manifest $Manifest `
                    -InstallDir $InstallDir `
                    -PackageConfig $package `
                    -PackagesDir $PackagesDir
                if ($status -eq "Installed" -or $status -eq "Updateable") { continue }

                $installEntries += New-ComponentChangeEntry -Action "Install" -PackageConfig $package
            }
        }
    }

    $reinstallEntries = @()
    foreach ($item in $toReinstall) {
        $reinstallEntries += New-ComponentChangeEntry -Action "Reinstall" -PackageConfig $item
    }

    # 削除順: 依存元から。残るパッケージが必要とする依存先は対象に含まれない
    $uninstallEntries = @()
    if ($toUninstall.Count -gt 0) {
        $orderedShortNames = @(Get-UninstallOrder `
            -ShortNames @($toUninstall | ForEach-Object { $_.ShortName }) `
            -Packages $Packages `
            -Manifest $Manifest)

        foreach ($shortName in $orderedShortNames) {
            $item = $toUninstall | Where-Object { $_.ShortName -eq $shortName } | Select-Object -First 1
            if (-not $item) { continue }
            $isLegacy = ([string]$Statuses[$shortName] -eq "Legacy")
            $uninstallEntries += New-ComponentChangeEntry -Action "Uninstall" -PackageConfig $item -IsLegacy:$isLegacy
        }
    }

    $total = $installEntries.Count + $reinstallEntries.Count + $uninstallEntries.Count

    return [PSCustomObject]@{
        Success   = ($errors.Count -eq 0)
        Errors    = @($errors)
        Install   = @($installEntries)
        Reinstall = @($reinstallEntries)
        Uninstall = @($uninstallEntries)
        IsEmpty   = ($total -eq 0)
    }
}

# 操作計画を実行する
# 戻り値: Success / Aborted / Results
# 依存先が失敗した場合、それを必要とするコンポーネントは実行せずスキップする。
# マニフェストは操作ごとに保存し、保存に失敗した時点で適用を止める。
# バッチ全体の自動ロールバックは行わず、完了済みの操作と失敗箇所を結果で示す。
function Invoke-ComponentChangePlan {
    param(
        [PSCustomObject]$Plan,
        [array]$Packages,
        [string]$InstallDir,
        [string]$ScriptDir,
        [hashtable]$Manifest
    )

    $results = @()
    $failed = @{}
    $aborted = $false
    $abortMessage = "マニフェストを保存できませんでした"

    foreach ($entry in $Plan.Install) {
        $package = Get-PackageByShortName -ShortName $entry.ShortName -Packages $Packages
        $deps = if ($package -and $package.ContainsKey("DependsOn")) { @($package.DependsOn) } else { @() }
        $blockedBy = @($deps | Where-Object { $failed.ContainsKey($_) })
        if ($blockedBy.Count -gt 0) {
            $failed[$entry.ShortName] = $true
            $results += New-ComponentChangeResult `
                -Status "Skipped" `
                -ShortName $entry.ShortName `
                -Message "依存先の失敗によりスキップしました: $($blockedBy -join ', ')"
            continue
        }

        # 依存は計画側で展開済みのため -SkipDeps で実行する
        $succeeded = Install-Component `
            -ShortName $entry.ShortName `
            -Packages $Packages `
            -InstallDir $InstallDir `
            -ScriptDir $ScriptDir `
            -Manifest $Manifest `
            -SkipDeps

        if ($succeeded) {
            if (-not (Write-Manifest -InstallDir $InstallDir -Manifest $Manifest)) {
                $results += New-ComponentChangeResult -Status "Aborted" -ShortName $entry.ShortName -Message $abortMessage
                $aborted = $true
                break
            }
            $results += New-ComponentChangeResult -Status "Installed" -ShortName $entry.ShortName
        } else {
            $failed[$entry.ShortName] = $true
            $results += New-ComponentChangeResult -Status "Failed" -ShortName $entry.ShortName -Message "インストールに失敗しました"
        }
    }

    if (-not $aborted) {
        foreach ($entry in $Plan.Reinstall) {
            $succeeded = Update-Component `
                -ShortName $entry.ShortName `
                -Packages $Packages `
                -InstallDir $InstallDir `
                -ScriptDir $ScriptDir `
                -Manifest $Manifest

            if (-not $succeeded) {
                $failed[$entry.ShortName] = $true
            }

            # Update-Component は失敗時もマニフェストから対象を外すため、成否によらず保存する
            if (-not (Write-Manifest -InstallDir $InstallDir -Manifest $Manifest)) {
                $results += New-ComponentChangeResult -Status "Aborted" -ShortName $entry.ShortName -Message $abortMessage
                $aborted = $true
                break
            }

            if ($succeeded) {
                $results += New-ComponentChangeResult -Status "Reinstalled" -ShortName $entry.ShortName
            } else {
                $results += New-ComponentChangeResult -Status "Failed" -ShortName $entry.ShortName -Message "再インストールに失敗しました"
            }
        }
    }

    if (-not $aborted) {
        # Legacy はマニフェストに無いため、削除処理が早期 return しないよう仮エントリを登録する
        foreach ($entry in $Plan.Uninstall) {
            if (-not $entry.IsLegacy) { continue }
            $package = Get-PackageByShortName -ShortName $entry.ShortName -Packages $Packages
            if (-not $package) { continue }

            Add-ComponentToManifest `
                -Manifest $Manifest `
                -ShortName $entry.ShortName `
                -Version $(if ($package.ContainsKey("Version")) { [string]$package.Version } else { "" }) `
                -ArchiveFile "(legacy)" `
                -Files @() `
                -PathDirs $(if ($package.ContainsKey("PathDirs")) { @($package.PathDirs) } else { @() }) `
                -EnvVars $(if ($package.ContainsKey("EnvVars")) { $package.EnvVars } else { @{} })
        }

        foreach ($entry in $Plan.Uninstall) {
            $succeeded = Uninstall-Component `
                -ShortName $entry.ShortName `
                -Packages $Packages `
                -InstallDir $InstallDir `
                -ScriptDir $ScriptDir `
                -Manifest $Manifest `
                -Force

            if ($succeeded) {
                if (-not (Write-Manifest -InstallDir $InstallDir -Manifest $Manifest)) {
                    $results += New-ComponentChangeResult -Status "Aborted" -ShortName $entry.ShortName -Message $abortMessage
                    $aborted = $true
                    break
                }
                $results += New-ComponentChangeResult -Status "Uninstalled" -ShortName $entry.ShortName
            } else {
                $failed[$entry.ShortName] = $true
                $results += New-ComponentChangeResult -Status "Failed" -ShortName $entry.ShortName -Message "アンインストールに失敗しました"
            }
        }
    }

    $succeededAll = ($aborted -eq $false) -and (@($results | Where-Object { $_.Status -eq "Failed" -or $_.Status -eq "Skipped" }).Count -eq 0)

    return [PSCustomObject]@{
        Success = $succeededAll
        Aborted = $aborted
        Results = @($results)
    }
}
