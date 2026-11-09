# Catalog.Tests.ps1
# packages.psd1 の読み込みおよび整合性検証の回帰テスト

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

    It "テレメトリの無効化値をリテラル環境変数として設定する" {
        foreach ($entry in @(
            @{ ShortName = "pwsh"; Key = "POWERSHELL_TELEMETRY_OPTOUT"; Value = "1" },
            @{ ShortName = "dotnet10sdk"; Key = "DOTNET_CLI_TELEMETRY_OPTOUT"; Value = "1" },
            @{ ShortName = "gh"; Key = "GH_TELEMETRY"; Value = "false" },
            @{ ShortName = "glab"; Key = "GLAB_SEND_TELEMETRY"; Value = "false" }
        )) {
            $package = $packages | Where-Object { $_.ShortName -eq $entry.ShortName }
            $values = Get-ComponentEnvVarValues -InstallDir $TestDrive -PackageConfig $package
            $values[$entry.Key] | Should Be $entry.Value
        }
    }

    It "git は初回導入で既定選択する" {
        $git = $packages | Where-Object { $_.ShortName -eq "git" }
        $git.DefaultChecked | Should Be $true
        $git.DisableIfCommand | Should Be "git"
    }

    It "git と vscode は Git のグローバル設定スクリプトを後処理に持つ" {
        $scriptPath = Join-Path (Get-DevbinSubscriptsDir) "Update-Git-Config.ps1"
        Test-Path $scriptPath -PathType Leaf | Should Be $true

        foreach ($shortName in @("git", "vscode")) {
            $package = $packages | Where-Object { $_.ShortName -eq $shortName }
            $paths = @($package.PostInstallScripts | ForEach-Object { $_.Path })
            ($paths -contains "Update-Git-Config.ps1") | Should Be $true
        }
    }

    It "copilot と agy は DisableIfCommand で外部検出する" {
        $copilot = $packages | Where-Object { $_.ShortName -eq "copilot" }
        $agy = $packages | Where-Object { $_.ShortName -eq "agy" }

        $copilot.DisableIfCommand | Should Be "copilot"
        $agy.DisableIfCommand | Should Be "agy"
    }

    It "libclang は共有 Python へ 18.1.1 を導入する" {
        $libclang = $packages | Where-Object { $_.ShortName -eq "libclang" }
        $libclang.ExtractStrategy | Should Be "PipInstall"
        $libclang.PipPackage | Should Be "libclang"
        $libclang.Version | Should Be "18.1.1"
        $libclang.MenuGroup | Should Be "C/C++・ビルド"
        ($libclang.DependsOn -join ",") | Should Be "python"
        ($libclang.DetectFiles -join ",") | Should Be "python3\Lib\site-packages\clang\native\libclang.dll"
        $libclang.DefaultChecked | Should Be $true
    }

    It "nasm は bin 直下へ 3.02 の実行ファイルを置く" {
        $nasm = $packages | Where-Object { $_.ShortName -eq "nasm" }
        $nasm.ExtractStrategy | Should Be "Subdirectory"
        $nasm.Version | Should Be "3.02"
        $nasm.MenuGroup | Should Be "C/C++・ビルド"
        ("nasm.exe" -match $nasm.FilePattern) | Should Be $true
        ("ndisasm.exe" -match $nasm.FilePattern) | Should Be $true
        ("LICENSE" -match $nasm.FilePattern) | Should Be $false
        ($nasm.DetectFiles -join ",") | Should Be "nasm.exe,ndisasm.exe"
        $nasm.DefaultChecked | Should Be $true
        @($nasm.PathDirs).Count | Should Be 0
        ("nasm-3.02-win64.zip" -match $nasm.ArchivePattern) | Should Be $true
        ("nasm-3.02-win32.zip" -match $nasm.ArchivePattern) | Should Be $false
    }

    It "strawberry-perl は perl を改名し、perl\bin だけを PATH の後段へ置く" {
        $perl = $packages | Where-Object { $_.ShortName -eq "strawberry-perl" }
        $perl.ExtractStrategy | Should Be "TargetDirectory"
        $perl.TargetDirectory | Should Be "strawberry-perl"
        $perl.PostSetupScript | Should Be "strawberry-perl-setup.ps1"
        $perl.Version | Should Be "5.42.3.1"
        $perl.MenuGroup | Should Be "C/C++・ビルド"
        ($perl.PathDirs -join ",") | Should Be "strawberry-perl\perl\bin"
        $perl.PathPosition | Should Be "Append"
        @($perl.EnvVars.Keys).Count | Should Be 0
        ($perl.DetectFiles -join ",") | Should Be "strawberry-perl\perl\bin\strawberry-perl.exe"
        ("strawberry-perl-5.42.3.1-64bit-portable.zip" -match $perl.ArchivePattern) | Should Be $true
        ("strawberry-perl-5.42.3.1-64bit.msi" -match $perl.ArchivePattern) | Should Be $false
        ("strawberry-perl-5.42.3.1-64bit-PDL.zip" -match $perl.ArchivePattern) | Should Be $false
    }

    It "strawberry-perl の後処理は perl.exe を改名し、ビルドに不要なものを削除する" {
        $target = Join-Path ([System.IO.Path]::GetTempPath()) ("devbin-perl-" + [guid]::NewGuid().ToString("N"))
        try {
            $bin = Join-Path $target "perl\bin"
            New-Item -ItemType Directory -Path $bin -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $bin "perl.exe") -Value "stub"
            Set-Content -LiteralPath (Join-Path $bin "perl542.dll") -Value "stub"
            $helperScripts = @("cpanm.bat", "mojo.bat", "pkg-config.bat", "perldoc.bat", "helper.cmd", "exetype.pl", "cpanm", "pkg-config")
            foreach ($name in $helperScripts) {
                Set-Content -LiteralPath (Join-Path $bin $name) -Value "stub"
            }
            Set-Content -LiteralPath (Join-Path $bin "libgcc_s_seh-1.dll") -Value "stub"
            Set-Content -LiteralPath (Join-Path $bin "perlglob.exe") -Value "stub"
            foreach ($dir in @("c\bin", "perl\vendor\lib", "perl\lib", "licenses")) {
                New-Item -ItemType Directory -Path (Join-Path $target $dir) -Force | Out-Null
            }
            Set-Content -LiteralPath (Join-Path $target "c\bin\gcc.exe") -Value "stub"
            Set-Content -LiteralPath (Join-Path $target "perl\vendor\lib\Portable.pm") -Value "stub"
            Set-Content -LiteralPath (Join-Path $target "perl\lib\Config.pm") -Value "stub"
            Set-Content -LiteralPath (Join-Path $target "licenses\perl.txt") -Value "stub"
            Set-Content -LiteralPath (Join-Path $target "portable.perl") -Value "stub"
            Set-Content -LiteralPath (Join-Path $target "portableshell.bat") -Value "stub"
            $script = Join-Path (Get-DevbinSubscriptsDir) "config\templates\strawberry-perl-setup.ps1"
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -TargetPath $target | Out-Null
            $LASTEXITCODE | Should Be 0
            (Test-Path -LiteralPath (Join-Path $bin "perl.exe")) | Should Be $false
            (Test-Path -LiteralPath (Join-Path $bin "strawberry-perl.exe")) | Should Be $true
            (Test-Path -LiteralPath (Join-Path $bin "perl542.dll")) | Should Be $true
            foreach ($name in $helperScripts) {
                (Test-Path -LiteralPath (Join-Path $bin $name)) | Should Be $false
            }
            (Test-Path -LiteralPath (Join-Path $bin "libgcc_s_seh-1.dll")) | Should Be $true
            (Test-Path -LiteralPath (Join-Path $bin "perlglob.exe")) | Should Be $true
            (Test-Path -LiteralPath (Join-Path $target "perl\lib\Config.pm")) | Should Be $true
            (Test-Path -LiteralPath (Join-Path $target "licenses\perl.txt")) | Should Be $true
            (Test-Path -LiteralPath (Join-Path $target "c")) | Should Be $false
            (Test-Path -LiteralPath (Join-Path $target "perl\vendor")) | Should Be $false
            (Test-Path -LiteralPath (Join-Path $target "portable.perl")) | Should Be $false
            (Test-Path -LiteralPath (Join-Path $target "portableshell.bat")) | Should Be $false
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -TargetPath $target | Out-Null
            $LASTEXITCODE | Should Be 0
        } finally {
            Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "get-pip の ArchivePattern は旧 tarball も対象にする" {
        $getPip = $packages | Where-Object { $_.ShortName -eq "get-pip" }
        ("pip-26.2.1.tar.gz" -match $getPip.ArchivePattern) | Should Be $true
        ("pip-26.1.1.tar.gz" -match $getPip.ArchivePattern) | Should Be $true
        ("python-3.14.7-embed-amd64.zip" -match $getPip.ArchivePattern) | Should Be $false
    }
}
