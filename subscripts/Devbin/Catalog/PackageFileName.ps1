# PackageFileName.ps1
# 保存アーカイブ名の決定
#
# 取得側 (Get-Packages) と導入側 (Install-Component) が同じ名前を期待するよう、
# 版表記の判定も含めてここに一本化する。

$script:DevbinCompoundExtensions = @(".tar.gz", ".tar.bz2", ".tar.xz", ".tar.zst", ".7z.exe")

# ダウンロード URL から、版を付けない素のファイル名を求める
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

    return $fileName
}

# ファイル名に版が含まれているかを判定する
# 区切り文字 (. _ -) と大文字小文字の違いは吸収する
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

# packages ディレクトリへ保存するときのファイル名を求める
# 素のファイル名に版が含まれていなければ、拡張子の手前に版を差し込む
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
