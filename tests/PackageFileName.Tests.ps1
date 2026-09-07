# PackageFileName.Tests.ps1
# 保存ファイル名の決定と版表記判定の回帰テスト

. (Join-Path $PSScriptRoot "TestHelpers.ps1")
Import-DevbinModules

Describe "Get-PackageBaseFileName" {

    It "通常の URL は末尾のファイル名をそのまま使う" {
        $package = @{ DownloadUrl = "https://nodejs.org/dist/v25.9.0/node-v25.9.0-win-x64.zip" }
        Get-PackageBaseFileName -Package $package | Should Be "node-v25.9.0-win-x64.zip"
    }

    It "DownloadFileName の指定を優先する" {
        $package = @{
            DownloadUrl = "https://example.com/get?id=1"
            DownloadFileName = "tool-1.2.3.zip"
        }
        Get-PackageBaseFileName -Package $package | Should Be "tool-1.2.3.zip"
    }

    It "SourceForge の download URL は手前のセグメントを使う" {
        $package = @{ DownloadUrl = "https://downloads.sourceforge.net/project/foo/foo-1.2.3.zip/download" }
        Get-PackageBaseFileName -Package $package | Should Be "foo-1.2.3.zip"
    }

    It "GitHub のタグアーカイブは リポジトリ名-タグ に組み替える" {
        $package = @{ DownloadUrl = "https://github.com/owner/myrepo/archive/refs/tags/v1.2.3.tar.gz" }
        Get-PackageBaseFileName -Package $package | Should Be "myrepo-1.2.3.tar.gz"
    }

    It "DownloadUrl が無ければ空文字を返す" {
        Get-PackageBaseFileName -Package @{} | Should Be ""
    }
}

Describe "Test-FileNameContainsVersion" {

    It "区切り文字と大文字小文字の違いを吸収する" {
        Test-FileNameContainsVersion -FileName "tool-1_2_3.zip" -Version "1.2.3" | Should Be $true
        Test-FileNameContainsVersion -FileName "Tool-1.2.3.zip" -Version "1.2.3" | Should Be $true
        Test-FileNameContainsVersion -FileName "tool.zip" -Version "1.2.3" | Should Be $false
    }

    It "どちらかが空なら false を返す" {
        Test-FileNameContainsVersion -FileName "" -Version "1.2.3" | Should Be $false
        Test-FileNameContainsVersion -FileName "tool.zip" -Version "" | Should Be $false
    }
}

Describe "Get-PackageDownloadFileName" {

    $cases = @(
        @{ FileName = "tool-1.2.3.zip";  Version = "1.2.3"; Expected = "tool-1.2.3.zip" },
        @{ FileName = "tool-1_2_3.zip";  Version = "1.2.3"; Expected = "tool-1_2_3.zip" },
        @{ FileName = "tool.zip";        Version = "1.2.3"; Expected = "tool-1.2.3.zip" },
        @{ FileName = "tool.tar.gz";     Version = "1.2.3"; Expected = "tool-1.2.3.tar.gz" },
        @{ FileName = "tool";            Version = "1.2.3"; Expected = "tool-1.2.3" },
        @{ FileName = "Tool-1.2.3.zip";  Version = "1.2.3"; Expected = "Tool-1.2.3.zip" }
    )

    foreach ($case in $cases) {
        $fileName = $case.FileName
        $version = $case.Version
        $expected = $case.Expected

        It "$fileName (版 $version) は $expected になる" {
            $package = @{
                DownloadUrl = "https://example.com/$fileName"
                Version = $version
            }
            Get-PackageDownloadFileName -Package $package | Should Be $expected
        }
    }

    It "版が空なら素のファイル名をそのまま返す" {
        $package = @{ DownloadUrl = "https://example.com/tool.zip" }
        Get-PackageDownloadFileName -Package $package | Should Be "tool.zip"
    }
}

Describe "保存ファイル名の実装の一本化" {

    # 取得側・導入側それぞれに残っていた重複定義が無いことを確認する
    $subscriptsDir = Get-DevbinSubscriptsDir
    $targets = @("Get-Packages.ps1", "Setup-Components.psm1")
    $fileNameFunctions = @("Get-PackageBaseFileName", "Get-PackageDownloadFileName", "Test-FileNameContainsVersion")

    foreach ($fileName in $targets) {
        $filePath = Join-Path $subscriptsDir $fileName

        It "$fileName に保存ファイル名の重複定義が残っていない" {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
            $defined = @()
            foreach ($functionAst in $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
                if ($fileNameFunctions -contains $functionAst.Name) {
                    $defined += $functionAst.Name
                }
            }
            ($defined -join ", ") | Should Be ""
        }
    }

    It "導入側が取得側と同じ保存ファイル名を期待する" {
        # 区切り文字の違いを吸収しない実装が残っていると、ここで食い違う
        $componentsPath = Join-Path $subscriptsDir "Setup-Components.psm1"
        $source = Get-Content $componentsPath -Raw
        ($source -match '\$baseFileName -notlike') | Should Be $false
        ($source -match 'Get-PackageDownloadFileName') | Should Be $true
    }
}
