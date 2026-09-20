# MenuState.ps1
# メニュー表示項目一覧およびコンポーネント選択状態の管理

# 表示用コンポーネント一覧を生成します (非表示パッケージは除外)。
function Get-MenuItems {
    param([array]$Packages)

    $items = @()
    foreach ($pkg in $Packages) {
        $isHidden = $pkg.ContainsKey("Hidden") -and $pkg.Hidden
        if (-not $isHidden) {
            $items += $pkg
        }
    }
    return $items
}

# メニュー項目一覧をパイプラインへ出力します (呼び出し側で @(Get-MenuItemList) により配列化可能)。
function Get-MenuItemList {
    param([hashtable]$State)

    if ($null -eq $State -or -not $State.ContainsKey("Items") -or $null -eq $State.Items) {
        return
    }

    $value = $State.Items
    if ($value -is [System.Collections.IDictionary]) {
        $value
        return
    }

    foreach ($item in @($value)) {
        $item
    }
}

function Get-MenuDisableReason {
    param(
        [hashtable]$State,
        $ItemOrName
    )

    if ($null -eq $State -or -not $State.ContainsKey("DisableReasons") -or $null -eq $State.DisableReasons) {
        return ""
    }

    return [string](Get-MenuFlag -Map $State.DisableReasons -ItemOrName $ItemOrName -Default "")
}

# hashtable[$null] 参照による実行時エラーを防ぐため、キーの有効性を確認した上で値を取得します。
function Get-MenuFlag {
    param(
        [hashtable]$Map,
        $ItemOrName,
        $Default = $false
    )

    $shortName = $null
    if ($ItemOrName -is [string]) {
        $shortName = $ItemOrName
    } elseif ($null -ne $ItemOrName) {
        $shortName = [string]$ItemOrName.ShortName
    }

    if ($null -eq $Map -or [string]::IsNullOrWhiteSpace($shortName) -or -not $Map.ContainsKey($shortName)) {
        return $Default
    }
    return $Map[$shortName]
}

# 依存関係の表示文字列を生成します。
function Get-DependencyDisplay {
    param(
        [hashtable]$PackageConfig,
        [array]$Packages
    )

    $deps = if ($PackageConfig.ContainsKey("DependsOn")) { @($PackageConfig.DependsOn) } else { @() }
    if ($deps.Count -eq 0) { return "-" }

    $visibleDeps = @()
    $hiddenDeps = @()

    foreach ($dep in $deps) {
        $depPkg = $null
        foreach ($p in $Packages) {
            if ($p.ShortName -eq $dep) { $depPkg = $p; break }
        }
        if ($depPkg -and $depPkg.ContainsKey("Hidden") -and $depPkg.Hidden) {
            $hiddenDeps += $dep
        } else {
            $name = if ($depPkg) { $depPkg.Name } else { $dep }
            $visibleDeps += $name
        }
    }

    $parts = @()
    if ($visibleDeps.Count -gt 0) {
        $parts += "-> " + ($visibleDeps -join ", ")
    }
    if ($hiddenDeps.Count -gt 0) {
        $shortNames = $hiddenDeps | ForEach-Object {
            $_ -replace "^mingw64-", ""
        }
        $parts += "(auto: " + ($shortNames -join ", ") + ")"
    }

    return $parts -join " "
}

# コンポーネントの状態に応じた初期選択状態を設定します。
function Set-MenuSelectionState {
    param(
        [hashtable]$Checked,
        [hashtable]$Reinstall,
        [string]$ShortName,
        [string]$Status,
        [bool]$IsDisabled,
        [bool]$HasAnyInstalled,
        [bool]$IsDefaultChecked
    )

    if ($HasAnyInstalled) {
        $Checked[$ShortName] = ($Status -eq "Installed" -or $Status -eq "Broken" -or $Status -eq "Legacy" -or $Status -eq "Updateable")
        $Reinstall[$ShortName] = ($Status -eq "Updateable")
    } else {
        $Checked[$ShortName] = $IsDefaultChecked -and -not $IsDisabled
        $Reinstall[$ShortName] = $false
    }

    if ($IsDisabled -and $Status -eq "NotInstalled") {
        $Checked[$ShortName] = $false
        $Reinstall[$ShortName] = $false
    }
}

