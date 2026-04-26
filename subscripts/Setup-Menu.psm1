# Setup-Menu.psm1
# CLI 対話型メニューモジュール - インタラクティブ TUI 版

# ヘッダー行数 (行0〜4: 空行, タイトル, 空行, ヘッダー行, 区切り線)
$script:HEADER_ROWS = 5
# フッター行数 (スクロール情報 + 凡例 + 空行 + キーバインド+選択数)
$script:FOOTER_ROWS = 4

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

    foreach ($item in $items) {
        $status = Get-ComponentStatus -Manifest $Manifest -InstallDir $InstallDir -PackageConfig $item
        $statuses[$item.ShortName] = $status
        if ($status -ne "NotInstalled") {
            $anyInstalled = $true
        }
    }

    # Disabled 判定: DisableIfCommand が devbin-win 外部で見つかった場合に非活性化
    $disabled = @{}
    foreach ($item in $items) {
        $disableCmd = if ($item.ContainsKey("DisableIfCommand")) { $item.DisableIfCommand } else { "" }
        if ($disableCmd) {
            $found = Get-Command $disableCmd -ErrorAction SilentlyContinue
            if ($found -and $found.Source) {
                $cmdPath = $found.Source
                $resolvedInstall = Resolve-Path $InstallDir -ErrorAction SilentlyContinue
                $absInstallDir = if ($resolvedInstall) { $resolvedInstall.Path } else { "" }
                $isOwn = $absInstallDir -and $cmdPath.StartsWith($absInstallDir, [System.StringComparison]::OrdinalIgnoreCase)
                $disabled[$item.ShortName] = -not $isOwn
            } else {
                $disabled[$item.ShortName] = $false
            }
        } else {
            $disabled[$item.ShortName] = $false
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
        InstallDir   = $InstallDir
        ScriptDir    = $ScriptDir
        NeedRedraw   = $true
        ViewportTop  = 0
        ViewportSize = $items.Count  # Render-Menu で確定
    }
}

# ステータスに対応する表示文字列と色を返す
function Get-StatusDisplay {
    param([string]$Status)
    switch ($Status) {
        "Installed"    { return @{ Label = "Installed";     Color = [ConsoleColor]::White } }
        "Updateable"   { return @{ Label = "Updateable";    Color = [ConsoleColor]::Cyan } }
        "Broken"       { return @{ Label = "Broken";        Color = [ConsoleColor]::Yellow } }
        "Legacy"       { return @{ Label = "Legacy";        Color = [ConsoleColor]::White } }
        default        { return @{ Label = "Not Installed"; Color = [ConsoleColor]::White } }
    }
}

# 1行を描画する
function Render-MenuLine {
    param(
        [int]$Row,
        [int]$Number,
        [hashtable]$Item,
        [bool]$IsChecked,
        [bool]$IsReinstall,
        [bool]$IsDisabled,
        [string]$Status,
        [bool]$IsCursor,
        [array]$Packages
    )

    [Console]::SetCursorPosition(0, $Row)

    $prefix    = if ($IsCursor) { ">" } else { " " }
    $checkbox  = if ($IsDisabled -and -not $IsChecked) { "[-]" } elseif ($IsReinstall) { "[R]" } elseif ($IsChecked) { "[X]" } else { "[ ]" }
    $statusDisp = Get-StatusDisplay -Status $Status
    if ($IsDisabled -and $Status -eq "NotInstalled") {
        $statusDisp = @{ Label = "External"; Color = [ConsoleColor]::DarkGray }
    }
    $depDisplay = Get-DependencyDisplay -PackageConfig $Item -Packages $Packages

    $componentField = "$checkbox $($Item.Name)"
    $line = "$prefix{0,3}  {1,-36} {2,-15} {3}" -f $Number, $componentField, $statusDisp.Label, $depDisplay

    $width = [Console]::WindowWidth - 1
    if ($line.Length -lt $width) {
        $line = $line.PadRight($width)
    } elseif ($line.Length -gt $width) {
        $line = $line.Substring(0, $width)
    }

    if ($IsCursor) {
        [Console]::ForegroundColor = [ConsoleColor]::White
        [Console]::BackgroundColor = [ConsoleColor]::DarkBlue
    } elseif ($IsDisabled -and -not $IsChecked) {
        [Console]::ForegroundColor = [ConsoleColor]::DarkGray
        [Console]::BackgroundColor = [ConsoleColor]::Black
    } else {
        [Console]::ForegroundColor = $statusDisp.Color
        [Console]::BackgroundColor = [ConsoleColor]::Black
    }
    [Console]::Write($line)
    [Console]::ResetColor()
}

