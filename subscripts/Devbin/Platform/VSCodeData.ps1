# VSCodeData.ps1
# VS Code の data フォルダーの退避と復元

# VS Code data フォルダーをバックアップする
function Backup-VSCodeData {
    param(
        [string]$InstallDirectory,
        [switch]$Silent = $false
    )

    $vscodeDataPath = Join-Path $InstallDirectory "vscode\data"
    if (!(Test-Path $vscodeDataPath)) {
        if (-not $Silent) {
            Write-Host "VS Code data folder not found, skipping backup: $vscodeDataPath"
        }
        return $null
    }

    # Data フォルダー内にファイルが存在するか確認
    $filesInData = Get-ChildItem -Path $vscodeDataPath -Recurse -File -ErrorAction SilentlyContinue
    if (-not $filesInData -or $filesInData.Count -eq 0) {
        if (-not $Silent) {
            Write-Host "VS Code data folder is empty, skipping backup: $vscodeDataPath"
        }
        return $null
    }

    $tempBackupDir = Join-Path ([System.IO.Path]::GetTempPath()) "vscode_data_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"

    try {
        if (-not $Silent) {
            Write-Host "Backing up VS Code data folder to: $tempBackupDir"
        }

        Copy-Item -Path $vscodeDataPath -Destination $tempBackupDir -Recurse -Force

        if (-not $Silent) {
            Write-Host "VS Code data backup completed successfully"
        }

        return $tempBackupDir
    } catch {
        if (-not $Silent) {
            Write-Host "Warning: Failed to backup VS Code data: $($_.Exception.Message)" -ForegroundColor Yellow
        }

        if (Test-Path $tempBackupDir) {
            Remove-Item -Path $tempBackupDir -Recurse -Force -ErrorAction SilentlyContinue
        }

        return $null
    }
}

# VS Code data フォルダーを復元する関数
function Restore-VSCodeData {
    param(
        [string]$InstallDirectory,
        [string]$BackupPath,
        [switch]$Silent = $false
    )

    if (-not $BackupPath -or !(Test-Path $BackupPath)) {
        if (-not $Silent) {
            Write-Host "VS Code data backup not found, skipping restore: $BackupPath"
        }
        return $false
    }

    $vscodeDir = Join-Path $InstallDirectory "vscode"
    if (!(Test-Path $vscodeDir)) {
        if (-not $Silent) {
            Write-Host "VS Code installation directory not found, skipping restore: $vscodeDir"
        }
        return $false
    }

    $vscodeDataPath = Join-Path $vscodeDir "data"

    try {
        if (-not $Silent) {
            Write-Host "Restoring VS Code data folder from backup: $BackupPath"
        }

        if (Test-Path $vscodeDataPath) {
            Remove-Item -Path $vscodeDataPath -Recurse -Force
        }

        Copy-Item -Path $BackupPath -Destination $vscodeDataPath -Recurse -Force

        if (-not $Silent) {
            Write-Host "VS Code data restoration completed successfully"
        }

        return $true
    } catch {
        if (-not $Silent) {
            Write-Host "Warning: Failed to restore VS Code data: $($_.Exception.Message)" -ForegroundColor Yellow
        }
        return $false
    } finally {
        if (Test-Path $BackupPath) {
            Remove-Item -Path $BackupPath -Recurse -Force -ErrorAction SilentlyContinue
            if (-not $Silent) {
                Write-Host "Cleaned up temporary backup directory"
            }
        }
    }
}
