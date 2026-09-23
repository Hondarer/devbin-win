# NpmCache.Tests.ps1
# npm オフラインキャッシュの判定と、npm install -g / uninstall -g の実行に関する回帰テスト
# npm の実行はモックに置き換え、外部通信と実環境の変更は行いません。

. (Join-Path $PSScriptRoot "TestHelpers.ps1")
Import-DevbinModules

# 検証に合格する最小構成のテスト用キャッシュを生成します。
function New-TestNpmCache {
    param(
        [string]$PackagesDir,
        [string]$ShortName = "demo",
        [string]$NpmPackage = "demo-cli",
        [string]$Version = "1.0.0",
        [string[]]$RequestedPackages = @(),
        [int]$SchemaVersion = 3
    )

    $cacheDirectory = Join-Path (Join-Path $PackagesDir "npm-packages") $ShortName
    foreach ($entry in @("index-v5", "content-v2")) {
        New-Item -ItemType Directory -Path (Join-Path $cacheDirectory "cache\_cacache\$entry") -Force | Out-Null
    }

    if ($RequestedPackages.Count -eq 0) {
        $RequestedPackages = @("$NpmPackage@$Version")
    }
    $manifest = [ordered]@{
        schemaVersion     = $SchemaVersion
        shortName         = $ShortName
        rootPackage       = $NpmPackage
        rootVersion       = $Version
        requestedPackages = @($RequestedPackages)
    }
    [System.IO.File]::WriteAllText((Join-Path $cacheDirectory "npm-cache-manifest.json"), ($manifest | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding($false)))

    return $cacheDirectory
}

