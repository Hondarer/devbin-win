# Get-Packages.ps1
# packages ディレクトリにダウンロードするスクリプト

param(
    [switch]$Force = $false
)

# スクリプトのディレクトリを取得
$ScriptDir = if ($PSScriptRoot) {
    $PSScriptRoot
} elseif ($MyInvocation.MyCommand.Path) {
    Split-Path -Parent $MyInvocation.MyCommand.Path
} else {
    Get-Location | Select-Object -ExpandProperty Path
}

# パッケージ設定を読み込む
$PackagesConfigPath = Join-Path $ScriptDir "config\packages.psd1"
if (-not (Test-Path $PackagesConfigPath)) {
    Write-Host "Error: Package configuration not found: $PackagesConfigPath" -ForegroundColor Red
    exit 1
}

$PackagesConfig = Invoke-Expression (Get-Content $PackagesConfigPath -Raw)
$Packages = $PackagesConfig.Packages

# packages ディレクトリが存在しない場合は作成
if (-not (Test-Path "packages")) {
    Write-Host "Creating packages directory..."
    New-Item -ItemType Directory -Path "packages" | Out-Null
}

# SourceForge の実際のダウンロード URL を取得
function Get-SourceForgeDownloadUrl {
    param([string]$Url)

    try {
        $ProgressPreference = 'SilentlyContinue'
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -ErrorAction Stop

        # meta refresh タグから実際のダウンロード URL を抽出
        if ($response.Content -match '<meta[^>]+http-equiv="refresh"[^>]+content="\d+;\s*url=([^"]+)"') {
            $downloadUrl = $matches[1]
            # HTML エンティティをデコード (&amp; -> &)
            $downloadUrl = $downloadUrl -replace '&amp;', '&'
            return $downloadUrl
        }

        # ダイレクトダウンロード URL を構築
        if ($Url -match 'sourceforge\.net/projects/([^/]+)/files/(.+)/download') {
            $project = $matches[1]
            $filePath = $matches[2]
            return "https://downloads.sourceforge.net/project/$project/$filePath"
        }

        return $Url
    }
    catch {
        return $Url
    }
}

# 共通のダウンロード関数
function Get-File {
    param(
        [string]$Url,
        [string]$OutputPath
    )

    $fileName = Split-Path $OutputPath -Leaf

    # ファイルが既に存在する場合はスキップ (-Force オプションが指定されていない場合)
    if ((Test-Path $OutputPath) -and -not $Force) {
        Write-Host "  $fileName already exists. Skipping."
        return $true
    }

    # 現在の設定を保存
    $originalProgressPreference = $ProgressPreference
    try {
        Write-Host "  Downloading $fileName..."

        # プログレスバーを無効化
        # Invoke-WebRequest のプログレスバーは性能に問題あり
        $ProgressPreference = 'SilentlyContinue'

        # SourceForge の URL の場合は実際のダウンロード URL を取得
        $downloadUrl = $Url
        if ($Url -match 'sourceforge\.net/projects/.+/files/.+/download') {
            $downloadUrl = Get-SourceForgeDownloadUrl -Url $Url
            Write-Host "    Resolved to: $downloadUrl"
        }

        Invoke-WebRequest -Uri $downloadUrl -OutFile $OutputPath -UseBasicParsing -ErrorAction Stop

        if (Test-Path $OutputPath) {
            $fileSize = (Get-Item $OutputPath).Length
            $fileSizeMB = [math]::Round($fileSize / 1MB, 2)
            Write-Host "  $fileName download completed. (${fileSizeMB} MB)"
            return $true
        } else {
            throw "Download failed"
        }
    }
    catch {
        Write-Host "  $fileName download failed: $($_.Exception.Message)" -ForegroundColor Red

        # 失敗した場合は部分的にダウンロードされたファイルを削除
        if (Test-Path $OutputPath) {
            Remove-Item $OutputPath -Force
        }

        return $false
    }
    finally {
        # 設定を復元
        $ProgressPreference = $originalProgressPreference
    }
}

# ダウンロード対象ファイルを packages.psd1 から取得
$downloads = @()
foreach ($package in $Packages) {
    if ($package.DownloadUrl) {
        $downloads += $package.DownloadUrl
    }
}

if ($downloads.Count -eq 0) {
    Write-Host "Error: No download URLs found in package configuration." -ForegroundColor Red
    exit 1
}

# ダウンロード実行
Write-Host "=== File Download Started ==="
Write-Host "Downloading files to packages directory."
Write-Host "Total packages: $($downloads.Count)"

if ($Force) {
    Write-Host "Force download mode: overwriting existing files." -ForegroundColor Yellow
}

$successCount = 0
$totalCount = $downloads.Count

foreach ($url in $downloads) {
    $uri = [Uri]$url
    $fileName = [System.IO.Path]::GetFileName($uri.AbsolutePath)

    # SourceForge の /download で終わる URL の場合、その前のセグメントを使用
    if ($fileName -eq "download" -and $uri.Host -like "*sourceforge.net*") {
        $pathSegments = $uri.AbsolutePath.Split('/', [StringSplitOptions]::RemoveEmptyEntries)
        $fileName = $pathSegments[-2]  # /download の前のセグメント
    }
    # GitHub の /archive/refs/tags/ URL の場合、リポジトリ名を含むファイル名を生成
    elseif ($uri.Host -eq "github.com" -and $uri.AbsolutePath -match '/([^/]+)/([^/]+)/archive/refs/tags/(.+)$') {
        $repoName = $matches[2]
        $tagName = [System.IO.Path]::GetFileNameWithoutExtension($matches[3])
        $extension = [System.IO.Path]::GetExtension($matches[3])
        # タグ名の先頭が "v" で始まる場合は除去
        $tagName = $tagName -replace '^v', ''
        $fileName = "$repoName-$tagName$extension"
    }

    $outputPath = Join-Path "packages" $fileName

    if (Get-File -Url $url -OutputPath $outputPath) {
        $successCount++
    }

    Start-Sleep -Milliseconds 500
}

Write-Host "`nDownload Summary:"
Write-Host "Success: $successCount / $totalCount"

if ($successCount -eq $totalCount) {
    Write-Host "`nAll files downloaded successfully." -ForegroundColor Green

    # packages フォルダ内のすべてのファイルのブロック解除
    Write-Host "`nUnblocking downloaded files..."
    $allFiles = Get-ChildItem -Path "packages" -File -ErrorAction SilentlyContinue
    $unblockedCount = 0
    foreach ($file in $allFiles) {
        try {
            Unblock-File -Path $file.FullName -ErrorAction Stop
            Write-Host "  Unblocked: $($file.Name)"
            $unblockedCount++
        } catch {
            Write-Host "  Warning: Failed to unblock $($file.Name): $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    if ($unblockedCount -gt 0) {
        Write-Host "`nUnblocked $unblockedCount file(s)." -ForegroundColor Green
    }
} else {
    $failedCount = $totalCount - $successCount
    Write-Host "`n$failedCount file(s) failed to download." -ForegroundColor Yellow
    Write-Host "Please check your network connection and try again."
    Write-Host "Use the -Force option to forcefully re-download existing files."
}
