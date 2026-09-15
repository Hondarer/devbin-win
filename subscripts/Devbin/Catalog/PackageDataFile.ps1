# PackageDataFile.ps1
# PowerShell データファイル (.psd1) の安全な読み込み
#
# Windows PowerShell 5.1 環境との互換性を確保するため、AST (抽象構文木) の SafeGetValue() を使用します。
# 構文解析によってハッシュテーブルノードのみを静的に抽出するため、
# Invoke-Expression とは異なりファイル内の任意コード実行を防止できます。

# .psd1 ファイルを解析してハッシュテーブルとして読み込み
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
