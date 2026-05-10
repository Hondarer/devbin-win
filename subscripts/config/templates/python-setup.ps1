# Python Post-Setup Script
# Python 埋め込みパッケージのセットアップを実行
# パラメータ: $TargetPath - Python がインストールされたディレクトリ

param(
    [Parameter(Mandatory=$true)]
    [string]$TargetPath
)

Write-Host "Running Python post-setup..."

function Set-PthFileContent {
    param(
        [string]$Path,
        [string[]]$Lines
    )

    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Path, ($Lines -join "`r`n"), $utf8NoBom)
}

function Get-NormalizedPthContent {
    param(
        [string[]]$Content,
        [string[]]$AdditionalEntries = @()
    )

    $newContent = @()
    $sitePackagesAdded = $false

    foreach ($line in $Content) {
        # import site に関するコメント行をスキップ
        if ($line -match "^#.*import.*site") {
            continue
        }
        # "Uncomment to run site.main()" コメントをスキップ
        elseif ($line -match "^#.*Uncomment.*site\.main") {
            continue
        }
        # 最後に追加するため既存の import site 行をスキップ
        elseif ($line -match "^import\s+site") {
            continue
        } else {
            $newContent += $line
        }

        if ($line -match "Lib\\site-packages") {
            $sitePackagesAdded = $true
        }
    }

    # 見つからない場合は site-packages を追加
    if (-not $sitePackagesAdded) {
        $newContent += "Lib\site-packages"
    }

    foreach ($entry in $AdditionalEntries) {
        if (-not [string]::IsNullOrWhiteSpace($entry) -and -not ($newContent -contains $entry)) {
            $newContent += $entry
        }
    }

    $newContent += ""
    $newContent += "# Uncomment to run site.main() automatically"
    $newContent += "import site"
    return $newContent
}

function Test-PipWheelPackages {
    param(
        [string]$DirectoryPath
    )

    $requiredPatterns = @(
        "pip-*.whl",
        "setuptools-*.whl",
        "wheel-*.whl",
        "packaging-*.whl"
    )

    $missing = @()
    foreach ($pattern in $requiredPatterns) {
        if (-not (Get-ChildItem -Path $DirectoryPath -Filter $pattern -File -ErrorAction SilentlyContinue | Select-Object -First 1)) {
            $missing += $pattern
        }
    }

    return $missing
}

# python3.exe のコピーを作成
$pythonExe = Join-Path $TargetPath "python.exe"
$python3Exe = Join-Path $TargetPath "python3.exe"

if ((Test-Path $pythonExe) -and !(Test-Path $python3Exe)) {
    try {
        Copy-Item -Path $pythonExe -Destination $python3Exe -Force
        Write-Host "Created python3.exe copy for compatibility"
    } catch {
        Write-Host "Warning: Failed to create python3.exe: $($_.Exception.Message)"
    }
}

# site-packages を有効にするため pth ファイルをパッチ
$pthFiles = Get-ChildItem -Path $TargetPath -Filter "*._pth"
foreach ($pthFile in $pthFiles) {
    Write-Host "Patching pth file: $($pthFile.Name)"

    $pthContent = Get-Content $pthFile.FullName
    $newContent = Get-NormalizedPthContent -Content $pthContent
    $hadSitePackagesPath = $pthContent -contains "Lib\site-packages"

    # 標準ライブラリの zip を最初に追加
    $zipFiles = Get-ChildItem -Path $TargetPath -Filter "python*.zip"
    if ($zipFiles) {
        $zipFile = $zipFiles[0].Name
        if (-not ($newContent -contains $zipFile)) {
            $newContent = @($zipFile) + $newContent
            Write-Host "  Added standard library: $zipFile"
        }
    }

    if (-not $hadSitePackagesPath) {
        Write-Host "  Added Lib\site-packages path"
    }

    Write-Host "  Enabled 'import site'"
    Set-PthFileContent -Path $pthFile.FullName -Lines $newContent
}

$pipArchiveFile = Get-ChildItem "packages\pip-*.tar.gz" | Select-Object -First 1
$pipArchivePath = if ($pipArchiveFile) { $pipArchiveFile.FullName } else { "" }
if (-not $pipArchivePath -or -not (Test-Path $pipArchivePath)) {
    Write-Host "Warning: pip source tarball not found at $pipArchivePath, skipping pip installation"
    Write-Host "Python post-setup completed."
    return
}

