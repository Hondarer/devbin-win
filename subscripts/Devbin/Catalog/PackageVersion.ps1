# PackageVersion.ps1
# パッケージの版の解決 (定義値、およびアーカイブ内のファイルからの読み取り)

# packages ディレクトリの既定値をリポジトリ基準の絶対パスで返す
function Get-DevbinDefaultPackagesDir {
    return (Join-Path $script:DevbinRepositoryRoot "packages")
}

# ZIP 内の特定エントリから版文字列を読み取る
function Resolve-PackageVersionFromZipEntry {
    param(
        [string]$ArchiveFile,
        [hashtable]$VersionSource
    )

    if ([string]::IsNullOrWhiteSpace($ArchiveFile) -or -not (Test-Path $ArchiveFile -PathType Leaf)) {
        return ""
    }

    $entryPath = if ($VersionSource.ContainsKey("Path")) { [string]$VersionSource.Path } else { "" }
    if ([string]::IsNullOrWhiteSpace($entryPath)) {
        return ""
    }

    $pattern = if ($VersionSource.ContainsKey("Pattern")) { [string]$VersionSource.Pattern } else { "" }

    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        $zip = [System.IO.Compression.ZipFile]::OpenRead($ArchiveFile)
        try {
            $normalizedEntryPath = $entryPath -replace '\\', '/'
            $entry = $zip.Entries | Where-Object {
                ($_.FullName -replace '\\', '/') -ieq $normalizedEntryPath
            } | Select-Object -First 1

            if (-not $entry) {
                return ""
            }

            $reader = [System.IO.StreamReader]::new($entry.Open())
            try {
                $content = $reader.ReadToEnd()
            } finally {
                $reader.Dispose()
            }

            if ([string]::IsNullOrWhiteSpace($content)) {
                return ""
            }

            if (-not [string]::IsNullOrWhiteSpace($pattern)) {
                $match = [regex]::Match($content, $pattern)
                if ($match.Success) {
                    return $match.Value
                }
                return ""
            }

            $firstLine = ($content -split "\r?\n") | Where-Object {
                -not [string]::IsNullOrWhiteSpace($_)
            } | Select-Object -First 1

            if ($null -eq $firstLine) {
                return ""
            }

            return $firstLine.Trim()
        } finally {
            $zip.Dispose()
        }
    } catch {
        Write-Host "Warning: Failed to read version from archive '$ArchiveFile': $($_.Exception.Message)" -ForegroundColor Yellow
        return ""
    }
}

# パッケージの版を解決する
# VersionSource.Type = ZipEntry のときだけアーカイブから読み取り、それ以外は定義の Version を使用する
function Resolve-PackageVersion {
    param(
        [hashtable]$PackageConfig,
        [string]$PackagesDir = "",
        [string]$ArchiveFile = ""
    )

    if ([string]::IsNullOrWhiteSpace($PackagesDir)) {
        $PackagesDir = Get-DevbinDefaultPackagesDir
    }

    $fallbackVersion = if ($PackageConfig.ContainsKey("Version")) { [string]$PackageConfig.Version } else { "" }

    if (-not $PackageConfig.ContainsKey("VersionSource")) {
        return $fallbackVersion
    }

    $versionSource = $PackageConfig.VersionSource
    if (-not ($versionSource -is [hashtable])) {
        return $fallbackVersion
    }

    $sourceType = if ($versionSource.ContainsKey("Type")) { [string]$versionSource.Type } else { "" }
    if ($sourceType -ne "ZipEntry") {
        return $fallbackVersion
    }

    $candidateArchive = ""
    if (-not [string]::IsNullOrWhiteSpace($ArchiveFile) -and (Test-Path $ArchiveFile -PathType Leaf)) {
        $candidateArchive = $ArchiveFile
    } else {
        $archivePattern = if ($PackageConfig.ContainsKey("ArchivePattern")) { [string]$PackageConfig.ArchivePattern } else { "" }
        if (-not [string]::IsNullOrWhiteSpace($archivePattern) -and (Test-Path $PackagesDir)) {
            $candidate = Get-ChildItem -Path $PackagesDir -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match $archivePattern } |
                Sort-Object Name -Descending |
                Select-Object -First 1
            if ($candidate) {
                $candidateArchive = $candidate.FullName
            }
        }
    }

    $resolvedVersion = Resolve-PackageVersionFromZipEntry -ArchiveFile $candidateArchive -VersionSource $versionSource
    if (-not [string]::IsNullOrWhiteSpace($resolvedVersion)) {
        return $resolvedVersion
    }

    return $fallbackVersion
}