# ビューポート位置をカーソルに追従させる
function Update-Viewport {
    param([hashtable]$State)

    $cursor = $State.CursorIndex
    if ($cursor -lt $State.ViewportTop) {
        $State.ViewportTop = $cursor
    } elseif ($cursor -ge $State.ViewportTop + $State.ViewportSize) {
        $State.ViewportTop = $cursor - $State.ViewportSize + 1
    }
}

# フッターを描画する
function Render-Footer {
    param([hashtable]$State)

    # footerStart = ヘッダー + ビューポート + スクロール情報行
    $footerStart = $script:HEADER_ROWS + $State.ViewportSize + 1
    $width = [Console]::WindowWidth - 1

    # 凡例
    [Console]::SetCursorPosition(0, $footerStart)
    [Console]::Write((" [X] Selected Installed  [R] Reinstall / Update  [ ] Not Selected  [-] External").PadRight($width))

    # 空行
    [Console]::SetCursorPosition(0, $footerStart + 1)
    [Console]::Write(" ".PadRight($width))

    # キーバインド + 選択数
    [Console]::SetCursorPosition(0, $footerStart + 2)
    $checkedCount = ($State.Checked.Values | Where-Object { $_ }).Count
    [Console]::Write((" ↑↓ 移動 | Space 選択切替 | A 全選択 | N 全解除 | Enter 適用 | Q 終了 | 選択: $checkedCount / $($State.Items.Count)").PadRight($width))

    [Console]::ResetColor()
}

