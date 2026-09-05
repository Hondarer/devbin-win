# MinGW PATH 動的削除スクリプト (PowerShell)
# Git MinGW バイナリを現在のセッションの PATH から削除します

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
    
    # 削除対象でない場合、かつ空でない場合のみ追加
    if (-not $shouldRemove -and $entry.Trim() -ne "") {
        $newPathEntries += $entry
    }
}

if ($pathChanged) {
    # 新しい PATH を設定
    $env:PATH = $newPathEntries -join ';'
    Write-Host "MinGW PATH removal completed."
} else {
    Write-Host "MinGW PATH was not set."
}
