# TestHelpers.ps1
# テスト間で共有するモジュール読み込みと一時領域のヘルパー

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:SubscriptsDir = Join-Path $script:RepoRoot "subscripts"

# InModuleScope の内側からもこのファイルを読み込めるようにする (プロセス内のみ有効)
$env:DEVBIN_TESTS_DIR = $PSScriptRoot

function Import-DevbinModules {
    Import-Module (Join-Path $script:SubscriptsDir "Devbin") -Force -ErrorAction Stop
}

function Get-DevbinSubscriptsDir {
    return $script:SubscriptsDir
}

function Get-DevbinRepoRoot {
    return $script:RepoRoot
}

# テスト専用の一時ディレクトリを作る (呼び出し側が Remove-TestDirectory で片付ける)
function New-TestDirectory {
    $path = Join-Path ([System.IO.Path]::GetTempPath()) ("devbin-test-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    return $path
}

function Remove-TestDirectory {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    $tempRoot = [System.IO.Path]::GetTempPath()
    # 一時領域の外を消さないよう、絶対パスを確認してから削除する
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    if (-not $fullPath.StartsWith([System.IO.Path]::GetFullPath($tempRoot), [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove a directory outside the temp area: $fullPath"
    }
    if (Test-Path $fullPath) {
        Remove-Item $fullPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# テスト用のパッケージ定義を作る
function New-TestPackage {
    param(
        [string]$ShortName,
        [string]$Version = "1.0.0",
        [string[]]$DependsOn = @(),
        [string[]]$PathDirs = @(),
        [string[]]$DetectFiles = @(),
        [hashtable]$Extra = @{}
    )

    $package = @{
        Name = $ShortName
        ShortName = $ShortName
        Version = $Version
        ArchivePattern = "$ShortName.*\.zip$"
        ExtractStrategy = "Standard"
        DependsOn = $DependsOn
        PathDirs = $PathDirs
        EnvVars = @{}
        DetectFiles = $DetectFiles
    }
    foreach ($key in $Extra.Keys) {
        $package[$key] = $Extra[$key]
    }
    return $package
}

# ShortName の一覧から、インストール済みマニフェストを作る
function New-TestManifest {
    param(
        [hashtable]$Components = @{}
    )

    $manifest = @{
        version = 1
        components = @{}
    }
    foreach ($shortName in $Components.Keys) {
        $manifest.components[$shortName] = $Components[$shortName]
    }
    return $manifest
}

function New-TestManifestEntry {
    param(
        [string]$Version = "1.0.0",
        [string]$ArchiveFile = "(test)",
        [string[]]$Files = @(),
        [string[]]$PathDirs = @()
    )

    return @{
        version = $Version
        archiveFile = $ArchiveFile
        files = $Files
        pathDirs = $PathDirs
        envVars = @{}
        installedAt = "2026-01-01T00:00:00Z"
    }
}
