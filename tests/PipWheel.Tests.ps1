# PipWheel.Tests.ps1
# pip パッケージ名の正規化および wheel ファイル検証の回帰テスト

. (Join-Path $PSScriptRoot "TestHelpers.ps1")
Import-DevbinModules

Describe "Get-NormalizedPipPackageName" {

    It "大文字と区切り文字を吸収する (PEP 503)" {
        Get-NormalizedPipPackageName -Name "Ruamel.YAML" | Should Be "ruamel-yaml"
        Get-NormalizedPipPackageName -Name "ruamel_yaml" | Should Be "ruamel-yaml"
        Get-NormalizedPipPackageName -Name "  ruamel-yaml  " | Should Be "ruamel-yaml"
    }
}

Describe "Get-PipWheelPackageNames" {

    It "IncludeCorePackages で Python 初期設定用のコアパッケージを返す" {
        $names = @(Get-PipWheelPackageNames -IncludeCorePackages)
        ($names -join ",") | Should Be "pip,setuptools,wheel,packaging,pytest"
    }

    It "Python 初期設定スクリプトがコアパッケージ一覧をインストールに使う" {
        $setupScriptPath = Join-Path (Get-DevbinSubscriptsDir) "config\templates\python-setup.ps1"
        $content = Get-Content -Path $setupScriptPath -Raw

        $content | Should Match '\$corePackages\s*=\s*@\(Get-PipWheelPackageNames -IncludeCorePackages\)'
        $content | Should Match '\$pipInstallArgs\s*\+=\s*\$corePackages'
        $content | Should Match '\$pipDownloadArgs\s*\+=\s*\$corePackages'
        $content | Should Match '\$completeOffline = Test-DevbinOfflineMode'
        $content | Should Match 'elseif \(\$completeOffline\)'
    }

    It "既に読み込み済みの Devbin を Force で置き換えない" {
        $setupScriptPath = Join-Path (Get-DevbinSubscriptsDir) "config\templates\python-setup.ps1"
        $content = Get-Content -Path $setupScriptPath -Raw

        $content | Should Match 'Get-Module -Name Devbin'
        $content | Should Match 'if \(-not \$loadedDevbinModule\)'
        $content | Should Match 'Import-Module \$devbinModulePath -Force'
    }

    It "指定がなければ空を返す" {
        $names = @(Get-PipWheelPackageNames)
        $names.Count | Should Be 0
    }

    It "PipPackage と Version から版指定付きの名前を作る" {
        $package = New-TestPackage -ShortName "yamllint" -Version "1.35.1" -Extra @{ PipPackage = "yamllint" }
        $names = @(Get-PipWheelPackageNames -PackageConfigs @($package))
        ($names -join ",") | Should Be "yamllint==1.35.1"
    }

    It "PipDependencies も対象に含める" {
        $package = New-TestPackage -ShortName "yamllint" -Version "1.35.1" -Extra @{
            PipPackage = "yamllint"
            PipDependencies = @("pathspec", "pyyaml")
        }
        $names = @(Get-PipWheelPackageNames -PackageConfigs @($package))
        ($names -join ",") | Should Be "yamllint==1.35.1,pathspec,pyyaml"
    }

    It "正規化後の名前が同じものは重複させない" {
        $package = New-TestPackage -ShortName "demo" -Extra @{
            PipDependencies = @("ruamel.yaml", "ruamel-yaml", "ruamel_yaml")
        }
        $names = @(Get-PipWheelPackageNames -PackageConfigs @($package))
        ($names -join ",") | Should Be "ruamel.yaml"
    }
}

Describe "Get-PipWheelDownloadSpecs" {

    It "検証側と同じ結果を返す (表記ゆれを別物として扱わない)" {
        $package = New-TestPackage -ShortName "demo" -Extra @{
            PipDependencies = @("ruamel.yaml", "ruamel-yaml")
        }
        $specs = @(Get-PipWheelDownloadSpecs -PackageConfigs @($package) -IncludeCorePackages)
        $names = @(Get-PipWheelPackageNames -PackageConfigs @($package) -IncludeCorePackages)
        ($specs -join ",") | Should Be ($names -join ",")
    }
}

Describe "Test-PipWheelPackages" {

    It "必要な wheel が揃っていれば空を返す" {
        $dir = New-TestDirectory
        try {
            New-Item -ItemType File -Path (Join-Path $dir "pip-25.0-py3-none-any.whl") -Force | Out-Null
            New-Item -ItemType File -Path (Join-Path $dir "setuptools-80.0-py3-none-any.whl") -Force | Out-Null

            $missing = @(Test-PipWheelPackages -DirectoryPath $dir -PackageNames @("pip", "setuptools"))
            $missing.Count | Should Be 0
        } finally {
            Remove-TestDirectory -Path $dir
        }
    }

    It "不足している wheel を返す" {
        $dir = New-TestDirectory
        try {
            New-Item -ItemType File -Path (Join-Path $dir "pip-25.0-py3-none-any.whl") -Force | Out-Null

            $missing = @(Test-PipWheelPackages -DirectoryPath $dir -PackageNames @("pip", "wheel"))
            ($missing -join ",") | Should Be "wheel-*.whl"
        } finally {
            Remove-TestDirectory -Path $dir
        }
    }

    It "wheel 名の表記ゆれを正規化して照合する" {
        $dir = New-TestDirectory
        try {
            New-Item -ItemType File -Path (Join-Path $dir "ruamel.yaml-0.18.6-py3-none-any.whl") -Force | Out-Null

            $missing = @(Test-PipWheelPackages -DirectoryPath $dir -PackageNames @("ruamel-yaml"))
            $missing.Count | Should Be 0
        } finally {
            Remove-TestDirectory -Path $dir
        }
    }

    It "版指定が一致しなければ不足として返す" {
        $dir = New-TestDirectory
        try {
            New-Item -ItemType File -Path (Join-Path $dir "pip-25.0-py3-none-any.whl") -Force | Out-Null

            $missing = @(Test-PipWheelPackages -DirectoryPath $dir -PackageNames @("pip==26.1"))
            ($missing -join ",") | Should Be "pip==26.1"
        } finally {
            Remove-TestDirectory -Path $dir
        }
    }

    It "ディレクトリが存在しなくても例外にしない" {
        $missing = @(Test-PipWheelPackages -DirectoryPath "C:\nonexistent-devbin-test" -PackageNames @("pip"))
        $missing.Count | Should Be 1
    }
}

