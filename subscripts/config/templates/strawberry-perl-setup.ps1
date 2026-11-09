param([string]$TargetPath)

# Strawberry Perl のポータブル版を、Windows 向けのビルド スクリプトの実行に必要な範囲へ絞ります。
#
# 1. perl.exe を strawberry-perl.exe に改名します。
#    perl\bin を PATH に追加しても、perl という名前のコマンドを PATH に置かないためです。
#    Git 付属の Perl (msys) を前提とするシェル スクリプトが、Strawberry Perl を起動しないようにします。
#    perl.exe は同じディレクトリの perl5xx.dll を読み込むため、ディレクトリは移しません。
#
# 2. 標準モジュールだけで動く構成にするため、次を削除します (約 986 MB から約 72 MB)。
#    - c: CPAN モジュールを C からビルドするための gcc などのツール一式
#    - perl\vendor: 標準以外の CPAN モジュール
#    - portable.perl と portableshell.bat: portable.perl があると、起動時に
#      perl\vendor の Portable モジュールを読み込むため、perl\vendor と一緒に削除します。
#    perl\bin の perl5xx.dll と gcc の実行時 DLL は残すため、c が無くても起動します。
#    - perl\bin 内の補助スクリプト (.bat / .cmd / .pl / 拡張子なし)
#      改名前の perl や削除済みのモジュールを呼ぶコマンドを PATH に残さないためです。
#    licenses などのライセンス文書は残します。

$binDir = Join-Path $TargetPath "perl\bin"
$sourcePath = Join-Path $binDir "perl.exe"
$destPath = Join-Path $binDir "strawberry-perl.exe"

if (Test-Path -LiteralPath $sourcePath) {
    Move-Item -LiteralPath $sourcePath -Destination $destPath -Force
    Write-Host "Renamed: perl.exe -> strawberry-perl.exe"
} elseif (Test-Path -LiteralPath $destPath) {
    Write-Host "Already renamed: strawberry-perl.exe"
} else {
    Write-Host "Error: perl.exe not found at $sourcePath" -ForegroundColor Red
    exit 1
}

# 実行ファイルと DLL は保持し、補助スクリプトだけを削除します。
Get-ChildItem -LiteralPath $binDir -File | Where-Object {
    $_.Extension -in @("", ".bat", ".cmd", ".pl")
} | ForEach-Object {
    Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
    Write-Host "Removed: perl\bin\$($_.Name)"
}

# 削除対象は $TargetPath からの相対パスです。
$trimTargets = @("c", "perl\vendor", "portable.perl", "portableshell.bat")
foreach ($relativePath in $trimTargets) {
    $trimPath = Join-Path $TargetPath $relativePath
    if (Test-Path -LiteralPath $trimPath) {
        Remove-Item -LiteralPath $trimPath -Recurse -Force
        Write-Host "Removed: $relativePath"
    }
}
