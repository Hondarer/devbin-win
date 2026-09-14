# OperationLog.ps1
# 操作ログの配置と Transcript の開始・終了
#
# 完全アンインストールは製品ルート (...\devbin-win) を消す。
# ログは消さないため、製品ルートの親ディレクトリへ書く。

$script:DevbinOperationLogState = @{
    Started = $false
    Path    = $null
}

# ボリューム直下など、操作ログを置かない場所かを判定する
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

# 操作ログの配置先 (製品ルートの親) を返す
function Get-DevbinOperationLogDirectory {
    param(
        [Parameter(Mandatory)]
        [string]$InstallDir
    )

    $productRoot = Get-DevbinProductRoot -InstallDir $InstallDir
    if ([string]::IsNullOrWhiteSpace($productRoot)) {
        return $null
    }

    $parent = Split-Path -Path $productRoot -Parent
    if ([string]::IsNullOrWhiteSpace($parent)) {
        return $null
    }

    $normalized = Get-NormalizedPathString -PathValue $parent
    if ($normalized) {
        return $normalized
    }
    return $parent.TrimEnd('\')
}

# 日時付きの操作ログパスを組み立てる。既存ファイルは上書きしない。
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

# Transcript が UTF-16 なら UTF-8 BOM に直す (Windows PowerShell 5.1 向け)
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

# 操作ログの Transcript を開始する。失敗しても導入処理は止めない。
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

# このモジュールが開始した Transcript だけを終了する。ログファイルは削除しない。
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
