# ComponentInstall.Tests.ps1
# Install モジュールのコンポーネントインストールおよびアンインストール処理のテスト
# 実ファイル操作は一時ディレクトリ内に限定し、外部通信およびユーザー環境の変更は行いません。

. (Join-Path $PSScriptRoot "TestHelpers.ps1")
Import-DevbinModules

Describe "Get-ComponentEnvVarValues" {

    It "相対値は InstallDir 基準の絶対パスにする" {
        $pkg = New-TestPackage -ShortName "tool" -Extra @{ EnvVars = @{ TOOL_HOME = "tool" } }
        $values = Get-ComponentEnvVarValues -InstallDir "C:\bin" -PackageConfig $pkg

        $values["TOOL_HOME"] | Should Be "C:\bin\tool"
    }

    It "空文字は InstallDir そのものを指す" {
        $pkg = New-TestPackage -ShortName "tool" -Extra @{ EnvVars = @{ TOOL_HOME = "" } }
        $values = Get-ComponentEnvVarValues -InstallDir "C:\bin" -PackageConfig $pkg

        $values["TOOL_HOME"] | Should Be "C:\bin"
    }

    It "EnvVarIsLiteral に挙げた項目はそのまま使う" {
        $pkg = New-TestPackage -ShortName "tool" -Extra @{
            EnvVars         = @{ TOOL_OPTS = "--flag" }
            EnvVarIsLiteral = @("TOOL_OPTS")
        }
        $values = Get-ComponentEnvVarValues -InstallDir "C:\bin" -PackageConfig $pkg

        $values["TOOL_OPTS"] | Should Be "--flag"
    }

    It "EnvVars がなければ空を返す" {
        $pkg = New-TestPackage -ShortName "tool"
        $values = Get-ComponentEnvVarValues -InstallDir "C:\bin" -PackageConfig $pkg

        $values.Count | Should Be 0
    }
}

Describe "Test-ComponentUsesEdge" {

    It "Browser = Edge のときだけ true を返す" {
        (Test-ComponentUsesEdge -PackageConfig (New-TestPackage -ShortName "a" -Extra @{ Browser = "Edge" })) | Should Be $true
        (Test-ComponentUsesEdge -PackageConfig (New-TestPackage -ShortName "b")) | Should Be $false
    }
}

Describe "Get-OtherComponentFiles" {

    It "対象コンポーネント自身のファイルは含めない" {
        $manifest = New-TestManifest -Components @{
            "a" = (New-TestManifestEntry -Files @("a.exe", "shared.dll"))
            "b" = (New-TestManifestEntry -Files @("b.exe", "shared.dll"))
        }
        $others = Get-OtherComponentFiles -Manifest $manifest -ShortName "a"

        $others.ContainsKey("a.exe") | Should Be $false
        $others.ContainsKey("b.exe") | Should Be $true
        $others.ContainsKey("shared.dll") | Should Be $true
    }

    It "空白のみの項目は無視する" {
        $manifest = New-TestManifest -Components @{
            "b" = (New-TestManifestEntry -Files @("b.exe", " "))
        }
        $others = Get-OtherComponentFiles -Manifest $manifest -ShortName "a"

        $others.Count | Should Be 1
    }
}

Describe "Get-ComponentRootDirectories" {

    It "先頭のディレクトリ名を重複なく返す" {
        $roots = @(Get-ComponentRootDirectories -Paths @("jdk-21\bin\java.exe", "jdk-21\lib\x.jar", "node\node.exe"))

        ($roots -join ",") | Should Be "jdk-21,node"
    }

    It "区切り文字はどちらでも扱える" {
        $roots = @(Get-ComponentRootDirectories -Paths @("cmake/bin/cmake.exe"))

        ($roots -join ",") | Should Be "cmake"
    }

    It "空の一覧では何も返さない" {
        $roots = @(Get-ComponentRootDirectories -Paths @())

        $roots.Count | Should Be 0
    }
}