# メニュー全体を描画する (フルリドロー)
function Render-Menu {
    param([hashtable]$State)

    # 描画前に色をリセットして Clear する
    [Console]::ResetColor()
    [Console]::Clear()
    [Console]::CursorVisible = $false
    $width = [Console]::WindowWidth - 1

    # 行 0: 空行
    [Console]::SetCursorPosition(0, 0)
    [Console]::Write(" ".PadRight($width))

    # 行 1: タイトル
    [Console]::SetCursorPosition(0, 1)
    [Console]::Write(("=== devbin-win コンポーネントマネージャー ===").PadRight($width))

    # 行 2: 空行
    [Console]::SetCursorPosition(0, 2)
    [Console]::Write(" ".PadRight($width))

    # 行 3: ヘッダー行
    [Console]::SetCursorPosition(0, 3)
    [Console]::Write(("  {0,3}  {1,-36} {2,-15} {3}" -f "#", "コンポーネント", "状態", "依存").PadRight($width))

    # 行 4: 区切り線
    [Console]::SetCursorPosition(0, 4)
    [Console]::Write((" " + "-" * ($width - 1)).PadRight($width))
    [Console]::ResetColor()

    # ビューポートサイズを計算 (ウィンドウリサイズにも対応)
    # WindowHeight の最終行に書き込むとバッファーがスクロールするため 1 行余裕を持たせる
    $maxViewport = [Console]::WindowHeight - 1 - $script:HEADER_ROWS - $script:FOOTER_ROWS
    $State.ViewportSize = [Math]::Min($State.Items.Count, [Math]::Max(1, $maxViewport))
    Update-Viewport -State $State

    # アイテム行 (ビューポート内のみ)
    $viewEnd = $State.ViewportTop + $State.ViewportSize
    for ($i = $State.ViewportTop; $i -lt $viewEnd; $i++) {
        $item = $State.Items[$i]
        Render-MenuLine `
            -Row ($script:HEADER_ROWS + $i - $State.ViewportTop) `
            -Number ($i + 1) `
            -Item $item `
            -IsChecked $State.Checked[$item.ShortName] `
            -IsReinstall $State.Reinstall[$item.ShortName] `
            -IsDisabled $State.Disabled[$item.ShortName] `
            -Status $State.Statuses[$item.ShortName] `
            -IsCursor ($i -eq $State.CursorIndex) `
            -Packages $State.Packages
    }

    # スクロール情報行 (ビューポート直下)
    $scrollRow = $script:HEADER_ROWS + $State.ViewportSize
    [Console]::SetCursorPosition(0, $scrollRow)
    $aboveCount = $State.ViewportTop
    $belowCount = $State.Items.Count - $viewEnd
    if ($aboveCount -gt 0 -or $belowCount -gt 0) {
        $parts = @()
        if ($aboveCount -gt 0) { $parts += "^ $aboveCount" }
        if ($belowCount -gt 0) { $parts += "v $belowCount" }
        $indicator = " " + ($parts -join " | ") + " "
        [Console]::ForegroundColor = [ConsoleColor]::DarkGray
        [Console]::Write((" ".PadRight($width - $indicator.Length) + $indicator))
        [Console]::ResetColor()
    } else {
        [Console]::Write(" ".PadRight($width))
    }

    Render-Footer -State $State

    # カーソルをフッター最終行の末尾に退避 (CursorVisible = $false なので見えない)
    $lastRow = $script:HEADER_ROWS + $State.ViewportSize + $script:FOOTER_ROWS - 1
    [Console]::SetCursorPosition(0, $lastRow)

    $State.NeedRedraw = $false
}

# チェック状態をトグルし、依存元 (子) を自動チェックする
function Toggle-CheckedItem {
    param([hashtable]$State, [int]$Index)

    $item = $State.Items[$Index]
    $shortName = $item.ShortName
    $status = $State.Statuses[$shortName]
    $isDisabled = $State.Disabled[$shortName]
    $propagateCheck = $false

    if ($status -eq "Installed" -or $status -eq "Legacy" -or $status -eq "Updateable") {
        if ($isDisabled) {
            # Disabled: チェック ON / Reinstall 遷移は禁止。チェック OFF (アンインストール) のみ許可
            if ($State.Checked[$shortName]) {
                $State.Reinstall[$shortName] = $false
                $State.Checked[$shortName] = $false
            }
            # Unchecked の場合は何もしない
        } else {
            # 3状態サイクル: Checked → Unchecked → Reinstall → Checked
            if ($State.Checked[$shortName] -and -not $State.Reinstall[$shortName]) {
                # Checked → Unchecked
                $State.Checked[$shortName] = $false
            } elseif ($State.Reinstall[$shortName]) {
                # Reinstall → Checked
                $State.Reinstall[$shortName] = $false
                $propagateCheck = $true
            } else {
                # Unchecked → Reinstall
                $State.Checked[$shortName] = $true
                $State.Reinstall[$shortName] = $true
            }
        }
    } else {
        # NotInstalled / Broken: Disabled の場合はチェック ON を禁止
        if (-not $isDisabled) {
            $newChecked = -not $State.Checked[$shortName]
            $State.Checked[$shortName] = $newChecked
            $propagateCheck = $newChecked
        }
    }

    if ($propagateCheck) {
        # チェック ON: この親に依存する子 (dependents) を推移的に自動チェック (auto-reinstall はしない)
        $queue = [System.Collections.Generic.Queue[string]]::new()
        $queue.Enqueue($shortName)
        $visited = @{ $shortName = $true }

        while ($queue.Count -gt 0) {
            $current = $queue.Dequeue()
            foreach ($child in $State.Items) {
                if ($visited[$child.ShortName]) { continue }
                $deps = if ($child.ContainsKey("DependsOn")) { @($child.DependsOn) } else { @() }
                if ($deps -contains $current) {
                    $State.Checked[$child.ShortName] = $true
                    $visited[$child.ShortName] = $true
                    $queue.Enqueue($child.ShortName)
                }
            }
        }
    }
}

# Apply: 差分計算 → 確認 → 実行
function Apply-CheckedState {
    param([hashtable]$State)

    $toInstall   = [System.Collections.Generic.List[object]]::new()
    $toUninstall = [System.Collections.Generic.List[object]]::new()
    $toReinstall = [System.Collections.Generic.List[object]]::new()

    foreach ($item in $State.Items) {
        $sn     = $item.ShortName
        $checked = $State.Checked[$sn]
        $status  = $State.Statuses[$sn]

        if ($checked -and $status -eq "NotInstalled") {
            $toInstall.Add($item)
        } elseif ($checked -and $status -eq "Broken") {
            $toReinstall.Add($item)
        } elseif ($State.Reinstall[$sn] -and ($status -eq "Installed" -or $status -eq "Legacy" -or $status -eq "Updateable")) {
            $toReinstall.Add($item)
        } elseif (-not $checked -and ($status -eq "Installed" -or $status -eq "Legacy" -or $status -eq "Updateable")) {
            $toUninstall.Add($item)
        }
    }

    # 依存関係の検証: チェック済みアイテムの依存先が未チェック+未インストールなら警告
    $missingDeps = @()
    foreach ($item in $State.Items) {
        if (-not $State.Checked[$item.ShortName]) { continue }
        $deps = if ($item.ContainsKey("DependsOn")) { @($item.DependsOn) } else { @() }
        foreach ($dep in $deps) {
            # 可視パッケージで未チェックかつ未インストールなら問題
            $depItem = $State.Items | Where-Object { $_.ShortName -eq $dep }
            if (-not $depItem) { continue }  # Hidden パッケージは Install-Component が処理する
            $depChecked = $State.Checked[$dep]
            $depStatus = $State.Statuses[$dep]
            if (-not $depChecked -and $depStatus -ne "Installed" -and $depStatus -ne "Legacy" -and $depStatus -ne "Updateable") {
                $missingDeps += @{ Item = $item; Dependency = $depItem }
            }
        }
    }

    if ($missingDeps.Count -gt 0) {
        [Console]::Clear()
        [Console]::CursorVisible = $true
        Write-Host ""
        Write-Host " 依存関係エラー: 必要なコンポーネントがチェックされていません" -ForegroundColor Red
        Write-Host ""
        foreach ($m in $missingDeps) {
            Write-Host "   $($m.Item.Name) -> $($m.Dependency.Name) が必要です" -ForegroundColor Yellow
        }
        Write-Host ""
        Write-Host " 依存先をチェックしてから再度 Enter を押してください。" -ForegroundColor DarkGray
        Write-Host " 何かキーを押してメニューに戻ります..." -ForegroundColor DarkGray
        [Console]::ReadKey($true) | Out-Null
        [Console]::CursorVisible = $false
        $State.NeedRedraw = $true
        return
    }

    if ($toInstall.Count -eq 0 -and $toUninstall.Count -eq 0 -and $toReinstall.Count -eq 0) {
        [Console]::Clear()
        [Console]::CursorVisible = $true
        Write-Host ""
        Write-Host " 変更はありません。" -ForegroundColor Green
        Start-Sleep -Seconds 1
        [Console]::CursorVisible = $false
        $State.NeedRedraw = $true
        return
    }

    # TUI を一時停止してスクロール表示へ切替
    [Console]::Clear()
    [Console]::CursorVisible = $true

    Write-Host ""
    Write-Host "=== 適用内容の確認 ==="
    Write-Host ""

    # インストール: 依存も展開して表示
    $resolvedInstall = [System.Collections.Generic.List[object]]::new()
    if ($toInstall.Count -gt 0) {
        $seen = @{}
        foreach ($item in $toInstall) {
            $allDeps = Resolve-Dependencies -ShortName $item.ShortName -Packages $State.Packages
            foreach ($dep in $allDeps) {
                if ($seen[$dep]) { continue }
                $seen[$dep] = $true
                $depPkg = Get-PackageByShortName -ShortName $dep -Packages $State.Packages
                if ($depPkg) {
                    $depStatus = Get-ComponentStatus -Manifest $State.Manifest -InstallDir $State.InstallDir -PackageConfig $depPkg
                    if ($depStatus -ne "Installed" -and $depStatus -ne "Updateable") {
                        $resolvedInstall.Add($depPkg)
                    }
                }
            }
        }

        Write-Host " インストール:"
        foreach ($item in $resolvedInstall) {
            Write-Host "   + $($item.Name)"
        }
        Write-Host ""
    }

    if ($toReinstall.Count -gt 0) {
        Write-Host " 再インストール:"
        foreach ($item in $toReinstall) {
            Write-Host "   ~ $($item.Name)"
        }
        Write-Host ""
    }

    if ($toUninstall.Count -gt 0) {
        Write-Host " アンインストール:"
        foreach ($item in $toUninstall) {
            Write-Host "   - $($item.Name)"
        }
        Write-Host ""
    }

    Write-Host " 続行しますか? [Y/n/Esc] " -NoNewline
    $confirmed = $false
    while ($true) {
        $key = [Console]::ReadKey($true)
        if ($key.Key -eq "Escape" -or $key.KeyChar -eq 'n' -or $key.KeyChar -eq 'N') {
            Write-Host "n"
            break
        } elseif ($key.Key -eq "Enter" -or $key.KeyChar -eq 'y' -or $key.KeyChar -eq 'Y') {
            Write-Host "y"
            $confirmed = $true
            break
        }
    }
    if (-not $confirmed) {
        Write-Host ""
        Write-Host "キャンセルしました"
        Start-Sleep -Milliseconds 500
        [Console]::CursorVisible = $false
        $State.NeedRedraw = $true
        return
    }

    Write-Host ""

    # インストール実行 (-SkipDeps: 依存は上で展開済み)
    if ($resolvedInstall.Count -gt 0) {
        foreach ($item in $resolvedInstall) {
            $r = Install-Component `
                -ShortName $item.ShortName `
                -Packages $State.Packages `
                -InstallDir $State.InstallDir `
                -ScriptDir $State.ScriptDir `
                -Manifest $State.Manifest `
                -SkipDeps
            if ($r) {
                Write-Manifest -InstallDir $State.InstallDir -Manifest $State.Manifest
            }
        }
    }

    # 再インストール実行
    foreach ($item in $toReinstall) {
        $r = Update-Component `
            -ShortName $item.ShortName `
            -Packages $State.Packages `
            -InstallDir $State.InstallDir `
            -ScriptDir $State.ScriptDir `
            -Manifest $State.Manifest
        if ($r) {
            Write-Manifest -InstallDir $State.InstallDir -Manifest $State.Manifest
        }
    }

    # Legacy アイテムをアンインストールできるよう、マニフェストに仮エントリを登録する
    # (Test-ComponentInstalled が false を返して早期リターンするのを防ぐ)
    foreach ($item in $toUninstall) {
        if ($State.Statuses[$item.ShortName] -eq "Legacy") {
            $pathDirs = if ($item.ContainsKey("PathDirs")) { @($item.PathDirs) } else { @() }
            $envVars  = if ($item.ContainsKey("EnvVars"))  { $item.EnvVars }     else { @{} }
            $version  = if ($item.ContainsKey("Version"))  { $item.Version }     else { "" }
            Add-ComponentToManifest `
                -Manifest $State.Manifest `
                -ShortName $item.ShortName `
                -Version $version `
                -ArchiveFile "(legacy)" `
                -Files @() `
                -PathDirs $pathDirs `
                -EnvVars $envVars
        }
    }

    # アンインストール実行 (依存逆順)
    if ($toUninstall.Count -gt 0) {
        $ordered = @()
        $remaining = [System.Collections.Generic.List[object]]($toUninstall)
        $maxPasses = $remaining.Count + 1
        $pass = 0
        while ($remaining.Count -gt 0 -and $pass -lt $maxPasses) {
            $pass++
            $progress = $false
            for ($idx = $remaining.Count - 1; $idx -ge 0; $idx--) {
                $pkg = $remaining[$idx]
                $dependents = Get-Dependents -ShortName $pkg.ShortName -Packages $State.Packages -Manifest $State.Manifest
                $blockedBy = $dependents | Where-Object {
                    $remaining | Where-Object { $_.ShortName -eq $_ }
                }
                if ($blockedBy.Count -eq 0) {
                    $ordered += $pkg
                    $remaining.RemoveAt($idx)
                    $progress = $true
                }
            }
            if (-not $progress) { break }
        }
        $ordered += $remaining

        foreach ($pkg in $ordered) {
            $r = Uninstall-Component `
                -ShortName $pkg.ShortName `
                -Packages $State.Packages `
                -InstallDir $State.InstallDir `
                -Manifest $State.Manifest `
                -Force
            if ($r) {
                Write-Manifest -InstallDir $State.InstallDir -Manifest $State.Manifest
            }
        }
    }

    Sync-EnvironmentVariables -VariableNames @("PATH") -Silent | Out-Null

    Write-Host ""
    Write-Host " 完了しました。何かキーを押してメニューに戻ります..."
    [Console]::ReadKey($true) | Out-Null

    # ステータスとチェック状態をリフレッシュ
    foreach ($item in $State.Items) {
        $State.Statuses[$item.ShortName] = Get-ComponentStatus `
            -Manifest $State.Manifest `
            -InstallDir $State.InstallDir `
            -PackageConfig $item
    }

    foreach ($item in $State.Items) {
        $status = $State.Statuses[$item.ShortName]
        Set-MenuSelectionState `
            -Checked $State.Checked `
            -Reinstall $State.Reinstall `
            -ShortName $item.ShortName `
            -Status $status `
            -IsDisabled $State.Disabled[$item.ShortName] `
            -HasAnyInstalled $true `
            -IsDefaultChecked $false
    }

    # アンインストール対象だったアイテムは、操作結果にかかわらず強制 OFF
    # (Legacy 状態でファイルが残っていても、ユーザーの意図は「外す」なので再チェックしない)
    foreach ($item in $toUninstall) {
        $State.Checked[$item.ShortName] = $false
    }

    [Console]::CursorVisible = $false
    $State.NeedRedraw = $true
}

