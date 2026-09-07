# Acquisition.Tests.ps1
# 取得処理 (対象選択・取得・検証・旧ファイル整理) のテスト
# 通信は行わず、Save-DownloadedFile をモックする

. (Join-Path $PSScriptRoot "TestHelpers.ps1")
Import-DevbinModules

Describe "Select-TargetPackages" {

    $packages = @(
        (New-TestPackage -ShortName "a"),
        (New-TestPackage -ShortName "b")
    )

    It "指定が無ければ全件を返す" {
        (@(Select-TargetPackages -Packages $packages) | ForEach-Object { $_.ShortName }) -join "," | Should Be "a,b"
    }

    It "指定した ShortName だけを返す" {
        (@(Select-TargetPackages -Packages $packages -ShortNames @("b")) | ForEach-Object { $_.ShortName }) -join "," | Should Be "b"
    }

    It "重複した指定はひとつにまとめる" {
        @(Select-TargetPackages -Packages $packages -ShortNames @("a", "a")).Count | Should Be 1
    }

    It "未定義の ShortName は例外にする" {
        { Select-TargetPackages -Packages $packages -ShortNames @("missing") } | Should Throw
    }
}

Describe "Get-ArchiveDownloadTargets" {

    It "DownloadUrl のあるパッケージだけを対象にする" {
        $packages = @(
            (New-TestPackage -ShortName "a" -Version "1.0.0" -Extra @{ DownloadUrl = "https://example.com/a.zip" }),
            (New-TestPackage -ShortName "b")
        )
        $targets = @(Get-ArchiveDownloadTargets -Packages $packages)

        $targets.Count | Should Be 1
        $targets[0].FileName | Should Be "a-1.0.0.zip"
    }

    It "DownloadHeaders を引き継ぐ" {
        $packages = @(
            (New-TestPackage -ShortName "a" -Extra @{
                DownloadUrl = "https://example.com/a.zip"
                DownloadHeaders = @{ "User-Agent" = "devbin" }
            })
        )
        $targets = @(Get-ArchiveDownloadTargets -Packages $packages)

        $targets[0].Headers["User-Agent"] | Should Be "devbin"
    }
}

Describe "Remove-OldPackageFiles" {

    It "現行以外の一致ファイルと元ファイル名を消す" {
        $dir = New-TestDirectory
        try {
            $package = New-TestPackage -ShortName "tool" -Version "2.0.0" -Extra @{
                ArchivePattern = "^tool-.*\.zip$"
                DownloadUrl = "https://example.com/tool.zip"
            }
            New-Item -ItemType File -Path (Join-Path $dir "tool-2.0.0.zip") -Force | Out-Null
            New-Item -ItemType File -Path (Join-Path $dir "tool-1.0.0.zip") -Force | Out-Null
            New-Item -ItemType File -Path (Join-Path $dir "tool.zip") -Force | Out-Null
            New-Item -ItemType File -Path (Join-Path $dir "other-1.0.0.zip") -Force | Out-Null

            Remove-OldPackageFiles -Package $package -CurrentFileName "tool-2.0.0.zip" -PackagesDir $dir

            (Test-Path (Join-Path $dir "tool-2.0.0.zip")) | Should Be $true
            (Test-Path (Join-Path $dir "tool-1.0.0.zip")) | Should Be $false
            (Test-Path (Join-Path $dir "tool.zip")) | Should Be $false
            (Test-Path (Join-Path $dir "other-1.0.0.zip")) | Should Be $true
        } finally {
            Remove-TestDirectory -Path $dir
        }
    }
}