Describe "Remove-ComponentCleanupFiles" {

    It "CleanupPatterns に一致するファイルだけを削除する" {
        $installDir = New-TestDirectory
        try {
            foreach ($name in @("app.exe", "app.exe.old-1-2", "app.exe.old-3-4", "other.exe")) {
                New-Item -ItemType File -Path (Join-Path $installDir $name) -Force | Out-Null
            }
            $pkg = New-TestPackage -ShortName "app" -Extra @{ CleanupPatterns = @("app.exe.old-*") }
            $manifest = New-TestManifest -Components @{ app = (New-TestManifestEntry -Files @("app.exe")) }

            Remove-ComponentCleanupFiles -ShortName "app" -PackageConfig $pkg -InstallDir $installDir -Manifest $manifest | Out-Null

            @(Get-ChildItem -LiteralPath $installDir -Name | Sort-Object) -join "," | Should Be "app.exe,other.exe"
        } finally {
            Remove-TestDirectory -Path $installDir
        }
    }

    It "他コンポーネントが記録しているファイルは削除しない" {
        $installDir = New-TestDirectory
        try {
            New-Item -ItemType File -Path (Join-Path $installDir "app.exe.old-1-2") -Force | Out-Null
            $pkg = New-TestPackage -ShortName "app" -Extra @{ CleanupPatterns = @("app.exe.old-*") }
            $manifest = New-TestManifest -Components @{ other = (New-TestManifestEntry -Files @("app.exe.old-1-2")) }

            Remove-ComponentCleanupFiles -ShortName "app" -PackageConfig $pkg -InstallDir $installDir -Manifest $manifest | Out-Null

            Test-Path (Join-Path $installDir "app.exe.old-1-2") | Should Be $true
        } finally {
            Remove-TestDirectory -Path $installDir
        }
    }

    It "アンインストール時のファイル削除で CleanupPatterns も削除する" {
        $installDir = New-TestDirectory
        try {
            New-Item -ItemType File -Path (Join-Path $installDir "app.exe") -Force | Out-Null
            New-Item -ItemType File -Path (Join-Path $installDir "app.exe.old-1-2") -Force | Out-Null
            $pkg = New-TestPackage -ShortName "app" -Extra @{ CleanupPatterns = @("app.exe.old-*") }
            $manifest = New-TestManifest -Components @{ app = (New-TestManifestEntry -Files @("app.exe")) }

            Remove-ComponentInstalledFiles -ShortName "app" -PackageConfig $pkg -InstallDir $installDir -Manifest $manifest -Files @("app.exe") | Out-Null

            @(Get-ChildItem -LiteralPath $installDir).Count | Should Be 0
        } finally {
            Remove-TestDirectory -Path $installDir
        }
    }
}

