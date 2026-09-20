# 実レジストリへの書き込み・変更通知・対話入力は行わない。
. "$PSScriptRoot\..\subscripts\Devbin\Environment\EnvironmentManager.ps1"

Describe 'Environment manager persistence' {
    BeforeEach {
        Mock Get-EnvRegistryEntries { @() }
        Mock Write-EnvUserValue { }
        Mock Send-EnvChangeNotification { }
    }
    It 'システムへの保存を拒否する' {
        { Save-EnvUserChange Machine TEST value String $null } | Should Throw
        Assert-MockCalled Write-EnvUserValue -Times 0 -Exactly -Scope It
    }
    It '未展開の参照と型をそのまま保存する' {
        $old = [pscustomobject]@{ Name = 'TEST'; Value = '%USERPROFILE%\old'; Kind = 'ExpandString' }
        Mock Get-EnvRegistryEntries { $old }
        Save-EnvUserChange User TEST '%USERPROFILE%\new' ExpandString $old | Out-Null
        Assert-MockCalled Write-EnvUserValue -Times 1 -Exactly -Scope It -ParameterFilter { $Value -ceq '%USERPROFILE%\new' -and $Kind -eq 'ExpandString' -and -not $Delete }
        Assert-MockCalled Send-EnvChangeNotification -Times 1 -Exactly -Scope It
    }
    It '空文字列と削除を区別する' {
        Save-EnvUserChange User TEST '' String $null | Out-Null
        Assert-MockCalled Write-EnvUserValue -Times 1 -Exactly -Scope It -ParameterFilter { $Value -eq '' -and -not $Delete }
    }
    It '既存の変数を明示的に削除する' {
        $old = [pscustomobject]@{ Name = 'TEST'; Value = 'old'; Kind = 'String' }
        Mock Get-EnvRegistryEntries { $old }
        Save-EnvUserChange User TEST '' String $old -Delete | Out-Null
        Assert-MockCalled Write-EnvUserValue -Times 1 -Exactly -Scope It -ParameterFilter { $Delete -and $Name -eq 'TEST' }
    }
    It '同名の新規作成を拒否する' {
        Mock Get-EnvRegistryEntries { [pscustomobject]@{ Name = 'test'; Value = ''; Kind = 'String' } }
        { Save-EnvUserChange User TEST new String $null } | Should Throw
        Assert-MockCalled Write-EnvUserValue -Times 0 -Exactly -Scope It
    }
    It '外部による値変更を検出する' {
        Mock Get-EnvRegistryEntries { [pscustomobject]@{ Name = 'TEST'; Value = 'OLD'; Kind = 'String' } }
        $old = [pscustomobject]@{ Name = 'TEST'; Value = 'old'; Kind = 'String' }
        { Save-EnvUserChange User TEST new String $old } | Should Throw
        Assert-MockCalled Write-EnvUserValue -Times 0 -Exactly -Scope It
    }
    It '外部による削除を検出する' {
        $old = [pscustomobject]@{ Name = 'TEST'; Value = 'old'; Kind = 'String' }
        { Save-EnvUserChange User TEST new String $old } | Should Throw
        Assert-MockCalled Write-EnvUserValue -Times 0 -Exactly -Scope It
    }
    It '通知失敗を保存失敗と区別する' {
        Mock Send-EnvChangeNotification { throw 'notification failed' }
        Save-EnvUserChange User TEST value String $null | Should Match '保存済み'
        Assert-MockCalled Write-EnvUserValue -Times 1 -Exactly -Scope It
    }
    It '書き込み失敗時は通知しない' {
        Mock Write-EnvUserValue { throw 'access denied' }
        { Save-EnvUserChange User TEST value String $null } | Should Throw
        Assert-MockCalled Send-EnvChangeNotification -Times 0 -Exactly -Scope It
    }
    It '不正な名前・値・型を拒否する' {
        { Save-EnvUserChange User 'A=B' value String $null } | Should Throw
        { Save-EnvUserChange User '' value String $null } | Should Throw
        { Save-EnvUserChange User TEST "a`0b" String $null } | Should Throw
        { Save-EnvUserChange User TEST value DWord $null } | Should Throw
        Assert-MockCalled Write-EnvUserValue -Times 0 -Exactly -Scope It
    }
}

