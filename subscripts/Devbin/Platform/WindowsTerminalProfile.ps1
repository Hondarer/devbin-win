# WindowsTerminalProfile.ps1
# Windows Terminal のプロファイル操作で共通に使う設定ファイルの読み書き
#
# Git Bash 用と MinGW 用のプロファイル更新スクリプトが共有する。

# settings.json の場所を特定する
# 見つからない場合は警告を出して $null を返す
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

# 変更前の settings.json を控えておく
function New-SettingsBackup {
    param([string]$SettingsPath)

    $backupPath = $SettingsPath + ".$(Get-Date -Format 'yyMMddHHmmss')"
    Copy-Item -Path $SettingsPath -Destination $backupPath
    return $backupPath
}

# settings.json を読み込む
# profiles.list が無ければ作ってから返す
function Get-TerminalSettings {
    param([string]$SettingsPath)

    $jsonContent = Get-Content -Path $SettingsPath -Raw -Encoding UTF8
    $settings = $jsonContent | ConvertFrom-Json

    if (-not $settings.profiles) {
        $settings | Add-Member -MemberType NoteProperty -Name "profiles" -Value ([PSCustomObject]@{})
    }
    if (-not $settings.profiles.list) {
        $settings.profiles | Add-Member -MemberType NoteProperty -Name "list" -Value @()
    }

    return $settings
}

# settings.json を保存する
function Save-TerminalSettings {
    param(
        [PSCustomObject]$Settings,
        [string]$SettingsPath
    )

    $jsonOutput = $Settings | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($SettingsPath, $jsonOutput, [System.Text.Encoding]::UTF8)
}
