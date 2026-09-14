# Platform.Tests.ps1
# OS 操作まわり (一時領域、HOME/XDG、Terminal 設定) のテスト
# 実ユーザーの環境変数とレジストリは変更しない

. (Join-Path $PSScriptRoot "TestHelpers.ps1")
Import-DevbinModules

Describe "Get-ValidCommandCandidates" {

    It "無いコマンドは空を返し、見つからないことをエラーにしない" {
        InModuleScope Devbin {
            $candidates = @(Get-ValidCommandCandidates -CommandName "devbin-missing-command-xyz")
            $candidates.Count | Should Be 0
        }

        $source = Get-Content (Join-Path (Get-DevbinSubscriptsDir) "Devbin\Platform\CommandLookup.ps1") -Raw
        $source | Should Match 'Get-Command \$CommandName -All -ErrorAction SilentlyContinue'
        $source | Should Not Match 'Get-Command \$CommandName -All -ErrorAction Stop'
    }
}

Describe "New-DevbinTempDirectory / Remove-DevbinTempDirectory" {

    It "呼び出しごとに別の一時ディレクトリを作る" {
        $first = New-DevbinTempDirectory -Prefix "devbin-test"
        $second = New-DevbinTempDirectory -Prefix "devbin-test"
        try {
            ($first -eq $second) | Should Be $false
            (Test-Path $first) | Should Be $true
            (Test-Path $second) | Should Be $true
        } finally {
            Remove-DevbinTempDirectory -Path $first
            Remove-DevbinTempDirectory -Path $second
        }
    }

    It "作った一時ディレクトリを中身ごと消す" {
        $path = New-DevbinTempDirectory -Prefix "devbin-test"
        New-Item -ItemType File -Path (Join-Path $path "a.txt") -Force | Out-Null

        Remove-DevbinTempDirectory -Path $path

        (Test-Path $path) | Should Be $false
    }

    It "一時領域の外は消さない" {
        $outside = Join-Path (Get-DevbinRepoRoot) "tests"
        Remove-DevbinTempDirectory -Path $outside

        (Test-Path $outside) | Should Be $true
    }

    It "一時領域のルート自体は削除しない" {
        InModuleScope Devbin {
            Mock Remove-Item { throw "ルートを削除してはいけません" }
            Remove-DevbinTempDirectory -Path ([IO.Path]::GetTempPath())
            Assert-MockCalled Remove-Item -Times 0 -Exactly
        }
    }

    It "空のパスを渡しても何も起きない" {
        { Remove-DevbinTempDirectory -Path "" } | Should Not Throw
    }
}

Describe "Get-DevbinHomeLayout" {

    It "HOME 配下の項目と環境変数名を返す" {
        $layout = @(Get-DevbinHomeLayout -HomePath "C:\home\user")
        $names = @($layout | ForEach-Object { $_.EnvName })

        ($names -join ",") | Should Be "CONTINUE_GLOBAL_DIR,XDG_CONFIG_HOME,XDG_CACHE_HOME,XDG_DATA_HOME,XDG_STATE_HOME"
        ($layout | Where-Object { $_.EnvName -eq "XDG_DATA_HOME" }).Path | Should Be "C:\home\user\.local\share"
    }
}

Describe "Get-DevbinHomePlan" {

    It "計画を作るだけで、環境も作業もしない" {
        $before = [Environment]::GetEnvironmentVariable("HOME", "User")
        $plan = Get-DevbinHomePlan
        $after = [Environment]::GetEnvironmentVariable("HOME", "User")

        $after | Should Be $before
        $plan.HomePath | Should Not BeNullOrEmpty
        (Test-Path $plan.HomePath) | Should Be (Test-Path $plan.HomePath)
    }

    It "既に設定されている環境変数は計画に入れない" {
        $plan = Get-DevbinHomePlan
        $planned = @($plan.EnvVars | ForEach-Object { $_.Name })

        foreach ($name in $planned) {
            $current = [Environment]::GetEnvironmentVariable($name, "User")
            [string]::IsNullOrWhiteSpace($current) | Should Be $true
        }
    }
}

Describe "Invoke-DevbinHomePlan" {

    It "ディレクトリを作り、結果を返す" {
        $root = New-TestDirectory
        try {
            $plan = [PSCustomObject]@{
                HomePath    = $root
                IsNewHome   = $false
                Directories = @((Join-Path $root ".config"), (Join-Path $root ".cache"))
                EnvVars     = @()
                Actions     = @()
                IsEmpty     = $false
            }

            $result = Invoke-DevbinHomePlan -Plan $plan

            $result.Success | Should Be $true
            (Test-Path (Join-Path $root ".config")) | Should Be $true
            (Test-Path (Join-Path $root ".cache")) | Should Be $true
        } finally {
            Remove-TestDirectory -Path $root
        }
    }
}

Describe "Get-ManagedUserPathValue (Platform への移動後)" {

    It "移動後も同じ順序で再構成する" {
        $installDir = New-TestDirectory
        try {
            New-Item -ItemType Directory -Path (Join-Path $installDir "a\bin") -Force | Out-Null
            $packages = @((New-TestPackage -ShortName "a" -PathDirs @("a\bin")))

            $result = Get-ManagedUserPathValue `
                -CurrentPath "C:\External\Tool" `
                -InstallDir $installDir `
                -Packages $packages `
                -InstalledShortNames @("a")

            $result | Should Be ((Join-Path $installDir "a\bin") + ";C:\External\Tool")
        } finally {
            Remove-TestDirectory -Path $installDir
        }
    }
}