Describe "Invoke-PipWheelDownload" {

    It "取得成功後は pip-packages を今回の wheel だけにする" {
        InModuleScope Devbin {
            . (Join-Path $env:DEVBIN_TESTS_DIR "TestHelpers.ps1")
            $dir = New-TestDirectory
            try {
                $dest = Join-Path $dir "pip-packages"
                New-Item -ItemType Directory -Path $dest -Force | Out-Null
                New-Item -ItemType File -Path (Join-Path $dest "pyyaml-6.0.3-cp313-cp313-win_amd64.whl") -Force | Out-Null
                New-Item -ItemType File -Path (Join-Path $dest "pip-26.1.1-py3-none-any.whl") -Force | Out-Null

                Mock Get-Command {
                    [PSCustomObject]@{ Source = "C:\Python\python.exe" }
                } -ParameterFilter { $Name -eq "python.exe" }
                Mock Save-PipWheelPackages {
                    New-Item -ItemType Directory -Path $DestinationDir -Force | Out-Null
                    foreach ($name in @("pip-26.2.1-py3-none-any.whl", "setuptools-84.0.0-py3-none-any.whl", "wheel-0.48.0-py3-none-any.whl", "packaging-26.3-py3-none-any.whl", "pytest-9.1.1-py3-none-any.whl")) {
                        New-Item -ItemType File -Path (Join-Path $DestinationDir $name) -Force | Out-Null
                    }
                    return 0
                }

                $result = Invoke-PipWheelDownload -Packages @() -PipInstallPackages @() -DestinationDir $dest -IncludeCorePackages
                $result.Success | Should Be $true
                $result.Skipped | Should Be $false
                (Test-Path (Join-Path $dest "pip-26.2.1-py3-none-any.whl")) | Should Be $true
                (Test-Path (Join-Path $dest "pyyaml-6.0.3-cp313-cp313-win_amd64.whl")) | Should Be $false
                (Test-Path (Join-Path $dest "pip-26.1.1-py3-none-any.whl")) | Should Be $false
            } finally {
                Remove-TestDirectory -Path $dir
            }
        }
    }

    It "取得失敗時は既存の pip-packages を残す" {
        InModuleScope Devbin {
            . (Join-Path $env:DEVBIN_TESTS_DIR "TestHelpers.ps1")
            $dir = New-TestDirectory
            try {
                $dest = Join-Path $dir "pip-packages"
                New-Item -ItemType Directory -Path $dest -Force | Out-Null
                New-Item -ItemType File -Path (Join-Path $dest "pip-26.1.1-py3-none-any.whl") -Force | Out-Null

                Mock Get-Command {
                    [PSCustomObject]@{ Source = "C:\Python\python.exe" }
                } -ParameterFilter { $Name -eq "python.exe" }
                Mock Save-PipWheelPackages { return 1 }

                $result = Invoke-PipWheelDownload -Packages @() -PipInstallPackages @() -DestinationDir $dest -IncludeCorePackages
                $result.Success | Should Be $false
                (Test-Path (Join-Path $dest "pip-26.1.1-py3-none-any.whl")) | Should Be $true
            } finally {
                Remove-TestDirectory -Path $dir
            }
        }
    }
}

Describe "pip 関連実装の一本化" {

    # 各スクリプトに旧実装の重複定義が残存していないことを確認します (Devbin モジュールへ集約済み)。
    $subscriptsDir = Get-DevbinSubscriptsDir
    $targets = @("Setup-Bin.ps1", "Get-Packages.ps1", "Devbin\Install\ComponentInstall.ps1", "Devbin\Install\ComponentSource.ps1", "Devbin\Extract\PackageManagerStrategy.ps1")
    $pipFunctions = @("Get-NormalizedPipPackageName", "Get-PipWheelPackageNames", "Get-PipWheelDownloadSpecs", "Test-PipWheelPackages")

    foreach ($fileName in $targets) {
        $filePath = Join-Path $subscriptsDir $fileName

        It "$fileName に pip 関連の重複定義が残っていない" {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
            $defined = @()
            foreach ($functionAst in $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
                if ($pipFunctions -contains $functionAst.Name) {
                    $defined += $functionAst.Name
                }
            }
            ($defined -join ", ") | Should Be ""
        }
    }
}
