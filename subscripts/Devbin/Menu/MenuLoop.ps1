# MenuLoop.ps1
# キー入力ディスパッチおよびメニューメインループ

# カーソル行の選択状態を切り替え、ビューポート内の項目と件数を再描画します。
function Invoke-MenuCursorToggle {
    param([hashtable]$State)

    Toggle-CheckedItem -State $State -Index $State.CursorIndex
    # 依存関係の連動選択があるため、ビューポート内の全項目行を再描画します。
    $items = @(Get-MenuItemList -State $State)
    $viewEnd = [Math]::Min($items.Count, $State.ViewportTop + $State.ViewportSize)
    for ($i = $State.ViewportTop; $i -lt $viewEnd; $i++) {
        $item = $items[$i]
        if ($null -eq $item -or [string]::IsNullOrWhiteSpace([string]$item.ShortName)) {
            continue
        }
        Render-MenuLine -Row ($script:HEADER_ROWS + $i - $State.ViewportTop) -Number ($i + 1) `
            -Item $item -IsChecked (Get-MenuFlag -Map $State.Checked -ItemOrName $item) `
            -IsReinstall (Get-MenuFlag -Map $State.Reinstall -ItemOrName $item) `
            -IsDisabled (Get-MenuFlag -Map $State.Disabled -ItemOrName $item) `
            -DisableReason (Get-MenuDisableReason -State $State -ItemOrName $item) `
            -Status (Get-MenuFlag -Map $State.Statuses -ItemOrName $item -Default "NotInstalled") `
            -IsCursor ($i -eq $State.CursorIndex) `
            -Packages $State.Packages
    }
    Render-Footer -State $State
    return "continue"
}

# キー入力を処理します (戻り値: "continue" または "quit")。
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
            return Invoke-MenuCursorToggle -State $State
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

# メニューのメイン対話ループを実行します。
function Invoke-MenuLoop {
    param(
        [array]$Packages,
        [string]$InstallDir,
        [string]$ScriptDir
    )

    # インストール先ディレクトリの作成、マニフェスト読み込み、レガシー検出は State モジュール側で実施します。
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
            try {
                if ($state.NeedRedraw) {
                    Render-Menu -State $state
                }
            } catch {
                Write-Host ""
                Write-Host " メニューの再描画に失敗しました: $($_.Exception.Message)" -ForegroundColor Yellow
                Write-Host " Q で終了できます。"
                $state.NeedRedraw = $false
            }

            $inputEvent = Read-MenuInput -InputModeState $inputModeState
            try {
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
            } catch {
                Write-Host " メニュー操作でエラーが発生しました: $($_.Exception.Message)" -ForegroundColor Yellow
                $state.NeedRedraw = $true
                $result = "continue"
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
