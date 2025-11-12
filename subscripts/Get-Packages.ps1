# Get-Packages.ps1
# packages ディレクトリにダウンロードするスクリプト

param(
    [switch]$Force = $false
)

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
        Write-Host "$fileName already exists. Skipping."
        return $true
    }

    # 現在の設定を保存
    $originalProgressPreference = $ProgressPreference
    try {
        Write-Host "Downloading $fileName..."

        # プログレスバーを無効化
        # Invoke-WebRequest のプログレスバーは性能に問題あり
        $ProgressPreference = 'SilentlyContinue'

        # SourceForge の URL の場合は実際のダウンロード URL を取得
        $downloadUrl = $Url
        if ($Url -match 'sourceforge\.net/projects/.+/files/.+/download') {
            $downloadUrl = Get-SourceForgeDownloadUrl -Url $Url
            Write-Host "  Resolved to: $downloadUrl"
        }

        Invoke-WebRequest -Uri $downloadUrl -OutFile $OutputPath -UseBasicParsing -ErrorAction Stop

        if (Test-Path $OutputPath) {
            $fileSize = (Get-Item $OutputPath).Length
            $fileSizeMB = [math]::Round($fileSize / 1MB, 2)
            Write-Host "$fileName download completed. (${fileSizeMB} MB)"
            return $true
        } else {
            throw "Download failed"
        }
    }
    catch {
        Write-Host "$fileName download failed: $($_.Exception.Message)" -ForegroundColor Red

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

# ダウンロード対象ファイルの定義
$downloads = @(
    "https://nodejs.org/dist/v22.18.0/node-v22.18.0-win-x64.zip",
    "https://github.com/jgm/pandoc/releases/download/3.8/pandoc-3.8-windows-x86_64.zip",
    "https://github.com/lierdakil/pandoc-crossref/releases/download/v0.3.21/pandoc-crossref-Windows-X64.7z",
    "https://www.doxygen.nl/files/doxygen-1.14.0.windows.x64.bin.zip",
    "https://github.com/Antonz0/doxybook2/releases/download/v1.6.1/doxybook2-windows-win64-v1.6.1.zip",
    "https://aka.ms/download-jdk/microsoft-jdk-21.0.8-windows-x64.zip",
    "https://github.com/plantuml/plantuml/releases/download/v1.2025.4/plantuml-1.2025.4.jar",
    "https://www.python.org/ftp/python/3.13.7/python-3.13.7-embed-amd64.zip",
    "https://bootstrap.pypa.io/get-pip.py",
    "https://github.com/git-for-windows/git/releases/download/v2.51.0.windows.1/PortableGit-2.51.0-64-bit.7z.exe",
    "https://builds.dotnet.microsoft.com/dotnet/Sdk/8.0.414/dotnet-sdk-8.0.414-win-x64.zip",
    "https://vscode.download.prss.microsoft.com/dbazure/download/stable/e3a5acfb517a443235981655413d566533107e92/VSCode-win32-x64-1.104.2.zip",
    "https://sourceforge.net/projects/gnuwin32/files/make/3.81/make-3.81-bin.zip/download",
    "https://sourceforge.net/projects/gnuwin32/files/make/3.81/make-3.81-dep.zip/download",
    "https://github.com/Kitware/CMake/releases/download/v4.1.2/cmake-4.1.2-windows-x86_64.zip",
    "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe",
    "https://github.com/Hondarer/nkf-bin/archive/refs/tags/v2.1.5-96c3371.zip"
)

# ダウンロード実行
Write-Host "=== File Download Started ==="
Write-Host "Downloading files to packages directory."

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

    # .exe ファイルのブロック解除
    Write-Host "`nUnblocking .exe files..."
    $exeFiles = Get-ChildItem -Path "packages" -Filter "*.exe" -ErrorAction SilentlyContinue
    $unblockedCount = 0
    foreach ($exeFile in $exeFiles) {
        try {
            Unblock-File -Path $exeFile.FullName -ErrorAction Stop
            Write-Host "  Unblocked: $($exeFile.Name)"
            $unblockedCount++
        } catch {
            Write-Host "  Warning: Failed to unblock $($exeFile.Name): $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    if ($unblockedCount -gt 0) {
        Write-Host "Unblocked $unblockedCount .exe file(s)." -ForegroundColor Green
    }

    Write-Host "`nPlease run subscripts\setup.ps1 to start the setup process."
} else {
    $failedCount = $totalCount - $successCount
    Write-Host "`n$failedCount file(s) failed to download." -ForegroundColor Yellow
    Write-Host "Please check your network connection and try again."
    Write-Host "Use the -Force option to forcefully re-download existing files."
}
