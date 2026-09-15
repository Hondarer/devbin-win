# Menu.Tests.ps1
# Devbin/Menu へ移した対話型メニューのテスト
# 画面描画とキー入力は行わず、状態を扱う関数だけを確認する

. (Join-Path $PSScriptRoot "TestHelpers.ps1")
Import-DevbinModules

Describe "Get-MenuItems" {

    It "Hidden なパッケージは一覧に出さない" {
        $packages = @(
            (New-TestPackage -ShortName "visible"),
            (New-TestPackage -ShortName "hidden-dep" -Extra @{ Hidden = $true })
        )
        $items = @(Get-MenuItems -Packages $packages)

        ($items | ForEach-Object { $_.ShortName }) -join "," | Should Be "visible"
    }

    It "空の一覧でも失敗しない" {
        $items = @(Get-MenuItems -Packages @())

        $items.Count | Should Be 0
    }
}

Describe "Get-MenuItemList / Get-MenuFlag" {

    It "単一の hashtable でも 1 件の配列として扱える" {
        InModuleScope Devbin {
            $pkg = @{ ShortName = "only"; Name = "Only" }
            $state = @{ Items = $pkg }
            $items = @(Get-MenuItemList -State $state)

            $items.Count | Should Be 1
            ($null -eq $items[0]) | Should Be $false
            $items[0].ShortName | Should Be "only"
        }
    }

    It "Items が無ければ空の配列を返す" {
        InModuleScope Devbin {
            @(Get-MenuItemList -State @{}).Count | Should Be 0
            @(Get-MenuItemList -State $null).Count | Should Be 0
        }
    }

    It "null キーでは終了エラーにしない" {
        InModuleScope Devbin {
            $map = @{ a = $true }
            { Get-MenuFlag -Map $map -ItemOrName $null } | Should Not Throw
            Get-MenuFlag -Map $map -ItemOrName $null | Should Be $false
            Get-MenuFlag -Map $map -ItemOrName @{ Name = "x" } | Should Be $false
            Get-MenuFlag -Map $map -ItemOrName "a" | Should Be $true
        }
    }
}

Describe "Get-DependencyDisplay" {

    It "見える依存は名前で並べる" {
        InModuleScope Devbin {
            . (Join-Path $env:DEVBIN_TESTS_DIR "TestHelpers.ps1")
            $packages = @(
                (New-TestPackage -ShortName "dep1"),
                (New-TestPackage -ShortName "app" -DependsOn @("dep1"))
            )
            $app = $packages | Where-Object { $_.ShortName -eq "app" }

            (Get-DependencyDisplay -PackageConfig $app -Packages $packages) | Should Be "-> dep1"
        }
    }

    It "隠し依存は auto として示す" {
        InModuleScope Devbin {
            . (Join-Path $env:DEVBIN_TESTS_DIR "TestHelpers.ps1")
            $packages = @(
                (New-TestPackage -ShortName "mingw64-hidden" -Extra @{ Hidden = $true }),
                (New-TestPackage -ShortName "app" -DependsOn @("mingw64-hidden"))
            )
            $app = $packages | Where-Object { $_.ShortName -eq "app" }

            (Get-DependencyDisplay -PackageConfig $app -Packages $packages) | Should Be "(auto: hidden)"
        }
    }

    It "依存がなければ - を返す" {
        InModuleScope Devbin {
            . (Join-Path $env:DEVBIN_TESTS_DIR "TestHelpers.ps1")
            $app = New-TestPackage -ShortName "app"

            (Get-DependencyDisplay -PackageConfig $app -Packages @($app)) | Should Be "-"
        }
    }
}

