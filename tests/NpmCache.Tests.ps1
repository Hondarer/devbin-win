# NpmCache.Tests.ps1
# npm オフラインキャッシュの検証処理 (Get-NpmCacheStatus) に関する回帰テスト

. (Join-Path $PSScriptRoot "TestHelpers.ps1")
Import-DevbinModules

# 検証に合格する最小構成のテスト用キャッシュを生成します。
function New-TestNpmCache {
    param(
        [string]$PackagesDir,
        [string]$ShortName = "demo",
        [string]$NpmPackage = "demo-cli",
        [string]$Version = "1.0.0"
    )

    $cacheDirectory = Join-Path (Join-Path $PackagesDir "npm-packages") $ShortName
    $archiveDirectory = Join-Path $cacheDirectory "archives"
    New-Item -ItemType Directory -Path $archiveDirectory -Force | Out-Null

    $archiveName = "$NpmPackage-$Version.tgz"
    $archivePath = Join-Path $archiveDirectory $archiveName
    [System.IO.File]::WriteAllBytes($archivePath, [byte[]](1, 2, 3, 4, 5))

    $sha512 = [System.Security.Cryptography.SHA512]::Create()
    try {
        $hash = $sha512.ComputeHash([System.IO.File]::ReadAllBytes($archivePath))
    } finally {
        $sha512.Dispose()
    }
    $integrity = "sha512-" + [Convert]::ToBase64String($hash)
    $relativePath = "archives/$archiveName"

    $manifest = [ordered]@{
        schemaVersion = 2
        shortName = $ShortName
        rootPackage = $NpmPackage
        rootVersion = $Version
        rootArchive = $relativePath
        installArchives = @($relativePath)
        archives = @(
            [ordered]@{
                name = $NpmPackage
                version = $Version
                identity = "$NpmPackage@$Version"
                relativePath = $relativePath
                size = (Get-Item $archivePath).Length
                integrity = $integrity
            }
        )
    }
    $manifestJson = $manifest | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText((Join-Path $cacheDirectory "npm-cache-manifest.json"), $manifestJson, (New-Object System.Text.UTF8Encoding($false)))

    $lockJson = @"
{
  "name": "devbin-npm-project",
  "lockfileVersion": 3,
  "requires": true,
  "packages": {
    "": { "name": "devbin-npm-project", "version": "1.0.0" },
    "node_modules/$NpmPackage": { "version": "$Version", "resolved": "https://registry.npmjs.org/$NpmPackage/-/$archiveName" }
  }
}
"@
    [System.IO.File]::WriteAllText((Join-Path $cacheDirectory "package-lock.json"), $lockJson, (New-Object System.Text.UTF8Encoding($false)))

    return $cacheDirectory
}