function Get-FontRegistryMatchState {
    param(
        [string]$FontName,
        [string]$RegistryPath,
        [string]$InstallDir = ""
    )

    $result = @{
        HasMatch = $false
        IsOwn    = $false
    }

    if ([string]::IsNullOrWhiteSpace($FontName) -or -not (Test-Path $RegistryPath)) {
        return $result
    }

    $fontProps = Get-ItemProperty -Path $RegistryPath -ErrorAction SilentlyContinue
    if (-not $fontProps) {
        return $result
    }

    $normalizedInstallDir = ""
    if ($InstallDir) {
        try {
            $normalizedInstallDir = [System.IO.Path]::GetFullPath($InstallDir)
        } catch {
            $normalizedInstallDir = $InstallDir
        }
        if ($normalizedInstallDir -and -not $normalizedInstallDir.EndsWith('\')) {
            $normalizedInstallDir += '\'
        }
    }

    $matches = $fontProps.PSObject.Properties | Where-Object { $_.Name -like "*$FontName*" }
    foreach ($match in $matches) {
        $result.HasMatch = $true
        $fontPath = if ($null -ne $match.Value) { [string]$match.Value } else { "" }
        if (-not $normalizedInstallDir -or [string]::IsNullOrWhiteSpace($fontPath)) {
            continue
        }

        $normalizedFontPath = ""
        try {
            $normalizedFontPath = [System.IO.Path]::GetFullPath($fontPath)
        } catch {
            $normalizedFontPath = $fontPath
        }

        if ($normalizedFontPath.StartsWith($normalizedInstallDir, [System.StringComparison]::OrdinalIgnoreCase)) {
            $result.IsOwn = $true
            break
        }
    }

    return $result
}

# メニュー状態ハッシュテーブルを初期化します。
function Initialize-MenuState {
    param(
        [array]$Packages,
        [hashtable]$Manifest,
        [string]$InstallDir,
        [string]$ScriptDir
    )

    $items = @(Get-MenuItems -Packages $Packages)
    $statuses = @{}
    $checked = @{}
    $anyInstalled = $false
    $packagesDir = Join-Path (Split-Path -Parent $ScriptDir) "packages"

    foreach ($item in $items) {
        $status = Get-ComponentStatus -Manifest $Manifest -InstallDir $InstallDir -PackageConfig $item -PackagesDir $packagesDir
        $statuses[$item.ShortName] = $status
        if ($status -ne "NotInstalled") {
            $anyInstalled = $true
        }
    }

    # 無効化 (Disabled) 判定: DisableIfCommand 指定のコマンドが devbin-win 外部に存在する場合に非活性化します。
    $disabled = @{}
    $resolvedInstall = Resolve-Path $InstallDir -ErrorAction SilentlyContinue
    $absInstallDir = if ($resolvedInstall) { $resolvedInstall.Path } else { $InstallDir }

    foreach ($item in $items) {
        $disableCmd = if ($item.ContainsKey("DisableIfCommand")) { $item.DisableIfCommand } else { "" }
        if ($disableCmd) {
            $found = Get-Command $disableCmd -ErrorAction SilentlyContinue
            if ($found -and $found.Source) {
                $cmdPath = $found.Source
                $isOwn = $absInstallDir -and $cmdPath.StartsWith($absInstallDir, [System.StringComparison]::OrdinalIgnoreCase)
                $disabled[$item.ShortName] = -not $isOwn
            } else {
                $disabled[$item.ShortName] = $false
            }
        } else {
            $disabled[$item.ShortName] = $false
        }
    }

    # 無効化 (Disabled) 判定: DisableIfFont 指定のフォントがレジストリ上で devbin-win 外部から登録済みの場合に非活性化します。
    foreach ($item in $items) {
        if ($disabled[$item.ShortName]) { continue }

        $disableFontName = if ($item.ContainsKey("DisableIfFont")) { $item.DisableIfFont } else { "" }
        if (-not $disableFontName) { continue }

        $hkcuMatch = Get-FontRegistryMatchState `
            -FontName $disableFontName `
            -RegistryPath "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts" `
            -InstallDir $absInstallDir
        if ($hkcuMatch.HasMatch -and -not $hkcuMatch.IsOwn) {
            $disabled[$item.ShortName] = $true
            continue
        }

        $hklmMatch = Get-FontRegistryMatchState `
            -FontName $disableFontName `
            -RegistryPath "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
        if ($hklmMatch.HasMatch) {
            $disabled[$item.ShortName] = $true
        }
    }

    $disableReasons = @{}
    foreach ($item in $items) {
        if ($disabled[$item.ShortName]) {
            $disableReasons[$item.ShortName] = "External"
        } else {
            $disableReasons[$item.ShortName] = ""
        }
    }

    $offlineMode = Test-DevbinOfflineMode -PackagesDir $packagesDir
    if ($offlineMode) {
        foreach ($item in $items) {
            if ($disabled[$item.ShortName]) { continue }
            if (-not (Test-ComponentTreeSourceAvailable -ShortName $item.ShortName -Packages $Packages -PackagesDir $packagesDir)) {
                $disabled[$item.ShortName] = $true
                $disableReasons[$item.ShortName] = "Unavailable"
            }
        }
    }

    $reinstall = @{}
    foreach ($item in $items) {
        $status = $statuses[$item.ShortName]
        $isDefaultChecked = ($item.ContainsKey("DefaultChecked") -and $item.DefaultChecked -eq $true)
        Set-MenuSelectionState `
            -Checked $checked `
            -Reinstall $reinstall `
            -ShortName $item.ShortName `
            -Status $status `
            -IsDisabled $disabled[$item.ShortName] `
            -HasAnyInstalled $anyInstalled `
            -IsDefaultChecked $isDefaultChecked
    }

    return @{
        Items          = $items
        Checked        = $checked
        Reinstall      = $reinstall
        Disabled       = $disabled
        DisableReasons = $disableReasons
        OfflineMode    = $offlineMode
        CursorIndex    = 0
        Statuses       = $statuses
        Manifest       = $Manifest
        Packages       = $Packages
        PackagesDir    = $packagesDir
        InstallDir     = $InstallDir
        ScriptDir      = $ScriptDir
        NeedRedraw     = $true
        ViewportTop    = 0
        ViewportSize   = $items.Count  # Render-Menu 実行時に確定
    }
}

# コンポーネントの状態および選択状態を再評価して更新します。
function Update-MenuStatuses {
    param(
        [hashtable]$State,
        [PSCustomObject]$Plan
    )

    foreach ($item in @(Get-MenuItemList -State $State)) {
        $shortName = [string]$item.ShortName
        if ([string]::IsNullOrWhiteSpace($shortName)) { continue }
        $State.Statuses[$shortName] = Get-ComponentStatus `
            -Manifest $State.Manifest `
            -InstallDir $State.InstallDir `
            -PackageConfig $item `
            -PackagesDir $State.PackagesDir
    }

    foreach ($item in @(Get-MenuItemList -State $State)) {
        $shortName = [string]$item.ShortName
        if ([string]::IsNullOrWhiteSpace($shortName)) { continue }
        Set-MenuSelectionState `
            -Checked $State.Checked `
            -Reinstall $State.Reinstall `
            -ShortName $shortName `
            -Status $State.Statuses[$shortName] `
            -IsDisabled (Get-MenuFlag -Map $State.Disabled -ItemOrName $shortName) `
            -HasAnyInstalled $true `
            -IsDefaultChecked $false
    }

    # アンインストール対象として処理された項目は、操作結果にかかわらず選択を解除します。
    # (ファイル残存によりレガシー状態として検出された場合でも、アンインストール意図を優先)
    foreach ($entry in @($Plan.Uninstall)) {
        $shortName = [string]$entry.ShortName
        if ([string]::IsNullOrWhiteSpace($shortName)) { continue }
        $State.Checked[$shortName] = $false
    }
}
