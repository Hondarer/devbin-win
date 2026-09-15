# FileDownload.ps1
# ファイルダウンロード共通処理
#
# ダウンロード失敗時に既存ファイルを破損させないよう、一時ファイルへ受信完了した後に置換します。

# SourceForge のリダイレクトおよびメタ更新タグから実際のダウンロード URL を解決
function Get-SourceForgeDownloadUrl {
    param([string]$Url)

    try {
        $ProgressPreference = 'SilentlyContinue'
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -ErrorAction Stop

        # meta refresh タグからリダイレクト先 URL を抽出
        if ($response.Content -match '<meta[^>]+http-equiv="refresh"[^>]+content="\d+;\s*url=([^"]+)"') {
            $downloadUrl = $matches[1]
            # HTML エンティティのデコード (&amp; -> &)
            $downloadUrl = $downloadUrl -replace '&amp;', '&'
            return $downloadUrl
        }

        # ダイレクトダウンロード URL の構築
        if ($Url -match 'sourceforge\.net/projects/([^/]+)/files/(.+)/download') {
            $project = $matches[1]
            $filePath = $matches[2]
            return "https://downloads.sourceforge.net/project/$project/$filePath"
        }

        return $Url
    } catch {
        return $Url
    }
}

# 指定 URL からファイルをダウンロードして保存
# 既存ファイルは -Force 指定時のみ上書き。取得失敗時は既存ファイルを保持
function Save-DownloadedFile {
    param(
        [string]$Url,
        [string]$OutputPath,
        [hashtable]$Headers = @{},
        [switch]$Force
    )

    $fileName = Split-Path $OutputPath -Leaf

    if ((Test-Path $OutputPath) -and -not $Force) {
        Write-Host "  $fileName already exists. Skipping."
        return $true
    }

    # ダウンロード途中の不完全ファイルによる既存破損を防ぐため、一時ファイルを経由して配置
    $temporaryPath = "$OutputPath.download"
    $originalProgressPreference = $ProgressPreference

    try {
        Write-Host "  Downloading $fileName..."

        # Invoke-WebRequest のプログレス表示に伴うスループット低下を回避するため非表示化
        $ProgressPreference = 'SilentlyContinue'

        $downloadUrl = $Url
        if ($Url -match 'sourceforge\.net/projects/.+/files/.+/download') {
            $downloadUrl = Get-SourceForgeDownloadUrl -Url $Url
            Write-Host "    Resolved to: $downloadUrl"
        }

        if (Test-Path $temporaryPath) {
            Remove-Item $temporaryPath -Force -ErrorAction SilentlyContinue
        }

        $requestArgs = @{
            Uri             = $downloadUrl
            OutFile         = $temporaryPath
            UseBasicParsing = $true
            ErrorAction     = 'Stop'
        }
        if ($Headers -and $Headers.Count -gt 0) {
            $requestArgs.Headers = $Headers
        }

        Invoke-WebRequest @requestArgs

        if (-not (Test-Path $temporaryPath)) {
            throw "Download failed"
        }

        Move-Item -LiteralPath $temporaryPath -Destination $OutputPath -Force -ErrorAction Stop

        $fileSizeMB = [math]::Round((Get-Item $OutputPath).Length / 1MB, 2)
        Write-Host "  $fileName download completed. (${fileSizeMB} MB)"
        return $true
    } catch {
        Write-Host "  $fileName download failed: $($_.Exception.Message)" -ForegroundColor Red
        if (Test-Path $OutputPath) {
            Write-Host "  既存のファイルはそのまま残します: $fileName" -ForegroundColor Yellow
        }
        return $false
    } finally {
        if (Test-Path $temporaryPath) {
            Remove-Item $temporaryPath -Force -ErrorAction SilentlyContinue
        }
        $ProgressPreference = $originalProgressPreference
    }
}

# packages ディレクトリ配下の全ファイルからゾーン識別子 (Mark-of-the-Web) を解除
function Unblock-PackageFiles {
    param([string]$PackagesDir)

    try {
        $allFiles = Get-ChildItem -Path $PackagesDir -File -Recurse -ErrorAction SilentlyContinue
        if ($allFiles) {
            $allFiles | Unblock-File -ErrorAction SilentlyContinue
            Write-Host "Unblocked $($allFiles.Count) file(s)."
        }
    } catch {
        Write-Host "  Warning: Failed to unblock some files: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}
