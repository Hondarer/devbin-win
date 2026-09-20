# OfflineMode.Tests.ps1
# packages/OFFLINE による完全オフラインモードの回帰テスト
# 外部通信は行いません。

. (Join-Path $PSScriptRoot "TestHelpers.ps1")
Import-DevbinModules

function New-OfflinePackagesLayout {
    $root = New-TestDirectory
    $subscripts = Join-Path $root "subscripts"
    $packages = Join-Path $root "packages"
    $install = Join-Path $root "bin"
    New-Item -ItemType Directory -Path $subscripts -Force | Out-Null
    New-Item -ItemType Directory -Path $packages -Force | Out-Null
    New-Item -ItemType Directory -Path $install -Force | Out-Null
    return @{
        Root       = $root
        Subscripts = $subscripts
        Packages   = $packages
        Install    = $install
    }
}

Describe "Test-DevbinOfflineMode" {

    It "マーカーが無ければオフラインではない" {
        $layout = New-OfflinePackagesLayout
        try {
            Test-DevbinOfflineMode -PackagesDir $layout.Packages | Should Be $false
        } finally {
            Remove-TestDirectory -Path $layout.Root
        }
    }

    It "packages/OFFLINE があればオフラインである" {
        $layout = New-OfflinePackagesLayout
        try {
            Set-Content -LiteralPath (Join-Path $layout.Packages "OFFLINE") -Value "" -Encoding ASCII
            Test-DevbinOfflineMode -PackagesDir $layout.Packages | Should Be $true
        } finally {
            Remove-TestDirectory -Path $layout.Root
        }
    }

    It "同名のディレクトリではオフラインにしない" {
        $layout = New-OfflinePackagesLayout
        try {
            New-Item -ItemType Directory -Path (Join-Path $layout.Packages "OFFLINE") | Out-Null
            Test-DevbinOfflineMode -PackagesDir $layout.Packages | Should Be $false
        } finally {
            Remove-TestDirectory -Path $layout.Root
        }
    }
}

Describe "Test-ComponentSourceAvailable" {

    It "ArchivePattern に一致するファイルがあれば true" {
        $layout = New-OfflinePackagesLayout
        try {
            New-Item -ItemType File -Path (Join-Path $layout.Packages "tool-1.0.0.zip") -Force | Out-Null
            $pkg = New-TestPackage -ShortName "tool" -Extra @{ ArchivePattern = "^tool-.*\.zip$" }
            Test-ComponentSourceAvailable -PackageConfig $pkg -PackagesDir $layout.Packages | Should Be $true
        } finally {
            Remove-TestDirectory -Path $layout.Root
        }
    }

    It "アーカイブが無ければ false" {
        $layout = New-OfflinePackagesLayout
        try {
            $pkg = New-TestPackage -ShortName "tool" -Extra @{ ArchivePattern = "^tool-.*\.zip$" }
            Test-ComponentSourceAvailable -PackageConfig $pkg -PackagesDir $layout.Packages | Should Be $false
        } finally {
            Remove-TestDirectory -Path $layout.Root
        }
    }

    It "VSBuildTools は channel/manifest とペイロードがあれば true" {
        $layout = New-OfflinePackagesLayout
        try {
            $vsbt = Join-Path $layout.Packages "vsbt"
            $payload = Join-Path $vsbt "x64"
            New-Item -ItemType Directory -Path $payload -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $vsbt "channel_release.json") -Value "{}" -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $vsbt "manifest_release.json") -Value "{}" -Encoding ASCII
            New-Item -ItemType File -Path (Join-Path $payload "payload.bin") -Force | Out-Null
            $pkg = New-TestPackage -ShortName "vsbt" -Extra @{
                ExtractStrategy = "VSBuildTools"
                VSBTConfig = @{ Target = "x64" }
            }
            Test-ComponentSourceAvailable -PackageConfig $pkg -PackagesDir $layout.Packages | Should Be $true
        } finally {
            Remove-TestDirectory -Path $layout.Root
        }
    }

    It "PipInstall は必要 wheel が無ければ false" {
        $layout = New-OfflinePackagesLayout
        try {
            $pkg = New-TestPackage -ShortName "yamllint" -Version "1.38.0" -Extra @{
                ExtractStrategy = "PipInstall"
                PipPackage = "yamllint"
            }
            Test-ComponentSourceAvailable -PackageConfig $pkg -PackagesDir $layout.Packages | Should Be $false
        } finally {
            Remove-TestDirectory -Path $layout.Root
        }
    }
}

