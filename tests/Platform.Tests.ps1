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
        ($files -contains "OperationLog.ps1") | Should Be $true
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

    It "cmd と cmd.template に UTF-8 BOM を付けない" {
        $bomFiles = @()
        $repoRoot = Get-DevbinRepoRoot
        $files = @(Get-ChildItem -Path $repoRoot -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object {
                $_.FullName -notmatch '\\(packages|dist|\.git)\\' -and
                ($_.Extension -eq ".cmd" -or $_.Name -like "*.cmd.template")
            })
        foreach ($file in $files) {
            $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
            if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
                $bomFiles += $file.Name
            }
        }

        ($bomFiles -join ", ") | Should Be ""

        $vsbt = Get-Content (Join-Path $subscriptsDir "Setup-VSBT.ps1") -Raw
        $vsbt | Should Match 'New-Object System\.Text\.UTF8Encoding \$false'
        $vsbt | Should Match 'WriteAllText\(\$cmdPath, \$cmdContent, \$utf8\)'
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

Describe "Register-VswhereInstance" {

    It "ディレクトリ作成に ErrorAction Stop を使わない" {
        $source = Get-Content (Join-Path (Get-DevbinSubscriptsDir) "Devbin\Platform\Vswhere.ps1") -Raw
        $source | Should Match 'New-Item -ItemType Directory -Path \$instancePath -Force -ErrorAction SilentlyContinue'
        $source | Should Not Match 'New-Item -ItemType Directory -Path \$instancePath -Force -ErrorAction Stop'
    }

    It "作成できなくても終了エラーにしない" {
        InModuleScope Devbin {
            Mock Test-Path { $false }
            Mock New-Item { $null }
            Mock Write-Host {}
            { Register-VswhereInstance -InstallPath "C:\nonexistent-devbin-test" -MsvcVersion "14.44" -SdkVersion "26100" -Targets @("x64") } | Should Not Throw
        }
    }
}

Describe "操作ログ" {

    It "標準の導入先では製品ルートの親を返す" {
        $directory = Get-DevbinOperationLogDirectory -InstallDir "C:\nonexistent-devbin-test\user\devbin-win\bin"
        $directory | Should Be "C:\nonexistent-devbin-test\user"
    }

    It "カスタム導入先ではその親を返す" {
        $directory = Get-DevbinOperationLogDirectory -InstallDir "C:\nonexistent-devbin-test\tools"
        $directory | Should Be "C:\nonexistent-devbin-test"
    }

    It "ファイル名は devbin-win の操作ログと日時が分かる" {
        $info = New-DevbinOperationLogPath -InstallDir "C:\nonexistent-devbin-test\user\devbin-win\bin" -Timestamp ([datetime]"2026-09-15 22:15:13")
        $info.FileName | Should Be "devbin-win-operation-20260915-221513.log"
        $info.Path | Should Be "C:\nonexistent-devbin-test\user\devbin-win-operation-20260915-221513.log"
        $info.UsedFallback | Should Be $false
    }

    It "同名ファイルがある場合は上書きせず PID を付ける" {
        $root = New-TestDirectory
        try {
            $installDir = Join-Path $root "user\devbin-win\bin"
            New-Item -ItemType Directory -Path $installDir -Force | Out-Null
            $stamp = [datetime]"2026-09-15 22:15:13"
            $first = New-DevbinOperationLogPath -InstallDir $installDir -Timestamp $stamp
            New-Item -ItemType File -Path $first.Path -Force | Out-Null

            $second = New-DevbinOperationLogPath -InstallDir $installDir -Timestamp $stamp
            $second.Path | Should Not Be $first.Path
            $second.FileName | Should Match "^devbin-win-operation-20260915-221513-$PID\.log$"
            (Test-Path -LiteralPath $first.Path) | Should Be $true
        } finally {
            Remove-TestDirectory -Path $root
        }
    }

    It "ボリューム直下へは置かず一時フォルダーへ退避する" {
        $info = New-DevbinOperationLogPath -InstallDir "C:\MyTools"
        $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\')
        $info.UsedFallback | Should Be $true
        ([System.IO.Path]::GetFullPath($info.Directory).TrimEnd('\')) | Should Be $tempRoot
        $info.FileName | Should Match '^devbin-win-operation-\d{8}-\d{6}'
    }

    It "Transcript を開始すると Write-Host が残り、終了後も消さない" {
        $root = New-TestDirectory
        $logPath = $null
        try {
            $installDir = Join-Path $root "user\devbin-win\bin"
            New-Item -ItemType Directory -Path $installDir -Force | Out-Null

            $logPath = Start-DevbinOperationLog -InstallDir $installDir
            [string]::IsNullOrWhiteSpace($logPath) | Should Be $false
            $logPath | Should Match 'devbin-win-operation-\d{8}-\d{6}.*\.log$'
            $parent = Split-Path -Path (Split-Path -Path $installDir -Parent) -Parent
            $logDir = Split-Path -Path $logPath -Parent
            ([string]::Equals($logDir, $parent, [StringComparison]::OrdinalIgnoreCase)) | Should Be $true

            Write-Host "DEVBIN_OPERATION_LOG_MARKER"
            Stop-DevbinOperationLog

            (Test-Path -LiteralPath $logPath) | Should Be $true
            $content = Get-Content -LiteralPath $logPath -Encoding UTF8 -Raw
            $content | Should Match "DEVBIN_OPERATION_LOG_MARKER"

            $bytes = [System.IO.File]::ReadAllBytes($logPath)
            ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should Be $true
        } finally {
            Stop-DevbinOperationLog
            Remove-TestDirectory -Path $root
        }
    }

    It "操作ログを削除する処理を持たない" {
        $source = Get-Content (Join-Path (Get-DevbinSubscriptsDir) "Devbin\Platform\OperationLog.ps1") -Raw
        $source | Should Not Match 'Remove-Item'
    }

    It "Setup-Bin.ps1 の Manage と Uninstall で操作ログを開始する" {
        $source = Get-Content (Join-Path (Get-DevbinSubscriptsDir) "Setup-Bin.ps1") -Raw
        $source | Should Match 'Start-DevbinOperationLog -InstallDir \$absoluteInstallDir'
        $source | Should Match 'Stop-DevbinOperationLog'
    }
}