Describe "Remove-ComponentInstalledFiles のルート ディレクトリの片付け" {

    It "記録にないファイルが残るルート ディレクトリは削除しない" {
        $installDir = New-TestDirectory
        try {
            New-Item -ItemType File -Path (Join-Path $installDir "node.exe") -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $installDir "node_modules\npm") -Force | Out-Null
            New-Item -ItemType File -Path (Join-Path $installDir "node_modules\npm\index.js") -Force | Out-Null
            # 利用者が npm -g で導入し、どのコンポーネントの記録にもないパッケージ
            New-Item -ItemType Directory -Path (Join-Path $installDir "node_modules\user-tool") -Force | Out-Null
            New-Item -ItemType File -Path (Join-Path $installDir "node_modules\user-tool\index.js") -Force | Out-Null
            $pkg = New-TestPackage -ShortName "nodejs"
            $files = @("node.exe", "node_modules\npm\index.js")
            $manifest = New-TestManifest -Components @{ nodejs = (New-TestManifestEntry -Files $files) }

            Remove-ComponentInstalledFiles -ShortName "nodejs" -PackageConfig $pkg -InstallDir $installDir -Manifest $manifest -Files $files | Out-Null

            (Test-Path (Join-Path $installDir "node_modules\npm\index.js")) | Should Be $false
            (Test-Path (Join-Path $installDir "node_modules\user-tool\index.js")) | Should Be $true
        } finally {
            Remove-TestDirectory -Path $installDir
        }
    }

    It "ファイルが残らなかったルート ディレクトリは、空の配下ごと削除する" {
        $installDir = New-TestDirectory
        try {
            New-Item -ItemType Directory -Path (Join-Path $installDir "jdk-21\bin") -Force | Out-Null
            New-Item -ItemType File -Path (Join-Path $installDir "jdk-21\bin\java.exe") -Force | Out-Null
            $pkg = New-TestPackage -ShortName "jdk"
            $files = @("jdk-21\bin\java.exe")
            $manifest = New-TestManifest -Components @{ jdk = (New-TestManifestEntry -Files $files) }

            Remove-ComponentInstalledFiles -ShortName "jdk" -PackageConfig $pkg -InstallDir $installDir -Manifest $manifest -Files $files | Out-Null

            (Test-Path (Join-Path $installDir "jdk-21")) | Should Be $false
        } finally {
            Remove-TestDirectory -Path $installDir
        }
    }

    It "ファイル一覧のないレガシー導入は、DetectFiles のルート ディレクトリごと削除する" {
        $installDir = New-TestDirectory
        try {
            New-Item -ItemType Directory -Path (Join-Path $installDir "graphviz") -Force | Out-Null
            New-Item -ItemType File -Path (Join-Path $installDir "graphviz\dot.exe") -Force | Out-Null
            New-Item -ItemType File -Path (Join-Path $installDir "graphviz\cgraph.dll") -Force | Out-Null
            $pkg = New-TestPackage -ShortName "graphviz" -DetectFiles @("graphviz\dot.exe")
            $manifest = New-TestManifest -Components @{ graphviz = (New-TestManifestEntry -Files @()) }

            Remove-ComponentInstalledFiles -ShortName "graphviz" -PackageConfig $pkg -InstallDir $installDir -Manifest $manifest -Files @() | Out-Null

            (Test-Path (Join-Path $installDir "graphviz")) | Should Be $false
        } finally {
            Remove-TestDirectory -Path $installDir
        }
    }
}

Describe "Update-Component" {

    It "再インストールでは生成ファイルを削除してからパッケージから導入する" {
        InModuleScope Devbin {
            . (Join-Path $env:DEVBIN_TESTS_DIR "TestHelpers.ps1")
            $installDir = New-TestDirectory
            try {
                New-Item -ItemType File -Path (Join-Path $installDir "app.exe.old-1-2") -Force | Out-Null
                $packages = @(New-TestPackage -ShortName "app" -Extra @{ SelfUpdating = $true; CleanupPatterns = @("app.exe.old-*") })
                $manifest = New-TestManifest -Components @{ app = (New-TestManifestEntry -Files @("app.exe")) }

                Mock Sync-ComponentManagerPath { }
                Mock Install-Component { return $true }

                Update-Component -ShortName "app" -Packages $packages -InstallDir $installDir -ScriptDir $installDir -Manifest $manifest |
                    Should Be $true
                Test-Path (Join-Path $installDir "app.exe.old-1-2") | Should Be $false
                Assert-MockCalled Install-Component -Scope It -Times 1 -Exactly -ParameterFilter { $ShortName -eq "app" }
            } finally {
                Remove-TestDirectory -Path $installDir
            }
        }
    }

    It "再インストールではマニフェストの既存ファイルを先に削除する" {
        InModuleScope Devbin {
            . (Join-Path $env:DEVBIN_TESTS_DIR "TestHelpers.ps1")
            $installDir = New-TestDirectory
            try {
                New-Item -ItemType File -Path (Join-Path $installDir "node.exe") -Force | Out-Null
                New-Item -ItemType Directory -Path (Join-Path $installDir "node_modules\npm") -Force | Out-Null
                New-Item -ItemType File -Path (Join-Path $installDir "node_modules\npm\old.js") -Force | Out-Null
                New-Item -ItemType Directory -Path (Join-Path $installDir "node_modules\pnpm") -Force | Out-Null
                New-Item -ItemType File -Path (Join-Path $installDir "node_modules\pnpm\keep.js") -Force | Out-Null
                $packages = @(New-TestPackage -ShortName "nodejs")
                $manifest = New-TestManifest -Components @{
                    nodejs = (New-TestManifestEntry -Files @("node.exe", "node_modules\npm\old.js"))
                    pnpm   = (New-TestManifestEntry -Files @("node_modules\pnpm\keep.js"))
                }

                Mock Sync-ComponentManagerPath { }
                Mock Install-Component { return $true }

                Update-Component -ShortName "nodejs" -Packages $packages -InstallDir $installDir -ScriptDir $installDir -Manifest $manifest |
                    Should Be $true
                (Test-Path (Join-Path $installDir "node.exe")) | Should Be $false
                (Test-Path (Join-Path $installDir "node_modules\npm\old.js")) | Should Be $false
                (Test-Path (Join-Path $installDir "node_modules\pnpm\keep.js")) | Should Be $true
            } finally {
                Remove-TestDirectory -Path $installDir
            }
        }
    }
}

