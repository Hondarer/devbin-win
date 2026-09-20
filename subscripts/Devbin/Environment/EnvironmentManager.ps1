# 保存値を展開せずに扱う、独立した環境変数マネージャー。
function Get-EnvRegistryEntries {
    param([ValidateSet('User', 'Machine')][string]$Scope)
    $root = if ($Scope -eq 'User') { [Microsoft.Win32.Registry]::CurrentUser } else { [Microsoft.Win32.Registry]::LocalMachine }
    $path = if ($Scope -eq 'User') { 'Environment' } else { 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment' }
    $key = $root.OpenSubKey($path, $false)
    if ($null -eq $key) { return }
    try {
        foreach ($name in ($key.GetValueNames() | Sort-Object)) {
            if ($name -eq '') { continue }
            [pscustomobject]@{
                Name = $name
                Value = $key.GetValue($name, '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                Kind = $key.GetValueKind($name).ToString()
            }
        }
    } finally { $key.Dispose() }
}

function Assert-EnvValue {
    param([string]$Name, [AllowEmptyString()][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Name) -or $Name.IndexOfAny([char[]]"=`0`r`n") -ge 0 -or $Name.Length -ge 255) {
        throw '名前は 1～254 文字で指定してください。空白のみ、=、改行、NUL は使用できません。'
    }
    if ($Value.Contains([string][char]0) -or $Value.Length -ge 32767) {
        throw '値に NUL は使用できません。長さは 32766 文字以下にしてください。'
    }
}

function Write-EnvUserValue {
    param([string]$Name, [string]$Value, [string]$Kind, [switch]$Delete)
    # 書き込み先は HKCU\Environment に固定。Machine の書き込み経路は設けない。
    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Environment')
    try {
        if ($Delete) { $key.DeleteValue($Name, $false) }
        else { $key.SetValue($Name, $Value, [Microsoft.Win32.RegistryValueKind]::$Kind) }
    } finally { $key.Dispose() }
}

function Send-EnvChangeNotification {
    if (-not ('Devbin.EnvironmentNotification' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace Devbin {
    public static class EnvironmentNotification {
        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern IntPtr SendMessageTimeout(IntPtr hwnd, uint msg, UIntPtr wparam,
            string lparam, uint flags, uint timeout, out UIntPtr result);
    }
}
'@
    }
    $result = [UIntPtr]::Zero
    $sent = [Devbin.EnvironmentNotification]::SendMessageTimeout([IntPtr]65535, 0x001A, [UIntPtr]::Zero, 'Environment', 2, 2000, [ref]$result)
    if ($sent -eq [IntPtr]::Zero) { throw '環境変更の通知に応答がありませんでした。' }
}

function Save-EnvUserChange {
    param([ValidateSet('User', 'Machine')][string]$Scope, [string]$Name,
        [AllowEmptyString()][string]$Value, [string]$Kind, $Original, [switch]$Delete)
    if ($Scope -ne 'User') { throw 'システム環境変数は表示専用です。' }
    Assert-EnvValue -Name $Name -Value $Value
    if ($Kind -notin @('String', 'ExpandString')) { throw '文字列以外の型は編集できません。' }
    $current = @(Get-EnvRegistryEntries -Scope User | Where-Object { $_.Name -eq $Name })
    if ($null -eq $Original) {
        if ($current.Count -gt 0) { throw '同名の変数が既に存在します。一覧を更新してください。' }
    } elseif ($current.Count -ne 1 -or $current[0].Kind -ne $Original.Kind -or [string]$current[0].Value -cne [string]$Original.Value) {
        throw '表示後に値が変更されました。一覧を更新してから編集してください。'
    }
    Write-EnvUserValue -Name $Name -Value $Value -Kind $Kind -Delete:$Delete
    try { Send-EnvChangeNotification } catch {
        return "保存済みですが、変更通知に失敗しました: $($_.Exception.Message) サインインし直すと反映されます。"
    }
    return '保存しました。既に起動しているアプリケーションには反映されません。必要に応じてサインインし直してください。'
}

function Get-EnvFilteredEntries {
    param([array]$Entries, [string]$Filter)
    @($Entries | Where-Object { $_.Name.IndexOf($Filter, [StringComparison]::OrdinalIgnoreCase) -ge 0 })
}

function Get-EnvDisplayText {
    param([string]$Text, [int]$Width)
    # 制御文字を無害化し、日本語の表示幅を考慮して折り返しを防ぐ。
    $text = $Text -replace '[\x00-\x1f\x7f]', ' '
    $builder = New-Object System.Text.StringBuilder
    $used = 0
    foreach ($c in $text.ToCharArray()) {
        $size = if ([int]$c -ge 0x1100) { 2 } else { 1 }
        if ($used + $size -gt $Width) { break }
        [void]$builder.Append($c)
        $used += $size
    }
    $builder.ToString()
}

function Read-EnvText {
    param([string]$Prompt, [AllowEmptyString()][string]$Initial = '')
    $script:EnvListFrame = $null
    Write-Host "$Prompt (Enter: 確定 / Esc: キャンセル)"
    $value = $Initial
    $position = $value.Length
    $row = [Console]::CursorTop
    $previousLine = $null
    [Console]::CursorVisible = $true
    try {
        while ($true) {
            $width = [Math]::Max(4, [Console]::WindowWidth - 2)
            $start = [Math]::Max(0, $position - [int]($width / 2) + 1)
            $prefix = Get-EnvDisplayText -Text $value.Substring($start, $position - $start) -Width $width
            $shown = Get-EnvDisplayText -Text $value.Substring($start) -Width $width
            $line = ConvertTo-EnvPaddedLine $shown $width
            if ($line -cne $previousLine) {
                [Console]::SetCursorPosition(0, $row)
                [Console]::Write($line)
                $previousLine = $line
            }
            $cursorWidth = 0
            foreach ($c in $prefix.ToCharArray()) { $cursorWidth += $(if ([int]$c -ge 0x1100) { 2 } else { 1 }) }
            [Console]::SetCursorPosition([Math]::Min($cursorWidth, $width), $row)
            $key = [Console]::ReadKey($true)
            switch ($key.Key) {
                'Escape' { return $null }
                'Enter' { return [pscustomobject]@{ Value = $value } }
                'LeftArrow' { $position = [Math]::Max(0, $position - 1) }
                'RightArrow' { $position = [Math]::Min($value.Length, $position + 1) }
                'Home' { $position = 0 }
                'End' { $position = $value.Length }
                'Backspace' { if ($position -gt 0) { $value = $value.Remove(--$position, 1) } }
                'Delete' { if ($position -lt $value.Length) { $value = $value.Remove($position, 1) } }
                default {
                    if (-not [char]::IsControl($key.KeyChar)) {
                        $value = $value.Insert($position, [string]$key.KeyChar)
                        $position++
                    }
                }
            }
        }
    } finally { [Console]::WriteLine(); [Console]::CursorVisible = $false }
}

function ConvertTo-EnvPaddedLine {
    param([string]$Text, [int]$Width)
    $shown = Get-EnvDisplayText $Text $Width
    $used = 0
    foreach ($c in $shown.ToCharArray()) { $used += $(if ([int]$c -ge 0x1100) { 2 } else { 1 }) }
    $shown + (' ' * [Math]::Max(0, $Width - $used))
}

function Get-EnvConsoleSize {
    @{ Width = [Console]::WindowWidth; Height = [Console]::WindowHeight }
}

function Clear-EnvListScreen {
    [Console]::Clear()
    [Console]::CursorVisible = $false
}

function Write-EnvScreenRow {
    param([int]$Row, [string]$Text, [ConsoleColor]$Foreground, [ConsoleColor]$Background)
    [Console]::SetCursorPosition(0, $Row)
    Write-Host -NoNewline $Text -ForegroundColor $Foreground -BackgroundColor $Background
}

function Set-EnvPromptPosition {
    param([int]$Row)
    [Console]::SetCursorPosition(0, $Row)
}

function Show-EnvList {
    param([string]$Title, [array]$Lines, [int]$Index, [string]$Help, [string]$Status,
        [string]$Columns = '項目', [switch]$Warning)
    $size = Get-EnvConsoleSize
    $width = [Math]::Max(1, $size.Width - 1)
    $height = [Math]::Max(1, $size.Height - 1)
    # Manage-Bin と同じヘッダー 5 行・フッター 4 行・最終行の余白。
    $page = [Math]::Min([Math]::Max(1, $Lines.Count), [Math]::Max(1, $size.Height - 10))
    $rows = @()
    for ($row = 0; $row -lt $height; $row++) {
        $rows += @{ Text = ''; Foreground = 'White'; Background = 'Black' }
    }
    if ($height -gt 1) { $rows[1].Text = "=== devbin-win $Title ===" }
    if ($height -gt 3) { $rows[3].Text = "  {0,3}  {1}" -f '#', $Columns }
    if ($height -gt 4) { $rows[4].Text = ' ' + ('-' * [Math]::Max(0, $width - 1)) }
    $top = 0
    if ($null -ne $script:EnvListFrame -and $script:EnvListFrame.Title -ceq $Title) {
        $top = [int]$script:EnvListFrame.Top
    }
    if ($Index -lt $top) { $top = $Index }
    elseif ($Index -ge $top + $page) { $top = $Index - $page + 1 }
    $top = [Math]::Max(0, [Math]::Min($top, $Lines.Count - $page))
    for ($i = $top; $i -lt [Math]::Min($Lines.Count, $top + $page); $i++) {
        $row = 5 + $i - $top
        if ($row -ge $height) { break }
        $prefix = if ($i -eq $Index) { '>' } else { ' ' }
        $rows[$row].Text = "$prefix{0,3}  {1}" -f ($i + 1), $Lines[$i]
        if ($i -eq $Index) { $rows[$row].Background = 'DarkBlue'; $rows[$row].Foreground = 'White' }
    }
    if ($Lines.Count -eq 0 -and $height -gt 5) { $rows[5].Text = '      (項目なし)' }
    $footer = [Math]::Min(5 + $page, $height - 1)
    $below = [Math]::Max(0, $Lines.Count - $top - $page)
    $indicators = @()
    if ($top -gt 0) { $indicators += "^ $top" }
    if ($below -gt 0) { $indicators += "v $below" }
    if ($indicators.Count -gt 0) {
        $indicator = ' ' + ($indicators -join ' | ') + ' '
        $rows[$footer].Text = $indicator.PadLeft($width)
    }
    $rows[$footer].Foreground = 'DarkGray'
    if ($footer + 1 -lt $height) {
        $rows[$footer + 1].Text = " $Status"
        if ($Warning) { $rows[$footer + 1].Foreground = 'Yellow' }
    }
    if ($footer + 3 -lt $height) {
        $rows[$footer + 3].Text = " ↑↓/Wheel 移動 | $Help | 位置: $([Math]::Min($Index + 1, $Lines.Count)) / $($Lines.Count)"
    }

    # 初回・別画面からの復帰・リサイズ以外は消去せず、文字と色が変わった行だけ上書きする。
    $previous = $script:EnvListFrame
    if ($null -eq $previous -or $previous.Width -ne $width -or $previous.Height -ne $height) {
        Clear-EnvListScreen
        $previous = $null
    }
    for ($row = 0; $row -lt $height; $row++) {
        $current = $rows[$row]
        $current.Text = ConvertTo-EnvPaddedLine $current.Text $width
        $old = if ($null -ne $previous) { $previous.Rows[$row] } else { $null }
        if ($null -eq $old -or $old.Text -cne $current.Text -or $old.Foreground -ne $current.Foreground -or $old.Background -ne $current.Background) {
            Write-EnvScreenRow $row $current.Text $current.Foreground $current.Background
        }
    }
    $script:EnvListFrame = @{ Width = $width; Height = $height; Rows = $rows; Title = $Title; Top = $top }
    Set-EnvPromptPosition ([Math]::Min($footer + 4, $height - 1))
}

function Get-EnvInputKey {
    param([hashtable]$InputMode)
    $event = Read-MenuInput -InputModeState $InputMode
    if ($event.Kind -eq 'Key') { return $event.KeyInfo.Key.ToString() }
    if ($event.Kind -eq 'Mouse') {
        $delta = ($event.MouseEvent.dwButtonState -shr 16) -band 0xffff
        if ($delta -gt 0 -and $delta -lt 32768) { return 'UpArrow' }
        if ($delta -ge 32768) { return 'DownArrow' }
    }
    return 'Resize'
}

function Get-EnvPageSize {
    [Math]::Max(1, [Console]::WindowHeight - 10)
}

function Move-EnvIndex {
    param([int]$Index, [int]$Count, [string]$Key, [int]$PageSize = 10)
    $page = [Math]::Max(1, $PageSize)
    switch ($Key) {
        'UpArrow' { $Index-- }
        'DownArrow' { $Index++ }
        'PageUp' { $Index -= $page }
        'PageDown' { $Index += $page }
        'Home' { $Index = 0 }
        'End' { $Index = $Count - 1 }
    }
    [Math]::Max(0, [Math]::Min($Index, $Count - 1))
}

function Edit-EnvPath {
    param([string]$Value, [hashtable]$InputMode)
    $parts = New-Object 'System.Collections.Generic.List[string]'
    # 空要素・重複・末尾のセミコロンも自動削除せずに保持する。
    foreach ($part in $Value.Split([char]';')) { $parts.Add($part) }
    $index = 0
    while ($true) {
        Show-EnvList 'PATH 項目編集' @($parts.ToArray()) $index 'A 追加 | E 編集 | D 削除 | U/J 上/下へ | S 確定 | Esc 破棄' '未保存' -Columns 'PATH の項目' -Warning
        $key = Get-EnvInputKey $InputMode
        $index = Move-EnvIndex $index $parts.Count $key (Get-EnvPageSize)
        switch ($key) {
            'Escape' { return $null }
            'S' { return [pscustomobject]@{ Value = $parts.ToArray() -join ';' } }
            'D' { if ($parts.Count -gt 0) { $parts.RemoveAt($index) } }
            'U' { if ($index -gt 0) { $tmp = $parts[$index]; $parts[$index] = $parts[$index-1]; $parts[--$index] = $tmp } }
            'J' { if ($index -lt $parts.Count-1) { $tmp = $parts[$index]; $parts[$index] = $parts[$index+1]; $parts[++$index] = $tmp } }
            { $_ -in @('A', 'E') } {
                if ($key -eq 'E' -and $parts.Count -eq 0) { break }
                $initial = if ($key -eq 'E') { $parts[$index] } else { '' }
                $edit = Read-EnvText '項目' $initial
                if ($null -ne $edit -and -not $edit.Value.Contains(';')) {
                    if ($key -eq 'A') { $parts.Add($edit.Value); $index = $parts.Count-1 }
                    else { $parts[$index] = $edit.Value }
                } elseif ($null -ne $edit) {
                    Write-Host '項目にセミコロン (;) は使用できません。任意のキーを押すと戻ります。' -ForegroundColor Yellow
                    [void][Console]::ReadKey($true)
                }
            }
        }
        $index = [Math]::Max(0, [Math]::Min($index, $parts.Count-1))
    }
}

function Show-EnvValueDetail {
    param($Entry)
    Write-Host '元の値:' -ForegroundColor White
    Write-Host ''
    Write-Host ($Entry.Value -replace '[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]', '?')
    if ($Entry.Kind -in @('String', 'ExpandString') -and
        ($Entry.Name -eq 'Path' -or ([string]$Entry.Value).Contains(';'))) {
        Write-Host ''
        Write-Host '項目別表示 (セミコロン区切り):' -ForegroundColor White
        Write-Host ''
        $number = 0
        foreach ($part in ([string]$Entry.Value).Split([char]';')) {
            $number++
            $display = if ($part -eq '') { '(空項目)' } else {
                $part -replace '[\x00-\x1f\x7f]', '?'
            }
            Write-Host ('{0,4}: {1}' -f $number, $display)
        }
    }
}

function Confirm-EnvChange {
    param([string]$Name, $Original, [string]$Value, [string]$Kind, [switch]$Delete)
    $script:EnvListFrame = $null
    [Console]::Clear()
    Write-Host '=== 適用内容の確認 ===' -ForegroundColor White
    Write-Host ''
    Write-Host " ユーザー環境変数: $Name [$Kind]" -ForegroundColor White
    Write-Host '変更前:'
    if ($null -eq $Original) { Write-Host '(未定義)' } else { Write-Host ($Original.Value -replace '[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]', '?') }
    Write-Host '変更後:'
    if ($Delete) { Write-Host '(削除)' -ForegroundColor Yellow }
    elseif ($Value -eq '') { Write-Host '(空文字列)' } else { Write-Host ($Value -replace '[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]', '?') }
    Write-Host '保存しますか? [Y]: 保存 / その他: キャンセル (長い値はスクロールして確認)'
    return ([Console]::ReadKey($true).Key -eq 'Y')
}

function Start-EnvironmentManager {
    $script:EnvListFrame = $null
    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) { throw '対話コンソールから実行してください。' }
    $inputMode = @{ Enabled = $false }
    $cursorVisible = [Console]::CursorVisible
    $foreground = [Console]::ForegroundColor
    $background = [Console]::BackgroundColor
    try {
        try { $inputMode = Enable-ConsoleMouseInput } catch { $inputMode = @{ Enabled = $false } }
        $scope = 'User'; $filter = ''; $index = 0; $status = ''; $statusWarning = $false
        $entries = @(Get-EnvRegistryEntries $scope)
        while ($true) {
            $items = @(Get-EnvFilteredEntries $entries $filter)
            $index = [Math]::Max(0, [Math]::Min($index, $items.Count-1))
            $label = if ($scope -eq 'User') { 'ユーザー (編集可能)' } else { 'システム (表示専用)' }
            $lines = @($items | ForEach-Object {
                '{0} {1,-15} {2}' -f (ConvertTo-EnvPaddedLine $_.Name 36), $_.Kind, $_.Value
            })
            $legend = if ($status) { $status } else { 'REG_SZ: String / REG_EXPAND_SZ: ExpandString' }
            $title = "環境変数 マネージャー  [$label]"
            if ($filter) { $title += " 検索: $filter" }
            $columns = '{0} {1} 値' -f (ConvertTo-EnvPaddedLine '変数名' 36), (ConvertTo-EnvPaddedLine '型' 15)
            Show-EnvList $title $lines $index 'Tab 切替 | / 検索 | Enter 詳細 | N 新規 | E 編集 | D 削除 | R 更新 | Q 終了' $legend -Columns $columns -Warning:$statusWarning
            $key = Get-EnvInputKey $inputMode
            $index = Move-EnvIndex $index $items.Count $key (Get-EnvPageSize)
            $selected = if ($items.Count -gt 0) { $items[$index] } else { $null }
            try {
                switch ($key) {
                    'Q' { return }
                    'Escape' { return }
                    'Tab' {
                        $nextScope = if ($scope -eq 'User') { 'Machine' } else { 'User' }
                        $nextEntries = @(Get-EnvRegistryEntries $nextScope)
                        $scope = $nextScope; $entries = $nextEntries; $index = 0; $status = ''; $statusWarning = $false
                    }
                    'R' { $entries = @(Get-EnvRegistryEntries $scope); $status = '再読み込みしました。'; $statusWarning = $false }
                    'Oem2' {
                        $search = Read-EnvText '名前で検索 (空欄で解除)' $filter
                        if ($null -ne $search) { $filter = $search.Value; $index = 0 }
                    }
                    'Enter' {
                        if ($null -ne $selected) {
                            $script:EnvListFrame = $null
                            [Console]::Clear()
                            Write-Host "$($selected.Name) [$($selected.Kind)] / $label" -ForegroundColor White
                            Write-Host ''
                            Show-EnvValueDetail -Entry $selected
                            Write-Host ''
                            Write-Host '保存値を展開せずに表示しています。任意のキーを押すと戻ります (長い値はスクロールして確認)。'
                            Write-Host ''
                            [void][Console]::ReadKey($true)
                        }
                    }
                    { $_ -in @('N', 'E', 'D') } {
                        if ($scope -ne 'User') { $status = 'システム環境変数は表示専用です。'; $statusWarning = $true; break }
                        if ($key -ne 'N' -and $null -eq $selected) { break }
                        $original = $selected
                        $name = if ($null -ne $selected) { $selected.Name } else { '' }
                        $kind = if ($null -ne $selected) { $selected.Kind } else { 'String' }
                        $value = ''
                        if ($key -eq 'N') {
                            $original = $null
                            $answer = Read-EnvText '新しい変数名'
                            if ($null -eq $answer) { break }
                            $name = $answer.Value
                            Assert-EnvValue $name ''
                            if (@($entries | Where-Object { $_.Name -eq $name }).Count -gt 0) { throw '同名の変数が既に存在します。[E] で編集してください。' }
                            $kind = 'String'
                        } elseif ($kind -notin @('String', 'ExpandString')) { throw '文字列以外の型は表示のみ対応しています。' }
                        if ($key -ne 'D') {
                            $initial = if ($null -ne $original) { [string]$original.Value } else { '' }
                            if ($name -eq 'Path') { $answer = Edit-EnvPath $initial $inputMode }
                            else { $answer = Read-EnvText '値 (既存の値を直接編集できます)' $initial }
                            if ($null -eq $answer) { break }
                            $value = $answer.Value
                            if ($key -eq 'N') {
                                Write-Host '値の型: E = 変数参照を展開する (REG_EXPAND_SZ) / S = 通常の文字列 (REG_SZ) / その他 = キャンセル'
                                $typeKey = [Console]::ReadKey($true).Key
                                if ($typeKey -eq 'E') { $kind = 'ExpandString' }
                                elseif ($typeKey -eq 'S') { $kind = 'String' }
                                else { break }
                            }
                            Assert-EnvValue $name $value
                        }
                        $delete = $key -eq 'D'
                        if (Confirm-EnvChange $name $original $value $kind -Delete:$delete) {
                            $status = Save-EnvUserChange -Scope $scope -Name $name -Value $value -Kind $kind -Original $original -Delete:$delete
                            $statusWarning = $status -like '保存済み。ただし*'
                            $entries = @(Get-EnvRegistryEntries $scope)
                        } else { $status = '変更をキャンセルしました。'; $statusWarning = $false }
                    }
                }
            } catch { $status = $_.Exception.Message; $statusWarning = $true }
        }
    } finally {
        Restore-ConsoleInputMode $inputMode
        [Console]::ForegroundColor = $foreground
        [Console]::BackgroundColor = $background
        [Console]::CursorVisible = $cursorVisible
        [Console]::Clear()
    }
}
