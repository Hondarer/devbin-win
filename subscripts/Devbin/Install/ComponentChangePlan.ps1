# ComponentChangePlan.ps1
# コンポーネント操作計画の作成および適用
#
# New-ComponentChangePlan は、パッケージ定義・現在状態・ユーザー選択に基づいて操作順序を策定します。
# Invoke-ComponentChangePlan は、確認画面に提示された操作計画を順次実行します。
# 依存関係の解決およびマニフェストの書き込み処理は、UI ではなく本モジュール側で集約して実施します。

# 操作項目 1 件を表すオブジェクトを生成します。
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

# 操作結果 1 件を表すオブジェクトを生成します。
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

# 選択状態およびコンポーネント状態から操作計画を生成します。
# 戻り値: Success / Errors / Install / Reinstall / Uninstall / IsEmpty
#   Install   : 依存先を優先する順序
#   Uninstall : 依存元を優先する順序
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

    # 依存関係の検証: 選択された項目の依存先が未選択かつ未インストールの場合はエラーを返します。
    $errors = @()
    foreach ($item in $Items) {
        if (-not $Checked[$item.ShortName]) { continue }
        $deps = if ($item.ContainsKey("DependsOn")) { @($item.DependsOn) } else { @() }
        foreach ($dep in $deps) {
            # 非表示 (Hidden) パッケージはインストール処理側で自動導入されるため、ここでは表示項目のみを検証します。
            $depItem = $Items | Where-Object { $_.ShortName -eq $dep } | Select-Object -First 1
            if (-not $depItem) { continue }
            if ($Checked[$dep]) { continue }
            if ($installedStatuses -contains [string]$Statuses[$dep]) { continue }
            $errors += "$($item.Name) には $($depItem.Name) が必要です"
        }
    }

    # 残存するパッケージが必要としている依存先は削除対象から除外します。
    $uninstallShortNames = @($toUninstall | ForEach-Object { [string]$_.ShortName })
    foreach ($item in $toUninstall) {
        $dependents = @(Get-Dependents -ShortName $item.ShortName -Packages $Packages -Manifest $Manifest)
        # 新規インストール予定およびレガシーコンポーネントはマニフェストに記録されていないため、選択状態も併せて検証します。
        $dependents += @($Items | Where-Object {
            $Checked[$_.ShortName] -and $_.ContainsKey("DependsOn") -and
            (@($_.DependsOn) -contains $item.ShortName)
        } | ForEach-Object { [string]$_.ShortName })
        $dependents = @($dependents | Select-Object -Unique)
        $stillNeededBy = @($dependents | Where-Object { $uninstallShortNames -notcontains $_ })
        foreach ($dependent in $stillNeededBy) {
            $dependentPackage = Get-PackageByShortName -ShortName $dependent -Packages $Packages
            $dependentName = if ($dependentPackage) { [string]$dependentPackage.Name } else { $dependent }
            $errors += "$($item.Name) は $dependentName が必要としているため削除できません"
        }
    }

    # インストール順序の決定: 依存先を優先します。
    $installEntries = @()
    $reinstallEntries = @()
    $reinstallNames = @($toReinstall | ForEach-Object { $_.ShortName })
    if (($toInstall.Count + $toReinstall.Count) -gt 0) {
        $resolution = Resolve-DependencyOrder -ShortNames @(($toInstall + $toReinstall) | ForEach-Object { $_.ShortName }) -Packages $Packages
        if (-not $resolution.Success) {
            $errors += $resolution.Errors
        } else {
            $seen = @{}
            foreach ($shortName in $resolution.Order) {
                if ($seen.ContainsKey($shortName)) { continue }
                $seen[$shortName] = $true

                $package = Get-PackageByShortName -ShortName $shortName -Packages $Packages
                if (-not $package) { continue }

                $status = if ($Statuses.ContainsKey($shortName)) { $Statuses[$shortName] } else { Get-ComponentStatus `
                    -Manifest $Manifest `
                    -InstallDir $InstallDir `
                    -PackageConfig $package `
                    -PackagesDir $PackagesDir }
                if ($reinstallNames -contains $shortName -or $status -eq "Broken") {
                    $reinstallEntries += New-ComponentChangeEntry -Action "Reinstall" -PackageConfig $package
                    continue
                }
                if ($installedStatuses -contains $status) { continue }

                $installEntries += New-ComponentChangeEntry -Action "Install" -PackageConfig $package
            }
        }
    }

    # アンインストール順序の決定: 依存元を優先します (残存パッケージが必要とする依存先は除外済み)。
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

# 操作計画を実行します。
# 戻り値: Success / Aborted / Results
# 依存先の処理が失敗した場合、そのコンポーネントを必要とする後続処理はスキップします。
# マニフェストは各操作の完了ごとに保存し、保存に失敗した時点で処理を中断します。
# バッチ全体の自動ロールバックは行わず、完了済みの操作と失敗箇所を結果として返します。
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

    # 新規インストールと再インストールを一括で依存順に整列します (修復前の依存先を用いた新規インストールを防止)。
    $deploymentEntries = @($Plan.Install) + @($Plan.Reinstall)
    $deploymentOrder = Resolve-DependencyOrder -ShortNames @($deploymentEntries | ForEach-Object { $_.ShortName }) -Packages $Packages
    if (-not $Plan.Success -or -not $deploymentOrder.Success) {
        return [PSCustomObject]@{ Success = $false; Aborted = $true; Results = @() }
    }
    foreach ($shortName in $deploymentOrder.Order) {
        $entry = $deploymentEntries | Where-Object { $_.ShortName -eq $shortName } | Select-Object -First 1
        if (-not $entry) { continue }
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

        # 依存関係は計画側で展開済みのため、-SkipDeps を指定して実行します。
        if ($entry.Action -eq "Reinstall") {
            $succeeded = Update-Component -ShortName $entry.ShortName -Packages $Packages `
                -InstallDir $InstallDir -ScriptDir $ScriptDir -Manifest $Manifest
        } else {
            $succeeded = Install-Component `
                -ShortName $entry.ShortName `
                -Packages $Packages `
                -InstallDir $InstallDir `
                -ScriptDir $ScriptDir `
                -Manifest $Manifest `
                -SkipDeps
        }

        # 再インストール時は失敗時にもマニフェストから対象が除外されるため、成否にかかわらず保存します。
        if ($succeeded -or $entry.Action -eq "Reinstall") {
            if (-not (Write-Manifest -InstallDir $InstallDir -Manifest $Manifest)) {
                $results += New-ComponentChangeResult -Status "Aborted" -ShortName $entry.ShortName -Message $abortMessage
                $aborted = $true
                break
            }
        }
        if ($succeeded) {
            $resultStatus = if ($entry.Action -eq "Reinstall") { "Reinstalled" } else { "Installed" }
            $results += New-ComponentChangeResult -Status $resultStatus -ShortName $entry.ShortName
        } else {
            $failed[$entry.ShortName] = $true
            $results += New-ComponentChangeResult -Status "Failed" -ShortName $entry.ShortName -Message "インストールに失敗しました"
        }
    }

    if (-not $aborted) {
        # レガシーコンポーネントはマニフェストに記録されていないため、削除処理が早期復帰しないよう仮エントリを登録します。
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