Describe "Resolve-ComponentSource" {

    It "ArchivePattern に一致するファイルを見つける" {
        $packagesDir = New-TestDirectory
        try {
            New-Item -ItemType File -Path (Join-Path $packagesDir "tool-1.0.0.zip") -Force | Out-Null
            $pkg = New-TestPackage -ShortName "tool" -Extra @{ ArchivePattern = "^tool-.*\.zip$" }

            $source = Resolve-ComponentSource `
                -ShortName "tool" `
                -PackageConfig $pkg `
                -Packages @($pkg) `
                -InstallDir $packagesDir `
                -ScriptDir "" `
                -PackagesDir $packagesDir

            $source.Success | Should Be $true
            (Split-Path $source.ArchiveFile -Leaf) | Should Be "tool-1.0.0.zip"
        } finally {
            Remove-TestDirectory -Path $packagesDir
        }
    }

    It "版を含まない元のファイル名にもフォールバックする" {
        $packagesDir = New-TestDirectory
        try {
            New-Item -ItemType File -Path (Join-Path $packagesDir "tool.zip") -Force | Out-Null
            $pkg = New-TestPackage -ShortName "tool" -Extra @{
                ArchivePattern = "^tool-[0-9].*\.zip$"
                DownloadUrl    = "https://example.invalid/dist/tool.zip"
            }

            $source = Resolve-ComponentSource `
                -ShortName "tool" `
                -PackageConfig $pkg `
                -Packages @($pkg) `
                -InstallDir $packagesDir `
                -ScriptDir "" `
                -PackagesDir $packagesDir

            $source.Success | Should Be $true
            (Split-Path $source.ArchiveFile -Leaf) | Should Be "tool.zip"
        } finally {
            Remove-TestDirectory -Path $packagesDir
        }
    }

    It "VSBuildTools はアーカイブを探さない" {
        $pkg = New-TestPackage -ShortName "vsbt" -Extra @{ ExtractStrategy = "VSBuildTools" }

        $source = Resolve-ComponentSource `
            -ShortName "vsbt" `
            -PackageConfig $pkg `
            -Packages @($pkg) `
            -InstallDir "C:\nonexistent" `
            -ScriptDir "" `
            -PackagesDir "C:\nonexistent"

        $source.Success | Should Be $true
        $source.ArchiveFile | Should BeNullOrEmpty
    }
}

