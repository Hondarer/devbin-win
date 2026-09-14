# MenuActions.ps1
# 選択内容の適用と、計画・結果の表示

# Apply: 差分計算 → 確認 → 実行
function Apply-CheckedState {
    param(
        [hashtable]$State,
        [hashtable]$InputModeState
    )

    # 操作計画の作成は Devbin/Install が担当する。UI は表示と確認だけを行う
    $plan = New-ComponentChangePlan `
        -Packages $State.Packages `
        -Items $State.Items `
        -Checked $State.Checked `
        -Reinstall $State.Reinstall `
        -Statuses $State.Statuses `
        -Manifest $State.Manifest `
        -InstallDir $State.InstallDir `
        -PackagesDir $State.PackagesDir

    if (-not $plan.Success) {
        [Console]::Clear()
        [Console]::CursorVisible = $true
        Write-Host ""
        Write-Host " 依存関係エラー: 計画を作成できません" -ForegroundColor Red
        Write-Host ""
        foreach ($message in $plan.Errors) {
            Write-Host "   $message" -ForegroundColor Yellow
        }
        Write-Host ""
        Write-Host " 依存先をチェックしてから再度 Enter を押してください。" -ForegroundColor DarkGray
        Write-Host " 何かキーを押してメニューに戻ります..." -ForegroundColor DarkGray
        [Console]::ReadKey($true) | Out-Null
        Resume-MenuConsole -State $State -InputModeState $InputModeState
        return
    }

    if ($plan.IsEmpty) {
        [Console]::Clear()
        [Console]::CursorVisible = $true
        Write-Host ""
        Write-Host " 変更はありません。" -ForegroundColor Green
        Start-Sleep -Seconds 1
        Resume-MenuConsole -State $State -InputModeState $InputModeState
        return
    }

    # TUI を一時停止してスクロール表示へ切替
    [Console]::Clear()
    [Console]::CursorVisible = $true
    Restore-ConsoleInputMode -InputModeState $InputModeState

    Show-ChangePlan -Plan $plan

    if (-not (Confirm-ChangePlan)) {
        Write-Host ""
        Write-Host "キャンセルしました"
        Start-Sleep -Milliseconds 500
        Resume-MenuConsole -State $State -InputModeState $InputModeState
        return
    }

    Write-Host ""

    # 適用中はスリープ / スクリーンセーバーを抑止する
    Start-BusySignal
    try {
        $outcome = Invoke-ComponentChangePlan `
            -Plan $plan `
            -Packages $State.Packages `
            -InstallDir $State.InstallDir `
            -ScriptDir $State.ScriptDir `
            -Manifest $State.Manifest

        Sync-EnvironmentVariables -VariableNames @("PATH", "BROWSER_PATH", "PUPPETEER_EXECUTABLE_PATH") -Silent | Out-Null

        Show-ChangeOutcome -Outcome $outcome
    } finally {
        Stop-BusySignal
        # 失敗しても状態表示とコンソールの復元は必ず行う
        Update-MenuStatuses -State $State -Plan $plan
    }

    Write-Host ""
    Write-Host " 何かキーを押してメニューに戻ります..."
    [Console]::ReadKey($true) | Out-Null

    Resume-MenuConsole -State $State -InputModeState $InputModeState
}

# 適用内容を表示する
function Show-ChangePlan {
    param([PSCustomObject]$Plan)

    Write-Host ""
    Write-Host "=== 適用内容の確認 ==="
    Write-Host ""

    if ($Plan.Install.Count -gt 0) {
        Write-Host " インストール:"
        foreach ($entry in $Plan.Install) {
            Write-Host "   + $($entry.Name)"
        }
        Write-Host ""
    }

    if ($Plan.Reinstall.Count -gt 0) {
        Write-Host " 再インストール:"
        foreach ($entry in $Plan.Reinstall) {
            Write-Host "   ~ $($entry.Name)"
        }
        Write-Host ""
    }

    if ($Plan.Uninstall.Count -gt 0) {
        Write-Host " アンインストール:"
        foreach ($entry in $Plan.Uninstall) {
            Write-Host "   - $($entry.Name)"
        }
        Write-Host ""
    }
}

# 続行するかを確認する
function Confirm-ChangePlan {
    return Read-ConfirmationKey -Prompt " 続行しますか? [Y/n/Esc] " -DefaultYes
}

# 適用結果を表示する
function Show-ChangeOutcome {
    param([PSCustomObject]$Outcome)

    Write-Host ""
    Write-Host "=== 適用結果 ==="
    Write-Host ""

    foreach ($result in $Outcome.Results) {
        $color = switch ($result.Status) {
            "Failed"  { "Red" }
            "Skipped" { "Yellow" }
            "Aborted" { "Red" }
            default   { "Green" }
        }
        $text = "   $($result.Status): $($result.ShortName)"
        if (-not [string]::IsNullOrWhiteSpace($result.Message)) {
            $text += " - $($result.Message)"
        }
        Write-Host $text -ForegroundColor $color

        foreach ($warning in $result.Warnings) {
            Write-Host "     警告: $warning" -ForegroundColor Yellow
        }
    }

    Write-Host ""
    if ($Outcome.Aborted) {
        Write-Host " 適用を中止しました。完了済みの操作は上記のとおりです。" -ForegroundColor Red
    } elseif ($Outcome.Success) {
        Write-Host " 完了しました。" -ForegroundColor Green
    } else {
        Write-Host " 一部の操作が完了しませんでした。" -ForegroundColor Yellow
    }
}

# メニュー表示へ戻る前に、コンソールの入力モードとカーソル状態を復元する
# キャンセル時・失敗時にも必ず通す
function Resume-MenuConsole {
    param(
        [hashtable]$State,
        [hashtable]$InputModeState
    )

    $newInputModeState = Enable-ConsoleMouseInput
    if ($newInputModeState.Enabled) {
        $InputModeState.Handle = $newInputModeState.Handle
        $InputModeState.OriginalMode = $newInputModeState.OriginalMode
        $InputModeState.Enabled = $true
    }

    [Console]::CursorVisible = $false
    $State.NeedRedraw = $true
}

function Invoke-MenuProductUninstall {
    param(
        [hashtable]$State,
        [hashtable]$InputModeState
    )

    [Console]::Clear()
    [Console]::CursorVisible = $true
    Restore-ConsoleInputMode -InputModeState $InputModeState

    $result = Invoke-ProductUninstall -InstallDir $State.InstallDir
    if ($result.Status -eq "Success") {
        Write-Host ""
        Write-Host " 何かキーを押して終了します..."
        [Console]::ReadKey($true) | Out-Null
        return "quit"
    }

    Write-Host ""
    switch ($result.Status) {
        "Failed" {
            Write-Host " 完全アンインストールに失敗しました。何かキーを押してメニューに戻ります..." -ForegroundColor Yellow
        }
        "Refused" {
            Write-Host " 標準のインストール先ではないため実行しませんでした。何かキーを押してメニューに戻ります..." -ForegroundColor Yellow
        }
        default {
            Write-Host " キャンセルしました。何かキーを押してメニューに戻ります..."
        }
    }
    [Console]::ReadKey($true) | Out-Null

    $newInputModeState = Enable-ConsoleMouseInput
    if ($newInputModeState.Enabled) {
        $InputModeState.Handle = $newInputModeState.Handle
        $InputModeState.OriginalMode = $newInputModeState.OriginalMode
        $InputModeState.Enabled = $true
    }

    [Console]::CursorVisible = $false
    $State.NeedRedraw = $true
    return "continue"
}
