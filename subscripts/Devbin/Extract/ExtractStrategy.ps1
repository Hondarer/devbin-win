# ExtractStrategy.ps1
# パッケージ定義の ExtractStrategy に応じた抽出処理のディスパッチ

# パッケージ定義に基づく抽出処理のディスパッチおよび事後スクリプト (PostSetupScript) の実行
function Invoke-ExtractStrategy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$PackageConfig,

        [Parameter(Mandatory=$false)]
        [string]$ArchiveFile = "",

        [Parameter(Mandatory)]
        [string]$BinDir,

        [Parameter(Mandatory)]
        [string]$ScriptDir,

        [string]$PackagesDir = "",

        [array]$Packages = @(),

        [string]$TempDir = ""
    )

    # 一時ディレクトリは実行ごとに分離 (呼び出し元から指定された場合はそれを優先)
    $ownsTempDir = [string]::IsNullOrWhiteSpace($TempDir)
    if ($ownsTempDir) {
        $TempDir = New-DevbinTempDirectory -Prefix "devbin-extract"
    } elseif (-not [System.IO.Path]::IsPathRooted($TempDir)) {
        $TempDir = [System.IO.Path]::GetFullPath($TempDir)
    }

    $strategy = $PackageConfig.ExtractStrategy

    Write-Host "Extracting $($PackageConfig.Name) using $strategy strategy..."

    $targetPath = $null

    try {
        switch ($strategy) {
            "Standard" {
                Invoke-StandardExtract -ArchiveFile $ArchiveFile -BinDir $BinDir -TempDir $TempDir
            }
            "Subdirectory" {
                Invoke-SubdirectoryExtract -ArchiveFile $ArchiveFile -BinDir $BinDir -TempDir $TempDir -ExtractPath $PackageConfig.ExtractPath -FilePattern $PackageConfig.FilePattern -RenameFiles $PackageConfig.RenameFiles
            }
            "SubdirectoryToTarget" {
                Invoke-SubdirectoryToTargetExtract -ArchiveFile $ArchiveFile -BinDir $BinDir -TempDir $TempDir -ExtractPath $PackageConfig.ExtractPath -TargetDirectory $PackageConfig.TargetDirectory
            }
            "VersionNormalized" {
                $targetPath = Invoke-VersionNormalizedExtract -ArchiveFile $ArchiveFile -BinDir $BinDir -TempDir $TempDir -VersionPattern $PackageConfig.VersionPattern -TargetDirectory $PackageConfig.TargetDirectory
            }
            "TargetDirectory" {
                $targetPath = Invoke-TargetDirectoryExtract -ArchiveFile $ArchiveFile -BinDir $BinDir -TempDir $TempDir -Config $PackageConfig
            }
            "JarWithWrapper" {
                Invoke-JarWithWrapperExtract -ArchiveFile $ArchiveFile -BinDir $BinDir -Config $PackageConfig
            }
            "SingleExecutable" {
                Invoke-SingleExecutableExtract -ArchiveFile $ArchiveFile -BinDir $BinDir -Config $PackageConfig
            }
            "SelfExtractingArchive" {
                $targetPath = Invoke-SelfExtractingArchiveExtract `
                    -ArchiveFile $ArchiveFile `
                    -BinDir $BinDir `
                    -Config $PackageConfig `
                    -ScriptDir $ScriptDir
            }
            "InnoSetup" {
                $targetPath = Invoke-InnoSetupExtract -ArchiveFile $ArchiveFile -BinDir $BinDir -TempDir $TempDir -Config $PackageConfig
            }
            "VSBuildTools" {
                return Invoke-VSBuildToolsExtract -BinDir $BinDir -ScriptDir $ScriptDir -Config $PackageConfig
            }
            "PipInstall" {
                return Invoke-PipInstallStrategy -BinDir $BinDir -Config $PackageConfig -PackagesDir $PackagesDir -Packages $Packages
            }
            "NpmInstall" {
                return Invoke-NpmInstallStrategy -BinDir $BinDir -Config $PackageConfig -PackagesDir $PackagesDir
            }
            default {
                Write-Host "Unknown strategy: $strategy" -ForegroundColor Red
                return $false
            }
        }

        # 事後スクリプト (PostSetupScript) の実行
        # PowerShell スクリプト (.ps1) はセッション汚染や exit による呼び出し元終了を防ぐため別プロセスで起動
        if ($PackageConfig.PostSetupScript) {
            $scriptTargetPath = if ($targetPath) { $targetPath } else { $BinDir }
            $scriptPath = Join-Path $ScriptDir "config\templates\$($PackageConfig.PostSetupScript)"
            if (Test-Path $scriptPath) {
                Write-Host "Running post-setup script: $($PackageConfig.PostSetupScript)"
                $extension = [System.IO.Path]::GetExtension($scriptPath)
                if ($extension -ieq ".ps1") {
                    & powershell.exe -ExecutionPolicy Bypass -File $scriptPath -TargetPath $scriptTargetPath
                } else {
                    & $scriptPath -TargetPath $scriptTargetPath
                }
                if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
                    throw "Post-setup script failed with exit code ${LASTEXITCODE}: $($PackageConfig.PostSetupScript)"
                }
            } else {
                Write-Host "Warning: Post-setup script not found: $scriptPath" -ForegroundColor Yellow
            }
        }

        Write-Host "$($PackageConfig.Name) extraction completed."
        return $true
    }
    catch {
        Write-Host "Error: Failed to extract $($PackageConfig.Name)" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        return $false
    }
    finally {
        # 自関数内で作成した一時ディレクトリは、処理の成否に関わらず確実に削除
        if ($ownsTempDir) {
            Remove-DevbinTempDirectory -Path $TempDir
        }
    }
}