Describe "Windows Terminal の設定読み込み" {
    It "コメントと URL を含む設定を読み込み既存プロファイルを保持する" {
        $root = New-TestDirectory
        try {
            $path = Join-Path $root "settings.json"
            [IO.File]::WriteAllText($path, '{ /* comment */ "profiles": { "list": [{ "name": "keep", "icon": "https://example.invalid/icon" }] } }')
            $settings = Get-TerminalSettings -SettingsPath $path
            $settings.profiles.list[0].name | Should Be "keep"
            $settings.profiles.list[0].icon | Should Be "https://example.invalid/icon"
            Save-TerminalSettings -Settings $settings -SettingsPath $path
            (Get-TerminalSettings -SettingsPath $path).profiles.list[0].name | Should Be "keep"
        } finally {
            Remove-TestDirectory -Path $root
        }
    }

    It "既存の空配列や null をエラーなく初期化する" {
        $root = New-TestDirectory
        try {
            $path = Join-Path $root "settings.json"
            foreach ($json in @('{"profiles":{"list":[]}}', '{"profiles":null}', '{}')) {
                [IO.File]::WriteAllText($path, $json)
                $settings = Get-TerminalSettings -SettingsPath $path -ErrorAction Stop
                $settings.profiles.PSObject.Properties.Match("list").Count | Should Be 1
                $settings.profiles.list.Count | Should Be 0
            }
        } finally {
            Remove-TestDirectory -Path $root
        }
    }
}

Describe "旧モジュールの整理" {

    $subscriptsDir = Get-DevbinSubscriptsDir

    It "Setup-Common.psm1 が残っていない" {
        (Test-Path (Join-Path $subscriptsDir "Setup-Common.psm1")) | Should Be $false
    }

    It "Platform が責務ごとのファイルに分かれている" {
        $platformDir = Join-Path $subscriptsDir "Devbin\Platform"
        $files = @(Get-ChildItem $platformDir -Filter "*.ps1" | ForEach-Object { $_.Name })

        ($files -contains "UserPath.ps1") | Should Be $true
        ($files -contains "WindowsTerminal.ps1") | Should Be $true
        ($files -contains "ProductUninstall.ps1") | Should Be $true
        ($files -contains "TempDirectory.ps1") | Should Be $true
    }

    It "固定名の temp_extract を使っていない" {
        $hits = @()
        foreach ($file in (Get-ChildItem $subscriptsDir -Recurse -Include *.ps1, *.psm1)) {
            if (Select-String -Path $file.FullName -Pattern 'temp_extract' -Quiet) {
                $hits += $file.Name
            }
        }
        ($hits -join ", ") | Should Be ""
    }

    It "Make-Dist.ps1 がカレントディレクトリを変更しない" {
        $source = Get-Content (Join-Path $subscriptsDir "Make-Dist.ps1") -Raw
        ($source -match 'Set-Location') | Should Be $false
    }

    It "確認プロンプトはキー 1 回で決まり Read-Host を使わない" {
        $productUninstall = Get-Content (Join-Path $subscriptsDir "Devbin\Platform\ProductUninstall.ps1") -Raw
        $menuActions = Get-Content (Join-Path $subscriptsDir "Devbin\Menu\MenuActions.ps1") -Raw
        $componentUninstall = Get-Content (Join-Path $subscriptsDir "Devbin\Install\ComponentUninstall.ps1") -Raw
        $setupHome = Get-Content (Join-Path $subscriptsDir "Setup-Home.ps1") -Raw
        $setupVsbt = Get-Content (Join-Path $subscriptsDir "Setup-VSBT.ps1") -Raw

        $productUninstall | Should Match 'function Read-ConfirmationKey'
        $productUninstall | Should Match 'Read-ConfirmationKey -Prompt "Continue\? \[y/N/Esc\] "'
        $productUninstall | Should Not Match 'Read-Host'
        $menuActions | Should Match 'Read-ConfirmationKey -Prompt " 続行しますか\? \[Y/n/Esc\] " -DefaultYes'
        $componentUninstall | Should Match 'Read-ConfirmationKey -Prompt "アンインストールを続行しますか\? \[y/N/Esc\] "'
        $componentUninstall | Should Not Match 'Read-Host'
        $setupHome | Should Match 'Read-ConfirmationKey -Prompt "Do you want to proceed\? \[Y/n/Esc\] " -DefaultYes'
        $setupHome | Should Not Match 'Read-Host'
        $setupVsbt | Should Match 'Read-ConfirmationKey -Prompt "Do you accept the license\? \[y/N/Esc\] "'
        $setupVsbt | Should Not Match 'Read-Host'
    }

    It "Terminal プロファイル操作が共通化されている" {
        foreach ($name in @("Update-GitBash-Profile.ps1", "Update-MinGW-Profile.ps1")) {
            $filePath = Join-Path $subscriptsDir $name
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
            $defined = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Name })

            ($defined -contains "Get-TerminalSettings") | Should Be $false
            ($defined -contains "Save-TerminalSettings") | Should Be $false
        }
    }
}
