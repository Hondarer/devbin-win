# DevbinModule.Tests.ps1
# 実行コンテキストと、パッケージ定義の読み込み・整合性検査のテスト

. (Join-Path $PSScriptRoot "TestHelpers.ps1")
Import-DevbinModules

# テスト用の packages.psd1 を書き出す
function New-TestCatalogFile {
    param(
        [string]$Directory,
        [string]$Body
    )

    $path = Join-Path $Directory "packages.psd1"
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($path, $Body, $utf8Bom)
    return $path
}

Describe "New-DevbinContext" {

    It "リポジトリ配下の絶対パスを組み立てる" {
        $context = New-DevbinContext -SubscriptsDir (Get-DevbinSubscriptsDir)

        $context.RepositoryRoot | Should Be (Get-DevbinRepoRoot)
        $context.ConfigPath | Should Be (Join-Path (Get-DevbinSubscriptsDir) "config\packages.psd1")
        $context.PackagesDir | Should Be (Join-Path (Get-DevbinRepoRoot) "packages")
        $context.PipPackagesDir | Should Be (Join-Path (Get-DevbinRepoRoot) "packages\pip-packages")
    }

    It "相対の InstallDir をリポジトリ基準の絶対パスに解決する" {
        $context = New-DevbinContext -InstallDir "bin" -SubscriptsDir (Get-DevbinSubscriptsDir)
        $context.InstallDir | Should Be (Join-Path (Get-DevbinRepoRoot) "bin")
    }

    It "絶対の InstallDir はそのまま使う" {
        $context = New-DevbinContext -InstallDir "C:\Tools\devbin" -SubscriptsDir (Get-DevbinSubscriptsDir)
        $context.InstallDir | Should Be "C:\Tools\devbin"
    }

    It "呼び出しごとに異なる一時領域を割り当てる" {
        $first = New-DevbinContext -SubscriptsDir (Get-DevbinSubscriptsDir)
        $second = New-DevbinContext -SubscriptsDir (Get-DevbinSubscriptsDir)
        ($first.TempRoot -eq $second.TempRoot) | Should Be $false
    }
}

Describe "Import-DevbinDataFile" {

    It ".psd1 をハッシュテーブルとして読み込む" {
        $dir = New-TestDirectory
        try {
            $path = New-TestCatalogFile -Directory $dir -Body "@{ Packages = @( @{ ShortName = 'a' } ) }"
            $data = Import-DevbinDataFile -Path $path
            $data.Packages[0].ShortName | Should Be "a"
        } finally {
            Remove-TestDirectory -Path $dir
        }
    }

    It "ファイル内のコードを実行しない" {
        $dir = New-TestDirectory
        try {
            $marker = Join-Path $dir "executed.txt"
            $body = "@{ Packages = @( @{ ShortName = (New-Item -ItemType File -Path '$marker').Name } ) }"
            $path = New-TestCatalogFile -Directory $dir -Body $body

            { Import-DevbinDataFile -Path $path } | Should Throw
            (Test-Path $marker) | Should Be $false
        } finally {
            Remove-TestDirectory -Path $dir
        }
    }

    It "存在しないファイルは例外にする" {
        { Import-DevbinDataFile -Path "C:\nonexistent-devbin-test\packages.psd1" } | Should Throw
    }
}

