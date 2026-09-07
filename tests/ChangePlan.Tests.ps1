# ChangePlan.Tests.ps1
# 操作計画の作成と適用のテスト

. (Join-Path $PSScriptRoot "TestHelpers.ps1")
Import-DevbinModules

# 計画作成に必要な状態をまとめて組み立てる
function New-TestPlanState {
    param(
        [array]$Packages,
        [hashtable]$Checked = @{},
        [hashtable]$Reinstall = @{},
        [hashtable]$Statuses = @{},
        [hashtable]$Manifest = $null
    )

    $items = @($Packages | Where-Object { -not ($_.ContainsKey("Hidden") -and $_.Hidden) })
    $checkedAll = @{}
    $reinstallAll = @{}
    $statusAll = @{}
    foreach ($package in $items) {
        $shortName = $package.ShortName
        $checkedAll[$shortName] = [bool]$Checked[$shortName]
        $reinstallAll[$shortName] = [bool]$Reinstall[$shortName]
        $statusAll[$shortName] = if ($Statuses.ContainsKey($shortName)) { $Statuses[$shortName] } else { "NotInstalled" }
    }

    return @{
        Packages  = $Packages
        Items     = $items
        Checked   = $checkedAll
        Reinstall = $reinstallAll
        Statuses  = $statusAll
        Manifest  = if ($Manifest) { $Manifest } else { New-TestManifest }
    }
}

function Invoke-TestPlan {
    param([hashtable]$State)

    return New-ComponentChangePlan `
        -Packages $State.Packages `
        -Items $State.Items `
        -Checked $State.Checked `
        -Reinstall $State.Reinstall `
        -Statuses $State.Statuses `
        -Manifest $State.Manifest `
        -InstallDir "C:\nonexistent-devbin-test" `
        -PackagesDir "C:\nonexistent-devbin-test"
}

