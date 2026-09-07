# ExecutableStrategy.ps1
# JarWithWrapper / SingleExecutable 戦略: 実行ファイル 1 つを配置する

# JarWithWrapper 戦略: JAR ファイル + ラッパー
function Invoke-JarWithWrapperExtract {
    param(
        [string]$ArchiveFile,
        [string]$BinDir,
        [hashtable]$Config
    )

    Unblock-ArchiveFile $ArchiveFile

    $jarFileName = $Config.JarName
    $jarDestination = Join-Path $BinDir $jarFileName

    Write-Host "JAR file: $(Split-Path $ArchiveFile -Leaf)"
    Copy-Item -Path $ArchiveFile -Destination $jarDestination -Force
    Write-Host "Copied to bin directory as $jarFileName"

    # ラッパースクリプトを生成
    $wrapperName = $Config.WrapperName
    if (-not $wrapperName) {
        Write-Host "Warning: WrapperName not specified in config" -ForegroundColor Yellow
        return $false
    }

    $wrapperContent = $Config.WrapperContent
    if (-not $wrapperContent) {
        Write-Host "Warning: WrapperContent not specified in config" -ForegroundColor Yellow
        return $false
    }

    $wrapperPath = Join-Path $BinDir $wrapperName
    $wrapperContent | Out-File -FilePath $wrapperPath -Encoding ASCII
    Write-Host "Created wrapper script: $wrapperName"

    return $true
}

# SingleExecutable 戦略: 単一実行ファイル
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

    Write-Host "EXE file: $exeFileName"

    try {
        Unblock-File -Path $ArchiveFile -ErrorAction SilentlyContinue
        Write-Host "Unblocked $exeFileName"
    } catch {
        # ブロック解除に失敗した場合は続行
    }

    Copy-Item -Path $ArchiveFile -Destination $exeDestination -Force
    Write-Host "Copied $exeFileName to bin directory as $targetName"

    try {
        Unblock-File -Path $exeDestination -ErrorAction SilentlyContinue
    } catch {
        # ブロック解除に失敗した場合は続行
    }

    return $true
}
