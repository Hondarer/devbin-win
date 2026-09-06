# PipWheel.Tests.ps1
# pip パッケージ名の正規化と wheel 検証の回帰テスト
# 4 ファイルに複製された実装が同じ結果を返すことも確認する

. (Join-Path $PSScriptRoot "TestHelpers.ps1")
Import-DevbinModules

Describe "Get-NormalizedPipPackageName" {

    It "大文字と区切り文字を吸収する (PEP 503)" {
        InModuleScope Setup-Components {
            Get-NormalizedPipPackageName -Name "Ruamel.YAML" | Should Be "ruamel-yaml"
            Get-NormalizedPipPackageName -Name "ruamel_yaml" | Should Be "ruamel-yaml"
            Get-NormalizedPipPackageName -Name "  ruamel-yaml  " | Should Be "ruamel-yaml"
        }
    }
}

Describe "Test-PipWheelPackages" {

    It "必要な wheel が揃っていれば空を返す" {
        $dir = New-TestDirectory
        try {
            New-Item -ItemType File -Path (Join-Path $dir "pip-25.0-py3-none-any.whl") -Force | Out-Null
            New-Item -ItemType File -Path (Join-Path $dir "setuptools-80.0-py3-none-any.whl") -Force | Out-Null

            $global:DevbinTestDir = $dir
            InModuleScope Setup-Components {
                $dir = $global:DevbinTestDir
                $missing = @(Test-PipWheelPackages -DirectoryPath $dir -PackageNames @("pip", "setuptools"))
                $missing.Count | Should Be 0
            }
        } finally {
            Remove-TestDirectory -Path $dir
        }
    }

    It "不足している wheel を返す" {
        $dir = New-TestDirectory
        try {
            New-Item -ItemType File -Path (Join-Path $dir "pip-25.0-py3-none-any.whl") -Force | Out-Null

            $global:DevbinTestDir = $dir
            InModuleScope Setup-Components {
                $dir = $global:DevbinTestDir
                $missing = @(Test-PipWheelPackages -DirectoryPath $dir -PackageNames @("pip", "wheel"))
                $missing.Count | Should Be 1
                $missing[0] | Should Be "wheel-*.whl"
            }
        } finally {
            Remove-TestDirectory -Path $dir
        }
    }

    It "wheel 名の表記ゆれを正規化して照合する" {
        $dir = New-TestDirectory
        try {
            New-Item -ItemType File -Path (Join-Path $dir "ruamel.yaml-0.18.6-py3-none-any.whl") -Force | Out-Null

            $global:DevbinTestDir = $dir
            InModuleScope Setup-Components {
                $dir = $global:DevbinTestDir
                $missing = @(Test-PipWheelPackages -DirectoryPath $dir -PackageNames @("ruamel-yaml"))
                $missing.Count | Should Be 0
            }
        } finally {
            Remove-TestDirectory -Path $dir
        }
    }

    It "版指定が一致しなければ不足として返す" {
        $dir = New-TestDirectory
        try {
            New-Item -ItemType File -Path (Join-Path $dir "pip-25.0-py3-none-any.whl") -Force | Out-Null

            $global:DevbinTestDir = $dir
            InModuleScope Setup-Components {
                $dir = $global:DevbinTestDir
                $missing = @(Test-PipWheelPackages -DirectoryPath $dir -PackageNames @("pip==26.1"))
                ($missing -join ",") | Should Be "pip==26.1"
            }
        } finally {
            Remove-TestDirectory -Path $dir
        }
    }

    It "ディレクトリが存在しなくても例外にしない" {
        InModuleScope Setup-Components {
            $missing = @(Test-PipWheelPackages -DirectoryPath "C:\nonexistent-devbin-test" -PackageNames @("pip"))
            $missing.Count | Should Be 1
        }
    }
}

Describe "複製された Test-PipWheelPackages の結果一致" {

    # Setup-Strategies / Get-Packages / Setup-Bin に複製された実装を取り出して比較する
    $subscriptsDir = Get-DevbinSubscriptsDir
    $sources = @{
        "Setup-Strategies.psm1" = @("Get-NormalizedPipPackageName", "Test-PipWheelPackages")
        "Get-Packages.ps1"      = @("Get-NormalizedPipPackageName", "Test-PipWheelPackages")
        "Setup-Bin.ps1"         = @("Get-NormalizedPipPackageName", "Test-PipWheelPackages")
    }

    foreach ($fileName in $sources.Keys) {
        $wanted = $sources[$fileName]
        $filePath = Join-Path $subscriptsDir $fileName
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
        $definitions = @()
        foreach ($functionAst in $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
            if ($wanted -contains $functionAst.Name) {
                $definitions += $functionAst.Extent.Text
            }
        }

        It "$fileName の実装が Setup-Components と同じ結果を返す" {
            $dir = New-TestDirectory
            try {
                New-Item -ItemType File -Path (Join-Path $dir "pip-25.0-py3-none-any.whl") -Force | Out-Null
                New-Item -ItemType File -Path (Join-Path $dir "ruamel.yaml-0.18.6-py3-none-any.whl") -Force | Out-Null
                $names = @("pip", "ruamel-yaml", "wheel")

                $scriptText = ($definitions -join "`n") + "`n" + 'Test-PipWheelPackages -DirectoryPath $args[0] -PackageNames $args[1]'
                $actual = @(& ([scriptblock]::Create($scriptText)) $dir $names)

                $global:DevbinTestDir = $dir
                $global:DevbinTestNames = $names
                $expected = InModuleScope Setup-Components {
                    $dir = $global:DevbinTestDir
                    $names = $global:DevbinTestNames
                    @(Test-PipWheelPackages -DirectoryPath $dir -PackageNames $names)
                }

                ($actual -join ",") | Should Be (@($expected) -join ",")
            } finally {
                Remove-TestDirectory -Path $dir
            }
        }
    }
}
