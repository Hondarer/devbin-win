# PackageFileName.Tests.ps1
# 保存ファイル名の決定と版表記判定の回帰テスト
# 取得側 (Get-Packages.ps1) と導入側 (Setup-Components.psm1) の一致も確認する

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

Describe "取得側と導入側の保存ファイル名の一致" {

    # 取得側の内部関数を、テストから呼べるようにスクリプト本体から取り出す
    $getPackagesPath = Join-Path (Get-DevbinSubscriptsDir) "Get-Packages.ps1"
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($getPackagesPath, [ref]$null, [ref]$null)
    $functionAsts = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($functionAst in $functionAsts) {
        if ($functionAst.Name -in @("Get-PackageDownloadFileName", "Get-PackageBaseFileName")) {
            . ([scriptblock]::Create($functionAst.Extent.Text))
        }
    }

    $cases = @(
        @{ FileName = "tool-1.2.3.zip";  Version = "1.2.3"; Expected = "tool-1.2.3.zip" },
        @{ FileName = "tool-1_2_3.zip";  Version = "1.2.3"; Expected = "tool-1_2_3.zip" },
        @{ FileName = "tool.zip";        Version = "1.2.3"; Expected = "tool-1.2.3.zip" },
        @{ FileName = "tool.tar.gz";     Version = "1.2.3"; Expected = "tool-1.2.3.tar.gz" },
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
            Get-PackageDownloadFileName -Package $package -Version $version | Should Be $expected
        }
    }
}