Describe "Import-PackageCatalog" {

    It "現在の packages.psd1 を整合性検査つきで読み込める" {
        $context = New-DevbinContext -SubscriptsDir (Get-DevbinSubscriptsDir)
        $catalog = Import-PackageCatalog -Path $context.ConfigPath

        ($catalog.Errors -join ", ") | Should Be ""
        $catalog.Success | Should Be $true
        $catalog.Packages.Count | Should Be 50
    }

    It "ShortName の重複を変更開始前に検出する" {
        $dir = New-TestDirectory
        try {
            $body = @"
@{
    Packages = @(
        @{ Name = 'A'; ShortName = 'a'; Version = '1'; ArchivePattern = 'a'; ExtractStrategy = 'Standard'; DependsOn = @(); PathDirs = @(); EnvVars = @{}; DetectFiles = @() },
        @{ Name = 'A2'; ShortName = 'a'; Version = '1'; ArchivePattern = 'a'; ExtractStrategy = 'Standard'; DependsOn = @(); PathDirs = @(); EnvVars = @{}; DetectFiles = @() }
    )
}
"@
            $path = New-TestCatalogFile -Directory $dir -Body $body
            $catalog = Import-PackageCatalog -Path $path

            $catalog.Success | Should Be $false
            ($catalog.Errors -join " ") | Should Match "ShortName が重複"
        } finally {
            Remove-TestDirectory -Path $dir
        }
    }

    It "未定義の依存先を検出する" {
        $dir = New-TestDirectory
        try {
            $body = @"
@{
    Packages = @(
        @{ Name = 'A'; ShortName = 'a'; Version = '1'; ArchivePattern = 'a'; ExtractStrategy = 'Standard'; DependsOn = @('missing'); PathDirs = @(); EnvVars = @{}; DetectFiles = @() }
    )
}
"@
            $path = New-TestCatalogFile -Directory $dir -Body $body
            $catalog = Import-PackageCatalog -Path $path

            $catalog.Success | Should Be $false
            ($catalog.Errors -join " ") | Should Match "missing"
        } finally {
            Remove-TestDirectory -Path $dir
        }
    }

    It "循環依存を検出する" {
        $dir = New-TestDirectory
        try {
            $body = @"
@{
    Packages = @(
        @{ Name = 'A'; ShortName = 'a'; Version = '1'; ArchivePattern = 'a'; ExtractStrategy = 'Standard'; DependsOn = @('b'); PathDirs = @(); EnvVars = @{}; DetectFiles = @() },
        @{ Name = 'B'; ShortName = 'b'; Version = '1'; ArchivePattern = 'b'; ExtractStrategy = 'Standard'; DependsOn = @('a'); PathDirs = @(); EnvVars = @{}; DetectFiles = @() }
    )
}
"@
            $path = New-TestCatalogFile -Directory $dir -Body $body
            $catalog = Import-PackageCatalog -Path $path

            $catalog.Success | Should Be $false
            ($catalog.Errors -join " ") | Should Match "循環依存"
        } finally {
            Remove-TestDirectory -Path $dir
        }
    }

    It "必須プロパティの不足を検出する" {
        $dir = New-TestDirectory
        try {
            $path = New-TestCatalogFile -Directory $dir -Body "@{ Packages = @( @{ ShortName = 'a' } ) }"
            $catalog = Import-PackageCatalog -Path $path

            $catalog.Success | Should Be $false
            ($catalog.Errors -join " ") | Should Match "必須プロパティ"
        } finally {
            Remove-TestDirectory -Path $dir
        }
    }

    It "Packages が無ければ失敗として返す" {
        $dir = New-TestDirectory
        try {
            $path = New-TestCatalogFile -Directory $dir -Body "@{ Other = 1 }"
            $catalog = Import-PackageCatalog -Path $path
            $catalog.Success | Should Be $false
        } finally {
            Remove-TestDirectory -Path $dir
        }
    }
}

Describe "Get-PackageTargetDirectory / Get-PythonDirectory" {

    $packages = @(
        (New-TestPackage -ShortName "python" -Extra @{ TargetDirectory = "python-3.14" }),
        (New-TestPackage -ShortName "nodejs")
    )

    It "TargetDirectory があればそれを使う" {
        Get-PackageTargetDirectory -PackageConfig $packages[0] | Should Be "python-3.14"
    }

    It "TargetDirectory が無ければ ShortName を使う" {
        Get-PackageTargetDirectory -PackageConfig $packages[1] | Should Be "nodejs"
    }

    It "Python の配置先を定義から引く" {
        Get-PythonDirectory -Packages $packages -InstallDir "C:in" | Should Be "C:in\python-3.14"
    }

    It "定義が無ければ空文字を返す" {
        Get-PythonDirectory -Packages @() -InstallDir "C:in" | Should Be ""
    }

    It "現在の定義では packages.psd1 の TargetDirectory と一致する" {
        $context = New-DevbinContext -SubscriptsDir (Get-DevbinSubscriptsDir)
        $catalog = Import-PackageCatalog -Path $context.ConfigPath
        $python = Get-PackageByShortName -ShortName "python" -Packages $catalog.Packages

        Get-PythonDirectory -Packages $catalog.Packages -InstallDir "C:in" |
            Should Be (Join-Path "C:in" $python.TargetDirectory)
    }
}

Describe "Python 配置先のハードコード" {

    It "コード側に python-3.13 が直書きされていない" {
        $subscriptsDir = Get-DevbinSubscriptsDir
        $hits = @()
        foreach ($file in (Get-ChildItem $subscriptsDir -Recurse -Include *.ps1, *.psm1)) {
            # packages.psd1 は設定なので対象外
            if (Select-String -Path $file.FullName -Pattern "python-3\.13" -Quiet) {
                $hits += $file.Name
            }
        }
        ($hits -join ", ") | Should Be ""
    }
}