Describe 'Environment manager navigation' {
    It '大文字・小文字を区別しない部分一致（リテラル）で検索できる' {
        $entries = @([pscustomobject]@{ Name = 'Path' }, [pscustomobject]@{ Name = 'A[B]' })
        @(Get-EnvFilteredEntries $entries 'PATH')[0].Name | Should Be 'Path'
        @(Get-EnvFilteredEntries $entries '[')[0].Name | Should Be 'A[B]'
        @(Get-EnvFilteredEntries $entries '*').Count | Should Be 0
        @(Get-EnvFilteredEntries @() '').Count | Should Be 0
    }
    It '項目がない場合や先頭・末尾への移動時にカーソルが範囲外にならない' {
        Move-EnvIndex 0 0 DownArrow | Should Be 0
        Move-EnvIndex 0 2 UpArrow | Should Be 0
        Move-EnvIndex 1 2 DownArrow | Should Be 1
        Move-EnvIndex 0 5 End | Should Be 4
    }
    It '制御文字を空白に置換し日本語の表示幅に合わせて文字数を制限する' {
        Get-EnvDisplayText ("a" + [char]27 + "b") 10 | Should Be 'a b'
        Get-EnvDisplayText '日本語abc' 5 | Should Be '日本'
    }
}

Describe 'Environment manager differential rendering' {
    BeforeEach {
        $script:EnvListFrame = $null
        Mock Get-EnvConsoleSize { @{ Width = 80; Height = 24 } }
        Mock Clear-EnvListScreen { }
        Mock Write-EnvScreenRow { }
        Mock Set-EnvPromptPosition { }
    }
    It '選択移動は旧選択行・新選択行・件数だけを書き換える' {
        Show-EnvList 'title' @('a', 'b', 'c') 0 'help' ''
        Show-EnvList 'title' @('a', 'b', 'c') 1 'help' ''
        Assert-MockCalled Clear-EnvListScreen -Times 1 -Exactly -Scope It
        Assert-MockCalled Write-EnvScreenRow -Times 26 -Exactly -Scope It
        Assert-MockCalled Write-EnvScreenRow -Times 2 -Exactly -Scope It -ParameterFilter { $Row -eq 5 }
        Assert-MockCalled Write-EnvScreenRow -Times 2 -Exactly -Scope It -ParameterFilter { $Row -eq 6 }
        Assert-MockCalled Write-EnvScreenRow -Times 1 -Exactly -Scope It -ParameterFilter { $Row -eq 7 }
    }
    It '同じ画面の再表示では1行も書き換えない' {
        Show-EnvList 'title' @('a') 0 'help' ''
        Show-EnvList 'title' @('a') 0 'help' ''
        Assert-MockCalled Clear-EnvListScreen -Times 1 -Exactly -Scope It
        Assert-MockCalled Write-EnvScreenRow -Times 23 -Exactly -Scope It
    }
    It '項目数が減った場合は不要になった行を空白で上書きする' {
        Show-EnvList 'title' @('a', 'b', 'c') 0 'help' ''
        Show-EnvList 'title' @('a') 0 'help' ''
        Assert-MockCalled Clear-EnvListScreen -Times 1 -Exactly -Scope It
        Assert-MockCalled Write-EnvScreenRow -Times 1 -Exactly -Scope It -ParameterFilter { $Row -eq 11 -and $Text -eq (' ' * 79) }
    }
    It 'リサイズ後は新しい寸法で再描画する' {
        Show-EnvList 'title' @('a') 0 'help' ''
        Mock Get-EnvConsoleSize { @{ Width = 60; Height = 20 } }
        Show-EnvList 'title' @('a') 0 'help' ''
        Assert-MockCalled Clear-EnvListScreen -Times 2 -Exactly -Scope It
        $script:EnvListFrame.Width | Should Be 59
        $script:EnvListFrame.Rows.Count | Should Be 19
    }
    It '詳細や入力画面から戻ったときは全行を再描画する' {
        Show-EnvList 'title' @('a') 0 'help' ''
        $script:EnvListFrame = $null
        Show-EnvList 'title' @('a') 0 'help' ''
        Assert-MockCalled Clear-EnvListScreen -Times 2 -Exactly -Scope It
        Assert-MockCalled Write-EnvScreenRow -Times 46 -Exactly -Scope It
    }
    It '日本語の表示幅に合わせて行末を空白で埋める' {
        ConvertTo-EnvPaddedLine '日本' 7 | Should Be '日本   '
    }
    It 'Bin と同じ配置・配色で通常表示と注意表示を分ける' {
        Show-EnvList 'title' @('a') 0 'Q 終了' '説明'
        $frame = $script:EnvListFrame
        $frame.Rows[0].Text.Trim() | Should Be ''
        $frame.Rows[1].Foreground | Should Be 'White'
        $frame.Rows[2].Text.Trim() | Should Be ''
        $frame.Rows[4].Text.Trim() | Should Match '^-+$'
        $frame.Rows[5].Background | Should Be 'DarkBlue'
        $frame.Rows[6].Text.Trim() | Should Be ''
        $frame.Rows[7].Foreground | Should Be 'White'
        $frame.Rows[8].Text.Trim() | Should Be ''
        $frame.Rows[9].Text | Should Match 'Q 終了.*位置: 1 / 1'
        Show-EnvList 'title' @('a') 0 'Q 終了' '未保存' -Warning
        $script:EnvListFrame.Rows[7].Foreground | Should Be 'Yellow'
    }
    It '一覧の端で一行ずつスクロールし残り件数を右端に表示する' {
        $lines = @(1..20 | ForEach-Object { "item $_" })
        Show-EnvList 'title' $lines 13 'Q 終了' ''
        $script:EnvListFrame.Top | Should Be 0
        Show-EnvList 'title' $lines 14 'Q 終了' ''
        $script:EnvListFrame.Top | Should Be 1
        $script:EnvListFrame.Rows[19].Text | Should Be (' ^ 1 | v 5 '.PadLeft(79))
        Assert-MockCalled Clear-EnvListScreen -Times 1 -Exactly -Scope It
    }
}