Describe "Get-NpmCacheStatus" {

    $packageConfig = @{
        Name = "Demo CLI"
        ShortName = "demo"
        NpmPackage = "demo-cli"
        Version = "1.0.0"
    }

    It "整合したキャッシュを有効と判定する" {
        $packagesDir = New-TestDirectory
        try {
            New-TestNpmCache -PackagesDir $packagesDir | Out-Null
            $status = Get-NpmCacheStatus -PackageConfig $packageConfig -PackagesDir $packagesDir
            ($status.Missing -join ",") | Should Be ""
            ($status.Invalid -join ",") | Should Be ""
            $status.IsValid | Should Be $true
        } finally {
            Remove-TestDirectory -Path $packagesDir
        }
    }

    It "マニフェストが無ければ無効と判定する" {
        $packagesDir = New-TestDirectory
        try {
            $status = Get-NpmCacheStatus -PackageConfig $packageConfig -PackagesDir $packagesDir
            $status.IsValid | Should Be $false
            ($status.Missing -join ",") | Should Match "npm-cache-manifest.json"
        } finally {
            Remove-TestDirectory -Path $packagesDir
        }
    }

    It "package-lock.json が無ければ無効と判定する" {
        $packagesDir = New-TestDirectory
        try {
            $cacheDirectory = New-TestNpmCache -PackagesDir $packagesDir
            Remove-Item (Join-Path $cacheDirectory "package-lock.json") -Force

            $status = Get-NpmCacheStatus -PackageConfig $packageConfig -PackagesDir $packagesDir
            $status.IsValid | Should Be $false
            ($status.Missing -join ",") | Should Match "package-lock.json"
        } finally {
            Remove-TestDirectory -Path $packagesDir
        }
    }

    It "アーカイブが欠けていれば無効と判定する" {
        $packagesDir = New-TestDirectory
        try {
            $cacheDirectory = New-TestNpmCache -PackagesDir $packagesDir
            Remove-Item (Join-Path $cacheDirectory "archives\demo-cli-1.0.0.tgz") -Force

            $status = Get-NpmCacheStatus -PackageConfig $packageConfig -PackagesDir $packagesDir
            $status.IsValid | Should Be $false
            ($status.Missing -join ",") | Should Match "demo-cli-1.0.0.tgz"
        } finally {
            Remove-TestDirectory -Path $packagesDir
        }
    }

    It "アーカイブが改変されていれば無効と判定する" {
        $packagesDir = New-TestDirectory
        try {
            $cacheDirectory = New-TestNpmCache -PackagesDir $packagesDir
            [System.IO.File]::WriteAllBytes((Join-Path $cacheDirectory "archives\demo-cli-1.0.0.tgz"), [byte[]](9, 9, 9, 9, 9))

            $status = Get-NpmCacheStatus -PackageConfig $packageConfig -PackagesDir $packagesDir
            $status.IsValid | Should Be $false
            ($status.Invalid -join ",") | Should Match "integrity mismatch"
        } finally {
            Remove-TestDirectory -Path $packagesDir
        }
    }

    It "定義の版が変わればキャッシュを無効と判定する" {
        $packagesDir = New-TestDirectory
        try {
            New-TestNpmCache -PackagesDir $packagesDir | Out-Null
            $newerConfig = @{
                Name = "Demo CLI"
                ShortName = "demo"
                NpmPackage = "demo-cli"
                Version = "2.0.0"
            }

            $status = Get-NpmCacheStatus -PackageConfig $newerConfig -PackagesDir $packagesDir
            $status.IsValid | Should Be $false
            ($status.Invalid -join ",") | Should Match "root version mismatch"
        } finally {
            Remove-TestDirectory -Path $packagesDir
        }
    }
}

