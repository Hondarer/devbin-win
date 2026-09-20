# StandardStrategy.ps1
# Standard 戦略: アーカイブを展開し、内容を bin ディレクトリへフラットに配置

# Standard 抽出戦略の実行 (アーカイブを展開し、ディレクトリ構造を保持してファイルを配置)
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

    Write-Host "    Extracted folder: $sourcePath"

    # node_modules/<name> は上書きコピーだと旧 npm の残骸が残る。アーカイブ側にあるパッケージディレクトリは先に置き換える。
    $sourceNodeModules = Join-Path $sourcePath "node_modules"
    if (Test-Path -LiteralPath $sourceNodeModules -PathType Container) {
        foreach ($packageDirectory in @(Get-ChildItem -LiteralPath $sourceNodeModules -Directory -Force -ErrorAction SilentlyContinue)) {
            $destinationPackageDirectory = Join-Path $BinDir (Join-Path "node_modules" $packageDirectory.Name)
            if (Test-Path -LiteralPath $destinationPackageDirectory) {
                Remove-Item -LiteralPath $destinationPackageDirectory -Recurse -Force -ErrorAction Stop
            }
        }
    }

    Get-ChildItem -Path $sourcePath -Recurse | ForEach-Object {
        if ($sourcePath -eq $TempDir) {
            $relativePath = $_.Name
        } else {
            $relativePath = $_.FullName.Substring($sourcePath.Length + 1)
        }

        # ファイルのみをコピー (空ディレクトリの不要な生成を防止)
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