# グローバル ツリーに package.json を持つパッケージを作成します。
function New-TestGlobalPackage {
    param(
        [string]$BinDir,
        [string]$Name,
        [string]$Version = "1.0.0",
        [string]$BinJson = ""
    )

    $directory = Join-Path (Join-Path $BinDir "node_modules") ($Name -replace '/', '\')
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $bin = if ($BinJson) { ",`"bin`":$BinJson" } else { "" }
    Set-Content -Path (Join-Path $directory "package.json") -Value "{`"name`":`"$Name`",`"version`":`"$Version`"$bin}"
    return $directory
}

$script:DemoConfig = @{
    Name       = "Demo CLI"
    ShortName  = "demo"
    NpmPackage = "demo-cli"
    Version    = "1.0.0"
}

Describe "Get-NpmCacheStatus" {

    It "整合したキャッシュを有効と判定する" {
        $packagesDir = New-TestDirectory
        try {
            New-TestNpmCache -PackagesDir $packagesDir | Out-Null

            $status = Get-NpmCacheStatus -PackageConfig $script:DemoConfig -PackagesDir $packagesDir
            $status.IsValid | Should Be $true
        } finally {
            Remove-TestDirectory -Path $packagesDir
        }
    }

    It "マニフェストが無ければ無効と判定する" {
        $packagesDir = New-TestDirectory
        try {
            $status = Get-NpmCacheStatus -PackageConfig $script:DemoConfig -PackagesDir $packagesDir
            $status.IsValid | Should Be $false
            ($status.Missing -join ",") | Should Match "npm-cache-manifest.json"
        } finally {
            Remove-TestDirectory -Path $packagesDir
        }
    }

    It "npm のキャッシュ本体が無ければ無効と判定する" {
        $packagesDir = New-TestDirectory
        try {
            $cacheDirectory = New-TestNpmCache -PackagesDir $packagesDir
            Remove-Item -LiteralPath (Join-Path $cacheDirectory "cache\_cacache\content-v2") -Recurse -Force

            $status = Get-NpmCacheStatus -PackageConfig $script:DemoConfig -PackagesDir $packagesDir
            $status.IsValid | Should Be $false
            ($status.Missing -join ",") | Should Match "content-v2"
        } finally {
            Remove-TestDirectory -Path $packagesDir
        }
    }

    It "独自の依存ツリーを記録した旧形式のキャッシュは無効と判定する" {
        $packagesDir = New-TestDirectory
        try {
            New-TestNpmCache -PackagesDir $packagesDir -SchemaVersion 2 | Out-Null

            $status = Get-NpmCacheStatus -PackageConfig $script:DemoConfig -PackagesDir $packagesDir
            $status.IsValid | Should Be $false
            ($status.Invalid -join ",") | Should Match "unsupported schema version"
        } finally {
            Remove-TestDirectory -Path $packagesDir
        }
    }

    It "定義の版が変わればキャッシュを無効と判定する" {
        $packagesDir = New-TestDirectory
        try {
            New-TestNpmCache -PackagesDir $packagesDir | Out-Null
            $newerConfig = $script:DemoConfig.Clone()
            $newerConfig.Version = "2.0.0"

            $status = Get-NpmCacheStatus -PackageConfig $newerConfig -PackagesDir $packagesDir
            $status.IsValid | Should Be $false
            ($status.Invalid -join ",") | Should Match "root version mismatch"
        } finally {
            Remove-TestDirectory -Path $packagesDir
        }
    }

    It "NpmDependencies が変わればキャッシュを無効と判定する" {
        $packagesDir = New-TestDirectory
        try {
            New-TestNpmCache -PackagesDir $packagesDir | Out-Null
            $config = $script:DemoConfig.Clone()
            $config.NpmDependencies = @("demo-plugin@^1.0.0")

            $status = Get-NpmCacheStatus -PackageConfig $config -PackagesDir $packagesDir
            $status.IsValid | Should Be $false
            ($status.Invalid -join ",") | Should Match "requested packages mismatch"
        } finally {
            Remove-TestDirectory -Path $packagesDir
        }
    }
}

Describe "npm のグローバル ツリーの参照" {

    It "導入されているパッケージの版を返し、未導入なら空文字を返す" {
        $binDir = New-TestDirectory
        try {
            New-TestGlobalPackage -BinDir $binDir -Name "@scope/demo-cli" -Version "2.1.0" | Out-Null

            Get-NpmGlobalPackageVersion -BinDir $binDir -PackageName "@scope/demo-cli" | Should Be "2.1.0"
            Get-NpmGlobalPackageVersion -BinDir $binDir -PackageName "missing" | Should Be ""
        } finally {
            Remove-TestDirectory -Path $binDir
        }
    }

    It "要求したパッケージのうち導入済みのものを所有パスとして返す" {
        $binDir = New-TestDirectory
        try {
            New-TestGlobalPackage -BinDir $binDir -Name "textlint" -Version "15.8.0" | Out-Null
            New-TestGlobalPackage -BinDir $binDir -Name "@scope/rule" -Version "1.0.0" | Out-Null
            $config = @{
                ShortName       = "textlint"
                NpmPackage      = "textlint"
                Version         = "15.8.0"
                NpmDependencies = @("@scope/rule@^1.0.0", "missing-rule@^1.0.0")
            }

            (@(Get-NpmComponentOwnedPaths -BinDir $binDir -PackageConfig $config) -join ",") | Should Be "node_modules\textlint,node_modules\@scope\rule"
        } finally {
            Remove-TestDirectory -Path $binDir
        }
    }
}

Describe "Invoke-NpmInstallFromCache" {

    It "bin を prefix として npm install -g --offline を実行する" {
        $packagesDir = New-TestDirectory
        $binDir = New-TestDirectory
        try {
            New-TestNpmCache -PackagesDir $packagesDir | Out-Null
            $global:DevbinNpmTestArgs = @{
                NpmCommandPath = "C:\fake\npm.cmd"
                BinDir         = $binDir
                PackagesDir    = $packagesDir
                PackageConfig  = $script:DemoConfig
            }

            $result = InModuleScope DevbinNpm {
                Mock Invoke-NpmCli {
                    $global:DevbinNpmCalledArgs = $Arguments
                    $directory = Join-Path $global:DevbinNpmTestArgs.BinDir "node_modules\demo-cli"
                    New-Item -ItemType Directory -Path $directory -Force | Out-Null
                    Set-Content -Path (Join-Path $directory "package.json") -Value '{"name":"demo-cli","version":"1.0.0"}'
                    return 0
                }
                Invoke-NpmInstallFromCache @global:DevbinNpmTestArgs
            }

            $result | Should Be $true
            $joined = $global:DevbinNpmCalledArgs -join " "
            $joined | Should Match "^install -g --prefix "
            $joined | Should Match ([regex]::Escape("--prefix $binDir "))
            $joined | Should Match "--offline --cache "
            $joined | Should Match "--ignore-scripts demo-cli@1\.0\.0$"
        } finally {
            Remove-Variable -Name DevbinNpmTestArgs, DevbinNpmCalledArgs -Scope Global -ErrorAction SilentlyContinue
            Remove-TestDirectory -Path $packagesDir
            Remove-TestDirectory -Path $binDir
        }
    }

    It "導入された版が定義と異なれば失敗する" {
        $packagesDir = New-TestDirectory
        $binDir = New-TestDirectory
        try {
            New-TestNpmCache -PackagesDir $packagesDir | Out-Null
            $global:DevbinNpmTestArgs = @{
                NpmCommandPath = "C:\fake\npm.cmd"
                BinDir         = $binDir
                PackagesDir    = $packagesDir
                PackageConfig  = $script:DemoConfig
            }

            $result = InModuleScope DevbinNpm {
                Mock Invoke-NpmCli {
                    $directory = Join-Path $global:DevbinNpmTestArgs.BinDir "node_modules\demo-cli"
                    New-Item -ItemType Directory -Path $directory -Force | Out-Null
                    Set-Content -Path (Join-Path $directory "package.json") -Value '{"name":"demo-cli","version":"0.9.0"}'
                    return 0
                }
                Invoke-NpmInstallFromCache @global:DevbinNpmTestArgs
            }

            $result | Should Be $false
        } finally {
            Remove-Variable -Name DevbinNpmTestArgs -Scope Global -ErrorAction SilentlyContinue
            Remove-TestDirectory -Path $packagesDir
            Remove-TestDirectory -Path $binDir
        }
    }

    It "キャッシュが無効なら npm を実行しない" {
        $packagesDir = New-TestDirectory
        try {
            $global:DevbinNpmTestArgs = @{
                NpmCommandPath = "C:\fake\npm.cmd"
                BinDir         = "C:\fake\bin"
                PackagesDir    = $packagesDir
                PackageConfig  = $script:DemoConfig
            }

            $result = InModuleScope DevbinNpm {
                Mock Invoke-NpmCli { return 0 }
                $installed = Invoke-NpmInstallFromCache @global:DevbinNpmTestArgs
                Assert-MockCalled Invoke-NpmCli -Times 0 -Exactly -Scope It
                $installed
            }

            $result | Should Be $false
        } finally {
            Remove-Variable -Name DevbinNpmTestArgs -Scope Global -ErrorAction SilentlyContinue
            Remove-TestDirectory -Path $packagesDir
        }
    }
}

Describe "Uninstall-NpmGlobalPackages" {

    It "導入済みのパッケージだけを npm uninstall -g に渡す" {
        $binDir = New-TestDirectory
        try {
            New-TestGlobalPackage -BinDir $binDir -Name "textlint" | Out-Null
            $npmPath = Join-Path $binDir "npm.cmd"
            Set-Content -Path $npmPath -Value "@echo off"
            $global:DevbinNpmTestArgs = @{
                NpmCommandPath = $npmPath
                BinDir         = $binDir
                PackageNames   = @("textlint", "missing-rule")
            }

            $result = InModuleScope DevbinNpm {
                Mock Invoke-NpmCli {
                    $global:DevbinNpmCalledArgs = $Arguments
                    Remove-Item -LiteralPath (Join-Path $global:DevbinNpmTestArgs.BinDir "node_modules\textlint") -Recurse -Force
                    return 0
                }
                Uninstall-NpmGlobalPackages @global:DevbinNpmTestArgs
            }

            $result | Should Be $true
            ($global:DevbinNpmCalledArgs -join " ") | Should Match "^uninstall -g --prefix .* textlint$"
        } finally {
            Remove-Variable -Name DevbinNpmTestArgs, DevbinNpmCalledArgs -Scope Global -ErrorAction SilentlyContinue
            Remove-TestDirectory -Path $binDir
        }
    }

    It "npm を実行できない場合は、パッケージと、そのパッケージを指す shim だけを削除する" {
        $binDir = New-TestDirectory
        try {
            New-TestGlobalPackage -BinDir $binDir -Name "@mermaid-js/mermaid-cli" -BinJson '{"mmdc":"src/cli.js"}' | Out-Null
            New-TestGlobalPackage -BinDir $binDir -Name "@mermaid-js/other" | Out-Null
            Set-Content -Path (Join-Path $binDir "mmdc.cmd") -Value '"%dp0%\node_modules\@mermaid-js\mermaid-cli\src\cli.js" %*'
            Set-Content -Path (Join-Path $binDir "mmdc") -Value 'exec node "$basedir/node_modules/@mermaid-js/mermaid-cli/src/cli.js" "$@"'
            # 同名のコマンドを別のパッケージが提供している shim は残す
            Set-Content -Path (Join-Path $binDir "mmdc.ps1") -Value '& "$basedir/node_modules/another/cli.js" $args'

            $result = Uninstall-NpmGlobalPackages -NpmCommandPath "" -BinDir $binDir -PackageNames @("@mermaid-js/mermaid-cli")

            $result | Should Be $true
            (Test-Path (Join-Path $binDir "node_modules\@mermaid-js\mermaid-cli")) | Should Be $false
            (Test-Path (Join-Path $binDir "node_modules\@mermaid-js\other")) | Should Be $true
            (Test-Path (Join-Path $binDir "mmdc.cmd")) | Should Be $false
            (Test-Path (Join-Path $binDir "mmdc")) | Should Be $false
            (Test-Path (Join-Path $binDir "mmdc.ps1")) | Should Be $true
        } finally {
            Remove-TestDirectory -Path $binDir
        }
    }

    It "空になったスコープのディレクトリも削除する" {
        $binDir = New-TestDirectory
        try {
            New-TestGlobalPackage -BinDir $binDir -Name "@plantuml/core" | Out-Null

            Uninstall-NpmGlobalPackages -NpmCommandPath "" -BinDir $binDir -PackageNames @("@plantuml/core") | Out-Null

            (Test-Path (Join-Path $binDir "node_modules\@plantuml")) | Should Be $false
            (Test-Path (Join-Path $binDir "node_modules")) | Should Be $true
        } finally {
            Remove-TestDirectory -Path $binDir
        }
    }
}

Describe "npm 出力の扱い" {

    It "標準エラーを Out-Host に流して赤字にしない" {
        $source = Get-Content (Join-Path (Get-DevbinSubscriptsDir) "Devbin\Packages\Npm\NpmGlobalPackages.ps1") -Raw

        $source | Should Match 'function Write-NpmNativeOutput'
        $source | Should Not Match '2>&1 \| Out-Host'
    }
}
