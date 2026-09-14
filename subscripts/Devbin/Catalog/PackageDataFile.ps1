# PackageDataFile.ps1
# .psd1 データファイルの読み込み
#
# Import-PowerShellDataFile は Windows PowerShell 5.1 に存在しないため、
# 同コマンドレットと同じ仕組みである AST の SafeGetValue() を使用する。
# 構文解析してハッシュテーブルのノードを取り出すだけなので、
# Invoke-Expression と違いファイル内のコードは実行されない。

# .psd1 をハッシュテーブルとして読み込む
function Import-DevbinDataFile {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path $Path -PathType Leaf)) {
        throw "Data file not found: $Path"
    }

    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$parseErrors)
    if ($parseErrors -and $parseErrors.Count -gt 0) {
        $firstError = $parseErrors[0]
        throw "Failed to parse data file '$Path': $($firstError.Message)"
    }

    $hashtableAst = $ast.Find(
        { param($node) $node -is [System.Management.Automation.Language.HashtableAst] },
        $false)
    if (-not $hashtableAst) {
        throw "No hashtable found in data file: $Path"
    }

    return $hashtableAst.SafeGetValue()
}
