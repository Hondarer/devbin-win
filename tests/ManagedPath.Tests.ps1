# ManagedPath.Tests.ps1
# 管理対象 PATH の再構成処理 (順序維持、重複排除、外部エントリ保持) の回帰テスト
# 実際のユーザー環境変数は変更せず、パス計算ロジックのみを検証します。

. (Join-Path $PSScriptRoot "TestHelpers.ps1")
Import-DevbinModules

Describe "Get-ManagedUserPathValue" {

    It "宣言順に前置し、外部エントリを後ろに残す" {
        $installDir = New-TestDirectory
        try {
            New-Item -ItemType Directory -Path (Join-Path $installDir "a\bin") -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $installDir "b\bin") -Force | Out-Null
            $packages = @(
                (New-TestPackage -ShortName "a" -PathDirs @("a\bin")),
                (New-TestPackage -ShortName "b" -PathDirs @("b\bin"))
            )

            $result = Get-ManagedUserPathValue `
                -CurrentPath "C:\External\Tool" `
                -InstallDir $installDir `
                -Packages $packages `
                -InstalledShortNames @("a", "b")

            $entries = @($result -split ';')
            $entries[0] | Should Be (Join-Path $installDir "a\bin")
            $entries[1] | Should Be (Join-Path $installDir "b\bin")
            $entries[2] | Should Be "C:\External\Tool"
        } finally {
            Remove-TestDirectory -Path $installDir
        }
    }

    It "PathPosition = Append のパッケージは外部エントリの後ろに置く" {
        $installDir = New-TestDirectory
        try {
            New-Item -ItemType Directory -Path (Join-Path $installDir "a\bin") -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $installDir "z\bin") -Force | Out-Null
            $packages = @(
                (New-TestPackage -ShortName "a" -PathDirs @("a\bin")),
                (New-TestPackage -ShortName "z" -PathDirs @("z\bin") -Extra @{ PathPosition = "Append" })
            )

            $result = Get-ManagedUserPathValue `
                -CurrentPath "C:\External\Tool" `
                -InstallDir $installDir `
                -Packages $packages `
                -InstalledShortNames @("a", "z")

            $entries = @($result -split ';')
            $entries[0] | Should Be (Join-Path $installDir "a\bin")
            $entries[1] | Should Be "C:\External\Tool"
            $entries[2] | Should Be (Join-Path $installDir "z\bin")
        } finally {
            Remove-TestDirectory -Path $installDir
        }
    }

    It "未インストールのパッケージのディレクトリは追加しない" {
        $installDir = New-TestDirectory
        try {
            New-Item -ItemType Directory -Path (Join-Path $installDir "a\bin") -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $installDir "b\bin") -Force | Out-Null
            $packages = @(
                (New-TestPackage -ShortName "a" -PathDirs @("a\bin")),
                (New-TestPackage -ShortName "b" -PathDirs @("b\bin"))
            )

            $result = Get-ManagedUserPathValue `
                -CurrentPath "" `
                -InstallDir $installDir `
                -Packages $packages `
                -InstalledShortNames @("a")

            $result | Should Be (Join-Path $installDir "a\bin")
        } finally {
            Remove-TestDirectory -Path $installDir
        }
    }

    It "HOME 配下のディレクトリは HOME を基準に追加し、devbin-win 外の導入なら既存の PATH を残す" {
        $installDir = New-TestDirectory
        $homeDir = New-TestDirectory
        try {
            $global:DevbinTestHomeDir = $homeDir
            Mock Get-DevbinHomeDirectory -ModuleName Devbin { $global:DevbinTestHomeDir }
            $homeBin = Join-Path $homeDir ".local\bin"
            New-Item -ItemType Directory -Path $homeBin -Force | Out-Null
            $packages = @( (New-TestPackage -ShortName "app" -PathDirs @(".local\bin") -DetectFiles @(".local\bin\app.exe") -Extra @{ InstallRoot = "Home" }) )

            $installed = Get-ManagedUserPathValue -CurrentPath "" -InstallDir $installDir -Packages $packages -InstalledShortNames @("app")
            $installed | Should Be $homeBin

            # devbin-win が解除した後で実体も無い場合は、管理下として PATH から外します。
            $removed = Get-ManagedUserPathValue -CurrentPath $homeBin -InstallDir $installDir -Packages $packages -InstalledShortNames @()
            $removed | Should Be ""

            # 公式インストーラーで導入済み (実体あり、devbin-win 未登録) の場合は、利用者の PATH を変更しません。
            New-Item -ItemType File -Path (Join-Path $homeBin "app.exe") -Force | Out-Null
            $kept = Get-ManagedUserPathValue -CurrentPath $homeBin -InstallDir $installDir -Packages $packages -InstalledShortNames @()
            $kept | Should Be $homeBin
        } finally {
            Remove-TestDirectory -Path $installDir
            Remove-TestDirectory -Path $homeDir
        }
    }

    It "既存 PATH に残っている管理下エントリを重複させない" {
        $installDir = New-TestDirectory
        try {
            New-Item -ItemType Directory -Path (Join-Path $installDir "a\bin") -Force | Out-Null
            $packages = @( (New-TestPackage -ShortName "a" -PathDirs @("a\bin")) )
            $existing = (Join-Path $installDir "a\bin") + ";C:\External\Tool"

            $result = Get-ManagedUserPathValue `
                -CurrentPath $existing `
                -InstallDir $installDir `
                -Packages $packages `
                -InstalledShortNames @("a")

            $entries = @($result -split ';')
            $entries.Count | Should Be 2
            $entries[0] | Should Be (Join-Path $installDir "a\bin")
        } finally {
            Remove-TestDirectory -Path $installDir
        }
    }

    It "アンインストール済みパッケージのエントリを既存 PATH から取り除く" {
        $installDir = New-TestDirectory
        try {
            New-Item -ItemType Directory -Path (Join-Path $installDir "a\bin") -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $installDir "b\bin") -Force | Out-Null
            $packages = @(
                (New-TestPackage -ShortName "a" -PathDirs @("a\bin")),
                (New-TestPackage -ShortName "b" -PathDirs @("b\bin"))
            )
            $existing = (Join-Path $installDir "b\bin") + ";C:\External\Tool"

            $result = Get-ManagedUserPathValue `
                -CurrentPath $existing `
                -InstallDir $installDir `
                -Packages $packages `
                -InstalledShortNames @("a")

            $result | Should Be ((Join-Path $installDir "a\bin") + ";C:\External\Tool")
        } finally {
            Remove-TestDirectory -Path $installDir
        }
    }

    It "存在しないディレクトリは PATH に追加しない" {
        $installDir = New-TestDirectory
        try {
            $packages = @( (New-TestPackage -ShortName "a" -PathDirs @("a\bin")) )

            $result = Get-ManagedUserPathValue `
                -CurrentPath "C:\External\Tool" `
                -InstallDir $installDir `
                -Packages $packages `
                -InstalledShortNames @("a")

            $result | Should Be "C:\External\Tool"
        } finally {
            Remove-TestDirectory -Path $installDir
        }
    }
}
