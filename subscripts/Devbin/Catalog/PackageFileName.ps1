# PackageFileName.ps1
# パッケージ保存ファイル名の解決
#
# パッケージ取得処理 (Get-Packages) とインストール処理 (Install-Component) で同一の保存ファイル名を参照できるよう、
# バージョン番号の包含判定およびファイル名生成ロジックを集約します。

$script:DevbinCompoundExtensions = @(".tar.gz", ".tar.bz2", ".tar.xz", ".tar.zst", ".7z.exe")

# ダウンロード URL から既定のベースファイル名を取得
function Get-PackageBaseFileName {
    param(
        [hashtable]$Package
    )

    $url = if ($Package.ContainsKey("DownloadUrl")) { [string]$Package.DownloadUrl } else { "" }
    if ([string]::IsNullOrWhiteSpace($url)) {
        return ""
    }

    $uri = [Uri]$url
    $fileName = if ($Package.ContainsKey("DownloadFileName")) { [string]$Package.DownloadFileName } else { "" }

    if ([string]::IsNullOrWhiteSpace($fileName)) {
        $fileName = [System.IO.Path]::GetFileName($uri.AbsolutePath)
    }

    # SourceForge の /download で終わる URL の場合、直前のパスセグメントを採用
    if ($fileName -eq "download" -and $uri.Host -like "*sourceforge.net*") {
        $pathSegments = $uri.AbsolutePath.Split('/', [StringSplitOptions]::RemoveEmptyEntries)
        $fileName = $pathSegments[-2]  # /download の前のセグメント
    }
    # GitHub の /archive/refs/tags/ URL の場合、リポジトリ名とタグ名を組み合わせたファイル名を生成
    elseif ($uri.Host -eq "github.com" -and $uri.AbsolutePath -match '/([^/]+)/([^/]+)/archive/refs/tags/(.+)$') {
        $repoName = $matches[2]
        $tagName = [System.IO.Path]::GetFileNameWithoutExtension($matches[3])
        $extension = [System.IO.Path]::GetExtension($matches[3])
        # タグ名先頭のプレフィックス "v" を除去
        $tagName = $tagName -replace '^v', ''
        $fileName = "$repoName-$tagName$extension"
    }

    return $fileName
}

# ファイル名にバージョン文字列が含まれているかを判定
# 区切り文字 (. _ -) および大文字小文字の差異を正規化して比較
function Test-FileNameContainsVersion {
    param(
        [string]$FileName,
        [string]$Version
    )

    if ([string]::IsNullOrWhiteSpace($FileName) -or [string]::IsNullOrWhiteSpace($Version)) {
        return $false
    }

    $normalizedFileName = $FileName.ToLowerInvariant() -replace '[_-]', '.'
    $normalizedVersion = $Version.ToLowerInvariant() -replace '[_-]', '.'
    return $normalizedFileName.Contains($normalizedVersion)
}

# packages ディレクトリに保存するアーカイブファイル名を生成
# ベースファイル名にバージョンが含まれていない場合、拡張子の直前にバージョン文字列を挿入
function Get-PackageDownloadFileName {
    param(
        [hashtable]$Package,
        [string]$Version = ""
    )

    $fileName = Get-PackageBaseFileName -Package $Package
    if ([string]::IsNullOrWhiteSpace($Version)) {
        $Version = if ($Package.ContainsKey("Version")) { [string]$Package.Version } else { "" }
    }

    if ([string]::IsNullOrWhiteSpace($Version) -or (Test-FileNameContainsVersion -FileName $fileName -Version $Version)) {
        return $fileName
    }

    $matchedCompoundExtension = $script:DevbinCompoundExtensions |
        Where-Object { $fileName.EndsWith($_, [StringComparison]::OrdinalIgnoreCase) } |
        Select-Object -First 1

    if ($matchedCompoundExtension) {
        $baseName = $fileName.Substring(0, $fileName.Length - $matchedCompoundExtension.Length)
        return "$baseName-$Version$matchedCompoundExtension"
    }

    $extension = [System.IO.Path]::GetExtension($fileName)
    if ([string]::IsNullOrEmpty($extension)) {
        return "$fileName-$Version"
    }

    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
    return "$baseName-$Version$extension"
}