Describe "導入処理の分割" {

    $subscriptsDir = Get-DevbinSubscriptsDir

    It "Setup-Components.psm1 が残っていない" {
        (Test-Path (Join-Path $subscriptsDir "Setup-Components.psm1")) | Should Be $false
    }

    It "Install が責務ごとのファイルに分かれている" {
        $installDir = Join-Path $subscriptsDir "Devbin\Install"
        $files = @(Get-ChildItem $installDir -Filter "*.ps1" | ForEach-Object { $_.Name } | Sort-Object)

        ($files -join ",") | Should Be "ComponentChangePlan.ps1,ComponentEnvironment.ps1,ComponentFileRemoval.ps1,ComponentInstall.ps1,ComponentPath.ps1,ComponentSource.ps1,ComponentUninstall.ps1,LifecycleScript.ps1"
    }

    It "環境変数の値の計算が一箇所にまとまっている" {
        $installDir = Join-Path $subscriptsDir "Devbin\Install"
        $hits = @()
        foreach ($file in (Get-ChildItem $installDir -Filter "*.ps1")) {
            if ($file.Name -eq "ComponentEnvironment.ps1") { continue }
            if (Select-String -Path $file.FullName -Pattern 'EnvVarIsLiteral' -Quiet) {
                $hits += $file.Name
            }
        }
        ($hits -join ", ") | Should Be ""
    }

    It "Edge の App Paths が無くてもエラーにしない" {
        $source = Get-Content (Join-Path $subscriptsDir "Devbin\Install\ComponentEnvironment.ps1") -Raw
        $source | Should Match 'Get-Item -LiteralPath \$registryPath -ErrorAction SilentlyContinue'
        $source | Should Not Match 'Get-Item -LiteralPath \$registryPath -ErrorAction Stop'
    }
}

