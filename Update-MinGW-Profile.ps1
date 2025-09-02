# Windows Terminal MinGW PowerShell プロファイル管理スクリプト
param(
    [switch]$Install,      # プロファイルをインストール
    [switch]$Uninstall,    # プロファイルをアンインストール
    [switch]$Force = $false # 強制実行
)

# 使用方法を表示
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

# Settings.jsonのパスを特定
function Get-WindowsTerminalSettingsPath {
    $possiblePaths = @(
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json",
        "$env:APPDATA\Microsoft\Windows Terminal\settings.json"
    )
    
    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            return $path
        }
    }
    
    Write-Error "Windows Terminal settings.json not found. Please ensure Windows Terminal is installed."
    return $null
}

# バックアップを作成
function New-SettingsBackup {
    param([string]$SettingsPath)
    
    $backupPath = $SettingsPath + ".$(Get-Date -Format 'yyMMddHHmmss')"
    Copy-Item -Path $SettingsPath -Destination $backupPath
    return $backupPath
}

# JSON設定を読み込み
function Get-TerminalSettings {
    param([string]$SettingsPath)
    
    $jsonContent = Get-Content -Path $SettingsPath -Raw -Encoding UTF8
    $settings = $jsonContent | ConvertFrom-Json
    
    # profiles.listが存在するか確認・作成
    if (-not $settings.profiles) {
        $settings | Add-Member -MemberType NoteProperty -Name "profiles" -Value ([PSCustomObject]@{})
    }
    if (-not $settings.profiles.list) {
        $settings.profiles | Add-Member -MemberType NoteProperty -Name "list" -Value @()
    }
    
    return $settings
}

# JSON設定を保存
function Save-TerminalSettings {
    param(
        [PSCustomObject]$Settings,
        [string]$SettingsPath
    )
    
    $jsonOutput = $Settings | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($SettingsPath, $jsonOutput, [System.Text.Encoding]::UTF8)
}

# MinGW PowerShell プロファイルをインストール
function Install-MinGWProfile {
    param(
        [string]$SettingsPath,
        [bool]$ForceUpdate = $false
    )
    
    # 追加したいプロファイル設定
    $newProfile = @{
        guid = "{d48c104b-44a7-4180-be8d-b542db93a384}"
        name = "Windows PowerShell (w/MinGW)"
        commandline = "powershell.exe -NoExit -Command `"& 'Add-MinGW-Path.ps1'`""
        startingDirectory = "%USERPROFILE%"
        icon = "ms-appx:///ProfileIcons/{61c54bbd-c2c6-5271-96e7-009a87ff44bf}.png"
    }
    
    try {
        # バックアップ作成
        $backupPath = New-SettingsBackup -SettingsPath $SettingsPath
        
        # 設定を読み込み
        $settings = Get-TerminalSettings -SettingsPath $SettingsPath
        
        # 既存プロファイルをチェック
        $existingProfile = $settings.profiles.list | Where-Object { 
            $_.guid -eq $newProfile.guid -or $_.name -eq $newProfile.name 
        }
        
        if ($existingProfile -and -not $ForceUpdate) {
            Write-Host "Profile '$($newProfile.name)' (GUID: $($newProfile.guid)) already exists."
            Write-Host "Use -Force parameter to force update."
            
            # 既存プロファイルの詳細を表示
            Write-Host "`nExisting profile information:"
            Write-Host "  Name: $($existingProfile.name)"
            Write-Host "  GUID: $($existingProfile.guid)"
            Write-Host "  Command: $($existingProfile.commandline)"
            
            return $false
        }
        
        if ($existingProfile -and $ForceUpdate) {
            Write-Host "Updating existing profile..."
            # 既存プロファイルを削除
            $settings.profiles.list = @($settings.profiles.list | Where-Object { 
                $_.guid -ne $newProfile.guid -and $_.name -ne $newProfile.name 
            })
        }
        
        # Add-MinGW-Path.ps1 の存在確認
        $addMinGWScript = "Add-MinGW-Path.ps1"
        $scriptFound = $false
        
        # PATH 内で Add-MinGW-Path.ps1 を検索
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
        
        # 設定を保存
        Save-TerminalSettings -Settings $settings -SettingsPath $SettingsPath
        
        Write-Host "MinGW PowerShell profile installation completed successfully!"
        Write-Host "Please restart Windows Terminal to see the new profile."
        
        # 追加されたプロファイル情報を表示
        Write-Host "`nInstalled profile information:"
        Write-Host "  Name: $($newProfile.name)"
        Write-Host "  GUID: $($newProfile.guid)"
        Write-Host "  Command: $($newProfile.commandline)"
        Write-Host "  Starting Directory: $($newProfile.startingDirectory)"
        Write-Host "`nBackup file: $backupPath"
        
        return $true
        
    } catch {
        Write-Error "Error occurred during installation: $($_.Exception.Message)"
        
        # バックアップから復元を提案
        if (Test-Path $backupPath) {
            Write-Host "`nTo restore from backup if needed:"
            Write-Host "Copy-Item -Path '$backupPath' -Destination '$SettingsPath' -Force"
        }
        
        return $false
    }
}

