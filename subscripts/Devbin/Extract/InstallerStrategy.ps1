# InstallerStrategy.ps1
# インストーラー形式 (自己解凍アーカイブ、Inno Setup、Visual Studio Build Tools) の抽出戦略

# SelfExtractingArchive 戦略: 自己解凍実行ファイルを実行してターゲットディレクトリへ展開
function Invoke-SelfExtractingArchiveExtract {
    param(
        [string]$ArchiveFile,
        [string]$BinDir,
        [hashtable]$Config,
        [string]$ScriptDir = ""
    )

    Unblock-ArchiveFile $ArchiveFile

    $targetDirectory = $Config.TargetDirectory
    $targetPath = Join-Path $BinDir $targetDirectory

    Write-Host "    Creating target directory: $targetDirectory"

    if (!(Test-Path $targetPath)) {
        New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
    }

    Write-Host "    Extracting (this may take a moment)..."

    $resolvedTargetPath = (Resolve-Path $targetPath).Path
    $extractArgs = @()

    foreach ($arg in $Config.ExtractArgs) {
        $processedArg = $arg -replace '\{TargetPath\}', "`"$resolvedTargetPath`""
        $extractArgs += $processedArg
    }

    $process = Start-Process -FilePath $ArchiveFile -ArgumentList $extractArgs -Wait -PassThru

    if ($process.ExitCode -eq 0) {
        Write-Host "    Extracted successfully to: $targetPath"

        # 抽出後処理 (PostExtract): 追加ファイルのコピー
        if ($Config.PostExtract -and $Config.PostExtract.CopyFiles) {
            Write-Host "    Copying additional files..."
            foreach ($fileEntry in $Config.PostExtract.CopyFiles) {
                $sourcePath = Resolve-PostExtractSourcePath `
                    -SourcePath ([string]$fileEntry.Source) `
                    -ScriptDir $ScriptDir
                $destPath = Join-Path $BinDir $fileEntry.Destination

                if (Test-Path -LiteralPath $sourcePath -PathType Leaf) {
                    Copy-Item -LiteralPath $sourcePath -Destination $destPath -Force
                    Write-Host "      Copied: $($fileEntry.Destination)"
                } else {
                    Write-Host "      Warning: File not found: $sourcePath" -ForegroundColor Yellow
                }
            }
        }

        return $targetPath
    } else {
        throw "Extraction failed with exit code: $($process.ExitCode)"
    }
}

# InnoSetup 戦略: innoextract を使用して Inno Setup インストーラーから指定サブディレクトリを展開
function Invoke-InnoSetupExtract {
    param(
        [string]$ArchiveFile,
        [string]$BinDir,
        [string]$TempDir,
        [hashtable]$Config
    )

    # innoextract.exe の存在確認
    $innoextractPath = Join-Path $BinDir "innoextract.exe"
    if (-not (Test-Path $innoextractPath)) {
        throw "innoextract.exe not found at: $innoextractPath. Please ensure innoextract is extracted first."
    }

    # 一時ディレクトリの初期化
    if (Test-Path $TempDir) {
        Remove-Item $TempDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

    # innoextract によるアーカイブ展開
    Write-Host "    Extracting with innoextract..."
    $innoextractArgs = @("-d", "`"$TempDir`"", "`"$ArchiveFile`"")
    $process = Start-Process -FilePath $innoextractPath -ArgumentList $innoextractArgs -Wait -PassThru -NoNewWindow

    if ($process.ExitCode -ne 0) {
        throw "innoextract failed with exit code: $($process.ExitCode)"
    }

    # ExtractPath で指定された展開先サブディレクトリを TargetDirectory へ配置
    $sourcePath = Join-Path $TempDir $Config.ExtractPath
    if (-not (Test-Path $sourcePath)) {
        throw "Source path not found: $sourcePath"
    }

    $targetPath = Join-Path $BinDir $Config.TargetDirectory

    # 既存のターゲットディレクトリが存在する場合は削除
    if (Test-Path $targetPath) {
        Remove-Item $targetPath -Recurse -Force
    }

    # 展開済みサブディレクトリを配置先へ移動
    Move-Item -Path $sourcePath -Destination $targetPath -Force
    Write-Host "    Extracted to: $targetPath"

    # 一時ディレクトリの削除
    if (Test-Path $TempDir) {
        Remove-Item $TempDir -Recurse -Force
    }

    return $targetPath
}

# VSBuildTools 戦略: Setup-VSBT.ps1 を呼び出して MSVC および Windows SDK をセットアップ
function Invoke-VSBuildToolsExtract {
    param(
        [string]$BinDir,
        [string]$ScriptDir,
        [hashtable]$Config
    )

    Write-Host "    Processing: $($Config.DisplayName)"

    $vsbtScript = Join-Path $ScriptDir "Setup-VSBT.ps1"

    if (-not (Test-Path $vsbtScript)) {
        Write-Host "    Error: Setup-VSBT.ps1 not found at: $vsbtScript" -ForegroundColor Red
        return $false
    }

    $vsbtConfig = $Config.VSBTConfig
    $outputPath = Join-Path $BinDir $Config.ExtractedName
    $downloadsPath = Join-Path (Split-Path -Parent $ScriptDir) "packages\vsbt"

    $params = @{
        MSVCVersion = $vsbtConfig.MSVCVersion
        SDKVersion = $vsbtConfig.SDKVersion
        Target = $vsbtConfig.Target
        HostArch = $vsbtConfig.HostArch
        OutputPath = $outputPath
        DownloadsPath = $downloadsPath
        AcceptLicense = $true
        SkipDevbinModuleImport = $true
    }

    $packagesDir = Split-Path -Parent $downloadsPath
    if (Test-DevbinOfflineMode -PackagesDir $packagesDir) {
        $params["OfflineMode"] = $true
    }

    Write-Host "    Executing Setup-VSBT.ps1..."
    Write-Host "      MSVC: $($params.MSVCVersion)"
    Write-Host "      SDK: $($params.SDKVersion)"
    Write-Host "      Target: $($params.Target)"
    Write-Host "      Output: $outputPath`n"

    try {
        & $vsbtScript @params

        if ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE) {
            Write-Host "    $($Config.DisplayName) setup completed" -ForegroundColor Green
            return $true
        } else {
            Write-Host "    Setup-VSBT.ps1 exited with code $LASTEXITCODE" -ForegroundColor Yellow
            return $false
        }
    } catch {
        Write-Host "    Error executing Setup-VSBT.ps1: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}
