# NpmCacheVerify.ps1
# npm オフラインキャッシュの整合性検証 (マニフェスト、package-lock、アーカイブ整合性)

function Get-NpmCacheStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$PackageConfig,

        [Parameter(Mandatory)]
        [string]$PackagesDir,

        [string]$CacheDirectory = ""
    )

    $cacheDirectory = if ([string]::IsNullOrWhiteSpace($CacheDirectory)) {
        Get-NpmPackageCacheDirectory -PackagesDir $PackagesDir -PackageConfig $PackageConfig
    } else {
        $CacheDirectory
    }
    $manifestPath = Get-NpmCacheManifestPath -CacheDirectory $cacheDirectory
    $lockPath = Get-NpmCacheLockPath -CacheDirectory $cacheDirectory
    $status = [ordered]@{
        IsValid = $false
        CacheDirectory = $cacheDirectory
        ManifestPath = $manifestPath
        LockPath = $lockPath
        RootArchivePath = $null
        InstallArchivePaths = @()
        ArchivePaths = @()
        Missing = @()
        Invalid = @()
        Manifest = $null
    }

    if (-not (Test-Path $manifestPath -PathType Leaf)) {
        $status.Missing += $script:NpmCacheManifestName
        return [pscustomobject]$status
    }

    try {
        $manifest = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $status.Manifest = $manifest

        if ($manifest.schemaVersion -ne $script:NpmCacheSchemaVersion) {
            $status.Invalid += "unsupported schema version: $($manifest.schemaVersion)"
        }
        if ([string]$manifest.shortName -ne [string]$PackageConfig.ShortName) {
            $status.Invalid += "manifest shortName mismatch"
        }

        $expectedPackage = if ($PackageConfig.ContainsKey("NpmPackage")) { [string]$PackageConfig.NpmPackage } else { "" }
        $expectedVersion = if ($PackageConfig.ContainsKey("Version")) { [string]$PackageConfig.Version } else { "" }
        if ([string]$manifest.rootPackage -ne $expectedPackage) {
            $status.Invalid += "root package mismatch"
        }
        if (-not [string]::IsNullOrWhiteSpace($expectedVersion) -and [string]$manifest.rootVersion -ne $expectedVersion) {
            $status.Invalid += "root version mismatch"
        }

        if (-not (Test-Path $lockPath -PathType Leaf)) {
            $status.Missing += $script:NpmCacheLockName
        } else {
            try {
                # package-lock v2/v3 のルート空文字キー ("") は Windows PowerShell 5.1 の
                # JSON パーサーでプロパティ化できないため、解析時のみ一時キーへ正規化
                # (元ファイル自体は改変せず原本性を維持)
                $lockText = Get-Content $lockPath -Raw -Encoding UTF8
                $normalizedLockText = $lockText -replace '("packages"\s*:\s*\{\s*)""(\s*:)', '$1"__devbin_npm_root__"$2'
                $lock = $normalizedLockText | ConvertFrom-Json
                $lockProperties = @($lock.PSObject.Properties.Name)
                if ($lockProperties -notcontains "lockfileVersion" -or [int]$lock.lockfileVersion -lt 2) {
                    $status.Invalid += "unsupported package-lock.json format"
                }
                if ($lockProperties -notcontains "packages") {
                    $status.Invalid += "package-lock.json packages section is missing"
                } else {
                    $rootLockProperty = @($lock.packages.PSObject.Properties | Where-Object { $_.Name -eq "__devbin_npm_root__" } | Select-Object -First 1)
                    if ($rootLockProperty.Count -eq 0) {
                        $status.Invalid += "package-lock.json root package is missing"
                    } else {
                        # packages[""] は準備時の一時プロジェクトを表し、
                        # 導入対象パッケージ本体は packages["node_modules/<root package>"] に定義される
                        $rootPackageEntryName = "node_modules/$([string]$manifest.rootPackage)"
                        $rootPackageProperty = @($lock.packages.PSObject.Properties | Where-Object { $_.Name -eq $rootPackageEntryName } | Select-Object -First 1)
                        if ($rootPackageProperty.Count -eq 0) {
                            $status.Invalid += "package-lock.json installed root package is missing"
                        } elseif ([string]$rootPackageProperty[0].Value.version -ne [string]$manifest.rootVersion) {
                            $status.Invalid += "package-lock.json installed root version mismatch"
                        }
                    }
                }
            } catch {
                $status.Invalid += "invalid package-lock.json"
            }
        }

        if ([string]::IsNullOrWhiteSpace([string]$manifest.rootArchive)) {
            $status.Invalid += "rootArchive is missing"
        }

        $manifestArchives = @($manifest.archives)
        $archiveRelativePaths = @{}
        if ($manifestArchives.Count -eq 0) {
            $status.Invalid += "archive list is empty"
        }

        foreach ($archive in $manifestArchives) {
            $relativePath = [string]$archive.relativePath
            if ([string]::IsNullOrWhiteSpace($relativePath) -or [System.IO.Path]::IsPathRooted($relativePath) -or $relativePath -match '^[A-Za-z]:' -or $relativePath -match '(^|[\\/])\.\.([\\/]|$)') {
                $status.Invalid += "invalid archive path"
                continue
            }

            $archiveRelativePaths[$relativePath] = $true
            $archivePath = Join-Path $cacheDirectory $relativePath
            $status.ArchivePaths += $archivePath
            if (-not (Test-Path $archivePath -PathType Leaf)) {
                $status.Missing += $relativePath
                continue
            }

            if ($archive.size -ne $null -and [int64](Get-Item $archivePath).Length -ne [int64]$archive.size) {
                $status.Invalid += "size mismatch: $relativePath"
                continue
            }

            if (-not [string]::IsNullOrWhiteSpace([string]$archive.integrity)) {
                try {
                    $actualIntegrity = Get-NpmArchiveIntegrity -Path $archivePath
                    if ($actualIntegrity -ne [string]$archive.integrity) {
                        $status.Invalid += "integrity mismatch: $relativePath"
                    }
                } catch {
                    $status.Invalid += "cannot hash archive: $relativePath"
                }
            } else {
                $status.Invalid += "integrity is missing: $relativePath"
            }
        }

        $rootArchiveRelativePath = [string]$manifest.rootArchive
        if ([string]::IsNullOrWhiteSpace($rootArchiveRelativePath) -or [System.IO.Path]::IsPathRooted($rootArchiveRelativePath) -or $rootArchiveRelativePath -match '^[A-Za-z]:' -or $rootArchiveRelativePath -match '(^|[\\/])\.\.([\\/]|$)') {
            $status.Invalid += "invalid root archive path"
        } elseif (-not $archiveRelativePaths.ContainsKey($rootArchiveRelativePath)) {
            $status.Invalid += "root archive is not listed in archive list"
        }
        $rootArchivePath = if (-not [string]::IsNullOrWhiteSpace($rootArchiveRelativePath) -and [System.IO.Path]::IsPathRooted($rootArchiveRelativePath) -eq $false -and $rootArchiveRelativePath -notmatch '^[A-Za-z]:' -and $rootArchiveRelativePath -notmatch '(^|[\\/])\.\.([\\/]|$)') {
            Join-Path $cacheDirectory $rootArchiveRelativePath
        } else {
            $null
        }
        $status.RootArchivePath = $rootArchivePath
        if ($rootArchivePath -and -not (Test-Path $rootArchivePath -PathType Leaf)) {
            $status.Missing += [string]$manifest.rootArchive
        }

        $installArchivePaths = @()
        foreach ($relativePath in @($manifest.installArchives)) {
            if ([string]::IsNullOrWhiteSpace([string]$relativePath) -or [System.IO.Path]::IsPathRooted([string]$relativePath) -or [string]$relativePath -match '^[A-Za-z]:' -or [string]$relativePath -match '(^|[\\/])\.\.([\\/]|$)') {
                $status.Invalid += "invalid install archive path"
                continue
            }
            if (-not $archiveRelativePaths.ContainsKey([string]$relativePath)) {
                $status.Invalid += "install archive is not listed in archive list: $relativePath"
            }
            $installPath = Join-Path $cacheDirectory ([string]$relativePath)
            if (-not (Test-Path $installPath -PathType Leaf)) {
                $status.Missing += [string]$relativePath
            } else {
                $installArchivePaths += $installPath
            }
        }
        $status.InstallArchivePaths = @($installArchivePaths)

        if ($PackageConfig.ContainsKey("ArchivePattern") -and -not [string]::IsNullOrWhiteSpace([string]$PackageConfig.ArchivePattern) -and (Test-Path $rootArchivePath -PathType Leaf)) {
            if ((Split-Path $rootArchivePath -Leaf) -notmatch [string]$PackageConfig.ArchivePattern) {
                $status.Invalid += "root archive filename does not match ArchivePattern"
            }
        }
    } catch {
        $status.Invalid += "manifest read failed: $($_.Exception.Message)"
    }

    $status.Missing = @($status.Missing | Select-Object -Unique)
    $status.Invalid = @($status.Invalid | Select-Object -Unique)
    $status.IsValid = ($status.Missing.Count -eq 0 -and $status.Invalid.Count -eq 0 -and $null -ne $status.RootArchivePath -and $status.InstallArchivePaths.Count -gt 0)
    return [pscustomobject]$status
}
