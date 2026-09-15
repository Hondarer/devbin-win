# Windows Terminal Git Bash プロファイル管理スクリプト
param(
    [switch]$Install,      # プロファイルの登録
    [switch]$Uninstall,    # プロファイルの削除
    [switch]$Force = $false, # 既存プロファイルの上書き登録
    [string]$InstallDir = ""  # devbin-win インストール先 (既定値: %ProgramData%\%USERNAME%\devbin-win\bin)
)

$ScriptDir = if ($PSScriptRoot) {
    $PSScriptRoot
} else {
    Split-Path -Parent $MyInvocation.MyCommand.Path
}

# Windows Terminal の設定操作処理は Devbin/Platform モジュールと共通化
try {
    Import-Module (Join-Path $ScriptDir "Devbin") -Force -ErrorAction Stop
} catch {
    Write-Host "Error importing Devbin: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# コマンドラインの使用方法を表示
function Show-Usage {
    Write-Host "`n=== Windows Terminal Git Bash Profile Manager ==="
    Write-Host "`nUsage:"
    Write-Host "  .\Update-GitBash-Profile.ps1 -Install                          # Install Git Bash profile"
    Write-Host "  .\Update-GitBash-Profile.ps1 -Uninstall                        # Uninstall Git Bash profile"
    Write-Host "  .\Update-GitBash-Profile.ps1 -Install -Force                   # Force overwrite existing profile"
    Write-Host "  .\Update-GitBash-Profile.ps1 -Install -InstallDir <path>       # Use custom install dir"
    Write-Host "`nOptions:"
    Write-Host "  -Install              Add Git Bash profile to Windows Terminal"
    Write-Host "  -Uninstall            Remove Git Bash profile from Windows Terminal"
    Write-Host "  -Force                Force overwrite existing profile (use with -Install)"
    Write-Host "  -InstallDir <path>    devbin-win bin directory (default: %ProgramData%\%USERNAME%\devbin-win\bin)"
    Write-Host "`nExamples:"
    Write-Host "  # Install profile"
    Write-Host "  .\Update-GitBash-Profile.ps1 -Install"
    Write-Host "`n  # Remove profile"
    Write-Host "  .\Update-GitBash-Profile.ps1 -Uninstall"
    Write-Host "`n  # Force update existing profile"
    Write-Host "  .\Update-GitBash-Profile.ps1 -Install -Force`n"
}

# Git Bash プロファイルの登録処理
function Install-GitBashProfile {
    param(
        [string]$SettingsPath,
        [string]$BinDir,
        [bool]$ForceUpdate = $false
    )
    
    # 登録対象のプロファイル定義
    $newProfile = @{
        guid = "{b2e42366-5d93-4fb7-be22-177d0a5850d1}"
        name = "Git Bash"
        commandline = "$BinDir\git\bin\bash.exe -i -l"
        startingDirectory = "%USERPROFILE%"
        icon = "$BinDir\git\mingw64\share\git\git-for-windows.ico"
    }
    
    try {
        # 設定ファイルのバックアップを作成
        $backupPath = New-SettingsBackup -SettingsPath $SettingsPath
        
        # 現在の設定を読み込み
        $settings = Get-TerminalSettings -SettingsPath $SettingsPath
        
        # 既存プロファイルの存在確認
        $existingProfile = $settings.profiles.list | Where-Object { 
            $_.guid -eq $newProfile.guid -or $_.name -eq $newProfile.name 
        }
        
        if ($existingProfile -and -not $ForceUpdate) {
            Write-Host "Profile '$($newProfile.name)' (GUID: $($newProfile.guid)) already exists."
            Write-Host "Use -Force parameter to force update."
            
            # 既存プロファイルの詳細情報を表示
            Write-Host "`nExisting profile information:"
            Write-Host "  Name: $($existingProfile.name)"
            Write-Host "  GUID: $($existingProfile.guid)"
            Write-Host "  Command: $($existingProfile.commandline)"
            
            return $false
        }
        
        if ($existingProfile -and $ForceUpdate) {
            Write-Host "Updating existing profile..."
            # 既存プロファイルを削除 (上書き更新用)
            $settings.profiles.list = @($settings.profiles.list | Where-Object { 
                $_.guid -ne $newProfile.guid -and $_.name -ne $newProfile.name 
            })
        }
        
        # 実行ファイルとアイコンファイルの存在確認
        $bashPath = $newProfile.commandline -replace ' -i -l$', ''
        $iconPath = $newProfile.icon
        
        if (-not (Test-Path $bashPath)) {
            Write-Warning "Warning: bash.exe not found: $bashPath"
            Write-Host "Profile will be added but may fail to execute."
        } else {
            #Write-Host "Verified bash.exe: $bashPath"
        }
        
        if (-not (Test-Path $iconPath)) {
            Write-Warning "Warning: Icon file not found: $iconPath"
            Write-Host "Default icon will be used."
        }
        
        # 新しいプロファイルを追加
        $newProfileObject = [PSCustomObject]$newProfile
        $settings.profiles.list = @($settings.profiles.list) + @($newProfileObject)
        
        # 更新後の設定を保存
        Save-TerminalSettings -Settings $settings -SettingsPath $SettingsPath
        
        #Write-Host "`nGit Bash profile installation completed successfully!"
        #Write-Host "Please restart Windows Terminal to see the new profile."
        
        # 追加されたプロファイル情報を表示
        #Write-Host "`nInstalled profile information:"
        #Write-Host "  Name: $($newProfile.name)"
        #Write-Host "  GUID: $($newProfile.guid)"
        #Write-Host "  Command: $($newProfile.commandline)"
        #Write-Host "  Starting Directory: $($newProfile.startingDirectory)"
        #Write-Host "  Icon: $($newProfile.icon)"
        #Write-Host "`nBackup file: $backupPath"
        
        return $true
        
    } catch {
        Write-Error "Error occurred during installation: $($_.Exception.Message)"
        
        # エラー発生時のバックアップ復元手順を表示
        if (Test-Path $backupPath) {
            Write-Host "`nTo restore from backup if needed:"
            Write-Host "Copy-Item -Path '$backupPath' -Destination '$SettingsPath' -Force"
        }
        
        return $false
    }
}

# Git Bash プロファイルの削除処理
function Uninstall-GitBashProfile {
    param([string]$SettingsPath)
    
    $targetGuid = "{b2e42366-5d93-4fb7-be22-177d0a5850d1}"
    $targetName = "Git Bash"
    
    try {
        # 設定ファイルのバックアップを作成
        $backupPath = New-SettingsBackup -SettingsPath $SettingsPath
        
        # 現在の設定を読み込み
        $settings = Get-TerminalSettings -SettingsPath $SettingsPath
        
        # 削除対象プロファイルを検索
        $targetProfiles = $settings.profiles.list | Where-Object { 
            $_.guid -eq $targetGuid -or $_.name -eq $targetName 
        }
        
        if (-not $targetProfiles) {
            return $false
        }
        
        # 削除対象プロファイルの詳細情報を表示
        #Write-Host "`nProfiles to be removed:"
        #foreach ($profile in $targetProfiles) {
        #    Write-Host "  Name: $($profile.name)"
        #    Write-Host "  GUID: $($profile.guid)"
        #    Write-Host "  Command: $($profile.commandline)"
        #}
        
        # 対象プロファイルを削除
        $originalCount = $settings.profiles.list.Count
        $settings.profiles.list = @($settings.profiles.list | Where-Object { 
            $_.guid -ne $targetGuid -and $_.name -ne $targetName 
        })
        $newCount = $settings.profiles.list.Count
        $removedCount = $originalCount - $newCount
        
        if ($removedCount -eq 0) {
            Write-Host "Git Bash profile was not present. Nothing to remove."
            return $true
        }
        
        # 更新後の設定を保存
        Save-TerminalSettings -Settings $settings -SettingsPath $SettingsPath
        
        #Write-Host "`nGit Bash profile uninstallation completed successfully!"
        #Write-Host "Please restart Windows Terminal to see the changes."
        #Write-Host "Removed profiles: $removedCount"
        #Write-Host "Backup file: $backupPath"
        
        return $true
        
    } catch {
        Write-Error "Error occurred during uninstallation: $($_.Exception.Message)"
        
        # エラー発生時のバックアップ復元手順を表示
        if (Test-Path $backupPath) {
            Write-Host "`nTo restore from backup if needed:"
            Write-Host "Copy-Item -Path '$backupPath' -Destination '$SettingsPath' -Force"
        }
        
        return $false
    }
}

# メイン処理
function Main {
    # パラメーターの検証
    if (-not $Install -and -not $Uninstall) {
        Show-Usage
        exit 0
    }
    
    if ($Install -and $Uninstall) {
        Write-Error "Cannot specify both -Install and -Uninstall at the same time."
        Show-Usage
        exit 1
    }
    
    # InstallDir の既定値を動的に解決
    $effectiveInstallDir = if ($InstallDir -and $InstallDir -ne "") {
        $InstallDir
    } else {
        "$env:ProgramData\$env:USERNAME\devbin-win\bin"
    }
    
    # settings.json の配置パスを取得
    $settingsPath = Get-WindowsTerminalSettingsPath -ProfileLabel "Git Bash profile"
    if (-not $settingsPath) {
        exit 0
    }
    
    # 指定された操作を実行
    $success = $false
    
    if ($Install) {
        Write-Host "Installing Git Bash profile..."
        $success = Install-GitBashProfile -SettingsPath $settingsPath -BinDir $effectiveInstallDir -ForceUpdate $Force
    }
    elseif ($Uninstall) {
        Write-Host "Uninstalling Git Bash profile..."
        $success = Uninstall-GitBashProfile -SettingsPath $settingsPath
    }
    
    if ($success) {
        exit 0
    } else {
        exit 1
    }
}

# エントリーポイントの呼び出し
Main
