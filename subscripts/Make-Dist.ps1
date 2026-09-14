# 配布用 zip 作成スクリプト
#
# カレントディレクトリは変更せず、リポジトリ基準の絶対パスで扱う。
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

$context = New-DevbinContext -SubscriptsDir $ScriptDir
$rootDir = $context.RepositoryRoot
$projectName = Split-Path -Leaf $rootDir

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $rootDir "dist"
} elseif (-not [System.IO.Path]::IsPathRooted($OutputDir)) {
    $OutputDir = Join-Path $rootDir $OutputDir
}

# zip ファイル名と出力パスを組み立て
$date = Get-Date -Format "yyMMdd"
$zipFileName = "$projectName-$date.zip"
$zipPath = Join-Path $OutputDir $zipFileName

Write-Host "Creating distribution package: $zipPath"

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    Write-Host "Created directory: $OutputDir"
}

if (Test-Path $zipPath) {
    Remove-Item $zipPath -Force
    Write-Host "Removed existing file: $zipPath"
}

Write-Host "Collecting files..."

# ステージング領域は実行ごとに分ける
$stagingRoot = New-DevbinTempDirectory -Prefix "$projectName-staging"
$archiveRoot = Join-Path $stagingRoot $projectName
New-Item -ItemType Directory -Path $archiveRoot -Force | Out-Null

try {
    # 収録対象 (リポジトリルートからの相対パス)
    # subscripts はフォルダーごと収録するため、Devbin 配下の新モジュールと
    # config/templates のテンプレートも自動的に含まれる
    $itemsToInclude = @(
        "packages",
        "README.md",
        "LICENSE",
        "docs",
        "subscripts",
        "Manage-Bin.cmd"
    )

    # 配布物に含めないファイル (アーカイブルートからの相対パス)
    $excludeFiles = @(
        "subscripts\Make-Dist.ps1"
    )

    $addedCount = 0
    foreach ($item in $itemsToInclude) {
        $sourcePath = Join-Path $rootDir $item
        if (-not (Test-Path $sourcePath)) {
            continue
        }

        Write-Host "Adding: $item"
        $destinationPath = Join-Path $archiveRoot $item
        $parentDir = Split-Path -Parent $destinationPath
        if (-not (Test-Path $parentDir)) {
            New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
        }
        Copy-Item $sourcePath -Destination $destinationPath -Recurse -Force
        $addedCount++
    }

    foreach ($excludeFile in $excludeFiles) {
        $excludePath = Join-Path $archiveRoot $excludeFile
        if (Test-Path $excludePath) {
            Remove-Item $excludePath -Force
            Write-Host "Excluded: $excludeFile"
        }
    }

    if ($addedCount -eq 0) {
        Write-Error "No files found to compress"
        exit 1
    }

    Write-Host "Compressing files..."

    # ステージングしたルートフォルダーごと圧縮し、zip のルート直下に親フォルダー名の階層を作成する
    Compress-Archive -Path $archiveRoot -DestinationPath $zipPath -Force
} finally {
    Remove-DevbinTempDirectory -Path $stagingRoot
}

Write-Host ""
Write-Host "Successfully created: $zipPath" -ForegroundColor Green

$fileSizeMB = [math]::Round((Get-Item $zipPath).Length / 1MB, 2)
Write-Host "File size: $fileSizeMB MB"
