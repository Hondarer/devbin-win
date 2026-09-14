# ExtractStrategy.ps1
# ExtractStrategy の指定に応じて戦略を呼び分ける

# メイン関数: 抽出戦略を実行
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

    # 一時領域は実行ごとに分ける。呼び出し元が指定した場合はそれを使う
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

        # PostSetupScript 実行
        # .ps1 は別プロセスで実行する。同一セッションだと Import-Module -Force や exit が導入処理ごと終わる。
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
        # 自分で作った一時領域は、成否によらず必ず片付ける
        if ($ownsTempDir) {
            Remove-DevbinTempDirectory -Path $TempDir
        }
    }
}