Describe "Invoke-ArchiveDownload" {

    It "取得に失敗したら旧ファイルを消さない" {
        $dir = New-TestDirectory
        try {
            $package = New-TestPackage -ShortName "tool" -Version "2.0.0" -Extra @{
                ArchivePattern = "^tool-.*\.zip$"
                DownloadUrl = "https://example.com/tool.zip"
            }
            New-Item -ItemType File -Path (Join-Path $dir "tool-1.0.0.zip") -Force | Out-Null

            InModuleScope Devbin {
                Mock Save-DownloadedFile { return $false }
            }

            $targets = @(Get-ArchiveDownloadTargets -Packages @($package))
            $result = Invoke-ArchiveDownload -Targets $targets -PackagesDir $dir

            $result.Success | Should Be $false
            ($result.FailedShortNames -join ",") | Should Be "tool"
            (Test-Path (Join-Path $dir "tool-1.0.0.zip")) | Should Be $true
        } finally {
            Remove-TestDirectory -Path $dir
        }
    }

    It "取得に成功したら旧ファイルを整理する" {
        $dir = New-TestDirectory
        try {
            $package = New-TestPackage -ShortName "tool" -Version "2.0.0" -Extra @{
                ArchivePattern = "^tool-.*\.zip$"
                DownloadUrl = "https://example.com/tool.zip"
            }
            New-Item -ItemType File -Path (Join-Path $dir "tool-1.0.0.zip") -Force | Out-Null

            $global:DevbinTestPackagesDir = $dir
            InModuleScope Devbin {
                Mock Save-DownloadedFile {
                    New-Item -ItemType File -Path (Join-Path $global:DevbinTestPackagesDir "tool-2.0.0.zip") -Force | Out-Null
                    return $true
                }
            }

            $targets = @(Get-ArchiveDownloadTargets -Packages @($package))
            $result = Invoke-ArchiveDownload -Targets $targets -PackagesDir $dir

            $result.Success | Should Be $true
            (Test-Path (Join-Path $dir "tool-2.0.0.zip")) | Should Be $true
            (Test-Path (Join-Path $dir "tool-1.0.0.zip")) | Should Be $false
        } finally {
            Remove-TestDirectory -Path $dir
        }
    }
}

Describe "Save-DownloadedFile" {

    It "既存ファイルがあり -Force が無ければ取得しない" {
        $dir = New-TestDirectory
        try {
            $outputPath = Join-Path $dir "tool.zip"
            Set-Content -Path $outputPath -Value "original" -Encoding Ascii

            InModuleScope Devbin {
                Mock Invoke-WebRequest { throw "should not be called" }
            }

            (Save-DownloadedFile -Url "https://example.com/tool.zip" -OutputPath $outputPath) | Should Be $true
            (Get-Content $outputPath -Raw).Trim() | Should Be "original"
        } finally {
            Remove-TestDirectory -Path $dir
        }
    }

    It "取得に失敗しても既存ファイルを壊さない" {
        $dir = New-TestDirectory
        try {
            $outputPath = Join-Path $dir "tool.zip"
            Set-Content -Path $outputPath -Value "original" -Encoding Ascii

            InModuleScope Devbin {
                Mock Invoke-WebRequest { throw "network error" }
            }

            (Save-DownloadedFile -Url "https://example.com/tool.zip" -OutputPath $outputPath -Force) | Should Be $false
            (Get-Content $outputPath -Raw).Trim() | Should Be "original"
            (Test-Path "$outputPath.download") | Should Be $false
        } finally {
            Remove-TestDirectory -Path $dir
        }
    }
}

Describe "Test-ShouldAcquirePipWheels" {

    It "対象を絞り込んでいなければ取得する" {
        InModuleScope Devbin {
            Test-ShouldAcquirePipWheels -TargetPackages @() -RequestedShortNames @() | Should Be $true
        }
    }

    It "python が対象に含まれていれば取得する" {
        $global:DevbinTestTargets = @((New-TestPackage -ShortName "python"))
        InModuleScope Devbin {
            Test-ShouldAcquirePipWheels -TargetPackages $global:DevbinTestTargets -RequestedShortNames @("python") | Should Be $true
        }
    }

    It "PipInstall 戦略が対象に含まれていれば取得する" {
        $global:DevbinTestTargets = @((New-TestPackage -ShortName "yamllint" -Extra @{ ExtractStrategy = "PipInstall" }))
        InModuleScope Devbin {
            Test-ShouldAcquirePipWheels -TargetPackages $global:DevbinTestTargets -RequestedShortNames @("yamllint") | Should Be $true
        }
    }

    It "無関係なパッケージだけなら取得しない" {
        $global:DevbinTestTargets = @((New-TestPackage -ShortName "nodejs"))
        InModuleScope Devbin {
            Test-ShouldAcquirePipWheels -TargetPackages $global:DevbinTestTargets -RequestedShortNames @("nodejs") | Should Be $false
        }
    }
}

Describe "Invoke-NpmCacheDownload" {

    It "対象が無ければ何もしない" {
        $result = Invoke-NpmCacheDownload -NpmInstallPackages @() -PackagesDir "C:\nonexistent-devbin-test"
        $result.Success | Should Be $true
        $result.Skipped | Should Be $true
    }
}

