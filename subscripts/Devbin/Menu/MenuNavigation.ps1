# MenuNavigation.ps1
# カーソル移動と選択状態の切り替え

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

function Move-MenuCursor {
    param(
        [hashtable]$State,
        [int]$Delta
    )

    if ($Delta -eq 0 -or $State.Items.Count -eq 0) {
        return "continue"
    }

    $oldIdx = $State.CursorIndex
    $newIdx = [Math]::Max(0, [Math]::Min($State.Items.Count - 1, $oldIdx + $Delta))
    if ($newIdx -eq $oldIdx) {
        return "continue"
    }

    $State.CursorIndex = $newIdx

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

    return "continue"
}

function Set-AllMenuItemsChecked {
    param([hashtable]$State)

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

function Clear-AllMenuItemsChecked {
    param([hashtable]$State)

    foreach ($item in $State.Items) {
        $State.Checked[$item.ShortName] = $false
        $State.Reinstall[$item.ShortName] = $false
    }

    $State.NeedRedraw = $true
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
