# Catalog.Tests.ps1
# packages.psd1 の読み込みと整合性の回帰テスト

. (Join-Path $PSScriptRoot "TestHelpers.ps1")
Import-DevbinModules

Describe "packages.psd1" {

    $configPath = Join-Path (Get-DevbinSubscriptsDir) "config\packages.psd1"
    $catalog = Import-PackageCatalog -Path $configPath
    $packages = @($catalog.Packages)
    $shortNames = @($packages | ForEach-Object { $_.ShortName })

    It "整合性検査を通って読み込める" {
        $catalog.Success | Should Be $true
        ($catalog.Errors -join ", ") | Should Be ""
        $packages.Count | Should BeGreaterThan 0
    }

    It "必須プロパティがすべてのパッケージに揃っている" {
        $required = @("Name", "ShortName", "Version", "ArchivePattern", "ExtractStrategy", "DependsOn", "PathDirs", "EnvVars", "DetectFiles")
        $missing = @()
        foreach ($package in $packages) {
            foreach ($key in $required) {
                if (-not $package.ContainsKey($key)) {
                    $missing += "$($package.ShortName): $key"
                }
            }
        }
        ($missing -join ", ") | Should Be ""
    }

    It "ShortName が重複しない" {
        $duplicates = @($shortNames | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
        ($duplicates -join ", ") | Should Be ""
    }

    It "DependsOn が未定義のパッケージを指さない" {
        $unknown = @()
        foreach ($package in $packages) {
            foreach ($dependency in @($package.DependsOn)) {
                if ($shortNames -notcontains $dependency) {
                    $unknown += "$($package.ShortName) -> $dependency"
                }
            }
        }
        ($unknown -join ", ") | Should Be ""
    }

    It "循環依存がない" {
        $result = Resolve-DependencyOrder -ShortNames $shortNames -Packages $packages
        ($result.Errors -join ", ") | Should Be ""
        $result.Success | Should Be $true
    }

    It "宣言順のすべてのパッケージが導入順に現れる" {
        $result = Resolve-DependencyOrder -ShortNames $shortNames -Packages $packages
        @($result.Order).Count | Should Be $packages.Count
    }
}