Describe "New-NpmOfflineInstallProject" {

    $packageConfig = @{
        Name = "Demo CLI"
        ShortName = "demo"
        NpmPackage = "demo-cli"
        Version = "1.0.0"
    }

    function Get-RewrittenLock {
        param([string]$ProjectDirectory)

        $lockPath = Join-Path $ProjectDirectory "package-lock.json"
        $lockText = Get-Content $lockPath -Raw -Encoding UTF8
        $normalized = $lockText -replace '("packages"\s*:\s*\{\s*)""(\s*:)', '$1"__devbin_npm_root__"$2'
        return ($normalized | ConvertFrom-Json)
    }

    It "dist-tag の latest を lock の版に置き換える" {
        $packagesDir = New-TestDirectory
        $projectDir = New-TestDirectory
        try {
            $cacheDirectory = New-TestNpmCache -PackagesDir $packagesDir
            $helperArchive = Join-Path $cacheDirectory "archives\helper-1.2.3.tgz"
            [System.IO.File]::WriteAllBytes($helperArchive, [byte[]](1, 2, 3, 4, 5))
            $sha512 = [System.Security.Cryptography.SHA512]::Create()
            try {
                $hash = $sha512.ComputeHash([System.IO.File]::ReadAllBytes($helperArchive))
            } finally {
                $sha512.Dispose()
            }
            $helperIntegrity = "sha512-" + [Convert]::ToBase64String($hash)

            $status = Get-NpmCacheStatus -PackageConfig $packageConfig -PackagesDir $packagesDir
            $archives = @($status.Manifest.archives)
            $archives += [pscustomobject]@{
                name = "helper"
                version = "1.2.3"
                identity = "helper@1.2.3"
                relativePath = "archives\helper-1.2.3.tgz"
                size = (Get-Item $helperArchive).Length
                integrity = $helperIntegrity
            }
            $status.Manifest.archives = $archives

            $lockJson = @"
{
  "name": "devbin-npm-project",
  "lockfileVersion": 3,
  "requires": true,
  "packages": {
    "": { "dependencies": { "demo-cli": "1.0.0" } },
    "node_modules/demo-cli": {
      "version": "1.0.0",
      "resolved": "https://registry.npmjs.org/demo-cli/-/demo-cli-1.0.0.tgz",
      "dependencies": { "helper": "latest" }
    },
    "node_modules/helper": {
      "version": "1.2.3",
      "resolved": "https://registry.npmjs.org/helper/-/helper-1.2.3.tgz"
    }
  }
}
"@
            [System.IO.File]::WriteAllText((Join-Path $cacheDirectory "package-lock.json"), $lockJson, (New-Object System.Text.UTF8Encoding($false)))

            $global:DevbinNpmOfflineStatus = $status
            $global:DevbinNpmOfflineConfig = $packageConfig
            $global:DevbinNpmOfflineProject = $projectDir
            InModuleScope DevbinNpm {
                New-NpmOfflineInstallProject -CacheStatus $global:DevbinNpmOfflineStatus -PackageConfig $global:DevbinNpmOfflineConfig -ProjectDirectory $global:DevbinNpmOfflineProject
            }

            $lock = Get-RewrittenLock -ProjectDirectory $projectDir
            [string]$lock.packages.'node_modules/demo-cli'.dependencies.helper | Should Be "1.2.3"
        } finally {
            Remove-Variable -Name DevbinNpmOfflineStatus, DevbinNpmOfflineConfig, DevbinNpmOfflineProject -Scope Global -ErrorAction SilentlyContinue
            Remove-TestDirectory -Path $packagesDir
            Remove-TestDirectory -Path $projectDir
        }
    }

    It "プラットフォーム制約のない任意依存が欠けていても失敗しない" {
        $packagesDir = New-TestDirectory
        $projectDir = New-TestDirectory
        try {
            $cacheDirectory = New-TestNpmCache -PackagesDir $packagesDir
            $status = Get-NpmCacheStatus -PackageConfig $packageConfig -PackagesDir $packagesDir

            $lockJson = @"
{
  "name": "devbin-npm-project",
  "lockfileVersion": 3,
  "requires": true,
  "packages": {
    "": { "dependencies": { "demo-cli": "1.0.0" } },
    "node_modules/demo-cli": {
      "version": "1.0.0",
      "resolved": "https://registry.npmjs.org/demo-cli/-/demo-cli-1.0.0.tgz"
    },
    "node_modules/@emnapi/runtime": {
      "version": "1.11.3",
      "resolved": "https://registry.npmjs.org/@emnapi/runtime/-/runtime-1.11.3.tgz",
      "optional": true
    }
  }
}
"@
            [System.IO.File]::WriteAllText((Join-Path $cacheDirectory "package-lock.json"), $lockJson, (New-Object System.Text.UTF8Encoding($false)))

            $global:DevbinNpmOfflineStatus = $status
            $global:DevbinNpmOfflineConfig = $packageConfig
            $global:DevbinNpmOfflineProject = $projectDir
            $threw = $false
            try {
                InModuleScope DevbinNpm {
                    New-NpmOfflineInstallProject -CacheStatus $global:DevbinNpmOfflineStatus -PackageConfig $global:DevbinNpmOfflineConfig -ProjectDirectory $global:DevbinNpmOfflineProject
                }
            } catch {
                $threw = $true
            }

            $threw | Should Be $false
            $lock = Get-RewrittenLock -ProjectDirectory $projectDir
            $names = @($lock.packages.PSObject.Properties | ForEach-Object { $_.Name })
            ($names -contains "node_modules/@emnapi/runtime") | Should Be $false
        } finally {
            Remove-Variable -Name DevbinNpmOfflineStatus, DevbinNpmOfflineConfig, DevbinNpmOfflineProject -Scope Global -ErrorAction SilentlyContinue
            Remove-TestDirectory -Path $packagesDir
            Remove-TestDirectory -Path $projectDir
        }
    }

    It "現在のプラットフォーム向けの任意依存が欠けていれば失敗する" {
        $packagesDir = New-TestDirectory
        $projectDir = New-TestDirectory
        try {
            $cacheDirectory = New-TestNpmCache -PackagesDir $packagesDir
            $status = Get-NpmCacheStatus -PackageConfig $packageConfig -PackagesDir $packagesDir

            $lockJson = @"
{
  "name": "devbin-npm-project",
  "lockfileVersion": 3,
  "requires": true,
  "packages": {
    "": { "dependencies": { "demo-cli": "1.0.0" } },
    "node_modules/demo-cli": {
      "version": "1.0.0",
      "resolved": "https://registry.npmjs.org/demo-cli/-/demo-cli-1.0.0.tgz"
    },
    "node_modules/demo-win32": {
      "version": "1.0.0",
      "resolved": "https://registry.npmjs.org/demo-win32/-/demo-win32-1.0.0.tgz",
      "optional": true,
      "os": ["win32"],
      "cpu": ["x64"]
    }
  }
}
"@
            [System.IO.File]::WriteAllText((Join-Path $cacheDirectory "package-lock.json"), $lockJson, (New-Object System.Text.UTF8Encoding($false)))

            $global:DevbinNpmOfflineStatus = $status
            $global:DevbinNpmOfflineConfig = $packageConfig
            $global:DevbinNpmOfflineProject = $projectDir
            $threw = $false
            try {
                InModuleScope DevbinNpm {
                    New-NpmOfflineInstallProject -CacheStatus $global:DevbinNpmOfflineStatus -PackageConfig $global:DevbinNpmOfflineConfig -ProjectDirectory $global:DevbinNpmOfflineProject
                }
            } catch {
                $threw = $true
            }

            $threw | Should Be $true
        } finally {
            Remove-Variable -Name DevbinNpmOfflineStatus, DevbinNpmOfflineConfig, DevbinNpmOfflineProject -Scope Global -ErrorAction SilentlyContinue
            Remove-TestDirectory -Path $packagesDir
            Remove-TestDirectory -Path $projectDir
        }
    }
}

