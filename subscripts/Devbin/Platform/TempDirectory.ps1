# TempDirectory.ps1
# 一時領域の作成と後始末
#
# 実行ごとに分離した領域を使い、削除対象の絶対パスを確認してから消す。
# 固定名の一時ディレクトリを共有すると、並行実行や作業ディレクトリの違いで
# 無関係なディレクトリを消しかねないため使わない。

# 実行ごとに分離した一時ディレクトリを作る
function New-DevbinTempDirectory {
    param([string]$Prefix = "devbin")

    $path = Join-Path ([System.IO.Path]::GetTempPath()) ("$Prefix-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    return $path
}

# 一時ディレクトリを削除する
# 一時領域の外を指していた場合は何もしない
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
