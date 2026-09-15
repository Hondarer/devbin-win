# TestHelpers.ps1
# テスト共通のモジュールインポートおよび一時ディレクトリ管理ヘルパー

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:SubscriptsDir = Join-Path $script:RepoRoot "subscripts"

# InModuleScope スコープ内からの参照を可能にするための環境変数を設定します (現在のプロセス内でのみ有効)。
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

# テスト専用の一時ディレクトリを作成します (呼び出し側で Remove-TestDirectory により破棄)。
function New-TestDirectory {
    $path = Join-Path ([System.IO.Path]::GetTempPath()) ("devbin-test-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    return $path
}

function Remove-TestDirectory {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    $tempRoot = [System.IO.Path]::GetTempPath()
    # 一時ディレクトリ外のファイル削除を防止するため、絶対パスを検証した上で削除します。
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    if (-not $fullPath.StartsWith([System.IO.Path]::GetFullPath($tempRoot), [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove a directory outside the temp area: $fullPath"
    }
    if (Test-Path $fullPath) {
        Remove-Item $fullPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# テスト用のパッケージ定義ハッシュテーブルを生成します。
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

# コンポーネント情報からテスト用のインストール済みマニフェストを生成します。
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