# MinGW PowerShell プロファイルをアンインストール
function Uninstall-MinGWProfile {
    param([string]$SettingsPath)
    
    $targetGuid = "{d48c104b-44a7-4180-be8d-b542db93a384}"
    $targetName = "Windows PowerShell (w/MinGW)"
    
    try {
        # バックアップ作成
        $backupPath = New-SettingsBackup -SettingsPath $SettingsPath
        
        # 設定を読み込み
        $settings = Get-TerminalSettings -SettingsPath $SettingsPath
        
        # 削除対象プロファイルを検索
        $targetProfiles = $settings.profiles.list | Where-Object { 
            $_.guid -eq $targetGuid -or $_.name -eq $targetName 
        }
        
        if (-not $targetProfiles) {
            Write-Host "MinGW PowerShell profile not found. It may have already been removed or was never installed."
            return $false
        }
        
        # プロファイルを削除
        $originalCount = $settings.profiles.list.Count
        $settings.profiles.list = @($settings.profiles.list | Where-Object { 
            $_.guid -ne $targetGuid -and $_.name -ne $targetName 
        })
        $newCount = $settings.profiles.list.Count
        $removedCount = $originalCount - $newCount
        
        if ($removedCount -eq 0) {
            Write-Host "No profiles were removed."
            return $false
        }
        
        # 設定を保存
        Save-TerminalSettings -Settings $settings -SettingsPath $SettingsPath
        
        Write-Host "MinGW PowerShell profile uninstallation completed successfully!"
        Write-Host "Please restart Windows Terminal to see the changes."
        Write-Host "Removed profiles: $removedCount"
        Write-Host "Backup file: $backupPath"
        
        return $true
        
    } catch {
        Write-Error "Error occurred during uninstallation: $($_.Exception.Message)"
        
        # バックアップから復元を提案
        if (Test-Path $backupPath) {
            Write-Host "`nTo restore from backup if needed:"
            Write-Host "Copy-Item -Path '$backupPath' -Destination '$SettingsPath' -Force"
        }
        
        return $false
    }
}

# メイン処理
function Main {
    # パラメータの検証
    if (-not $Install -and -not $Uninstall) {
        Show-Usage
        exit 0
    }
    
    if ($Install -and $Uninstall) {
        Write-Error "Cannot specify both -Install and -Uninstall at the same time."
        Show-Usage
        exit 1
    }
    
    # Settings.jsonのパスを取得
    $settingsPath = Get-WindowsTerminalSettingsPath
    if (-not $settingsPath) {
        exit 1
    }
    
    # 操作実行
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

# スクリプト実行
Main
