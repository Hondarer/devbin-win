# Setup-Home.ps1
# HOME 環境変数とホームディレクトリのセットアップスクリプト

# 現在のユーザー名を取得
$userName = [Environment]::UserName

# HOME 環境変数をチェック
$homeEnvVar = [Environment]::GetEnvironmentVariable("HOME", "User")

if ([string]::IsNullOrEmpty($homeEnvVar)) {
    Write-Host "HOME environment variable not set. Starting setup..."
    
    # ホームディレクトリのパスを定義
    $baseHomePath = "C:\ProgramData\home"
    $homePath = "$baseHomePath\$userName"
    $continuePath = "$homePath\.continue"
    
    Write-Host "Username: $userName"
    Write-Host "Base home directory: $baseHomePath"
    Write-Host "User home directory: $homePath"
    Write-Host "Continue directory: $continuePath"
    
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
    
    # HOME 環境変数を設定
    Write-Host "Setting HOME environment variable..."
    [Environment]::SetEnvironmentVariable("HOME", $homePath, "User")
    Write-Host "HOME environment variable set: $homePath"
    
    # CONTINUE_GLOBAL_DIR 環境変数を設定
    Write-Host "Setting CONTINUE_GLOBAL_DIR environment variable..."
    [Environment]::SetEnvironmentVariable("CONTINUE_GLOBAL_DIR", $continuePath, "User")
    Write-Host "CONTINUE_GLOBAL_DIR environment variable set: $continuePath"
    
    Write-Host ""
    Write-Host "Setup complete!"
    Write-Host "Start a new terminal session for environment variables to take effect."
} else {
    Write-Host "HOME environment variable already set: $homeEnvVar"
    
    # CONTINUE_GLOBAL_DIR もチェック
    $continueEnvVar = [Environment]::GetEnvironmentVariable("CONTINUE_GLOBAL_DIR", "User")
    if ([string]::IsNullOrEmpty($continueEnvVar)) {
        Write-Host "CONTINUE_GLOBAL_DIR environment variable not set. Setting now..."
        $continuePath = "$homeEnvVar\.continue"
        
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
        }
        
        [Environment]::SetEnvironmentVariable("CONTINUE_GLOBAL_DIR", $continuePath, "User")
        Write-Host "CONTINUE_GLOBAL_DIR environment variable set: $continuePath"
    } else {
        Write-Host "CONTINUE_GLOBAL_DIR environment variable also already set: $continueEnvVar"
    }
}
