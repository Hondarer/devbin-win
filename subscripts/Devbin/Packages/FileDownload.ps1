# FileDownload.ps1
# ファイル取得の共通処理
#
# 取得に失敗したとき、既にある資材を壊さないよう一時ファイルへ受けてから置き換える。

# SourceForge の実際のダウンロード URL を取得する
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
    } catch {
        return $Url
    }
}

# ファイルを取得する
# 既存ファイルは -Force のときだけ置き換える。取得に失敗した場合、既存ファイルはそのまま残す
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

    # 取得中の内容で既存ファイルを壊さないよう、一時ファイルへ受けてから置き換える
    $temporaryPath = "$OutputPath.download"
    $originalProgressPreference = $ProgressPreference

    try {
        Write-Host "  Downloading $fileName..."

        # Invoke-WebRequest のプログレスバーは性能に問題があるため無効化する
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

# packages ディレクトリのファイルのブロックを解除する
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
