# MinGW PATH 動的追加スクリプト (PowerShell)
# Git MinGW バイナリを現在のセッションの PATH に追加します

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$baseDir = $scriptDir
$mingwPath = Join-Path $baseDir "git\mingw64\bin"
$usrPath = Join-Path $baseDir "git\usr\bin"

# MinGW パスの存在確認
if (-not (Test-Path $mingwPath)) {
    Write-Host "Error: MinGW path not found: $mingwPath"
    Write-Host "Please ensure Git is properly installed"
    exit 1
}

if (-not (Test-Path $usrPath)) {
    Write-Host "Error: usr/bin path not found: $usrPath"
    Write-Host "Please ensure Git is properly installed"
    exit 1
}

$pathsToAdd = @($mingwPath, $usrPath)
$currentPath = $env:PATH
$pathChanged = $false

foreach ($pathToAdd in $pathsToAdd) {
    # 既存の PATH にパスが含まれているかチェック
    $pathExists = $currentPath -split ';' | Where-Object { $_ -eq $pathToAdd }
    
    if ($pathExists) {
        #Write-Host "PATH already set: $pathToAdd"
    } else {
        # パスを先頭に追加
        $env:PATH = "$pathToAdd;$env:PATH"
        #Write-Host "Added: $pathToAdd"
        $pathChanged = $true
    }
}

if ($pathChanged) {
    Write-Host "MinGW PATH addition completed."
} else {
    Write-Host "MinGW PATH already set."
}
