# MenuNavigation.ps1
# メニューカーソル移動および選択状態の更新処理

# カーソル位置に合わせてビューポートのスクロール範囲を調整します。
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
        # ビューポート外へ移動した場合: スクロール位置を更新し全体を再描画します。
        Update-Viewport -State $State
        $State.NeedRedraw = $true
    } else {
        # ビューポート内の移動の場合: 変更された 2 行のみを部分更新します。
        $old = $items[$oldIdx]
        if ($null -ne $old) {
            Render-MenuLine -Row ($script:HEADER_ROWS + $oldIdx - $State.ViewportTop) -Number ($oldIdx + 1) `
                -Item $old -IsChecked (Get-MenuFlag -Map $State.Checked -ItemOrName $old) `
                -IsReinstall (Get-MenuFlag -Map $State.Reinstall -ItemOrName $old) `
                -IsDisabled (Get-MenuFlag -Map $State.Disabled -ItemOrName $old) `
                -DisableReason (Get-MenuDisableReason -State $State -ItemOrName $old) `
                -Status (Get-MenuFlag -Map $State.Statuses -ItemOrName $old -Default "NotInstalled") `
                -IsCursor $false -Packages $State.Packages
        }

        $new = $items[$newIdx]
        if ($null -ne $new) {
            Render-MenuLine -Row ($script:HEADER_ROWS + $newIdx - $State.ViewportTop) -Number ($newIdx + 1) `
                -Item $new -IsChecked (Get-MenuFlag -Map $State.Checked -ItemOrName $new) `
                -IsReinstall (Get-MenuFlag -Map $State.Reinstall -ItemOrName $new) `
                -IsDisabled (Get-MenuFlag -Map $State.Disabled -ItemOrName $new) `
                -DisableReason (Get-MenuDisableReason -State $State -ItemOrName $new) `
                -Status (Get-MenuFlag -Map $State.Statuses -ItemOrName $new -Default "NotInstalled") `
                -IsCursor $true -Packages $State.Packages
        }
    }

    return "continue"
}

function Set-AllMenuItemsChecked {
    param([hashtable]$State)

    foreach ($item in @(Get-MenuItemList -State $State)) {
        # 無効化 (Disabled) かつ未インストールの項目は選択を禁止します。
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

# 項目の選択状態を切り替え、必要に応じて依存関係にある項目を自動選択します。
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
            # 無効化 (Disabled) の場合: 再インストールや選択への遷移を禁止し、選択解除 (アンインストール) のみを許可します。
            if ($State.Checked[$shortName]) {
                $State.Reinstall[$shortName] = $false
                $State.Checked[$shortName] = $false
            }
            # 未選択の場合は状態を変更しません。
        } else {
            # 状態遷移サイクル: 選択中 (Checked) → 未選択 (Unchecked) → 再インストール (Reinstall) → 選択中 (Checked)
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
        # 未インストールまたは破損状態の場合: 無効化 (Disabled) 項目に対する選択を禁止します。
        if (-not $isDisabled) {
            $newChecked = -not $State.Checked[$shortName]
            $State.Checked[$shortName] = $newChecked
            $propagateCheck = $newChecked
        }
    }

    if ($propagateCheck) {
        # 選択有効化時: 当該コンポーネントに依存する他の項目を推移的に自動選択します (自動再インストールは行いません)。
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
