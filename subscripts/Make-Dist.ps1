# 配布用 ZIP アーカイブ生成スクリプト
#
# 作業ディレクトリの変更は行わず、リポジトリルートを基準とした絶対パスで処理します。
# 収録ファイルはリポジトリから ZIP へ直接書き込み、一時領域 (TEMP) へのステージングは行いません。
# ステージングすると、一時領域のパスの分だけ npm キャッシュ等の深いパスが延び、
# 長いパスが有効でない環境では MAX_PATH (260 文字) を超えて複製に失敗するためです。
# OneDrive 配下のようにリポジトリルート自体が深い場合にも備え、ファイルの列挙と読み込みは
# 拡張長パス形式 (\\?\) で行い、パスの長さに依存しないようにします。
param(
    [string]$OutputDir = ""
)

$ScriptDir = if ($PSScriptRoot) {
    $PSScriptRoot
} else {
    Split-Path -Parent $MyInvocation.MyCommand.Path
}

try {
    Import-Module (Join-Path $ScriptDir "Devbin") -Force -ErrorAction Stop
} catch {
    Write-Host "Error importing Devbin: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$context = New-DevbinContext -SubscriptsDir $ScriptDir
$rootDir = [System.IO.Path]::GetFullPath($context.RepositoryRoot).TrimEnd('\', '/')
$projectName = Split-Path -Leaf $rootDir

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $rootDir "dist"
} elseif (-not [System.IO.Path]::IsPathRooted($OutputDir)) {
    $OutputDir = [System.IO.Path]::GetFullPath((Join-Path $rootDir $OutputDir))
}

# ZIP ファイル名と出力先パスの生成
$date = Get-Date -Format "yyMMdd"
$zipFileName = "$projectName-$date.zip"
$zipPath = Join-Path $OutputDir $zipFileName

Write-Host "Creating distribution package: $zipPath"

if (-not (Test-Path -LiteralPath $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    Write-Host "Created directory: $OutputDir"
}

if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
    Write-Host "Removed existing file: $zipPath"
}

Write-Host "Collecting files..."

# アーカイブ収録対象 (リポジトリルートからの相対パス)
# subscripts ディレクトリ配下は再帰的に収録されるため、Devbin モジュールおよび
# config/templates 配下の各種テンプレートファイルも自動的に含まれます。
$itemsToInclude = @(
    "packages",
    "README.md",
    "LICENSE",
    "docs",
    "subscripts",
    "Manage-Bin.cmd",
    "Manage-Env.cmd"
)

# 配布対象外ファイル (リポジトリルートからの相対パス)
$excludeFiles = @(
    "subscripts\Make-Dist.ps1"
)

# 収録するファイルの絶対パス (拡張長パス形式) と、リポジトリルートからの相対パスの組を列挙
# PowerShell のコマンドレットは \\?\ 形式を正しく扱えないため、.NET の API のみで処理します。
$longRootDir = Convert-ToLongPath $rootDir
$entries = New-Object System.Collections.Generic.List[object]
foreach ($item in $itemsToInclude) {
    $sourcePath = [System.IO.Path]::Combine($longRootDir, $item)
    if ([System.IO.File]::Exists($sourcePath)) {
        $files = @($sourcePath)
    } elseif ([System.IO.Directory]::Exists($sourcePath)) {
        $files = @([System.IO.Directory]::EnumerateFiles($sourcePath, "*", [System.IO.SearchOption]::AllDirectories))
    } else {
        continue
    }

    Write-Host "Adding: $item"
    foreach ($file in $files) {
        $relativePath = $file.Substring($longRootDir.Length + 1)
        if ($excludeFiles -contains $relativePath) {
            Write-Host "Excluded: $relativePath"
            continue
        }
        $entries.Add([pscustomobject]@{ FullPath = $file; RelativePath = $relativePath })
    }
}

if ($entries.Count -eq 0) {
    Write-Error "No files found to compress"
    exit 1
}

Write-Host "Compressing $($entries.Count) files..."

# ZIP アーカイブ直下にプロジェクト名フォルダーの階層を構築
# エントリー名の区切り文字は ZIP 仕様に従い '/' を使用
$archive = $null
$succeeded = $false
try {
    $archive = [System.IO.Compression.ZipFile]::Open((Convert-ToLongPath $zipPath), [System.IO.Compression.ZipArchiveMode]::Create)
    foreach ($entry in $entries) {
        $entryName = "$projectName/" + ($entry.RelativePath -replace '\\', '/')
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $archive, $entry.FullPath, $entryName, [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
    $succeeded = $true
} catch {
    Write-Host "Error: failed to create the archive: $($_.Exception.Message)" -ForegroundColor Red
} finally {
    if ($null -ne $archive) {
        $archive.Dispose()
    }
    # 途中で失敗した不完全な ZIP は残さない
    if (-not $succeeded -and (Test-Path -LiteralPath $zipPath)) {
        Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
    }
}

if (-not $succeeded) {
    exit 1
}

Write-Host ""
Write-Host "Successfully created: $zipPath" -ForegroundColor Green

$fileSizeMB = [math]::Round((Get-Item -LiteralPath $zipPath).Length / 1MB, 2)
Write-Host "File size: $fileSizeMB MB"
