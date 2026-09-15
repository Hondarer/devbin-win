# TempDirectory.ps1
# 一時領域の作成とクリーンアップ処理
#
# 実行単位で独立した一時領域を割り当て、削除対象の絶対パスを検証した上で安全に削除します。
# 固定名の一時ディレクトリを使用すると、並行実行や作業ディレクトリの違いによって
# 意図しないディレクトリを誤って削除するリスクがあるため使用を避けます。

# 実行単位で独立した一時ディレクトリを作成
function New-DevbinTempDirectory {
    param([string]$Prefix = "devbin")

    $path = Join-Path ([System.IO.Path]::GetTempPath()) ("$Prefix-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    return $path
}

# 一時ディレクトリの削除
# 一時領域のルート外部を指している場合は安全のため削除を中止
function Remove-DevbinTempDirectory {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }

    try {
        $fullPath = [System.IO.Path]::GetFullPath($Path)
        $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\', '/')
    } catch {
        Write-Host "Warning: 一時ディレクトリのパスを解決できません: $Path" -ForegroundColor Yellow
        return
    }

    if ($fullPath.TrimEnd('\', '/') -eq $tempRoot -or
        -not $fullPath.StartsWith(($tempRoot + [System.IO.Path]::DirectorySeparatorChar), [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Host "Warning: 一時領域の外を指しているため削除しません: $fullPath" -ForegroundColor Yellow
        return
    }

    if (Test-Path $fullPath) {
        Remove-Item $fullPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}
