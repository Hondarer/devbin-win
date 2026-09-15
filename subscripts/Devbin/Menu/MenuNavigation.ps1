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

    if ($State.ContainsKey("Items") -and $null -ne $State.Items) {
        $count = @($State.Items).Count
        $size = [Math]::Max(1, [int]$State.ViewportSize)
        $maxTop = [Math]::Max(0, $count - $size)
        if ($State.ViewportTop -gt $maxTop) {
            $State.ViewportTop = $maxTop
        }
        if ($State.ViewportTop -lt 0) {
            $State.ViewportTop = 0
        }
    }
}

function Move-MenuCursor {
    param(
        [hashtable]$State,
        [int]$Delta
    )

    $items = @(Get-MenuItemList -State $State)
    if ($Delta -eq 0 -or $items.Count -eq 0) {
        return "continue"
    }

    $oldIdx = $State.CursorIndex
    $newIdx = [Math]::Max(0, [Math]::Min($items.Count - 1, $oldIdx + $Delta))
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
        $old = $items[$oldIdx]
        if ($null -ne $old) {
            Render-MenuLine -Row ($script:HEADER_ROWS + $oldIdx - $State.ViewportTop) -Number ($oldIdx + 1) `
                -Item $old -IsChecked (Get-MenuFlag -Map $State.Checked -ItemOrName $old) `
                -IsReinstall (Get-MenuFlag -Map $State.Reinstall -ItemOrName $old) `
                -IsDisabled (Get-MenuFlag -Map $State.Disabled -ItemOrName $old) `
                -Status (Get-MenuFlag -Map $State.Statuses -ItemOrName $old -Default "NotInstalled") `
                -IsCursor $false -Packages $State.Packages
        }

        $new = $items[$newIdx]
        if ($null -ne $new) {
            Render-MenuLine -Row ($script:HEADER_ROWS + $newIdx - $State.ViewportTop) -Number ($newIdx + 1) `
                -Item $new -IsChecked (Get-MenuFlag -Map $State.Checked -ItemOrName $new) `
                -IsReinstall (Get-MenuFlag -Map $State.Reinstall -ItemOrName $new) `
                -IsDisabled (Get-MenuFlag -Map $State.Disabled -ItemOrName $new) `
                -Status (Get-MenuFlag -Map $State.Statuses -ItemOrName $new -Default "NotInstalled") `
                -IsCursor $true -Packages $State.Packages
        }
    }

    return "continue"
}

function Set-AllMenuItemsChecked {
    param([hashtable]$State)

    foreach ($item in @(Get-MenuItemList -State $State)) {
        # Disabled かつ NotInstalled はチェック ON を禁止
        if ((Get-MenuFlag -Map $State.Disabled -ItemOrName $item) -and ((Get-MenuFlag -Map $State.Statuses -ItemOrName $item -Default "NotInstalled") -eq "NotInstalled")) {
            continue
        }
        $shortName = [string]$item.ShortName
        if ([string]::IsNullOrWhiteSpace($shortName)) { continue }
        $State.Checked[$shortName] = $true
        $State.Reinstall[$shortName] = $false
    }

    $State.NeedRedraw = $true
}

function Clear-AllMenuItemsChecked {
    param([hashtable]$State)

    foreach ($item in @(Get-MenuItemList -State $State)) {
        $shortName = [string]$item.ShortName
        if ([string]::IsNullOrWhiteSpace($shortName)) { continue }
        $State.Checked[$shortName] = $false
        $State.Reinstall[$shortName] = $false
    }

    $State.NeedRedraw = $true
}

# チェック状態をトグルし、依存元 (子) を自動チェックする
function Toggle-CheckedItem {
    param([hashtable]$State, [int]$Index)

    $item = @(Get-MenuItemList -State $State)[$Index]
    if ($null -eq $item) {
        return
    }
    $shortName = [string]$item.ShortName
    if ([string]::IsNullOrWhiteSpace($shortName)) {
        return
    }
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
            foreach ($child in @(Get-MenuItemList -State $State)) {
                $childName = [string]$child.ShortName
                if ([string]::IsNullOrWhiteSpace($childName) -or $visited.ContainsKey($childName)) { continue }
                $deps = if ($child.ContainsKey("DependsOn")) { @($child.DependsOn) } else { @() }
                if ($deps -contains $current) {
                    $State.Checked[$childName] = $true
                    $visited[$childName] = $true
                    $queue.Enqueue($childName)
                }
            }
        }
    }
}
