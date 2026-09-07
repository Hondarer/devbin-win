# Manifest.Tests.ps1
# マニフェスト入出力と状態判定の回帰テスト

. (Join-Path $PSScriptRoot "TestHelpers.ps1")
Import-DevbinModules

Describe "Write-Manifest" {

    It "保存に成功すると true を返し、読み戻せる" {
        $installDir = New-TestDirectory
        try {
            $manifest = New-TestManifest -Components @{ app = (New-TestManifestEntry -Version "2.0.0") }
            (Write-Manifest -InstallDir $installDir -Manifest $manifest) | Should Be $true

            $reloaded = Read-Manifest -InstallDir $installDir
            $reloaded.components.app.version | Should Be "2.0.0"
        } finally {
            Remove-TestDirectory -Path $installDir
        }
    }

    It "既存ファイルを置換できない場合は false を返して旧内容を保持する" {
        $root = New-TestDirectory
        $lockedFile = $null
        try {
            $old = New-TestManifest -Components @{ app = (New-TestManifestEntry -Version "1.0.0") }
            (Write-Manifest -InstallDir $root -Manifest $old) | Should Be $true
            $path = Get-ManifestPath -InstallDir $root
            $lockedFile = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
            $new = New-TestManifest -Components @{ app = (New-TestManifestEntry -Version "2.0.0") }
            (Write-Manifest -InstallDir $root -Manifest $new) | Should Be $false
            (Read-Manifest -InstallDir $root).components.app.version | Should Be "1.0.0"
            (Test-Path "$path.tmp") | Should Be $false
            $lockedFile.Dispose()
            $lockedFile = $null
            (Write-Manifest -InstallDir $root -Manifest $new) | Should Be $true
            (Read-Manifest -InstallDir $root).components.app.version | Should Be "2.0.0"
        } finally {
            if ($lockedFile) { $lockedFile.Dispose() }
            Remove-TestDirectory -Path $root
        }
    }

    It "保存に失敗すると false を返す" {
        $root = New-TestDirectory
        try {
            $installDir = Join-Path $root "no\such\place"
            (Write-Manifest -InstallDir $installDir -Manifest (New-TestManifest)) | Should Be $false
        } finally {
            Remove-TestDirectory -Path $root
        }
    }

    It "一時ファイルを残さない" {
        $installDir = New-TestDirectory
        try {
            Write-Manifest -InstallDir $installDir -Manifest (New-TestManifest) | Out-Null
            $manifestPath = Get-ManifestPath -InstallDir $installDir
            (Test-Path "$manifestPath.tmp") | Should Be $false
        } finally {
            Remove-TestDirectory -Path $installDir
        }
    }
}

Describe "Get-ComponentStatus" {

    It "マニフェストにあり、検出ファイルも揃っていれば Installed" {
        $installDir = New-TestDirectory
        try {
            New-Item -ItemType File -Path (Join-Path $installDir "app.exe") -Force | Out-Null
            $package = New-TestPackage -ShortName "app" -Version "1.0.0" -DetectFiles @("app.exe")
            $manifest = New-TestManifest -Components @{ app = (New-TestManifestEntry -Version "1.0.0") }

            Get-ComponentStatus -Manifest $manifest -InstallDir $installDir -PackageConfig $package -PackagesDir $installDir |
                Should Be "Installed"
        } finally {
            Remove-TestDirectory -Path $installDir
        }
    }

    It "定義の版が新しければ Updateable" {
        $installDir = New-TestDirectory
        try {
            New-Item -ItemType File -Path (Join-Path $installDir "app.exe") -Force | Out-Null
            $package = New-TestPackage -ShortName "app" -Version "2.0.0" -DetectFiles @("app.exe")
            $manifest = New-TestManifest -Components @{ app = (New-TestManifestEntry -Version "1.0.0") }

            Get-ComponentStatus -Manifest $manifest -InstallDir $installDir -PackageConfig $package -PackagesDir $installDir |
                Should Be "Updateable"
        } finally {
            Remove-TestDirectory -Path $installDir
        }
    }

    It "マニフェストにあるのに検出ファイルが無ければ Broken" {
        $installDir = New-TestDirectory
        try {
            $package = New-TestPackage -ShortName "app" -Version "1.0.0" -DetectFiles @("app.exe")
            $manifest = New-TestManifest -Components @{ app = (New-TestManifestEntry -Version "1.0.0") }

            Get-ComponentStatus -Manifest $manifest -InstallDir $installDir -PackageConfig $package -PackagesDir $installDir |
                Should Be "Broken"
        } finally {
            Remove-TestDirectory -Path $installDir
        }
    }

    It "マニフェストに無いのに検出ファイルがあれば Legacy" {
        $installDir = New-TestDirectory
        try {
            New-Item -ItemType File -Path (Join-Path $installDir "app.exe") -Force | Out-Null
            $package = New-TestPackage -ShortName "app" -Version "1.0.0" -DetectFiles @("app.exe")

            Get-ComponentStatus -Manifest (New-TestManifest) -InstallDir $installDir -PackageConfig $package -PackagesDir $installDir |
                Should Be "Legacy"
        } finally {
            Remove-TestDirectory -Path $installDir
        }
    }

    It "どちらも無ければ NotInstalled" {
        $installDir = New-TestDirectory
        try {
            $package = New-TestPackage -ShortName "app" -Version "1.0.0" -DetectFiles @("app.exe")

            Get-ComponentStatus -Manifest (New-TestManifest) -InstallDir $installDir -PackageConfig $package -PackagesDir $installDir |
                Should Be "NotInstalled"
        } finally {
            Remove-TestDirectory -Path $installDir
        }
    }
}

Describe "Compare-PackageVersion" {

    It "左が新しければ 1 を返す" {
        Compare-PackageVersion -LeftVersion "2.0.0" -RightVersion "1.9.9" | Should Be 1
    }

    It "同じなら 0 を返す" {
        Compare-PackageVersion -LeftVersion "1.0.0" -RightVersion "1.0.0" | Should Be 0
    }

    It "左が古ければ -1 を返す" {
        Compare-PackageVersion -LeftVersion "1.0.0" -RightVersion "1.0.1" | Should Be -1
    }
}