Describe "Test-ComponentTreeSourceAvailable" {

    It "Hidden 依存の資材が無いと親も false" {
        $layout = New-OfflinePackagesLayout
        try {
            New-Item -ItemType File -Path (Join-Path $layout.Packages "app-1.0.0.zip") -Force | Out-Null
            $hidden = New-TestPackage -ShortName "hidden-dep" -Extra @{
                ArchivePattern = "^hidden-dep-.*\.zip$"
                Hidden = $true
            }
            $app = New-TestPackage -ShortName "app" -DependsOn @("hidden-dep") -Extra @{
                ArchivePattern = "^app-.*\.zip$"
            }
            Test-ComponentTreeSourceAvailable -ShortName "app" -Packages @($hidden, $app) -PackagesDir $layout.Packages | Should Be $false
        } finally {
            Remove-TestDirectory -Path $layout.Root
        }
    }

    It "自分と依存の資材が揃えば true" {
        $layout = New-OfflinePackagesLayout
        try {
            New-Item -ItemType File -Path (Join-Path $layout.Packages "app-1.0.0.zip") -Force | Out-Null
            New-Item -ItemType File -Path (Join-Path $layout.Packages "hidden-dep-1.0.0.zip") -Force | Out-Null
            $hidden = New-TestPackage -ShortName "hidden-dep" -Extra @{
                ArchivePattern = "^hidden-dep-.*\.zip$"
                Hidden = $true
            }
            $app = New-TestPackage -ShortName "app" -DependsOn @("hidden-dep") -Extra @{
                ArchivePattern = "^app-.*\.zip$"
            }
            Test-ComponentTreeSourceAvailable -ShortName "app" -Packages @($hidden, $app) -PackagesDir $layout.Packages | Should Be $true
        } finally {
            Remove-TestDirectory -Path $layout.Root
        }
    }
}

Describe "Invoke-PackageAcquisition のオフライン抑止" {

    It "OFFLINE があるときは取得せず失敗する" {
        InModuleScope Devbin {
            . (Join-Path $env:DEVBIN_TESTS_DIR "TestHelpers.ps1")
            $root = New-TestDirectory
            try {
                $packagesDir = Join-Path $root "packages"
                New-Item -ItemType Directory -Path $packagesDir -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $packagesDir "OFFLINE") -Value "" -Encoding ASCII
                $pkg = New-TestPackage -ShortName "tool" -Extra @{ DownloadUrl = "https://example.invalid/tool.zip" }
                $context = [PSCustomObject]@{
                    PackagesDir    = $packagesDir
                    SubscriptsDir  = (Join-Path $root "subscripts")
                    PipPackagesDir = Join-Path $packagesDir "pip-packages"
                }
                Mock Invoke-ArchiveDownload { throw "network should not be used" }

                $result = Invoke-PackageAcquisition -Packages @($pkg) -Context $context
                $result.Success | Should Be $false
                ($result.Messages -join " ") | Should Match "OFFLINE"
            } finally {
                Remove-TestDirectory -Path $root
            }
        }
    }

    It "AllowOfflineAcquisition なら OFFLINE があっても取得処理に進む" {
        InModuleScope Devbin {
            . (Join-Path $env:DEVBIN_TESTS_DIR "TestHelpers.ps1")
            $root = New-TestDirectory
            try {
                $packagesDir = Join-Path $root "packages"
                New-Item -ItemType Directory -Path $packagesDir -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $packagesDir "OFFLINE") -Value "" -Encoding ASCII
                $pkg = New-TestPackage -ShortName "tool" -Version "1.0.0" -Extra @{
                    DownloadUrl    = "https://example.invalid/tool.zip"
                    ArchivePattern = "^tool-.*\.zip$"
                }
                $context = [PSCustomObject]@{
                    PackagesDir    = $packagesDir
                    SubscriptsDir  = (Join-Path $root "subscripts")
                    PipPackagesDir = Join-Path $packagesDir "pip-packages"
                }
                Mock Invoke-ArchiveDownload {
                    [PSCustomObject]@{
                        Success          = $true
                        SuccessCount     = 1
                        TotalCount       = 1
                        FailedShortNames = @()
                    }
                }
                Mock Unblock-PackageFiles { }
                Mock Test-ShouldAcquirePipWheels { $false }

                $result = Invoke-PackageAcquisition -Packages @($pkg) -Context $context -AllowOfflineAcquisition
                $result.Success | Should Be $true
                ($result.Messages -join " ") | Should Not Match "取得はしません"
            } finally {
                Remove-TestDirectory -Path $root
            }
        }
    }
}

