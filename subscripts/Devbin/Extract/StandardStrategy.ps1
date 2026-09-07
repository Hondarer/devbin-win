# StandardStrategy.ps1
# Standard 戦略: 展開した中身をそのまま bin へ配置する

# Standard 戦略: 標準的な ZIP 展開
function Invoke-StandardExtract {
    param(
        [string]$ArchiveFile,
        [string]$BinDir,
        [string]$TempDir
    )

    Unblock-ArchiveFile $ArchiveFile
    Expand-ArchiveToTemp -ArchiveFile $ArchiveFile -TempDir $TempDir

    $sourcePath = Get-ExtractedSourcePath $TempDir
    if (-not $sourcePath) {
        throw "Extracted folder not found"
    }

    Write-Host "Extracted folder: $sourcePath"

    Get-ChildItem -Path $sourcePath -Recurse | ForEach-Object {
        if ($sourcePath -eq $TempDir) {
            $relativePath = $_.Name
        } else {
            $relativePath = $_.FullName.Substring($sourcePath.Length + 1)
        }

        # ファイルのみをコピー (空のディレクトリは作成しない)
        if (-not $_.PSIsContainer) {
            $destinationPath = Join-Path $BinDir $relativePath

            $destinationDir = Split-Path $destinationPath -Parent
            if ($destinationDir -and !(Test-Path $destinationDir)) {
                New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
            }
            Copy-Item -Path $_.FullName -Destination $destinationPath -Force
        }
    }

    return $true
}