# pip をインストール
Write-Host "Installing pip..."
$pythonExe = Join-Path $TargetPath "python.exe"
if (Test-Path $pythonExe) {
    $extractRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("devbin-pip-src-" + [guid]::NewGuid().ToString("N"))
    $originalPythonHome = $env:PYTHONHOME
    $hadPythonHome = Test-Path Env:PYTHONHOME
    $pthSnapshots = @()

    try {
        New-Item -ItemType Directory -Path $extractRoot -Force | Out-Null
        Write-Host "Extracting pip source tarball..."

        $extractScript = @"
import pathlib
import sys
import tarfile

archive_path = pathlib.Path(sys.argv[1])
extract_root = pathlib.Path(sys.argv[2])
with tarfile.open(archive_path, 'r:gz') as archive:
    archive.extractall(extract_root)
"@
        & $pythonExe -c $extractScript $pipArchivePath $extractRoot
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to extract pip source tarball (exit code: $LASTEXITCODE)"
        }

        $pipRootDir = Get-ChildItem -Path $extractRoot -Directory | Select-Object -First 1
        if (-not $pipRootDir) {
            throw "pip source root directory not found under $extractRoot"
        }

        $pipSourcePath = Join-Path $pipRootDir.FullName "src"
        if (-not (Test-Path $pipSourcePath)) {
            throw "pip source directory not found: $pipSourcePath"
        }

        foreach ($pthFile in $pthFiles) {
            $originalContent = Get-Content $pthFile.FullName
            $pthSnapshots += [PSCustomObject]@{
                Path = $pthFile.FullName
                Content = @($originalContent)
            }

            $patchedContent = Get-NormalizedPthContent -Content $originalContent -AdditionalEntries @($pipSourcePath)
            Set-PthFileContent -Path $pthFile.FullName -Lines $patchedContent
        }
        Write-Host "Temporarily added pip source path to embedded Python search paths"

        # pip-packages フォルダが存在する場合はオフラインインストール
        $pipPackagesDir = "packages\pip-packages"
        $offlineMode = Test-Path $pipPackagesDir
        $missingWheels = @()

        if ($offlineMode) {
            $missingWheels = Test-PipWheelPackages -DirectoryPath $pipPackagesDir
            if ($missingWheels.Count -gt 0) {
                Write-Host "Warning: Offline wheel cache is incomplete: $($missingWheels -join ', ')"
                Write-Host "Falling back to online installation."
                $offlineMode = $false
            }
        }

        if ($offlineMode) {
            Write-Host "Using offline installation with local wheel files..."
            $pipPackagesAbsPath = (Resolve-Path $pipPackagesDir).Path
            & $pythonExe -m pip install --no-warn-script-location `
                --no-index --find-links=$pipPackagesAbsPath pip setuptools wheel
        } else {
            Write-Host "Using online installation (downloading from PyPI)..."
            & $pythonExe -m pip install --no-warn-script-location pip setuptools wheel

            # インストール後に wheel を取得して次回オフライン用に保存
            $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "devbin-pip-wheels"
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

            & $pythonExe -m pip download --only-binary=:all: pip setuptools wheel --dest $tempDir 2>$null

            if (Test-Path $tempDir) {
                New-Item -ItemType Directory -Path $pipPackagesDir -Force | Out-Null
                Copy-Item -Path "$tempDir\*.whl" -Destination $pipPackagesDir -Force
                Write-Host "Saved wheel files to $pipPackagesDir for future offline use"
                Remove-Item -Path $tempDir -Recurse -Force
            }
        }

        if ($LASTEXITCODE -eq 0) {
            Write-Host "pip installed successfully"
        } else {
            Write-Host "Warning: pip installation may have issues (exit code: $LASTEXITCODE)"
        }
    } catch {
        Write-Host "Warning: Failed to install pip: $($_.Exception.Message)"
    } finally {
        if ($hadPythonHome) {
            $env:PYTHONHOME = $originalPythonHome
        } else {
            Remove-Item Env:PYTHONHOME -ErrorAction SilentlyContinue
        }

        foreach ($snapshot in $pthSnapshots) {
            Set-PthFileContent -Path $snapshot.Path -Lines $snapshot.Content
        }

        if (Test-Path $extractRoot) {
            Remove-Item -Path $extractRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
} else {
    Write-Host "Warning: python.exe not found, skipping pip installation"
}

Write-Host "Python post-setup completed."
