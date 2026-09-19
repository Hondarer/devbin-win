# ExecutableStrategy.ps1
# JarWithWrapper および SingleExecutable 戦略: 単一バイナリやラッパー付き実行ファイルの配置

# JarWithWrapper 戦略: JAR ファイルを bin ディレクトリへ配置し、起動用ラッパースクリプトを生成
function Invoke-JarWithWrapperExtract {
    param(
        [string]$ArchiveFile,
        [string]$BinDir,
        [hashtable]$Config
    )

    Unblock-ArchiveFile $ArchiveFile

    $jarFileName = $Config.JarName
    $jarDestination = Join-Path $BinDir $jarFileName

    Write-Host "    JAR file: $(Split-Path $ArchiveFile -Leaf)"
    Copy-Item -Path $ArchiveFile -Destination $jarDestination -Force
    Write-Host "    Copied to bin directory as $jarFileName"

    # 起動用ラッパースクリプトを生成
    $wrapperName = $Config.WrapperName
    if (-not $wrapperName) {
        Write-Host "    Warning: WrapperName not specified in config" -ForegroundColor Yellow
        return $false
    }

    $wrapperContent = $Config.WrapperContent
    if (-not $wrapperContent) {
        Write-Host "    Warning: WrapperContent not specified in config" -ForegroundColor Yellow
        return $false
    }

    $wrapperPath = Join-Path $BinDir $wrapperName
    $wrapperContent | Out-File -FilePath $wrapperPath -Encoding ASCII
    Write-Host "    Created wrapper script: $wrapperName"

    return $true
}

# SingleExecutable 戦略: 単一の実行可能ファイルを bin ディレクトリへ配置
function Invoke-SingleExecutableExtract {
    param(
        [string]$ArchiveFile,
        [string]$BinDir,
        [hashtable]$Config
    )

    Unblock-ArchiveFile $ArchiveFile

    $exeFileName = Split-Path $ArchiveFile -Leaf
    $targetName = if ($Config.TargetName) { $Config.TargetName } else { $exeFileName }
    $exeDestination = Join-Path $BinDir $targetName

    Write-Host "    EXE file: $exeFileName"

    try {
        Unblock-File -Path $ArchiveFile -ErrorAction SilentlyContinue
        Write-Host "    Unblocked $exeFileName"
    } catch {
        # ゾーン識別子の解除に失敗した場合も処理を継続
    }

    Copy-Item -Path $ArchiveFile -Destination $exeDestination -Force
    Write-Host "    Copied $exeFileName to bin directory as $targetName"

    try {
        Unblock-File -Path $exeDestination -ErrorAction SilentlyContinue
    } catch {
        # ゾーン識別子の解除に失敗した場合も処理を継続
    }

    return $true
}
