# OperationLog.ps1
# 操作ログの配置パス解決および Transcript のライフサイクル管理
#
# 完全アンインストール時に製品ルート (...\devbin-win) が削除されるため、
# ログファイルは %ProgramData%\%USERNAME%\log に保存します。

$script:DevbinOperationLogState = @{
    Started = $false
    Path    = $null
}

# 指定パスがボリューム直下など操作ログ配置に適さない場所かを判定
function Test-DevbinOperationLogDirectoryAllowed {
    param(
        [string]$Directory
    )

    if ([string]::IsNullOrWhiteSpace($Directory)) {
        return $false
    }

    $normalized = Get-NormalizedPathString -PathValue $Directory
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return $false
    }

    $root = $null
    try {
        $root = [System.IO.Path]::GetPathRoot($normalized)
    } catch {
        return $false
    }

    if ([string]::IsNullOrWhiteSpace($root)) {
        return $false
    }

    return -not [string]::Equals(
        $normalized.TrimEnd('\'),
        $root.TrimEnd('\'),
        [StringComparison]::OrdinalIgnoreCase
    )
}

# 操作ログの配置先ディレクトリ (導入先によらずユーザーの log) を取得
function Get-DevbinOperationLogDirectory {
    param(
        [Parameter(Mandatory)]
        [string]$InstallDir
    )

    return Get-DevbinLogDirectory
}

# タイムスタンプを付与した一意な操作ログのファイルパスを生成 (既存ファイルの上書きを防止)
function New-DevbinOperationLogPath {
    param(
        [Parameter(Mandatory)]
        [string]$InstallDir,
        [datetime]$Timestamp = (Get-Date),
        [switch]$ForceFallback
    )

    $usedFallback = [bool]$ForceFallback
    $directory = $null
    if (-not $ForceFallback) {
        $directory = Get-DevbinOperationLogDirectory -InstallDir $InstallDir
    }

    if ($usedFallback -or -not (Test-DevbinOperationLogDirectoryAllowed -Directory $directory)) {
        $directory = Get-NormalizedPathString -PathValue ([System.IO.Path]::GetTempPath())
        $usedFallback = $true
    }

    if ([string]::IsNullOrWhiteSpace($directory)) {
        throw "操作ログの配置先を決定できません"
    }

    $stamp = $Timestamp.ToString("yyyyMMdd-HHmmss")
    $candidates = @(
        "devbin-win-operation-$stamp.log"
        "devbin-win-operation-$stamp-$PID.log"
        "devbin-win-operation-$stamp-$PID-$([Guid]::NewGuid().ToString('N').Substring(0, 8)).log"
    )

    $fileName = $null
    $path = $null
    foreach ($candidate in $candidates) {
        $candidatePath = Join-Path $directory $candidate
        if (-not (Test-Path -LiteralPath $candidatePath)) {
            $fileName = $candidate
            $path = $candidatePath
            break
        }
    }

    if (-not $path) {
        throw "操作ログのファイル名を一意にできません"
    }

    return [PSCustomObject]@{
        Directory    = $directory
        Path         = $path
        FileName     = $fileName
        UsedFallback = $usedFallback
    }
}

# Transcript 出力が UTF-16 LE の場合、UTF-8 with BOM に変換 (Windows PowerShell 5.1 互換対応)
function Convert-DevbinOperationLogToUtf8 {
    param(
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return
    }

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 2) {
        return
    }

    $isUtf16Le = ($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE)
    if (-not $isUtf16Le) {
        return
    }

    $text = [System.Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2)
    $utf8 = New-Object System.Text.UTF8Encoding $true
    [System.IO.File]::WriteAllText($Path, $text, $utf8)
}

# 操作ログの記録 (Transcript) を開始 (開始に失敗した場合もセットアップ処理は継続)
function Start-DevbinOperationLog {
    param(
        [Parameter(Mandatory)]
        [string]$InstallDir
    )

    if ($script:DevbinOperationLogState.Started) {
        return $script:DevbinOperationLogState.Path
    }

    $info = $null
    try {
        $info = New-DevbinOperationLogPath -InstallDir $InstallDir
        if (-not (Test-Path -LiteralPath $info.Directory)) {
            New-Item -ItemType Directory -Path $info.Directory -Force | Out-Null
        }
    } catch {
        try {
            $info = New-DevbinOperationLogPath -InstallDir $InstallDir -ForceFallback
            if (-not (Test-Path -LiteralPath $info.Directory)) {
                New-Item -ItemType Directory -Path $info.Directory -Force | Out-Null
            }
        } catch {
            Write-Host "Warning: 操作ログの配置先を準備できません: $($_.Exception.Message)" -ForegroundColor Yellow
            return $null
        }
    }

    if ($info.UsedFallback) {
        Write-Host "Warning: 操作ログの既定配置先が使えないため、一時フォルダーへ書き込みます: $($info.Directory)" -ForegroundColor Yellow
    }

    try {
        Start-Transcript -Path $info.Path | Out-Null
        $script:DevbinOperationLogState.Started = $true
        $script:DevbinOperationLogState.Path = $info.Path
        Write-Host "操作ログ: $($info.Path)"
        return $info.Path
    } catch {
        $message = [string]$_.Exception.Message
        if ($message -match 'already been started|既に開始') {
            Write-Host "操作ログ: 既存の Transcript を継続します"
            return $null
        }

        Write-Host "Warning: 操作ログを開始できませんでした: $message" -ForegroundColor Yellow
        return $null
    }
}

# 自モジュールで開始した Transcript を終了 (ログファイルは保持)
function Stop-DevbinOperationLog {
    if (-not $script:DevbinOperationLogState.Started) {
        $script:DevbinOperationLogState.Path = $null
        return
    }

    $path = $script:DevbinOperationLogState.Path
    Write-Host "操作ログを保存します: $path"
    try {
        Stop-Transcript | Out-Null
    } catch {
        Write-Host "Warning: 操作ログの終了に失敗しました: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    $script:DevbinOperationLogState.Started = $false
    $script:DevbinOperationLogState.Path = $null

    try {
        Convert-DevbinOperationLogToUtf8 -Path $path
    } catch {
        Write-Host "Warning: 操作ログの文字コード変換に失敗しました: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}
