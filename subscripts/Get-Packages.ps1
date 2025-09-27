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
        Invoke-WebRequest -Uri $Url -OutFile $OutputPath -UseBasicParsing -ErrorAction Stop
        
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
    # 設定を復元
    $ProgressPreference = $originalProgressPreference
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
    "https://builds.dotnet.microsoft.com/dotnet/Sdk/8.0.414/dotnet-sdk-8.0.414-win-x64.zip"
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
    $fileName = [System.IO.Path]::GetFileName(([Uri]$url).AbsolutePath)
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
    Write-Host "Please run subscripts\setup.ps1 to start the setup process."
} else {
    $failedCount = $totalCount - $successCount
    Write-Host "`n$failedCount file(s) failed to download." -ForegroundColor Yellow
    Write-Host "Please check your network connection and try again."
    Write-Host "Use the -Force option to forcefully re-download existing files."
}
