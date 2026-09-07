# MenuRender.ps1
# メニューの描画

# ヘッダー行数 (行0〜4: 空行, タイトル, 空行, ヘッダー行, 区切り線)
$script:HEADER_ROWS = 5
# フッター行数 (スクロール情報 + 凡例 + 空行 + キーバインド+選択数)
$script:FOOTER_ROWS = 4

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
    [Console]::Write((" ↑↓/Wheel 移動 | Space 選択切替 | A 全選択 | N 全解除 | Enter 適用 | U 完全アンインストール | Q 終了 | 選択: $checkedCount / $($State.Items.Count)").PadRight($width))

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
