# Python Post-Setup Script
# Python 埋め込みパッケージのセットアップを実行
# パラメータ: $TargetPath - Python がインストールされたディレクトリ

param(
    [Parameter(Mandatory=$true)]
    [string]$TargetPath
)

Write-Host "Running Python post-setup..."

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

# get-pip.py が存在する場合はコピー
$getPipPath = "packages\get-pip.py"
if (Test-Path $getPipPath) {
    $getPipDestination = Join-Path $TargetPath "get-pip.py"
    Copy-Item -Path $getPipPath -Destination $getPipDestination -Force
    Write-Host "Copied get-pip.py to Python directory"

    # site-packages を有効にするため pth ファイルをパッチ
    $pthFiles = Get-ChildItem -Path $TargetPath -Filter "*._pth"
    foreach ($pthFile in $pthFiles) {
        Write-Host "Patching pth file: $($pthFile.Name)"

        $pthContent = Get-Content $pthFile.FullName
        $newContent = @()
        $sitePackagesAdded = $false

        foreach ($line in $pthContent) {
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

            # site-packages が既に存在するかチェック
            if ($line -match "Lib\\site-packages") {
                $sitePackagesAdded = $true
            }
        }

        # 標準ライブラリの zip を最初に追加
        $zipFiles = Get-ChildItem -Path $TargetPath -Filter "python*.zip"
        if ($zipFiles) {
            $zipFile = $zipFiles[0].Name
            if (-not ($newContent -contains $zipFile)) {
                $newContent = @($zipFile) + $newContent
                Write-Host "  Added standard library: $zipFile"
            }
        }

        # 見つからない場合は site-packages を追加
        if (-not $sitePackagesAdded) {
            $newContent += "Lib\site-packages"
            Write-Host "  Added Lib\site-packages path"
        }

        # 最後に import site を追加 (適切なコメント付き)
        $newContent += ""
        $newContent += "# Uncomment to run site.main() automatically"
        $newContent += "import site"
        Write-Host "  Enabled 'import site'"

        # 変更された内容を書き戻し (BOM なし UTF-8)
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($pthFile.FullName, ($newContent -join "`r`n"), $utf8NoBom)
    }

    # pip をインストール
    Write-Host "Installing pip..."
    $pythonExe = Join-Path $TargetPath "python.exe"
    if (Test-Path $pythonExe) {
        try {
            # pip-packages フォルダが存在する場合はオフラインインストール
            $pipPackagesDir = "packages\pip-packages"
            $offlineMode = Test-Path $pipPackagesDir

            if ($offlineMode) {
                Write-Host "Using offline installation with local wheel files..."
                $pipPackagesAbsPath = (Resolve-Path $pipPackagesDir).Path
                & $pythonExe $getPipDestination --no-warn-script-location `
                    --no-index --find-links=$pipPackagesAbsPath
            } else {
                Write-Host "Using online installation (downloading from PyPI)..."

                # 一時ディレクトリに wheel をダウンロード
                $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "devbin-pip-wheels"
                New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

                # pip download で wheel ファイルを取得
                & $pythonExe -m pip download pip setuptools wheel --dest $tempDir --no-deps 2>$null

                # get-pip.py で通常インストール
                & $pythonExe $getPipDestination --no-warn-script-location

                # ダウンロードした wheel を packages/pip-packages に保存
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
            # 環境変数をクリーンアップ
            Remove-Item Env:PYTHONHOME -ErrorAction SilentlyContinue
            Remove-Item Env:PYTHONPATH -ErrorAction SilentlyContinue
        }
    } else {
        Write-Host "Warning: python.exe not found, skipping pip installation"
    }
} else {
    Write-Host "Warning: get-pip.py not found at $getPipPath, skipping pip installation"
}

Write-Host "Python post-setup completed."
