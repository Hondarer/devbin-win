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
