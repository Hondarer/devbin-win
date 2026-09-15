# 配布用 ZIP アーカイブ生成スクリプト
#
# 作業ディレクトリの変更は行わず、リポジトリルートを基準とした絶対パスで処理します。
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

# ZIP ファイル名と出力先パスの生成
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

# 実行単位で独立したステージング領域を作成
$stagingRoot = New-DevbinTempDirectory -Prefix "$projectName-staging"
$archiveRoot = Join-Path $stagingRoot $projectName
New-Item -ItemType Directory -Path $archiveRoot -Force | Out-Null

try {
    # アーカイブ収録対象 (リポジトリルートからの相対パス)
    # subscripts ディレクトリ配下は再帰的に収録されるため、Devbin モジュールおよび
    # config/templates 配下の各種テンプレートファイルも自動的に含まれます。
    $itemsToInclude = @(
        "packages",
        "README.md",
        "LICENSE",
        "docs",
        "subscripts",
        "Manage-Bin.cmd"
    )

    # 配布対象外ファイル (アーカイブルートからの相対パス)
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

    # ステージングしたルートフォルダーごと圧縮し、ZIP アーカイブ直下にプロジェクト名フォルダーの階層を構築
    Compress-Archive -Path $archiveRoot -DestinationPath $zipPath -Force
} finally {
    Remove-DevbinTempDirectory -Path $stagingRoot
}

Write-Host ""
Write-Host "Successfully created: $zipPath" -ForegroundColor Green

$fileSizeMB = [math]::Round((Get-Item $zipPath).Length / 1MB, 2)
Write-Host "File size: $fileSizeMB MB"
