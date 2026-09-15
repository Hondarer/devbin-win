# Windows Terminal MinGW PowerShell プロファイル管理スクリプト
param(
    [switch]$Install,      # プロファイルの登録
    [switch]$Uninstall,    # プロファイルの削除
    [switch]$Force = $false # 既存プロファイルの上書き登録
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
    Write-Host "`n=== Windows Terminal MinGW PowerShell Profile Manager ==="
    Write-Host "`nUsage:"
    Write-Host "  .\Update-MinGW-Profile.ps1 -Install         # Install MinGW PowerShell profile"
    Write-Host "  .\Update-MinGW-Profile.ps1 -Uninstall       # Uninstall MinGW PowerShell profile"
    Write-Host "  .\Update-MinGW-Profile.ps1 -Install -Force  # Force overwrite existing profile"
    Write-Host "`nOptions:"
    Write-Host "  -Install     Add MinGW PowerShell profile to Windows Terminal"
    Write-Host "  -Uninstall   Remove MinGW PowerShell profile from Windows Terminal" 
    Write-Host "  -Force       Force overwrite existing profile (use with -Install)"
    Write-Host "`nExamples:"
    Write-Host "  # Install profile"
    Write-Host "  .\Update-MinGW-Profile.ps1 -Install"
    Write-Host "`n  # Remove profile"
    Write-Host "  .\Update-MinGW-Profile.ps1 -Uninstall"
    Write-Host "`n  # Force update existing profile"
    Write-Host "  .\Update-MinGW-Profile.ps1 -Install -Force`n"
}

# MinGW PowerShell プロファイルの登録処理
function Install-MinGWProfile {
    param(
        [string]$SettingsPath,
        [bool]$ForceUpdate = $false
    )
    
    # 登録対象のプロファイル定義
    $newProfile = @{
        guid = "{d48c104b-44a7-4180-be8d-b542db93a384}"
        name = "Windows PowerShell (w/MinGW)"
        commandline = "powershell.exe -NoExit -ExecutionPolicy Bypass -Command `"& 'Add-MinGW-Path.ps1'`""
        startingDirectory = "%USERPROFILE%"
        icon = "ms-appx:///ProfileIcons/{61c54bbd-c2c6-5271-96e7-009a87ff44bf}.png"
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
        
        # Add-MinGW-Path.ps1 の存在確認
        $addMinGWScript = "Add-MinGW-Path.ps1"
        $scriptFound = $false
        
        # PATH 環境変数から Add-MinGW-Path.ps1 を検索
        $pathDirs = $env:PATH -split ';'
        foreach ($dir in $pathDirs) {
            if ($dir -and (Test-Path (Join-Path $dir $addMinGWScript))) {
                $scriptFound = $true
                break
            }
        }
        
        if (-not $scriptFound) {
            Write-Warning "Warning: Add-MinGW-Path.ps1 not found in PATH"
            Write-Host "The profile will be created but Add-MinGW-Path.ps1 may not execute properly."
            Write-Host "Please ensure Add-MinGW-Path.ps1 is available in PATH when using this profile."
        }
        
        # 新しいプロファイルを追加
        $newProfileObject = [PSCustomObject]$newProfile
        $settings.profiles.list = @($settings.profiles.list) + @($newProfileObject)
        
        # 更新後の設定を保存
        Save-TerminalSettings -Settings $settings -SettingsPath $SettingsPath
        
        #Write-Host "MinGW PowerShell profile installation completed successfully!"
        #Write-Host "Please restart Windows Terminal to see the new profile."
        
        # 追加されたプロファイル情報を表示
        #Write-Host "`nInstalled profile information:"
        #Write-Host "  Name: $($newProfile.name)"
        #Write-Host "  GUID: $($newProfile.guid)"
        #Write-Host "  Command: $($newProfile.commandline)"
        #Write-Host "  Starting Directory: $($newProfile.startingDirectory)"
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

# MinGW PowerShell プロファイルの削除処理
function Uninstall-MinGWProfile {
    param([string]$SettingsPath)
    
    $targetGuid = "{d48c104b-44a7-4180-be8d-b542db93a384}"
    $targetName = "Windows PowerShell (w/MinGW)"
    
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
            Write-Host "MinGW profile was not present. Nothing to remove."
            return $true
        }
        
        # 更新後の設定を保存
        Save-TerminalSettings -Settings $settings -SettingsPath $SettingsPath
        
        #Write-Host "`nMinGW PowerShell profile uninstallation completed successfully!"
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
    
    # settings.json の配置パスを取得
    $settingsPath = Get-WindowsTerminalSettingsPath -ProfileLabel "MinGW profile"
    if (-not $settingsPath) {
        exit 0
    }
    
    # 指定された操作を実行
    $success = $false
    
    if ($Install) {
        Write-Host "Installing MinGW PowerShell profile..."
        $success = Install-MinGWProfile -SettingsPath $settingsPath -ForceUpdate $Force
    }
    elseif ($Uninstall) {
        Write-Host "Uninstalling MinGW PowerShell profile..."
        $success = Uninstall-MinGWProfile -SettingsPath $settingsPath
    }
    
    if ($success) {
        exit 0
    } else {
        exit 1
    }
}

# エントリーポイントの呼び出し
Main
