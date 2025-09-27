# Setup-Home.ps1
# HOME 環境変数とホームディレクトリのセットアップスクリプト

# 現在のユーザー名を取得
$userName = [Environment]::UserName

# HOME 環境変数をチェック
$homeEnvVar = [Environment]::GetEnvironmentVariable("HOME", "User")

if ([string]::IsNullOrEmpty($homeEnvVar)) {
    # ホームディレクトリのパスを定義
    $baseHomePath = "C:\ProgramData\home"
    $homePath = "$baseHomePath\$userName"
    $continuePath = "$homePath\.continue"

    # XDG Base Directory Specification のパスを定義
    $xdgConfigPath = "$homePath\.config"
    $xdgCachePath = "$homePath\.cache"
    $xdgDataPath = "$homePath\.local\share"
    $xdgStatePath = "$homePath\.local\state"
    
    Write-Host "HOME Environment Setup"
    Write-Host "======================"
    Write-Host ""
    Write-Host "Current Status:"
    Write-Host "  Username: $userName"
    Write-Host ""
    Write-Host "Planned Actions:"
    
    $actions = @()
    
    # ベースディレクトリチェック
    if (!(Test-Path $baseHomePath)) {
        $actions += "  - Create base home directory: $baseHomePath"
    }
    
    # ユーザーホームディレクトリチェック
    if (!(Test-Path $homePath)) {
        $actions += "  - Create user home directory: $homePath"
    }
    
    # .continue ディレクトリチェック
    if (!(Test-Path $continuePath)) {
        $actions += "  - Create continue directory: $continuePath"
    }

    # XDG ディレクトリチェック
    if (!(Test-Path $xdgConfigPath)) {
        $actions += "  - Create XDG config directory: $xdgConfigPath"
    }
    if (!(Test-Path $xdgCachePath)) {
        $actions += "  - Create XDG cache directory: $xdgCachePath"
    }
    if (!(Test-Path $xdgDataPath)) {
        $actions += "  - Create XDG data directory: $xdgDataPath"
    }
    if (!(Test-Path $xdgStatePath)) {
        $actions += "  - Create XDG state directory: $xdgStatePath"
    }

    # 環境変数設定
    $actions += "  - Set HOME environment variable to: $homePath"
    $actions += "  - Set CONTINUE_GLOBAL_DIR environment variable to: $continuePath"
    $actions += "  - Set XDG_CONFIG_HOME environment variable to: $xdgConfigPath"
    $actions += "  - Set XDG_CACHE_HOME environment variable to: $xdgCachePath"
    $actions += "  - Set XDG_DATA_HOME environment variable to: $xdgDataPath"
    $actions += "  - Set XDG_STATE_HOME environment variable to: $xdgStatePath"
    
    # 実行予定内容を表示
    if ($actions.Count -eq 6) {
        Write-Host "  - All directories already exist"
    }
    foreach ($action in $actions) {
        Write-Host $action
    }
    
    Write-Host ""
    $confirmation = Read-Host "Do you want to proceed? (Y/n)"
    if ($confirmation -eq "n" -or $confirmation -eq "N") {
        Write-Host "Setup cancelled by user."
        exit 0
    }
    
    Write-Host ""
    Write-Host "Starting setup..."
    
    # ベースホームディレクトリ (C:\ProgramData\home) が存在しない場合は作成
    if (!(Test-Path $baseHomePath)) {
        Write-Host "Creating base home directory: $baseHomePath"
        try {
            New-Item -ItemType Directory -Path $baseHomePath -Force | Out-Null
            Write-Host "Base home directory created successfully"
        } catch {
            Write-Host "Failed to create base home directory: $($_.Exception.Message)"
            Write-Host "Please ensure you have administrator privileges or the directory is writable"
            exit 1
        }
    } else {
        Write-Host "Base home directory already exists: $baseHomePath"
    }
    
    # ユーザーホームディレクトリが存在しない場合は作成
    if (!(Test-Path $homePath)) {
        Write-Host "Creating user home directory: $homePath"
        try {
            New-Item -ItemType Directory -Path $homePath -Force | Out-Null
            Write-Host "User home directory created successfully"
        } catch {
            Write-Host "Failed to create user home directory: $($_.Exception.Message)"
            exit 1
        }
    } else {
        Write-Host "User home directory already exists: $homePath"
    }
    
    # .continue ディレクトリが存在しない場合は作成
    if (!(Test-Path $continuePath)) {
        Write-Host "Creating continue directory: $continuePath"
        try {
            New-Item -ItemType Directory -Path $continuePath -Force | Out-Null
            Write-Host "Continue directory created successfully"
        } catch {
            Write-Host "Failed to create continue directory: $($_.Exception.Message)"
            exit 1
        }
    } else {
        Write-Host "Continue directory already exists: $continuePath"
    }

    # XDG ディレクトリが存在しない場合は作成
    if (!(Test-Path $xdgConfigPath)) {
        Write-Host "Creating XDG config directory: $xdgConfigPath"
        try {
            New-Item -ItemType Directory -Path $xdgConfigPath -Force | Out-Null
            Write-Host "XDG config directory created successfully"
        } catch {
            Write-Host "Failed to create XDG config directory: $($_.Exception.Message)"
            exit 1
        }
    } else {
        Write-Host "XDG config directory already exists: $xdgConfigPath"
    }

    if (!(Test-Path $xdgCachePath)) {
        Write-Host "Creating XDG cache directory: $xdgCachePath"
        try {
            New-Item -ItemType Directory -Path $xdgCachePath -Force | Out-Null
            Write-Host "XDG cache directory created successfully"
        } catch {
            Write-Host "Failed to create XDG cache directory: $($_.Exception.Message)"
            exit 1
        }
    } else {
        Write-Host "XDG cache directory already exists: $xdgCachePath"
    }

    if (!(Test-Path $xdgDataPath)) {
        Write-Host "Creating XDG data directory: $xdgDataPath"
        try {
            New-Item -ItemType Directory -Path $xdgDataPath -Force | Out-Null
            Write-Host "XDG data directory created successfully"
        } catch {
            Write-Host "Failed to create XDG data directory: $($_.Exception.Message)"
            exit 1
        }
    } else {
        Write-Host "XDG data directory already exists: $xdgDataPath"
    }

    if (!(Test-Path $xdgStatePath)) {
        Write-Host "Creating XDG state directory: $xdgStatePath"
        try {
            New-Item -ItemType Directory -Path $xdgStatePath -Force | Out-Null
            Write-Host "XDG state directory created successfully"
        } catch {
            Write-Host "Failed to create XDG state directory: $($_.Exception.Message)"
            exit 1
        }
    } else {
        Write-Host "XDG state directory already exists: $xdgStatePath"
    }
    
    # HOME 環境変数を設定
    Write-Host "Setting HOME environment variable..."
    [Environment]::SetEnvironmentVariable("HOME", $homePath, "User")
    Write-Host "HOME environment variable set: $homePath"
    
    # CONTINUE_GLOBAL_DIR 環境変数を設定
    Write-Host "Setting CONTINUE_GLOBAL_DIR environment variable..."
    [Environment]::SetEnvironmentVariable("CONTINUE_GLOBAL_DIR", $continuePath, "User")
    Write-Host "CONTINUE_GLOBAL_DIR environment variable set: $continuePath"

    # XDG 環境変数を設定
    Write-Host "Setting XDG_CONFIG_HOME environment variable..."
    [Environment]::SetEnvironmentVariable("XDG_CONFIG_HOME", $xdgConfigPath, "User")
    Write-Host "XDG_CONFIG_HOME environment variable set: $xdgConfigPath"

    Write-Host "Setting XDG_CACHE_HOME environment variable..."
    [Environment]::SetEnvironmentVariable("XDG_CACHE_HOME", $xdgCachePath, "User")
    Write-Host "XDG_CACHE_HOME environment variable set: $xdgCachePath"

    Write-Host "Setting XDG_DATA_HOME environment variable..."
    [Environment]::SetEnvironmentVariable("XDG_DATA_HOME", $xdgDataPath, "User")
    Write-Host "XDG_DATA_HOME environment variable set: $xdgDataPath"

    Write-Host "Setting XDG_STATE_HOME environment variable..."
    [Environment]::SetEnvironmentVariable("XDG_STATE_HOME", $xdgStatePath, "User")
    Write-Host "XDG_STATE_HOME environment variable set: $xdgStatePath"
    
    Write-Host ""
    Write-Host "Setup complete!"
    Write-Host "Start a new terminal session for environment variables to take effect."
} else {
    Write-Host "HOME Environment Setup"
    Write-Host "======================"
    Write-Host ""
    Write-Host "Current Status:"
    Write-Host "  Username: $userName"
    
    # XDG Base Directory Specification のパスを定義 (既存の HOME を基準に)
    $xdgConfigPath = "$homeEnvVar\.config"
    $xdgCachePath = "$homeEnvVar\.cache"
    $xdgDataPath = "$homeEnvVar\.local\share"
    $xdgStatePath = "$homeEnvVar\.local\state"

    # CONTINUE_GLOBAL_DIR もチェック
    $continueEnvVar = [Environment]::GetEnvironmentVariable("CONTINUE_GLOBAL_DIR", "User")
    $xdgConfigEnvVar = [Environment]::GetEnvironmentVariable("XDG_CONFIG_HOME", "User")
    $xdgCacheEnvVar = [Environment]::GetEnvironmentVariable("XDG_CACHE_HOME", "User")
    $xdgDataEnvVar = [Environment]::GetEnvironmentVariable("XDG_DATA_HOME", "User")
    $xdgStateEnvVar = [Environment]::GetEnvironmentVariable("XDG_STATE_HOME", "User")

    $needsSetup = [string]::IsNullOrEmpty($continueEnvVar) -or [string]::IsNullOrEmpty($xdgConfigEnvVar) -or [string]::IsNullOrEmpty($xdgCacheEnvVar) -or [string]::IsNullOrEmpty($xdgDataEnvVar) -or [string]::IsNullOrEmpty($xdgStateEnvVar)

    if ($needsSetup) {
        $continuePath = "$homeEnvVar\.continue"

        Write-Host ""
        Write-Host "Planned Actions:"

        $actions = @()

        # .continue ディレクトリチェック
        if ([string]::IsNullOrEmpty($continueEnvVar) -and !(Test-Path $continuePath)) {
            $actions += "  - Create continue directory: $continuePath"
        }

        # XDG ディレクトリチェック
        if ([string]::IsNullOrEmpty($xdgConfigEnvVar) -and !(Test-Path $xdgConfigPath)) {
            $actions += "  - Create XDG config directory: $xdgConfigPath"
        }
        if ([string]::IsNullOrEmpty($xdgCacheEnvVar) -and !(Test-Path $xdgCachePath)) {
            $actions += "  - Create XDG cache directory: $xdgCachePath"
        }
        if ([string]::IsNullOrEmpty($xdgDataEnvVar) -and !(Test-Path $xdgDataPath)) {
            $actions += "  - Create XDG data directory: $xdgDataPath"
        }
        if ([string]::IsNullOrEmpty($xdgStateEnvVar) -and !(Test-Path $xdgStatePath)) {
            $actions += "  - Create XDG state directory: $xdgStatePath"
        }

        # 環境変数設定
        if ([string]::IsNullOrEmpty($continueEnvVar)) {
            $actions += "  - Set CONTINUE_GLOBAL_DIR environment variable to: $continuePath"
        }
        if ([string]::IsNullOrEmpty($xdgConfigEnvVar)) {
            $actions += "  - Set XDG_CONFIG_HOME environment variable to: $xdgConfigPath"
        }
        if ([string]::IsNullOrEmpty($xdgCacheEnvVar)) {
            $actions += "  - Set XDG_CACHE_HOME environment variable to: $xdgCachePath"
        }
        if ([string]::IsNullOrEmpty($xdgDataEnvVar)) {
            $actions += "  - Set XDG_DATA_HOME environment variable to: $xdgDataPath"
        }
        if ([string]::IsNullOrEmpty($xdgStateEnvVar)) {
            $actions += "  - Set XDG_STATE_HOME environment variable to: $xdgStatePath"
        }
        
        # 実行予定内容を表示
        if ($actions.Count -eq 0) {
            Write-Host "  - All directories and environment variables already exist"
        }
        foreach ($action in $actions) {
            Write-Host $action
        }

        Write-Host ""
        $confirmation = Read-Host "Do you want to proceed? (Y/n)"
        if ($confirmation -eq "n" -or $confirmation -eq "N") {
            Write-Host "Setup cancelled by user."
            exit 0
        }

        Write-Host ""
        Write-Host "Starting setup..."

        # .continue ディレクトリが存在しない場合は作成
        if ([string]::IsNullOrEmpty($continueEnvVar) -and !(Test-Path $continuePath)) {
            Write-Host "Creating continue directory: $continuePath"
            try {
                New-Item -ItemType Directory -Path $continuePath -Force | Out-Null
                Write-Host "Continue directory created successfully"
            } catch {
                Write-Host "Failed to create continue directory: $($_.Exception.Message)"
                exit 1
            }
        }

        # XDG ディレクトリが存在しない場合は作成
        if ([string]::IsNullOrEmpty($xdgConfigEnvVar) -and !(Test-Path $xdgConfigPath)) {
            Write-Host "Creating XDG config directory: $xdgConfigPath"
            try {
                New-Item -ItemType Directory -Path $xdgConfigPath -Force | Out-Null
                Write-Host "XDG config directory created successfully"
            } catch {
                Write-Host "Failed to create XDG config directory: $($_.Exception.Message)"
                exit 1
            }
        }

        if ([string]::IsNullOrEmpty($xdgCacheEnvVar) -and !(Test-Path $xdgCachePath)) {
            Write-Host "Creating XDG cache directory: $xdgCachePath"
            try {
                New-Item -ItemType Directory -Path $xdgCachePath -Force | Out-Null
                Write-Host "XDG cache directory created successfully"
            } catch {
                Write-Host "Failed to create XDG cache directory: $($_.Exception.Message)"
                exit 1
            }
        }

        if ([string]::IsNullOrEmpty($xdgDataEnvVar) -and !(Test-Path $xdgDataPath)) {
            Write-Host "Creating XDG data directory: $xdgDataPath"
            try {
                New-Item -ItemType Directory -Path $xdgDataPath -Force | Out-Null
                Write-Host "XDG data directory created successfully"
            } catch {
                Write-Host "Failed to create XDG data directory: $($_.Exception.Message)"
                exit 1
            }
        }

        if ([string]::IsNullOrEmpty($xdgStateEnvVar) -and !(Test-Path $xdgStatePath)) {
            Write-Host "Creating XDG state directory: $xdgStatePath"
            try {
                New-Item -ItemType Directory -Path $xdgStatePath -Force | Out-Null
                Write-Host "XDG state directory created successfully"
            } catch {
                Write-Host "Failed to create XDG state directory: $($_.Exception.Message)"
                exit 1
            }
        }

        # 環境変数を設定
        if ([string]::IsNullOrEmpty($continueEnvVar)) {
            [Environment]::SetEnvironmentVariable("CONTINUE_GLOBAL_DIR", $continuePath, "User")
            Write-Host "CONTINUE_GLOBAL_DIR environment variable set: $continuePath"
        }

        if ([string]::IsNullOrEmpty($xdgConfigEnvVar)) {
            [Environment]::SetEnvironmentVariable("XDG_CONFIG_HOME", $xdgConfigPath, "User")
            Write-Host "XDG_CONFIG_HOME environment variable set: $xdgConfigPath"
        }

        if ([string]::IsNullOrEmpty($xdgCacheEnvVar)) {
            [Environment]::SetEnvironmentVariable("XDG_CACHE_HOME", $xdgCachePath, "User")
            Write-Host "XDG_CACHE_HOME environment variable set: $xdgCachePath"
        }

        if ([string]::IsNullOrEmpty($xdgDataEnvVar)) {
            [Environment]::SetEnvironmentVariable("XDG_DATA_HOME", $xdgDataPath, "User")
            Write-Host "XDG_DATA_HOME environment variable set: $xdgDataPath"
        }

        if ([string]::IsNullOrEmpty($xdgStateEnvVar)) {
            [Environment]::SetEnvironmentVariable("XDG_STATE_HOME", $xdgStatePath, "User")
            Write-Host "XDG_STATE_HOME environment variable set: $xdgStatePath"
        }
        
        Write-Host ""
        Write-Host "Setup complete!"
        Write-Host "Start a new terminal session for environment variables to take effect."
    } else {
        Write-Host "  HOME environment variable: Already set ($homeEnvVar)"
        Write-Host "  CONTINUE_GLOBAL_DIR environment variable: Already set ($continueEnvVar)"
        Write-Host "  XDG_CONFIG_HOME environment variable: Already set ($xdgConfigEnvVar)"
        Write-Host "  XDG_CACHE_HOME environment variable: Already set ($xdgCacheEnvVar)"
        Write-Host "  XDG_DATA_HOME environment variable: Already set ($xdgDataEnvVar)"
        Write-Host "  XDG_STATE_HOME environment variable: Already set ($xdgStateEnvVar)"
        Write-Host ""
        Write-Host "All environment variables and directories are already configured."
    }
}
