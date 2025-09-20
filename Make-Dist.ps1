# 配布用zip作成スクリプト
param(
    [string]$OutputDir = "dist"
)

# スクリプトのディレクトリに移動
Set-Location -Path $PSScriptRoot

# プロジェクト名をスクリプトの親フォルダ名から取得
$projectName = Split-Path -Leaf $PSScriptRoot

# 現在の日付を取得 (yymmdd形式)
$date = Get-Date -Format "yyMMdd"

# zip ファイル名と出力パスを組み立て
$zipFileName = "$projectName-$date.zip"
$zipPath = Join-Path $OutputDir $zipFileName

Write-Host "Creating distribution package: $zipPath"

# dist ディレクトリが存在しない場合は作成
if (!(Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir | Out-Null
    Write-Host "Created directory: $OutputDir"
}

# 既存の zip ファイルが存在する場合は削除
if (Test-Path $zipPath) {
    Remove-Item $zipPath -Force
    Write-Host "Removed existing file: $zipPath"
}

Write-Host "Collecting files..."

# ステージングディレクトリを作成して、その直下にプロジェクト名のルートフォルダを作成
$stagingRoot = Join-Path $env:TEMP "$projectName-staging-$date-$PID"
$archiveRoot = Join-Path $stagingRoot $projectName
New-Item -ItemType Directory -Path $archiveRoot -Force | Out-Null

# 追加対象のファイル・ディレクトリ一覧
$itemsToInclude = @(
    "packages",
    "README.md",
    "Install.md",
    "Setup.ps1",
    "Install.cmd",
    "Uninstall.cmd",
    "Setup-Home.md",
    "Setup-Home.ps1",
    "Setup-Home.cmd",
    "Update-GitBash-Profile.md",
    "Update-GitBash-Profile.ps1",
    "Install-GitBash-Profile.cmd",
    "Uninstall-GitBash-Profile.cmd",
    "Update-MinGW-Profile.md",
    "Update-MinGW-Profile.ps1",
    "Install-MinGW-Profile.cmd",
    "Uninstall-MinGW-Profile.cmd"
)

$addedCount = 0
foreach ($item in $itemsToInclude) {
    if (Test-Path $item) {
        Write-Host "Adding: $item"
        $dest = Join-Path $archiveRoot $item
        # 親ディレクトリを事前に作成してからコピー
        $parentDir = Split-Path -Parent $dest
        if (!(Test-Path $parentDir)) {
            New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
        }
        Copy-Item $item -Destination $dest -Recurse -Force
        $addedCount++
    }
}

if ($addedCount -eq 0) {
    # ステージングディレクトリをクリーンアップして終了
    if (Test-Path $stagingRoot) {
        Remove-Item $stagingRoot -Recurse -Force
    }
    Write-Error "No files found to compress"
    exit 1
}

Write-Host "Compressing files..."

# ステージングしたルートフォルダごと圧縮することで、zip のルート直下に親フォルダ名の階層を作る
Compress-Archive -Path $archiveRoot -DestinationPath $zipPath -Force

# ステージングディレクトリをクリーンアップ
if (Test-Path $stagingRoot) {
    Remove-Item $stagingRoot -Recurse -Force
}

Write-Host "`nSuccessfully created: $zipPath" -ForegroundColor Green

# ファイルサイズを表示
$fileSize = (Get-Item $zipPath).Length
$fileSizeMB = [math]::Round($fileSize / 1MB, 2)
Write-Host "File size: $fileSizeMB MB"
