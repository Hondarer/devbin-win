# MenuLoop.ps1
# キー操作の振り分けとメニューの主ループ

# キー入力を処理する (戻り値: "continue" or "quit")
function Handle-KeyInput {
    param(
        [hashtable]$State,
        [System.ConsoleKeyInfo]$KeyInfo,
        [hashtable]$InputModeState
    )

    switch ($KeyInfo.Key) {
        "UpArrow" {
            return Move-MenuCursor -State $State -Delta -1
        }

        "DownArrow" {
            return Move-MenuCursor -State $State -Delta 1
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
            Apply-CheckedState -State $State -InputModeState $InputModeState
        }

        "Escape" {
            return "quit"
        }

        "A" {
            Set-AllMenuItemsChecked -State $State
        }

        "N" {
            Clear-AllMenuItemsChecked -State $State
        }

        "U" {
            return Invoke-MenuProductUninstall -State $State -InputModeState $InputModeState
        }

        "Q" {
            return "quit"
        }

        default {
            switch ($KeyInfo.KeyChar) {
                { $_ -eq 'a' -or $_ -eq 'A' } {
                    Set-AllMenuItemsChecked -State $State
                }
                { $_ -eq 'n' -or $_ -eq 'N' } {
                    Clear-AllMenuItemsChecked -State $State
                }
                { $_ -eq 'u' -or $_ -eq 'U' } {
                    return Invoke-MenuProductUninstall -State $State -InputModeState $InputModeState
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

    # 導入先の作成、マニフェストの読み込み、Legacy 検出は State が担当する
    $initialized = Initialize-ComponentManifest -InstallDir $InstallDir -Packages $Packages
    $manifest = $initialized.Manifest

    if ($initialized.LegacyDetected) {
        Write-Host ""
        Write-Host "既存のインストールを検出しました (マニフェストなし)" -ForegroundColor Cyan
        if ($initialized.Saved) {
            Write-Host "マニフェストを生成しました" -ForegroundColor Green
        } else {
            Write-Host "マニフェストの保存に失敗しました" -ForegroundColor Red
        }
        Start-Sleep -Seconds 1
    }

    $state = Initialize-MenuState `
        -Packages $Packages `
        -Manifest $manifest `
        -InstallDir $InstallDir `
        -ScriptDir $ScriptDir

    $originalCursorVisible = [Console]::CursorVisible
    $inputModeState = Enable-ConsoleMouseInput

    try {
        while ($true) {
            if ($state.NeedRedraw) {
                Render-Menu -State $state
            }

            $inputEvent = Read-MenuInput -InputModeState $inputModeState
            switch ($inputEvent.Kind) {
                "Mouse" {
                    $result = Handle-MouseInput -State $state -MouseEvent $inputEvent.MouseEvent
                }
                "Resize" {
                    $state.NeedRedraw = $true
                    $result = "continue"
                }
                default {
                    $result = Handle-KeyInput -State $state -KeyInfo $inputEvent.KeyInfo -InputModeState $inputModeState
                }
            }

            if ($result -eq "quit") {
                break
            }
        }
    } finally {
        Restore-ConsoleInputMode -InputModeState $inputModeState
        [Console]::CursorVisible = $originalCursorVisible
        [Console]::ResetColor()
        [Console]::Clear()
    }

    Write-Host ""
    Write-Host "終了します。環境変数の変更を反映するにはターミナルを再起動してください。"
    Write-Host ""
}
