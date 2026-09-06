# NpmCache.Tests.ps1
# npm オフラインキャッシュの検証 (Get-NpmCacheStatus) の回帰テスト

. (Join-Path $PSScriptRoot "TestHelpers.ps1")
Import-DevbinModules

# 検証を通る最小構成のキャッシュを組み立てる
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
        schemaVersion = 1
        shortName = $ShortName
        rootPackage = $NpmPackage
        rootVersion = $Version
        rootArchive = $relativePath
        installArchives = @($relativePath)
        archives = @(
            [ordered]@{
                name = $NpmPackage
                version = $Version
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
