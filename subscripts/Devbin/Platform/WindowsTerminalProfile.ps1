# WindowsTerminalProfile.ps1
# Windows Terminal プロファイル操作における共通設定ファイルの入出力処理
#
# Git Bash 用および MinGW 用のプロファイル更新スクリプトから共有されます。

# settings.json の配置パスを特定
# ファイルが存在しない場合は警告メッセージを出力して $null を返却
function Get-WindowsTerminalSettingsPath {
    param([string]$ProfileLabel = "profile")

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

    Write-Warning "Windows Terminal settings.json not found. Skipping $ProfileLabel update."
    return $null
}

# 変更前の settings.json のバックアップを生成
function New-SettingsBackup {
    param([string]$SettingsPath)

    $backupPath = $SettingsPath + ".$(Get-Date -Format 'yyMMddHHmmss')"
    Copy-Item -Path $SettingsPath -Destination $backupPath
    return $backupPath
}

# settings.json の読み込み
# profiles.list プロパティが存在しない場合は空配列として初期化して返却
function Get-TerminalSettings {
    param([string]$SettingsPath)

    $jsonContent = Get-Content -Path $SettingsPath -Raw -Encoding UTF8
    $settings = ConvertFrom-JsonWithComments -JsonText $jsonContent
    if ($null -eq $settings -or $settings -isnot [PSCustomObject]) {
        throw "Windows Terminal settings must be a JSON object: $SettingsPath"
    }

    if (-not $settings.profiles) {
        $settings | Add-Member -MemberType NoteProperty -Name "profiles" -Value ([PSCustomObject]@{}) -Force
    }
    if (-not $settings.profiles.list) {
        $settings.profiles | Add-Member -MemberType NoteProperty -Name "list" -Value @() -Force
    }

    return $settings
}

# settings.json の保存
function Save-TerminalSettings {
    param(
        [PSCustomObject]$Settings,
        [string]$SettingsPath
    )

    $jsonOutput = $Settings | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($SettingsPath, $jsonOutput, [System.Text.Encoding]::UTF8)
}
