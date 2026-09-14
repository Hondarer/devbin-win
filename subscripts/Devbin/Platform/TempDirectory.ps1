# TempDirectory.ps1
# 一時領域の作成とクリーンアップ
#
# 実行ごとに分離した領域を使用し、削除対象の絶対パスを確認してから削除する。
# 固定名の一時ディレクトリを共有すると、並行実行や作業ディレクトリの違いで
# 無関係なディレクトリを削除しかねないため使用しない。

# 実行ごとに分離した一時ディレクトリを作成する
function New-DevbinTempDirectory {
    param([string]$Prefix = "devbin")

    $path = Join-Path ([System.IO.Path]::GetTempPath()) ("$Prefix-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    return $path
}

# 一時ディレクトリを削除する
# 一時領域の外を指している場合は何も処理しない
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
