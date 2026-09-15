# MinGW PATH 動的削除スクリプト (PowerShell)
# Git MinGW バイナリを現在のセッションの PATH から削除します。

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$baseDir = $scriptDir
$mingwPath = Join-Path $baseDir "git\mingw64\bin"
$usrPath = Join-Path $baseDir "git\usr\bin"

$pathsToRemove = @($mingwPath, $usrPath)
$currentPathEntries = $env:PATH -split ';'
$newPathEntries = @()
$pathChanged = $false

foreach ($entry in $currentPathEntries) {
    $shouldRemove = $false
    
    foreach ($pathToRemove in $pathsToRemove) {
        if ($entry -eq $pathToRemove) {
            #Write-Host "Removed: $entry"
            $shouldRemove = $true
            $pathChanged = $true
            break
        }
    }
    
    # 削除対象ではなく、かつ空文字でないエントリのみ保持
    if (-not $shouldRemove -and $entry.Trim() -ne "") {
        $newPathEntries += $entry
    }
}

if ($pathChanged) {
    # フィルタリング後の新しい PATH を環境変数に設定
    $env:PATH = $newPathEntries -join ';'
    Write-Host "MinGW PATH removal completed."
} else {
    Write-Host "MinGW PATH was not set."
}
