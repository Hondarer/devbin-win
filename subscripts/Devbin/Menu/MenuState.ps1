# MenuState.ps1
# メニューに表示する一覧と状態を作る

# 表示用コンポーネント一覧を構築する (Hidden パッケージを除外)
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

# 依存表示文字列を生成する
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

# ステータスに応じた初期選択状態を設定する
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

# メニュー状態を初期化する
function Initialize-MenuState {
    param(
        [array]$Packages,
        [hashtable]$Manifest,
        [string]$InstallDir,
        [string]$ScriptDir
    )

    $items = Get-MenuItems -Packages $Packages
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

    # Disabled 判定: DisableIfCommand が devbin-win 外部で見つかった場合に非活性化
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

    # Disabled 判定: DisableIfFont が HKCU/HKLM で devbin-win 外部登録済みの場合に非活性化
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
        Items        = $items
        Checked      = $checked
        Reinstall    = $reinstall
        Disabled     = $disabled
        CursorIndex  = 0
        Statuses     = $statuses
        Manifest     = $Manifest
        Packages     = $Packages
        PackagesDir  = $packagesDir
        InstallDir   = $InstallDir
        ScriptDir    = $ScriptDir
        NeedRedraw   = $true
        ViewportTop  = 0
        ViewportSize = $items.Count  # Render-Menu で確定
    }
}

# ステータスとチェック状態を取り直す
function Update-MenuStatuses {
    param(
        [hashtable]$State,
        [PSCustomObject]$Plan
    )

    foreach ($item in $State.Items) {
        $State.Statuses[$item.ShortName] = Get-ComponentStatus `
            -Manifest $State.Manifest `
            -InstallDir $State.InstallDir `
            -PackageConfig $item `
            -PackagesDir $State.PackagesDir
    }

    foreach ($item in $State.Items) {
        Set-MenuSelectionState `
            -Checked $State.Checked `
            -Reinstall $State.Reinstall `
            -ShortName $item.ShortName `
            -Status $State.Statuses[$item.ShortName] `
            -IsDisabled $State.Disabled[$item.ShortName] `
            -HasAnyInstalled $true `
            -IsDefaultChecked $false
    }

    # アンインストール対象だったアイテムは、操作結果にかかわらず強制 OFF
    # (Legacy 状態でファイルが残っていても、ユーザーの意図は「外す」なので再チェックしない)
    foreach ($entry in $Plan.Uninstall) {
        $State.Checked[$entry.ShortName] = $false
    }
}