Describe "Resolve-ComponentSource のオフライン抑止" {

    It "OFFLINE があるときは不足アーカイブを取得しない" {
        InModuleScope Devbin {
            . (Join-Path $env:DEVBIN_TESTS_DIR "TestHelpers.ps1")
            $root = New-TestDirectory
            try {
                $packagesDir = Join-Path $root "packages"
                $installDir = Join-Path $root "bin"
                New-Item -ItemType Directory -Path $packagesDir -Force | Out-Null
                New-Item -ItemType Directory -Path $installDir -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $packagesDir "OFFLINE") -Value "" -Encoding ASCII
                $pkg = New-TestPackage -ShortName "tool" -Extra @{ ArchivePattern = "^tool-.*\.zip$" }
                Mock Invoke-PackageAcquisitionForShortNames { throw "should not acquire" }

                $source = Resolve-ComponentSource `
                    -ShortName "tool" `
                    -PackageConfig $pkg `
                    -Packages @($pkg) `
                    -InstallDir $installDir `
                    -ScriptDir (Join-Path $root "subscripts") `
                    -PackagesDir $packagesDir

                $source.Success | Should Be $false
            } finally {
                Remove-TestDirectory -Path $root
            }
        }
    }

    It "OFFLINE が無くアーカイブがあるときは成功する" {
        $layout = New-OfflinePackagesLayout
        try {
            New-Item -ItemType File -Path (Join-Path $layout.Packages "tool-1.0.0.zip") -Force | Out-Null
            $pkg = New-TestPackage -ShortName "tool" -Extra @{ ArchivePattern = "^tool-.*\.zip$" }
            $source = Resolve-ComponentSource `
                -ShortName "tool" `
                -PackageConfig $pkg `
                -Packages @($pkg) `
                -InstallDir $layout.Install `
                -ScriptDir $layout.Subscripts `
                -PackagesDir $layout.Packages

            $source.Success | Should Be $true
            (Split-Path $source.ArchiveFile -Leaf) | Should Be "tool-1.0.0.zip"
        } finally {
            Remove-TestDirectory -Path $layout.Root
        }
    }
}

