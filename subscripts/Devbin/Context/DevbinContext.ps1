# DevbinContext.ps1
# 実行コンテキスト: リポジトリ配下の絶対パスをひとまとめにする
#
# カレントディレクトリに依存しないよう、各処理はここで解決した絶対パスを受け取る。

# 実行コンテキストを作る
# InstallDir は相対パスで渡されても絶対パスに解決する
function New-DevbinContext {
    param(
        [string]$InstallDir = "",
        [string]$SubscriptsDir = ""
    )

    $subscripts = if ([string]::IsNullOrWhiteSpace($SubscriptsDir)) {
        $script:DevbinSubscriptsDir
    } else {
        [System.IO.Path]::GetFullPath($SubscriptsDir)
    }
    $repositoryRoot = Split-Path -Parent $subscripts

    $resolvedInstallDir = ""
    if (-not [string]::IsNullOrWhiteSpace($InstallDir)) {
        $resolvedInstallDir = if ([System.IO.Path]::IsPathRooted($InstallDir)) {
            [System.IO.Path]::GetFullPath($InstallDir)
        } else {
            [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot $InstallDir))
        }
    }

    $packagesDir = Join-Path $repositoryRoot "packages"

    return [PSCustomObject]@{
        RepositoryRoot = $repositoryRoot
        SubscriptsDir  = $subscripts
        ConfigPath     = Join-Path $subscripts "config\packages.psd1"
        TemplatesDir   = Join-Path $subscripts "config\templates"
        PackagesDir    = $packagesDir
        PipPackagesDir = Join-Path $packagesDir "pip-packages"
        NpmPackagesDir = Join-Path $packagesDir "npm-packages"
        InstallDir     = $resolvedInstallDir
        TempRoot       = Join-Path ([System.IO.Path]::GetTempPath()) ("devbin-" + [Guid]::NewGuid().ToString("N"))
    }
}