Describe "npm 出力の扱い" {

    It "標準エラーを Out-Host に流して赤字にしない" {
        $source = Get-Content (Join-Path (Get-DevbinSubscriptsDir) "Devbin\Packages\Npm\NpmOfflineInstall.ps1") -Raw

        $source | Should Match 'function Write-NpmNativeOutput'
        $source | Should Not Match '2>&1 \| Out-Host'
    }
}

Describe "npm オフライン導入の prefix への配置" {

    It "node_modules\.bin 用の shim を prefix 直下用の参照へ書き換える" {
        $global:DevbinNpmShimSource = @(
            '"%dp0%\..\@scope\demo-cli\bin\cli.js" %*'
            'exec node  "$basedir/../@scope/demo-cli/bin/cli.js" "$@"'
        ) -join "`n"
        try {
            $converted = InModuleScope DevbinNpm {
                ConvertTo-NpmPrefixShimContent -Content $global:DevbinNpmShimSource
            }
            $converted | Should Match ([regex]::Escape('"%dp0%\node_modules\@scope\demo-cli\bin\cli.js"'))
            $converted | Should Match ([regex]::Escape('"$basedir/node_modules/@scope/demo-cli/bin/cli.js"'))
            $converted | Should Not Match ([regex]::Escape('\..\'))
            $converted | Should Not Match ([regex]::Escape('/../'))
        } finally {
            Remove-Variable -Name DevbinNpmShimSource -Scope Global -ErrorAction SilentlyContinue
        }
    }

    It "最上位のパッケージ単位で配置し、入れ子の依存と同じスコープの他パッケージを保つ" {
        $projectDir = New-TestDirectory
        $binDir = New-TestDirectory
        try {
            $sourceNodeModules = Join-Path $projectDir "node_modules"
            New-Item -ItemType Directory -Path (Join-Path $sourceNodeModules "@scope\demo-cli\node_modules\helper") -Force | Out-Null
            Set-Content -Path (Join-Path $sourceNodeModules "@scope\demo-cli\package.json") -Value '{"name":"@scope/demo-cli","version":"2.0.0"}'
            Set-Content -Path (Join-Path $sourceNodeModules "@scope\demo-cli\node_modules\helper\package.json") -Value '{"name":"helper","version":"13.0.0"}'
            New-Item -ItemType Directory -Path (Join-Path $sourceNodeModules ".bin") -Force | Out-Null
            Set-Content -Path (Join-Path $sourceNodeModules ".bin\demo.cmd") -Value '"%dp0%\..\@scope\demo-cli\bin\cli.js" %*'
            Set-Content -Path (Join-Path $sourceNodeModules ".package-lock.json") -Value '{}'

            $targetNodeModules = Join-Path $binDir "node_modules"
            New-Item -ItemType Directory -Path (Join-Path $targetNodeModules "@scope\demo-cli") -Force | Out-Null
            Set-Content -Path (Join-Path $targetNodeModules "@scope\demo-cli\stale.js") -Value 'old'
            New-Item -ItemType Directory -Path (Join-Path $targetNodeModules "@scope\other") -Force | Out-Null
            Set-Content -Path (Join-Path $targetNodeModules "@scope\other\package.json") -Value '{}'
            New-Item -ItemType Directory -Path (Join-Path $targetNodeModules "helper") -Force | Out-Null
            Set-Content -Path (Join-Path $targetNodeModules "helper\package.json") -Value '{"name":"helper","version":"2.0.0"}'

            $global:DevbinNpmCopyProject = $projectDir
            $global:DevbinNpmCopyBin = $binDir
            InModuleScope DevbinNpm {
                Copy-NpmOfflineInstallToPrefix -ProjectDirectory $global:DevbinNpmCopyProject -BinDir $global:DevbinNpmCopyBin
            }

            (Test-Path (Join-Path $targetNodeModules "@scope\demo-cli\node_modules\helper\package.json")) | Should Be $true
            (Test-Path (Join-Path $targetNodeModules "@scope\demo-cli\stale.js")) | Should Be $false
            (Test-Path (Join-Path $targetNodeModules "@scope\other\package.json")) | Should Be $true
            (Get-Content (Join-Path $targetNodeModules "helper\package.json") -Raw) | Should Match '"2.0.0"'
            (Test-Path (Join-Path $targetNodeModules ".package-lock.json")) | Should Be $false
            (Test-Path (Join-Path $targetNodeModules ".bin")) | Should Be $false
            (Get-Content (Join-Path $binDir "demo.cmd") -Raw) | Should Match ([regex]::Escape('"%dp0%\node_modules\@scope\demo-cli\bin\cli.js"'))
        } finally {
            Remove-Variable -Name DevbinNpmCopyProject, DevbinNpmCopyBin -Scope Global -ErrorAction SilentlyContinue
            Remove-TestDirectory -Path $projectDir
            Remove-TestDirectory -Path $binDir
        }
    }
}
