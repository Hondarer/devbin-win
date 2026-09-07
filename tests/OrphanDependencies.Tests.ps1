# OrphanDependencies.Tests.ps1
# 孤立した隠し依存パッケージの削除に関する回帰テスト

. (Join-Path $PSScriptRoot "TestHelpers.ps1")
Import-DevbinModules

Describe "Remove-OrphanDependencies" {

    $packages = @(
        (New-TestPackage -ShortName "hidden-dep" -Extra @{ Hidden = $true }),
        (New-TestPackage -ShortName "app" -DependsOn @("hidden-dep")),
        (New-TestPackage -ShortName "other-app" -DependsOn @("hidden-dep")),
        (New-TestPackage -ShortName "visible-dep"),
        (New-TestPackage -ShortName "app2" -DependsOn @("visible-dep"))
    )

    It "誤った引数名で呼ぶと実行時エラーになる" {
        $manifest = New-TestManifest
        { Remove-OrphanDependencies -ShortName "app" -Packages $packages -InstallDir "C:\nonexistent" -Manifest $manifest -ErrorAction Stop } |
            Should Throw
    }

    It "他に依存元がない隠し依存を削除する" {
        InModuleScope Devbin {
            . (Join-Path $env:DEVBIN_TESTS_DIR "TestHelpers.ps1")
            $packages = @(
                (New-TestPackage -ShortName "hidden-dep" -Extra @{ Hidden = $true }),
                (New-TestPackage -ShortName "app" -DependsOn @("hidden-dep"))
            )
            $manifest = New-TestManifest -Components @{ "hidden-dep" = (New-TestManifestEntry) }

            Mock Uninstall-Component { return $true }
            Remove-OrphanDependencies -UninstalledShortName "app" -Packages $packages -InstallDir "C:\nonexistent" -Manifest $manifest
            Assert-MockCalled Uninstall-Component -Scope It -Times 1 -Exactly -ParameterFilter { $ShortName -eq "hidden-dep" }
        }
    }

    It "他の依存元が残っている隠し依存は削除しない" {
        InModuleScope Devbin {
            . (Join-Path $env:DEVBIN_TESTS_DIR "TestHelpers.ps1")
            $packages = @(
                (New-TestPackage -ShortName "hidden-dep" -Extra @{ Hidden = $true }),
                (New-TestPackage -ShortName "app" -DependsOn @("hidden-dep")),
                (New-TestPackage -ShortName "other-app" -DependsOn @("hidden-dep"))
            )
            $manifest = New-TestManifest -Components @{
                "hidden-dep" = (New-TestManifestEntry)
                "other-app"  = (New-TestManifestEntry)
            }

            Mock Uninstall-Component { return $true }
            Remove-OrphanDependencies -UninstalledShortName "app" -Packages $packages -InstallDir "C:\nonexistent" -Manifest $manifest
            Assert-MockCalled Uninstall-Component -Scope It -Times 0 -Exactly
        }
    }

    It "Hidden でない依存先は削除しない" {
        InModuleScope Devbin {
            . (Join-Path $env:DEVBIN_TESTS_DIR "TestHelpers.ps1")
            $packages = @(
                (New-TestPackage -ShortName "visible-dep"),
                (New-TestPackage -ShortName "app2" -DependsOn @("visible-dep"))
            )
            $manifest = New-TestManifest -Components @{ "visible-dep" = (New-TestManifestEntry) }

            Mock Uninstall-Component { return $true }
            Remove-OrphanDependencies -UninstalledShortName "app2" -Packages $packages -InstallDir "C:\nonexistent" -Manifest $manifest
            Assert-MockCalled Uninstall-Component -Scope It -Times 0 -Exactly
        }
    }
}