Describe "New-ComponentChangePlan" {

    $packages = @(
        (New-TestPackage -ShortName "base"),
        (New-TestPackage -ShortName "mid" -DependsOn @("base")),
        (New-TestPackage -ShortName "leaf" -DependsOn @("mid"))
    )

    It "導入は依存先から順に並べる" {
        $state = New-TestPlanState -Packages $packages -Checked @{ base = $true; mid = $true; leaf = $true }
        $plan = Invoke-TestPlan -State $state

        $plan.Success | Should Be $true
        (@($plan.Install | ForEach-Object { $_.ShortName }) -join ",") | Should Be "base,mid,leaf"
    }

    It "削除は依存元から順に並べる" {
        $manifest = New-TestManifest -Components @{
            base = (New-TestManifestEntry)
            mid  = (New-TestManifestEntry)
            leaf = (New-TestManifestEntry)
        }
        $state = New-TestPlanState -Packages $packages -Manifest $manifest `
            -Statuses @{ base = "Installed"; mid = "Installed"; leaf = "Installed" }
        $plan = Invoke-TestPlan -State $state

        (@($plan.Uninstall | ForEach-Object { $_.ShortName }) -join ",") | Should Be "leaf,mid,base"
    }

    It "残るパッケージが必要とする依存先を外そうとしたら中断する" {
        $manifest = New-TestManifest -Components @{
            base = (New-TestManifestEntry)
            mid  = (New-TestManifestEntry)
        }
        # base のチェックだけ外す。mid は残るので base は削除できない
        $state = New-TestPlanState -Packages $packages -Manifest $manifest `
            -Checked @{ mid = $true } `
            -Statuses @{ base = "Installed"; mid = "Installed"; leaf = "NotInstalled" }
        $plan = Invoke-TestPlan -State $state

        $plan.Success | Should Be $false
        ($plan.Errors -join " ") | Should Match "base"
    }

    It "依存先が未チェックかつ未インストールなら失敗として返す" {
        $state = New-TestPlanState -Packages $packages -Checked @{ leaf = $true }
        $plan = Invoke-TestPlan -State $state

        $plan.Success | Should Be $false
    }

    It "Hidden 依存はメニューに出ないが導入計画には入る" {
        $withHidden = @(
            (New-TestPackage -ShortName "hidden-dep" -Extra @{ Hidden = $true }),
            (New-TestPackage -ShortName "app" -DependsOn @("hidden-dep"))
        )
        $state = New-TestPlanState -Packages $withHidden -Checked @{ app = $true }
        $plan = Invoke-TestPlan -State $state

        $plan.Success | Should Be $true
        (@($plan.Install | ForEach-Object { $_.ShortName }) -join ",") | Should Be "hidden-dep,app"
    }

    It "Broken と再選択した Updateable は再インストールにする" {
        $manifest = New-TestManifest -Components @{
            base = (New-TestManifestEntry)
            mid  = (New-TestManifestEntry)
        }
        $state = New-TestPlanState -Packages $packages -Manifest $manifest `
            -Checked @{ base = $true; mid = $true } `
            -Reinstall @{ mid = $true } `
            -Statuses @{ base = "Broken"; mid = "Updateable"; leaf = "NotInstalled" }
        $plan = Invoke-TestPlan -State $state

        (@($plan.Reinstall | ForEach-Object { $_.ShortName }) -join ",") | Should Be "base,mid"
    }

    It "Legacy の削除対象には印を付ける" {
        $state = New-TestPlanState -Packages $packages `
            -Statuses @{ base = "Legacy"; mid = "NotInstalled"; leaf = "NotInstalled" }
        $plan = Invoke-TestPlan -State $state

        $plan.Uninstall[0].ShortName | Should Be "base"
        $plan.Uninstall[0].IsLegacy | Should Be $true
    }

    It "変更が無ければ IsEmpty を返す" {
        $state = New-TestPlanState -Packages $packages
        $plan = Invoke-TestPlan -State $state

        $plan.IsEmpty | Should Be $true
    }
}

Describe "Invoke-ComponentChangePlan" {

    $packages = @(
        (New-TestPackage -ShortName "base"),
        (New-TestPackage -ShortName "mid" -DependsOn @("base"))
    )

    function New-TestChangePlan {
        param(
            [array]$Install = @(),
            [array]$Reinstall = @(),
            [array]$Uninstall = @()
        )

        return [PSCustomObject]@{
            Success   = $true
            Errors    = @()
            Install   = @($Install)
            Reinstall = @($Reinstall)
            Uninstall = @($Uninstall)
            IsEmpty   = $false
        }
    }

    function New-TestEntry {
        param([string]$Action, [string]$ShortName)

        return [PSCustomObject]@{
            Action    = $Action
            ShortName = $ShortName
            Name      = $ShortName
            IsLegacy  = $false
        }
    }

    It "依存先が失敗したら依存元をスキップする" {
        $installDir = New-TestDirectory
        try {
            $global:DevbinTestFailShortName = "base"
            InModuleScope Devbin {
                Mock Install-Component { return ($ShortName -ne $global:DevbinTestFailShortName) }
            }

            $plan = New-TestChangePlan -Install @(
                (New-TestEntry -Action "Install" -ShortName "base"),
                (New-TestEntry -Action "Install" -ShortName "mid")
            )
            $outcome = Invoke-ComponentChangePlan -Plan $plan -Packages $packages `
                -InstallDir $installDir -ScriptDir (Get-DevbinSubscriptsDir) -Manifest (New-TestManifest)

            $outcome.Success | Should Be $false
            $outcome.Results[0].Status | Should Be "Failed"
            $outcome.Results[1].Status | Should Be "Skipped"
            $outcome.Results[1].Message | Should Match "base"
        } finally {
            Remove-TestDirectory -Path $installDir
        }
    }

    It "成功すると操作ごとにマニフェストを保存する" {
        $installDir = New-TestDirectory
        try {
            InModuleScope Devbin {
                Mock Install-Component {
                    Add-ComponentToManifest -Manifest $Manifest -ShortName $ShortName `
                        -Version "1.0.0" -ArchiveFile "(test)" -Files @() -PathDirs @()
                    return $true
                }
            }

            $manifest = New-TestManifest
            $plan = New-TestChangePlan -Install @((New-TestEntry -Action "Install" -ShortName "base"))
            $outcome = Invoke-ComponentChangePlan -Plan $plan -Packages $packages `
                -InstallDir $installDir -ScriptDir (Get-DevbinSubscriptsDir) -Manifest $manifest

            $outcome.Success | Should Be $true
            $outcome.Results[0].Status | Should Be "Installed"

            $saved = Read-Manifest -InstallDir $installDir
            $saved.components.ContainsKey("base") | Should Be $true
        } finally {
            Remove-TestDirectory -Path $installDir
        }
    }

    It "マニフェストを保存できなければ適用を中止する" {
        $root = New-TestDirectory
        try {
            InModuleScope Devbin {
                Mock Install-Component { return $true }
            }

            $installDir = Join-Path $root "no\such\place"
            $plan = New-TestChangePlan -Install @(
                (New-TestEntry -Action "Install" -ShortName "base"),
                (New-TestEntry -Action "Install" -ShortName "mid")
            )
            $outcome = Invoke-ComponentChangePlan -Plan $plan -Packages $packages `
                -InstallDir $installDir -ScriptDir (Get-DevbinSubscriptsDir) -Manifest (New-TestManifest)

            $outcome.Aborted | Should Be $true
            $outcome.Results.Count | Should Be 1
            $outcome.Results[0].Status | Should Be "Aborted"
        } finally {
            Remove-TestDirectory -Path $root
        }
    }

    It "再インストールは失敗してもマニフェストを保存する" {
        $installDir = New-TestDirectory
        try {
            InModuleScope Devbin {
                Mock Update-Component {
                    # 実際の Update-Component は失敗時もマニフェストから対象を外す
                    Remove-ComponentFromManifest -Manifest $Manifest -ShortName $ShortName
                    return $false
                }
            }

            $manifest = New-TestManifest -Components @{ base = (New-TestManifestEntry) }
            $plan = New-TestChangePlan -Reinstall @((New-TestEntry -Action "Reinstall" -ShortName "base"))
            $outcome = Invoke-ComponentChangePlan -Plan $plan -Packages $packages `
                -InstallDir $installDir -ScriptDir (Get-DevbinSubscriptsDir) -Manifest $manifest

            $outcome.Results[0].Status | Should Be "Failed"

            $saved = Read-Manifest -InstallDir $installDir
            $saved.components.ContainsKey("base") | Should Be $false
        } finally {
            Remove-TestDirectory -Path $installDir
        }
    }
}

Describe "一括導入モードの廃止" {

    $binPath = Join-Path (Get-DevbinSubscriptsDir) "Setup-Bin.ps1"

    It "-Install と -Extract のパラメータが無い" {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($binPath, [ref]$null, [ref]$null)
        $names = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })

        ($names -contains "Install") | Should Be $false
        ($names -contains "Extract") | Should Be $false
        ($names -contains "Manage") | Should Be $true
        ($names -contains "Uninstall") | Should Be $true
    }

    It "RunPostInstallInBatch が定義から消えている" {
        $context = New-DevbinContext -SubscriptsDir (Get-DevbinSubscriptsDir)
        $source = Get-Content $context.ConfigPath -Raw

        ($source -match "RunPostInstallInBatch") | Should Be $false
    }

    It "メニューが依存解決とマニフェスト保存を行わない" {
        $menuDir = Join-Path (Get-DevbinSubscriptsDir) "Devbin\Menu"
        $source = ((Get-ChildItem $menuDir -Filter "*.ps1" | ForEach-Object { Get-Content $_.FullName -Raw }) -join "`n")

        ($source -match "Write-Manifest") | Should Be $false
        ($source -match "Resolve-DependencyOrder") | Should Be $false
        ($source -match "Get-UninstallOrder") | Should Be $false
        ($source -match "Install-Component") | Should Be $false
    }
}