Describe 'Environment manager PATH editor' {
    BeforeEach {
        Mock Show-EnvList { }
        Mock Read-EnvText { [pscustomobject]@{ Value = 'new' } }
        Mock Get-EnvPageSize { 10 }
    }
    It '編集しない場合は空要素・重複・参照を保持する' {
        Mock Get-EnvInputKey { 'S' }
        (Edit-EnvPath 'a;;%HOME%;a;' @{}).Value | Should Be 'a;;%HOME%;a;'
    }
    It 'Escape キー押下時は値を返さず編集を破棄する' {
        Mock Get-EnvInputKey { 'Escape' }
        $result = Edit-EnvPath 'a;b' @{}
        ($null -eq $result) | Should Be $true
    }
    It '項目を下へ移動できる' {
        $script:envKeyNumber = 0
        Mock Get-EnvInputKey { $script:envKeyNumber++; if ($script:envKeyNumber -eq 1) { 'J' } else { 'S' } }
        (Edit-EnvPath 'a;b;c' @{}).Value | Should Be 'b;a;c'
    }
    It '最後の項目を削除して空文字列にできる' {
        $script:envKeyNumber = 0
        Mock Get-EnvInputKey { $script:envKeyNumber++; if ($script:envKeyNumber -eq 1) { 'D' } else { 'S' } }
        (Edit-EnvPath 'a' @{}).Value | Should Be ''
    }
}
