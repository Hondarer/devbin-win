# Dependencies.Tests.ps1
# パッケージ依存関係の解決 (インストール順、アンインストール順、循環依存、欠落検出) の回帰テスト

. (Join-Path $PSScriptRoot "TestHelpers.ps1")
Import-DevbinModules

Describe "Resolve-DependencyOrder" {

    $packages = @(
        (New-TestPackage -ShortName "base"),
        (New-TestPackage -ShortName "mid" -DependsOn @("base")),
        (New-TestPackage -ShortName "leaf" -DependsOn @("mid")),
        (New-TestPackage -ShortName "other" -DependsOn @("base"))
    )

    It "依存先が先に来る順序を返す" {
        $result = Resolve-DependencyOrder -ShortNames @("leaf") -Packages $packages
        $result.Success | Should Be $true
        ($result.Order -join ",") | Should Be "base,mid,leaf"
    }

    It "複数指定でも共有する依存先を 1 度だけ返す" {
        $result = Resolve-DependencyOrder -ShortNames @("mid", "other") -Packages $packages
        $result.Success | Should Be $true
        ($result.Order -join ",") | Should Be "base,mid,other"
    }

    It "循環依存を失敗として返す" {
        $cyclic = @(
            (New-TestPackage -ShortName "a" -DependsOn @("b")),
            (New-TestPackage -ShortName "b" -DependsOn @("a"))
        )
        $result = Resolve-DependencyOrder -ShortNames @("a") -Packages $cyclic
        $result.Success | Should Be $false
        ($result.Errors -join " ") | Should Match "循環依存"
    }

    It "自己参照も循環依存として扱う" {
        $selfRef = @( (New-TestPackage -ShortName "a" -DependsOn @("a")) )
        $result = Resolve-DependencyOrder -ShortNames @("a") -Packages $selfRef
        $result.Success | Should Be $false
    }

    It "未定義の依存先を失敗として返す" {
        $broken = @( (New-TestPackage -ShortName "a" -DependsOn @("missing")) )
        $result = Resolve-DependencyOrder -ShortNames @("a") -Packages $broken
        $result.Success | Should Be $false
        ($result.Errors -join " ") | Should Match "missing"
    }

    It "問題がなければ Errors は空になる" {
        $result = Resolve-DependencyOrder -ShortNames @("base") -Packages $packages
        $result.Errors.Count | Should Be 0
    }
}

Describe "Get-Dependents" {

    $packages = @(
        (New-TestPackage -ShortName "base"),
        (New-TestPackage -ShortName "mid" -DependsOn @("base")),
        (New-TestPackage -ShortName "leaf" -DependsOn @("base"))
    )

    It "インストール済みの依存元のみを返す" {
        $manifest = New-TestManifest -Components @{ mid = (New-TestManifestEntry) }
        $result = @(Get-Dependents -ShortName "base" -Packages $packages -Manifest $manifest)
        ($result -join ",") | Should Be "mid"
    }

    It "未インストールの依存元は返さない" {
        $manifest = New-TestManifest
        $result = @(Get-Dependents -ShortName "base" -Packages $packages -Manifest $manifest)
        $result.Count | Should Be 0
    }
}

Describe "Get-UninstallOrder" {

    $packages = @(
        (New-TestPackage -ShortName "base"),
        (New-TestPackage -ShortName "mid" -DependsOn @("base")),
        (New-TestPackage -ShortName "leaf" -DependsOn @("mid"))
    )
    $manifest = New-TestManifest -Components @{
        base = (New-TestManifestEntry)
        mid  = (New-TestManifestEntry)
        leaf = (New-TestManifestEntry)
    }

    It "依存元から依存先の順に並べる" {
        $result = @(Get-UninstallOrder -ShortNames @("base", "mid", "leaf") -Packages $packages -Manifest $manifest)
        ($result -join ",") | Should Be "leaf,mid,base"
    }

    It "入力順が逆でも同じ順序になる" {
        $result = @(Get-UninstallOrder -ShortNames @("leaf", "mid", "base") -Packages $packages -Manifest $manifest)
        ($result -join ",") | Should Be "leaf,mid,base"
    }

    It "対象がひとつなら、そのまま返す" {
        $result = @(Get-UninstallOrder -ShortNames @("leaf") -Packages $packages -Manifest $manifest)
        ($result -join ",") | Should Be "leaf"
    }

    It "対象外の依存元がいても順序を返す" {
        $result = @(Get-UninstallOrder -ShortNames @("base", "mid") -Packages $packages -Manifest $manifest)
        ($result -join ",") | Should Be "mid,base"
    }

    It "入力をすべて含む" {
        $result = @(Get-UninstallOrder -ShortNames @("base", "mid", "leaf") -Packages $packages -Manifest $manifest)
        $result.Count | Should Be 3
    }
}