# キー入力を処理する (戻り値: "continue" or "quit")
function Handle-KeyInput {
    param(
        [hashtable]$State,
        [System.ConsoleKeyInfo]$KeyInfo
    )

    switch ($KeyInfo.Key) {
        "UpArrow" {
            $oldIdx = $State.CursorIndex
            if ($oldIdx -le 0) { return "continue" }
            $State.CursorIndex = $oldIdx - 1
            $newIdx = $State.CursorIndex

            if ($newIdx -lt $State.ViewportTop -or $newIdx -ge $State.ViewportTop + $State.ViewportSize) {
                # ビューポート外: スクロールしてフルリドロー
                Update-Viewport -State $State
                $State.NeedRedraw = $true
            } else {
                # ビューポート内: 2行だけ更新
                $old = $State.Items[$oldIdx]
                Render-MenuLine -Row ($script:HEADER_ROWS + $oldIdx - $State.ViewportTop) -Number ($oldIdx + 1) `
                    -Item $old -IsChecked $State.Checked[$old.ShortName] -IsReinstall $State.Reinstall[$old.ShortName] `
                    -IsDisabled $State.Disabled[$old.ShortName] `
                    -Status $State.Statuses[$old.ShortName] -IsCursor $false -Packages $State.Packages

                $new = $State.Items[$newIdx]
                Render-MenuLine -Row ($script:HEADER_ROWS + $newIdx - $State.ViewportTop) -Number ($newIdx + 1) `
                    -Item $new -IsChecked $State.Checked[$new.ShortName] -IsReinstall $State.Reinstall[$new.ShortName] `
                    -IsDisabled $State.Disabled[$new.ShortName] `
                    -Status $State.Statuses[$new.ShortName] -IsCursor $true -Packages $State.Packages
            }
        }

        "DownArrow" {
            $oldIdx = $State.CursorIndex
            if ($oldIdx -ge $State.Items.Count - 1) { return "continue" }
            $State.CursorIndex = $oldIdx + 1
            $newIdx = $State.CursorIndex

            if ($newIdx -lt $State.ViewportTop -or $newIdx -ge $State.ViewportTop + $State.ViewportSize) {
                # ビューポート外: スクロールしてフルリドロー
                Update-Viewport -State $State
                $State.NeedRedraw = $true
            } else {
                # ビューポート内: 2行だけ更新
                $old = $State.Items[$oldIdx]
                Render-MenuLine -Row ($script:HEADER_ROWS + $oldIdx - $State.ViewportTop) -Number ($oldIdx + 1) `
                    -Item $old -IsChecked $State.Checked[$old.ShortName] -IsReinstall $State.Reinstall[$old.ShortName] `
                    -IsDisabled $State.Disabled[$old.ShortName] `
                    -Status $State.Statuses[$old.ShortName] -IsCursor $false -Packages $State.Packages

                $new = $State.Items[$newIdx]
                Render-MenuLine -Row ($script:HEADER_ROWS + $newIdx - $State.ViewportTop) -Number ($newIdx + 1) `
                    -Item $new -IsChecked $State.Checked[$new.ShortName] -IsReinstall $State.Reinstall[$new.ShortName] `
                    -IsDisabled $State.Disabled[$new.ShortName] `
                    -Status $State.Statuses[$new.ShortName] -IsCursor $true -Packages $State.Packages
            }
        }

        "Spacebar" {
            Toggle-CheckedItem -State $State -Index $State.CursorIndex
            # 依存伝播があるためビューポート内のアイテム行を全て再描画
            $viewEnd = $State.ViewportTop + $State.ViewportSize
            for ($i = $State.ViewportTop; $i -lt $viewEnd; $i++) {
                $item = $State.Items[$i]
                Render-MenuLine -Row ($script:HEADER_ROWS + $i - $State.ViewportTop) -Number ($i + 1) `
                    -Item $item -IsChecked $State.Checked[$item.ShortName] -IsReinstall $State.Reinstall[$item.ShortName] `
                    -IsDisabled $State.Disabled[$item.ShortName] `
                    -Status $State.Statuses[$item.ShortName] -IsCursor ($i -eq $State.CursorIndex) `
                    -Packages $State.Packages
            }
            Render-Footer -State $State
        }

        "Enter" {
            Apply-CheckedState -State $State
        }

        "Escape" {
            return "quit"
        }

        default {
            switch ($KeyInfo.KeyChar) {
                { $_ -eq 'a' -or $_ -eq 'A' } {
                    foreach ($item in $State.Items) {
                        # Disabled かつ NotInstalled はチェック ON を禁止
                        if ($State.Disabled[$item.ShortName] -and $State.Statuses[$item.ShortName] -eq "NotInstalled") {
                            continue
                        }
                        $State.Checked[$item.ShortName] = $true
                        $State.Reinstall[$item.ShortName] = $false
                    }
                    $State.NeedRedraw = $true
                }
                { $_ -eq 'n' -or $_ -eq 'N' } {
                    foreach ($item in $State.Items) {
                        $State.Checked[$item.ShortName] = $false
                        $State.Reinstall[$item.ShortName] = $false
                    }
                    $State.NeedRedraw = $true
                }
                { $_ -eq 'q' -or $_ -eq 'Q' } {
                    return "quit"
                }
            }
        }
    }

    return "continue"
}

