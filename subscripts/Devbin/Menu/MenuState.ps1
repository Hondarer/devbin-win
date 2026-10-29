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

# 表示行を生成します。区切りには ShortName がなく、状態管理の Items には含めません。
function Get-MenuRowList {
    param([hashtable]$State)

    $previousGroup = ""
    foreach ($item in @(Get-MenuItemList -State $State)) {
        $group = if ($item.ContainsKey("MenuGroup")) { [string]$item.MenuGroup } else { "" }
        if ($group -and $group -ne $previousGroup) {
            @{ IsHeading = $true; Name = $group }
        }
        $item
        $previousGroup = $group
    }
}

# 区切りを除いた、コンポーネントの連続番号を返します。
function Get-MenuRowNumber {
    param([array]$Rows, [int]$Index)

    $number = 0
    for ($i = 0; $i -le $Index -and $i -lt $Rows.Count; $i++) {
        if (-not [string]::IsNullOrWhiteSpace([string]$Rows[$i].ShortName)) { $number++ }
    }
    return $number
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

# 版の表示文字列を生成します。
# 未導入は導入される版、導入済みは導入されている版、更新可能は「導入されている版 -> 導入される版」を示します。
# FileVersion には、自己更新するツールまたは devbin-win 外部の導入について、ファイルから読み取った版を渡します。
function Get-MenuVersionDisplay {
    param(
        [hashtable]$PackageConfig,
        [string]$Status,
        [string]$DisableReason = "",
        [string]$FileVersion = "",
        [hashtable]$Manifest,
        [string]$InstallDir,
        [string]$PackagesDir = ""
    )

    switch ($Status) {
        "Updateable" {
            $installed = Get-ComponentInstalledVersion -Manifest $Manifest -InstallDir $InstallDir -PackageConfig $PackageConfig -ExecutableVersion $FileVersion
            $package = Resolve-PackageVersion -PackageConfig $PackageConfig -PackagesDir $PackagesDir
            return "$installed -> $package"
        }
        { $_ -eq "Installed" -or $_ -eq "Broken" } {
            return (Get-ComponentInstalledVersion -Manifest $Manifest -InstallDir $InstallDir -PackageConfig $PackageConfig -ExecutableVersion $FileVersion)
        }
        "Legacy" { return "" }
    }

    # devbin-win 外部に導入済みの場合は、外部のファイルから読み取った版を示します。
    if ($DisableReason -eq "External") {
        return $FileVersion
    }

    return (Resolve-PackageVersion -PackageConfig $PackageConfig -PackagesDir $PackagesDir)
}

# 版を読み取るファイルのパスを返します (読み取りが不要な場合は "")。
function Get-MenuVersionFilePath {
    param(
        [hashtable]$State,
        [hashtable]$Item,
        [string]$Status
    )

    if ($Status -in @("Installed", "Broken", "Updateable")) {
        return (Get-SelfUpdatingVersionPath -InstallDir $State.InstallDir -PackageConfig $Item)
    }
    if ($Status -eq "NotInstalled" -and (Get-MenuDisableReason -State $State -ItemOrName $Item) -eq "External") {
        $externalPaths = if ($State.ContainsKey("ExternalPaths") -and $State.ExternalPaths) { $State.ExternalPaths } else { @{} }
        return [string](Get-MenuFlag -Map $externalPaths -ItemOrName $Item -Default "")
    }
    return ""
}

# 全コンポーネントの版の表示文字列を再評価します。
# ファイルから版を読み取る項目は、プロセスをまとめて起動してから共通の期限で終了を待ち、並列に読み取ります。
function Update-MenuVersions {
    param(
        [hashtable]$State,
        [int]$TimeoutMilliseconds = 3000
    )

    $items = @(Get-MenuItemList -State $State | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.ShortName) })
    $probes = @{}
    foreach ($item in $items) {
        $status = [string](Get-MenuFlag -Map $State.Statuses -ItemOrName $item -Default "NotInstalled")
        $path = Get-MenuVersionFilePath -State $State -Item $item -Status $status
        if ($path) {
            $probes[[string]$item.ShortName] = Start-PackageVersionProbe -PackageConfig $item -Path $path
        }
    }

    $deadline = [datetime]::UtcNow.AddMilliseconds($TimeoutMilliseconds)
    $State.Versions = @{}
    foreach ($item in $items) {
        $shortName = [string]$item.ShortName
        $fileVersion = if ($probes.ContainsKey($shortName)) { Wait-VersionProbe -Probe $probes[$shortName] -DeadlineUtc $deadline } else { "" }
        $State.Versions[$shortName] = Get-MenuVersionDisplay `
            -PackageConfig $item `
            -Status (Get-MenuFlag -Map $State.Statuses -ItemOrName $shortName -Default "NotInstalled") `
            -DisableReason (Get-MenuDisableReason -State $State -ItemOrName $shortName) `
            -FileVersion $fileVersion `
            -Manifest $State.Manifest `
            -InstallDir $State.InstallDir `
            -PackagesDir $State.PackagesDir
    }
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
        # devbin-win 外部の登録が指すフォント ファイルの絶対パス (版の表示に使用)
        FilePath = ""
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
        if ([string]::IsNullOrWhiteSpace($fontPath)) {
            continue
        }

        # HKLM の登録はファイル名だけの場合があり、その場合は Windows のフォント フォルダーを基準とします。
        if (-not [System.IO.Path]::IsPathRooted($fontPath)) {
            $fontPath = Join-Path (Join-Path $env:SystemRoot "Fonts") $fontPath
        }

        $normalizedFontPath = ""
        try {
            $normalizedFontPath = [System.IO.Path]::GetFullPath($fontPath)
        } catch {
            $normalizedFontPath = $fontPath
        }

        if ($normalizedInstallDir -and $normalizedFontPath.StartsWith($normalizedInstallDir, [System.StringComparison]::OrdinalIgnoreCase)) {
            $result.IsOwn = $true
            $result.FilePath = ""
            break
        }
        if (-not $result.FilePath) {
            $result.FilePath = $normalizedFontPath
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
    $externalPaths = @{}
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
                if (-not $isOwn) { $externalPaths[$item.ShortName] = $cmdPath }
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
            if ($hkcuMatch.FilePath) { $externalPaths[$item.ShortName] = $hkcuMatch.FilePath }
            continue
        }

        $hklmMatch = Get-FontRegistryMatchState `
            -FontName $disableFontName `
            -RegistryPath "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
        if ($hklmMatch.HasMatch) {
            $disabled[$item.ShortName] = $true
            if ($hklmMatch.FilePath) { $externalPaths[$item.ShortName] = $hklmMatch.FilePath }
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

    # 完全オフラインモードでは、資材のある項目だけを残し、無い項目は Unavailable として非活性化します。
    $offlineMode = Test-DevbinOfflineMode -PackagesDir $packagesDir
    $offlineAvailable = @{}
    if ($offlineMode) {
        foreach ($item in $items) {
            $offlineAvailable[$item.ShortName] = $false
            if ($disabled[$item.ShortName]) { continue }
            if (Test-ComponentTreeSourceAvailable -ShortName $item.ShortName -Packages $Packages -PackagesDir $packagesDir) {
                $offlineAvailable[$item.ShortName] = $true
            } else {
                $disabled[$item.ShortName] = $true
                $disableReasons[$item.ShortName] = "Unavailable"
            }
        }
    }

    $reinstall = @{}
    foreach ($item in $items) {
        $status = $statuses[$item.ShortName]
        $isDefaultChecked = ($item.ContainsKey("DefaultChecked") -and $item.DefaultChecked -eq $true)
        # 完全オフラインモードでは資材を用意した項目が選択意図とみなせるため、DefaultChecked = $false でも選択します。
        if ($offlineMode -and $offlineAvailable[$item.ShortName]) {
            $isDefaultChecked = $true
        }
        Set-MenuSelectionState `
            -Checked $checked `
            -Reinstall $reinstall `
            -ShortName $item.ShortName `
            -Status $status `
            -IsDisabled $disabled[$item.ShortName] `
            -HasAnyInstalled $anyInstalled `
            -IsDefaultChecked $isDefaultChecked
    }

    $state = @{
        Items          = $items
        Checked        = $checked
        Reinstall      = $reinstall
        Disabled       = $disabled
        DisableReasons = $disableReasons
        ExternalPaths  = $externalPaths
        Versions       = @{}
        OfflineMode    = $offlineMode
        CursorIndex    = $(if ($items.Count -gt 0 -and $items[0].MenuGroup) { 1 } else { 0 })
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
    Update-MenuVersions -State $state
    return $state
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

    Update-MenuVersions -State $State

    # アンインストール対象として処理された項目は、操作結果にかかわらず選択を解除します。
    # (ファイル残存によりレガシー状態として検出された場合でも、アンインストール意図を優先)
    foreach ($entry in @($Plan.Uninstall)) {
        $shortName = [string]$entry.ShortName
        if ([string]::IsNullOrWhiteSpace($shortName)) { continue }
        $State.Checked[$shortName] = $false
    }
}