Describe "Get-VsBuildToolsParameters" {

    It "VSBTConfig から引数を組み立てる" {
        InModuleScope Devbin {
            $package = @{
                ShortName = "vsbt"
                VSBTConfig = @{
                    MSVCVersion = "14.44"
                    SDKVersion  = "10.0.26100.0"
                    Target      = "x64"
                    HostArch    = "x64"
                }
            }
            $parameters = Get-VsBuildToolsParameters -PackageConfig $package
            $parameters.MSVCVersion | Should Be "14.44"
            $parameters.Target | Should Be "x64"
        }
    }

    It "VSBTConfig が無ければ例外にする" {
        InModuleScope Devbin {
            { Get-VsBuildToolsParameters -PackageConfig @{ ShortName = "vsbt" } } | Should Throw
        }
    }
}

Describe "取得処理の一本化" {

    $subscriptsDir = Get-DevbinSubscriptsDir

    It "Get-Packages.ps1 は取得処理を自前で持たない" {
        $filePath = Join-Path $subscriptsDir "Get-Packages.ps1"
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
        $functions = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))

        $functions.Count | Should Be 0
    }

    It "導入中の自動取得も Invoke-PackageAcquisition を通る" {
        $filePath = Join-Path $subscriptsDir "Setup-Components.psm1"
        $source = Get-Content $filePath -Raw

        ($source -match "Invoke-PackageAcquisition") | Should Be $true
        # 案内メッセージ以外で取得スクリプトを起動していないこと
        ($source -match 'getPackagesScript') | Should Be $false
    }

    It "npm の実装は子モジュールに分かれている" {
        $npmDir = Join-Path $subscriptsDir "Devbin\Packages\Npm"
        $files = @(Get-ChildItem $npmDir -Filter "*.ps1" | ForEach-Object { $_.Name } | Sort-Object)

        ($files -join ",") | Should Be "NpmCacheBuild.ps1,NpmCacheLayout.ps1,NpmCacheVerify.ps1,NpmOfflineInstall.ps1"
        (Test-Path (Join-Path $subscriptsDir "Setup-NpmCache.psm1")) | Should Be $false
    }
}

Describe "VSBT 環境スクリプトのテンプレート" {

    $templateDir = Join-Path (Get-DevbinSubscriptsDir) "config\templates"

    foreach ($templateName in @("vsbt-env.cmd.template", "vsbt-env.ps1.template")) {
        $templatePath = Join-Path $templateDir $templateName

        It "$templateName が存在する" {
            (Test-Path $templatePath -PathType Leaf) | Should Be $true
        }
    }

    It "Setup-VSBT.ps1 に長いヒアドキュメントが残っていない" {
        $vsbtPath = Join-Path (Get-DevbinSubscriptsDir) "Setup-VSBT.ps1"
        $source = Get-Content $vsbtPath -Raw

        ($source -match '\$cmdContent = @"') | Should Be $false
        ($source -match '\$ps1Content = @"') | Should Be $false
        ($source -match 'Expand-VsbtTemplate') | Should Be $true
    }

    It "テンプレートを展開すると値が差し込まれ、プレースホルダーが残らない" {
        $vsbtPath = Join-Path (Get-DevbinSubscriptsDir) "Setup-VSBT.ps1"
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($vsbtPath, [ref]$null, [ref]$null)
        $functionAst = @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Expand-VsbtTemplate'
        }, $true)) | Select-Object -First 1

        $definition = $functionAst.Extent.Text.Replace('$PSScriptRoot', "'" + (Get-DevbinSubscriptsDir) + "'")
        . ([scriptblock]::Create($definition))

        $HostArch = "x64"
        $content = Expand-VsbtTemplate `
            -TemplateName "vsbt-env.cmd.template" `
            -TargetArch "arm64" `
            -MsvcVersion "14.44.35207" `
            -MsvcMajorMinor "14.44" `
            -SdkVersion "10.0.26100.0"

        ($content -match '\{\{') | Should Be $false
        ($content -match 'set "TARGET_ARCH=arm64"') | Should Be $true
        ($content -match 'set "TARGET_SDK_VERSION=10\.0\.26100\.0"') | Should Be $true
    }
}