# メインの対話ループ
function Invoke-MenuLoop {
    param(
        [array]$Packages,
        [string]$InstallDir,
        [string]$ScriptDir
    )

    if (-not (Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }

    $manifest = Read-Manifest -InstallDir $InstallDir

    # レガシーインストール検出
    $manifestPath = Get-ManifestPath -InstallDir $InstallDir
    if (-not (Test-Path $manifestPath) -and (Test-Path $InstallDir)) {
        $existingFiles = Get-ChildItem -Path $InstallDir -File -ErrorAction SilentlyContinue
        if ($existingFiles -and $existingFiles.Count -gt 0) {
            Write-Host ""
            Write-Host "既存のインストールを検出しました (マニフェストなし)" -ForegroundColor Cyan
            $manifest = Initialize-LegacyManifest -InstallDir $InstallDir -Packages $Packages
            Write-Manifest -InstallDir $InstallDir -Manifest $manifest
            Write-Host "マニフェストを生成しました" -ForegroundColor Green
            Start-Sleep -Seconds 1
        }
    }

    $state = Initialize-MenuState `
        -Packages $Packages `
        -Manifest $manifest `
        -InstallDir $InstallDir `
        -ScriptDir $ScriptDir

    $originalCursorVisible = [Console]::CursorVisible

    try {
        while ($true) {
            if ($state.NeedRedraw) {
                Render-Menu -State $state
            }

            $keyInfo = [Console]::ReadKey($true)
            $result = Handle-KeyInput -State $state -KeyInfo $keyInfo

            if ($result -eq "quit") {
                break
            }
        }
    } finally {
        [Console]::CursorVisible = $originalCursorVisible
        [Console]::ResetColor()
        [Console]::Clear()
    }

    Write-Host ""
    Write-Host "終了します。環境変数の変更を反映するにはターミナルを再起動してください。"
    Write-Host ""
}

Export-ModuleMember -Function @(
    'Get-MenuItems',
    'Invoke-MenuLoop'
)