Describe "Set-MenuSelectionState" {

    It "導入済みがある場合は現在の状態を引き継ぐ" {
        InModuleScope Devbin {
            $checked = @{}
            $reinstall = @{}
            Set-MenuSelectionState -Checked $checked -Reinstall $reinstall -ShortName "a" `
                -Status "Updateable" -IsDisabled $false -HasAnyInstalled $true -IsDefaultChecked $false

            $checked["a"] | Should Be $true
            $reinstall["a"] | Should Be $true
        }
    }

    It "初回導入では既定の選択に従う" {
        InModuleScope Devbin {
            $checked = @{}
            $reinstall = @{}
            Set-MenuSelectionState -Checked $checked -Reinstall $reinstall -ShortName "a" `
                -Status "NotInstalled" -IsDisabled $false -HasAnyInstalled $false -IsDefaultChecked $true

            $checked["a"] | Should Be $true
            $reinstall["a"] | Should Be $false
        }
    }

    It "使えない項目は未導入なら選択しない" {
        InModuleScope Devbin {
            $checked = @{}
            $reinstall = @{}
            Set-MenuSelectionState -Checked $checked -Reinstall $reinstall -ShortName "a" `
                -Status "NotInstalled" -IsDisabled $true -HasAnyInstalled $false -IsDefaultChecked $true

            $checked["a"] | Should Be $false
        }
    }
}

Describe "Update-Viewport" {

    It "カーソルが上に出たら追従する" {
        InModuleScope Devbin {
            $state = @{ CursorIndex = 2; ViewportTop = 5; ViewportSize = 10 }
            Update-Viewport -State $state

            $state.ViewportTop | Should Be 2
        }
    }

    It "カーソルが下に出たら追従する" {
        InModuleScope Devbin {
            $state = @{ CursorIndex = 12; ViewportTop = 0; ViewportSize = 10 }
            Update-Viewport -State $state

            $state.ViewportTop | Should Be 3
        }
    }

    It "表示範囲内なら動かさない" {
        InModuleScope Devbin {
            $state = @{ CursorIndex = 4; ViewportTop = 2; ViewportSize = 10 }
            Update-Viewport -State $state

            $state.ViewportTop | Should Be 2
        }
    }

    It "一覧より下にはみ出さない" {
        InModuleScope Devbin {
            $state = @{
                Items = @(@{ ShortName = "a" }, @{ ShortName = "b" }, @{ ShortName = "c" })
                CursorIndex = 1
                ViewportTop = 2
                ViewportSize = 3
            }
            Update-Viewport -State $state

            $state.ViewportTop | Should Be 0
        }
    }
}

Describe "Set-AllMenuItemsChecked / Clear-AllMenuItemsChecked" {

    It "使えない未導入の項目は選択しない" {
        InModuleScope Devbin {
            $state = @{
                Items      = @(@{ ShortName = "a" }, @{ ShortName = "b" })
                Checked    = @{ a = $false; b = $false }
                Reinstall  = @{ a = $false; b = $false }
                Disabled   = @{ a = $false; b = $true }
                Statuses   = @{ a = "NotInstalled"; b = "NotInstalled" }
                NeedRedraw = $false
            }
            Set-AllMenuItemsChecked -State $state

            $state.Checked["a"] | Should Be $true
            $state.Checked["b"] | Should Be $false
        }
    }

    It "すべての選択を外す" {
        InModuleScope Devbin {
            $state = @{
                Items      = @(@{ ShortName = "a" }, @{ ShortName = "b" })
                Checked    = @{ a = $true; b = $true }
                Reinstall  = @{ a = $true; b = $true }
                Disabled   = @{ a = $false; b = $false }
                Statuses   = @{ a = "Installed"; b = "Installed" }
                NeedRedraw = $false
            }
            Clear-AllMenuItemsChecked -State $state

            $state.Checked["a"] | Should Be $false
            $state.Reinstall["b"] | Should Be $false
        }
    }
}

Describe "Get-StatusDisplay" {

    It "未知の状態は Not Installed として表示する" {
        InModuleScope Devbin {
            (Get-StatusDisplay -Status "Installed").Label | Should Be "Installed"
            (Get-StatusDisplay -Status "NoSuchStatus").Label | Should Be "Not Installed"
        }
    }
}

Describe "Initialize-MenuState" {

    It "表示項目が 1 件でも Items は配列になり、0 番目が読める" {
        InModuleScope Devbin {
            . (Join-Path $env:DEVBIN_TESTS_DIR "TestHelpers.ps1")
            $pkg = New-TestPackage -ShortName "only"
            $state = Initialize-MenuState `
                -Packages @($pkg) `
                -Manifest @{ version = 1; components = @{} } `
                -InstallDir "C:\nonexistent-devbin-test" `
                -ScriptDir "C:\nonexistent-devbin-test"

            $state.Items -is [System.Array] | Should Be $true
            $state.Items.Count | Should Be 1
            ($null -eq $state.Items[0]) | Should Be $false
            $state.Items[0].ShortName | Should Be "only"
            { Get-MenuFlag -Map $state.Checked -ItemOrName $state.Items[0] } | Should Not Throw
        }
    }
}

Describe "Initialize-ConsoleInputType" {

    It "コンソール入力のネイティブ定義を用意する" {
        InModuleScope Devbin {
            Initialize-ConsoleInputType

            (("Devbin.ConsoleInputNative" -as [type]) -ne $null) | Should Be $true
        }
    }

    It "繰り返し呼んでも失敗しない" {
        InModuleScope Devbin {
            { Initialize-ConsoleInputType; Initialize-ConsoleInputType } | Should Not Throw
        }
    }
}

Describe "メニューの分割" {

    $subscriptsDir = Get-DevbinSubscriptsDir

    It "Setup-Menu.psm1 が残っていない" {
        (Test-Path (Join-Path $subscriptsDir "Setup-Menu.psm1")) | Should Be $false
    }

    It "Menu が責務ごとのファイルに分かれている" {
        $menuDir = Join-Path $subscriptsDir "Devbin\Menu"
        $files = @(Get-ChildItem $menuDir -Filter "*.ps1" | ForEach-Object { $_.Name } | Sort-Object)

        ($files -join ",") | Should Be "ConsoleInput.ps1,MenuActions.ps1,MenuLoop.ps1,MenuNavigation.ps1,MenuRender.ps1,MenuState.ps1"
    }

    It "コンソール入力の定義は読み込み時に走らせない" {
        $consoleInputPath = Join-Path $subscriptsDir "Devbin\Menu\ConsoleInput.ps1"
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($consoleInputPath, [ref]$null, [ref]$null)
        $topLevel = @($ast.EndBlock.Statements | Where-Object { -not ($_ -is [System.Management.Automation.Language.FunctionDefinitionAst]) })

        # 関数定義と定数の代入だけが並んでいること (Add-Type は関数の中)
        @($topLevel | Where-Object { -not ($_ -is [System.Management.Automation.Language.AssignmentStatementAst]) }).Count | Should Be 0
    }
}