Describe "オフライン時のメニュー非活性" {

    It "資材が無い項目は Unavailable で選択しない" {
        InModuleScope Devbin {
            . (Join-Path $env:DEVBIN_TESTS_DIR "TestHelpers.ps1")
            $root = New-TestDirectory
            try {
                $subscripts = Join-Path $root "subscripts"
                $packages = Join-Path $root "packages"
                $install = Join-Path $root "bin"
                New-Item -ItemType Directory -Path $subscripts -Force | Out-Null
                New-Item -ItemType Directory -Path $packages -Force | Out-Null
                New-Item -ItemType Directory -Path $install -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $packages "OFFLINE") -Value "" -Encoding ASCII
                $pkg = New-TestPackage -ShortName "tool" -Extra @{
                    ArchivePattern = "^tool-.*\.zip$"
                    DefaultChecked = $true
                }
                $state = Initialize-MenuState `
                    -Packages @($pkg) `
                    -Manifest @{ version = 1; components = @{} } `
                    -InstallDir $install `
                    -ScriptDir $subscripts

                $state.OfflineMode | Should Be $true
                $state.Disabled["tool"] | Should Be $true
                $state.DisableReasons["tool"] | Should Be "Unavailable"
                $state.Checked["tool"] | Should Be $false
            } finally {
                Remove-TestDirectory -Path $root
            }
        }
    }

    It "資材があればオフラインでも選択できる" {
        InModuleScope Devbin {
            . (Join-Path $env:DEVBIN_TESTS_DIR "TestHelpers.ps1")
            $root = New-TestDirectory
            try {
                $subscripts = Join-Path $root "subscripts"
                $packages = Join-Path $root "packages"
                $install = Join-Path $root "bin"
                New-Item -ItemType Directory -Path $subscripts -Force | Out-Null
                New-Item -ItemType Directory -Path $packages -Force | Out-Null
                New-Item -ItemType Directory -Path $install -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $packages "OFFLINE") -Value "" -Encoding ASCII
                New-Item -ItemType File -Path (Join-Path $packages "tool-1.0.0.zip") -Force | Out-Null
                $pkg = New-TestPackage -ShortName "tool" -Extra @{
                    ArchivePattern = "^tool-.*\.zip$"
                    DefaultChecked = $true
                }
                $state = Initialize-MenuState `
                    -Packages @($pkg) `
                    -Manifest @{ version = 1; components = @{} } `
                    -InstallDir $install `
                    -ScriptDir $subscripts

                $state.OfflineMode | Should Be $true
                $state.Disabled["tool"] | Should Be $false
                $state.Checked["tool"] | Should Be $true
            } finally {
                Remove-TestDirectory -Path $root
            }
        }
    }

    It "オフラインでは DefaultChecked = false でも資材があれば選択する" {
        InModuleScope Devbin {
            . (Join-Path $env:DEVBIN_TESTS_DIR "TestHelpers.ps1")
            $root = New-TestDirectory
            try {
                $subscripts = Join-Path $root "subscripts"
                $packages = Join-Path $root "packages"
                $install = Join-Path $root "bin"
                New-Item -ItemType Directory -Path $subscripts -Force | Out-Null
                New-Item -ItemType Directory -Path $packages -Force | Out-Null
                New-Item -ItemType Directory -Path $install -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $packages "OFFLINE") -Value "" -Encoding ASCII
                New-Item -ItemType File -Path (Join-Path $packages "tool-1.0.0.zip") -Force | Out-Null
                $pkg = New-TestPackage -ShortName "tool" -Extra @{
                    ArchivePattern = "^tool-.*\.zip$"
                    DefaultChecked = $false
                }
                $state = Initialize-MenuState `
                    -Packages @($pkg) `
                    -Manifest @{ version = 1; components = @{} } `
                    -InstallDir $install `
                    -ScriptDir $subscripts

                $state.Disabled["tool"] | Should Be $false
                $state.Checked["tool"] | Should Be $true
            } finally {
                Remove-TestDirectory -Path $root
            }
        }
    }

    It "オフラインでなければ DefaultChecked = false は選択しない" {
        InModuleScope Devbin {
            . (Join-Path $env:DEVBIN_TESTS_DIR "TestHelpers.ps1")
            $root = New-TestDirectory
            try {
                $subscripts = Join-Path $root "subscripts"
                $packages = Join-Path $root "packages"
                $install = Join-Path $root "bin"
                New-Item -ItemType Directory -Path $subscripts -Force | Out-Null
                New-Item -ItemType Directory -Path $packages -Force | Out-Null
                New-Item -ItemType Directory -Path $install -Force | Out-Null
                New-Item -ItemType File -Path (Join-Path $packages "tool-1.0.0.zip") -Force | Out-Null
                $pkg = New-TestPackage -ShortName "tool" -Extra @{
                    ArchivePattern = "^tool-.*\.zip$"
                    DefaultChecked = $false
                }
                $state = Initialize-MenuState `
                    -Packages @($pkg) `
                    -Manifest @{ version = 1; components = @{} } `
                    -InstallDir $install `
                    -ScriptDir $subscripts

                $state.OfflineMode | Should Be $false
                $state.Checked["tool"] | Should Be $false
            } finally {
                Remove-TestDirectory -Path $root
            }
        }
    }
}

Describe "Get-DisabledStatusDisplay" {

    It "Unavailable と External を分ける" {
        InModuleScope Devbin {
            (Get-DisabledStatusDisplay -Reason "Unavailable").Label | Should Be "Unavailable"
            (Get-DisabledStatusDisplay -Reason "External").Label | Should Be "External"
            (Get-DisabledStatusDisplay -Reason "").Label | Should Be "External"
        }
    }
}