Describe "npm -g との相互運用" {

    Context "表示は npm のグローバル ツリーの実物から求め、マニフェストは変更しない" {
        It "表示は npm のグローバル ツリーの実物から求め、マニフェストは変更しない" {
            InModuleScope Devbin {
                . (Join-Path $env:DEVBIN_TESTS_DIR "TestHelpers.ps1")
                $installDir = New-TestDirectory
                try {
                    foreach ($entry in @(@("widdershins", "4.0.2"), @("minimist", "1.2.7"))) {
                        $directory = Join-Path $installDir ("node_modules\" + $entry[0])
                        New-Item -ItemType Directory -Path $directory -Force | Out-Null
                        Set-Content -Path (Join-Path $directory "package.json") -Value ("{`"name`":`"" + $entry[0] + "`",`"version`":`"" + $entry[1] + "`"}")
                    }
                    $widdershins = New-TestPackage -ShortName "widdershins" -Version "4.0.1" -Extra @{ ExtractStrategy = "NpmInstall"; NpmPackage = "widdershins" }
                    $minimist = New-TestPackage -ShortName "minimist" -Version "1.2.8" -Extra @{ ExtractStrategy = "NpmInstall"; NpmPackage = "minimist" }
                    $puppeteer = New-TestPackage -ShortName "puppeteer" -Version "25.11.0" -Extra @{ ExtractStrategy = "NpmInstall"; NpmPackage = "puppeteer" }
                    # devbin が最後に操作した結果: puppeteer だけを導入済み
                    $manifest = New-TestManifest -Components @{ puppeteer = (New-TestManifestEntry -Version "25.11.0" -Files @("node_modules\puppeteer")) }

                    # npm -g で導入 (定義より新しい版)
                    Get-ComponentStatus -Manifest $manifest -InstallDir $installDir -PackageConfig $widdershins | Should Be "Installed"
                    # npm -g で導入 (定義より古い版)
                    Get-ComponentStatus -Manifest $manifest -InstallDir $installDir -PackageConfig $minimist | Should Be "Updateable"
                    # npm -g で削除
                    Get-ComponentStatus -Manifest $manifest -InstallDir $installDir -PackageConfig $puppeteer | Should Be "NotInstalled"

                    (@($manifest.components.Keys) -join ",") | Should Be "puppeteer"
                    $manifest.components["puppeteer"].version | Should Be "25.11.0"
                } finally {
                    Remove-TestDirectory -Path $installDir
                }
            }
        }
    }

    Context "導入済みかの判定は、インストール先を渡すと npm のグローバル ツリーの実物で行う" {
        It "導入済みかの判定は、インストール先を渡すと npm のグローバル ツリーの実物で行う" {
            InModuleScope Devbin {
                . (Join-Path $env:DEVBIN_TESTS_DIR "TestHelpers.ps1")
                $installDir = New-TestDirectory
                try {
                    $directory = Join-Path $installDir "node_modules\pnpm"
                    New-Item -ItemType Directory -Path $directory -Force | Out-Null
                    Set-Content -Path (Join-Path $directory "package.json") -Value '{"name":"pnpm","version":"12.5.1"}'
                    $packages = @(
                        New-TestPackage -ShortName "pnpm" -Extra @{ ExtractStrategy = "NpmInstall"; NpmPackage = "pnpm" }
                        New-TestPackage -ShortName "antfu-ni" -DependsOn @("pnpm") -Extra @{ ExtractStrategy = "NpmInstall"; NpmPackage = "@antfu/ni" }
                        New-TestPackage -ShortName "tool"
                    )
                    $manifest = New-TestManifest -Components @{
                        "antfu-ni" = (New-TestManifestEntry -Files @("node_modules\@antfu\ni"))
                        tool       = (New-TestManifestEntry -Files @("tool.exe"))
                    }

                    # npm -g で導入され、マニフェストに記録がない
                    (Test-ComponentInstalled -Manifest $manifest -ShortName "pnpm" -Packages $packages -InstallDir $installDir) | Should Be $true
                    # マニフェストに記録があるが、npm -g で削除された
                    (Test-ComponentInstalled -Manifest $manifest -ShortName "antfu-ni" -Packages $packages -InstallDir $installDir) | Should Be $false
                    # npm 以外はマニフェストで判定する
                    (Test-ComponentInstalled -Manifest $manifest -ShortName "tool" -Packages $packages -InstallDir $installDir) | Should Be $true
                    # インストール先を渡さない場合は従来どおりマニフェストで判定する
                    (Test-ComponentInstalled -Manifest $manifest -ShortName "antfu-ni") | Should Be $true
                    # 依存元も実物で判定する (antfu-ni は削除済みなので pnpm の依存元にならない)
                    @(Get-Dependents -ShortName "pnpm" -Packages $packages -Manifest $manifest -InstallDir $installDir).Count | Should Be 0
                } finally {
                    Remove-TestDirectory -Path $installDir
                }
            }
        }
    }

    Context "Manage-Bin の起動時に npm -g の状態をマニフェストへ書き込まない" {
        It "Manage-Bin の起動時に npm -g の状態をマニフェストへ書き込まない" {
            InModuleScope Devbin {
                . (Join-Path $env:DEVBIN_TESTS_DIR "TestHelpers.ps1")
                $installDir = New-TestDirectory
                try {
                    Set-Content -Path (Join-Path $installDir ".devbin-manifest.json") -Value '{"version":1,"components":{}}'
                    $directory = Join-Path $installDir "node_modules\minimist"
                    New-Item -ItemType Directory -Path $directory -Force | Out-Null
                    Set-Content -Path (Join-Path $directory "package.json") -Value '{"name":"minimist","version":"1.2.8"}'
                    $packages = @(New-TestPackage -ShortName "minimist" -Version "1.2.8" -Extra @{ ExtractStrategy = "NpmInstall"; NpmPackage = "minimist" })

                    Mock Write-Manifest { $true }

                    $initialized = Initialize-ComponentManifest -InstallDir $installDir -Packages $packages
                    $initialized.Manifest.components.Count | Should Be 0
                    Assert-MockCalled Write-Manifest -Times 0 -Exactly -Scope It
                } finally {
                    Remove-TestDirectory -Path $installDir
                }
            }
        }
    }

    Context "npm -g で導入されたパッケージも Manage-Bin からアンインストールできる" {
        It "npm -g で導入されたパッケージも Manage-Bin からアンインストールできる" {
            InModuleScope Devbin {
                . (Join-Path $env:DEVBIN_TESTS_DIR "TestHelpers.ps1")
                $installDir = New-TestDirectory
                try {
                    $directory = Join-Path $installDir "node_modules\widdershins"
                    New-Item -ItemType Directory -Path $directory -Force | Out-Null
                    Set-Content -Path (Join-Path $directory "package.json") -Value '{"name":"widdershins","version":"4.0.1"}'
                    $packages = @(New-TestPackage -ShortName "widdershins" -Extra @{ ExtractStrategy = "NpmInstall"; NpmPackage = "widdershins" })
                    $manifest = New-TestManifest

                    Mock Uninstall-NpmGlobalPackages { $true }
                    Mock Remove-DevbinComponentStorage { @() }
                    Mock Sync-ComponentManagerPath { }

                    Uninstall-Component -ShortName "widdershins" -Packages $packages -InstallDir $installDir -Manifest $manifest | Should Be $true
                    Assert-MockCalled Uninstall-NpmGlobalPackages -Times 1 -Exactly -Scope It
                } finally {
                    Remove-TestDirectory -Path $installDir
                }
            }
        }
    }

    Context "npm -g で削除されたパッケージは、記録が残っていても Manage-Bin から導入できる" {
        It "npm -g で削除されたパッケージは、記録が残っていても Manage-Bin から導入できる" {
            InModuleScope Devbin {
                . (Join-Path $env:DEVBIN_TESTS_DIR "TestHelpers.ps1")
                $installDir = New-TestDirectory
                try {
                    $packages = @(New-TestPackage -ShortName "widdershins" -Extra @{ ExtractStrategy = "NpmInstall"; NpmPackage = "widdershins" })
                    $manifest = New-TestManifest -Components @{ widdershins = (New-TestManifestEntry -Files @("node_modules\widdershins")) }

                    Mock Resolve-ComponentSource { [pscustomobject]@{ Success = $false; ArchiveFile = $null } }

                    # 既にインストール済みとして省略されず、導入処理 (資材の確認) に進む
                    Install-Component -ShortName "widdershins" -Packages $packages -InstallDir $installDir -ScriptDir $installDir -Manifest $manifest -SkipDeps | Should Be $false
                    Assert-MockCalled Resolve-ComponentSource -Times 1 -Exactly -Scope It
                } finally {
                    Remove-TestDirectory -Path $installDir
                }
            }
        }
    }

    Context "アンインストールは要求したパッケージを npm uninstall -g で削除し、ファイル一覧による削除は行わない" {
        It "アンインストールは要求したパッケージを npm uninstall -g で削除し、ファイル一覧による削除は行わない" {
            InModuleScope Devbin {
                . (Join-Path $env:DEVBIN_TESTS_DIR "TestHelpers.ps1")
                $installDir = New-TestDirectory
                try {
                    $directory = Join-Path $installDir "node_modules\textlint"
                    New-Item -ItemType Directory -Path $directory -Force | Out-Null
                    Set-Content -Path (Join-Path $directory "package.json") -Value '{"name":"textlint","version":"15.8.0"}'
                    $packages = @(New-TestPackage -ShortName "textlint" -Extra @{
                        ExtractStrategy = "NpmInstall"
                        NpmPackage      = "textlint"
                        NpmDependencies = @("textlint-rule-preset-ja-spacing@^3.0.3")
                    })
                    $manifest = New-TestManifest -Components @{ textlint = (New-TestManifestEntry -Files @("node_modules\textlint")) }

                    Mock Uninstall-NpmGlobalPackages { $true }
                    Mock Remove-ComponentInstalledFiles { }
                    Mock Remove-DevbinComponentStorage { @() }
                    Mock Sync-ComponentManagerPath { }

                    Uninstall-Component -ShortName "textlint" -Packages $packages -InstallDir $installDir -Manifest $manifest | Should Be $true
                    Assert-MockCalled Uninstall-NpmGlobalPackages -Times 1 -Exactly -ParameterFilter {
                        ($PackageNames -join ",") -eq "textlint,textlint-rule-preset-ja-spacing"
                    }
                    Assert-MockCalled Remove-ComponentInstalledFiles -Times 0 -Exactly
                    $manifest.components.ContainsKey("textlint") | Should Be $false
                } finally {
                    Remove-TestDirectory -Path $installDir
                }
            }
        }
    }

    Context "再インストールは npm に置き換えを任せ、先にファイルを削除しない" {
        It "再インストールは npm に置き換えを任せ、先にファイルを削除しない" {
            InModuleScope Devbin {
                . (Join-Path $env:DEVBIN_TESTS_DIR "TestHelpers.ps1")
                $installDir = New-TestDirectory
                try {
                    $packages = @(New-TestPackage -ShortName "widdershins" -Extra @{ ExtractStrategy = "NpmInstall"; NpmPackage = "widdershins" })
                    $manifest = New-TestManifest -Components @{ widdershins = (New-TestManifestEntry -Files @("node_modules\widdershins")) }

                    Mock Sync-ComponentManagerPath { }
                    Mock Remove-ComponentInstalledFiles { }
                    Mock Install-Component { return $true }

                    Update-Component -ShortName "widdershins" -Packages $packages -InstallDir $installDir -ScriptDir $installDir -Manifest $manifest |
                        Should Be $true
                    Assert-MockCalled Remove-ComponentInstalledFiles -Times 0 -Exactly
                    Assert-MockCalled Install-Component -Times 1 -Exactly -ParameterFilter { $ShortName -eq "widdershins" }
                } finally {
                    Remove-TestDirectory -Path $installDir
                }
            }
        }
    }

    Context "導入はファイルの差分ではなく、要求したパッケージのディレクトリと実際の版を記録する" {
        It "導入はファイルの差分ではなく、要求したパッケージのディレクトリと実際の版を記録する" {
            InModuleScope Devbin {
                . (Join-Path $env:DEVBIN_TESTS_DIR "TestHelpers.ps1")
                $installDir = New-TestDirectory
                try {
                    $packages = @(New-TestPackage -ShortName "demo" -Version "1.0.0" -Extra @{ ExtractStrategy = "NpmInstall"; NpmPackage = "@scope/demo" })
                    $manifest = New-TestManifest

                    Mock Resolve-ComponentSource { [pscustomobject]@{ Success = $true; ArchiveFile = $null } }
                    Mock Get-DirectorySnapshot { throw "snapshot must not be taken" }
                    Mock Initialize-DevbinComponentStorage { @() }
                    Mock Sync-ComponentManagerPath { }
                    Mock Invoke-PackageLifecycleScripts { }
                    Mock Invoke-ExtractStrategy {
                        $directory = Join-Path $BinDir "node_modules\@scope\demo"
                        New-Item -ItemType Directory -Path $directory -Force | Out-Null
                        Set-Content -Path (Join-Path $directory "package.json") -Value '{"name":"@scope/demo","version":"1.0.0"}'
                        return $true
                    }

                    Install-Component -ShortName "demo" -Packages $packages -InstallDir $installDir -ScriptDir $installDir -Manifest $manifest -SkipDeps |
                        Should Be $true
                    (@($manifest.components["demo"].files) -join ",") | Should Be "node_modules\@scope\demo"
                    $manifest.components["demo"].version | Should Be "1.0.0"
                    $manifest.components["demo"].archiveFile | Should Be "(npm install -g)"
                } finally {
                    Remove-TestDirectory -Path $installDir
                }
            }
        }
    }
}
