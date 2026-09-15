# WindowsTerminal.ps1
# Windows Terminal 設定ファイルの読み取りおよびプロファイルのクリーンアップ

# コメント構文 (// および /* */) を含む JSON 文字列を解析してオブジェクトに変換
function ConvertFrom-JsonWithComments {
    param(
        [string]$JsonText
    )

    if ([string]::IsNullOrWhiteSpace($JsonText)) {
        return $null
    }

    # Windows Terminal の settings.json に含まれるコメント構文を事前に除去
    $builder = New-Object System.Text.StringBuilder
    $inString = $false
    $escaped = $false
    $index = 0
    $length = $JsonText.Length

    while ($index -lt $length) {
        $ch = $JsonText[$index]

        if ($inString) {
            [void]$builder.Append($ch)
            if ($escaped) {
                $escaped = $false
            } elseif ($ch -eq [char]92) {
                $escaped = $true
            } elseif ($ch -eq '"') {
                $inString = $false
            }
            $index++
            continue
        }

        if ($ch -eq '"') {
            $inString = $true
            [void]$builder.Append($ch)
            $index++
            continue
        }

        if ($ch -eq '/' -and ($index + 1) -lt $length) {
            $next = $JsonText[$index + 1]
            if ($next -eq '/') {
                while ($index -lt $length -and $JsonText[$index] -ne "`n") {
                    $index++
                }
                continue
            }
            if ($next -eq '*') {
                $index += 2
                while (($index + 1) -lt $length -and -not ($JsonText[$index] -eq '*' -and $JsonText[$index + 1] -eq '/')) {
                    $index++
                }
                $index += 2
                continue
            }
        }

        [void]$builder.Append($ch)
        $index++
    }

    return ($builder.ToString() | ConvertFrom-Json)
}

function Get-WindowsTerminalSettingsPaths {
    return @(
        (Join-Path $env:LOCALAPPDATA "Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"),
        (Join-Path $env:LOCALAPPDATA "Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json"),
        (Join-Path $env:APPDATA "Microsoft\Windows Terminal\settings.json")
    )
}

function Test-DevbinWindowsTerminalProfileGuid {
    param([string]$GuidValue)

    if ([string]::IsNullOrWhiteSpace($GuidValue)) {
        return $false
    }

    $normalized = $GuidValue.Trim().Trim("{}")
    $known = @(
        "b2e42366-5d93-4fb7-be22-177d0a5850d1",
        "d48c104b-44a7-4180-be8d-b542db93a384"
    )
    foreach ($guid in $known) {
        if ([string]::Equals($normalized, $guid, [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

function Remove-WindowsTerminalProfilesForRoot {
    param(
        [string]$Root
    )

    $settingsPaths = @(Get-WindowsTerminalSettingsPaths | Where-Object { $_ -and (Test-Path $_) })
    if ($settingsPaths.Count -eq 0) {
        Write-Host "  Windows Terminal settings.json not found, skipping profile cleanup"
        return
    }

    foreach ($settingsPath in $settingsPaths) {
        $backupPath = $null
        try {
            $jsonContent = Get-Content -Path $settingsPath -Raw -Encoding UTF8
            $settings = ConvertFrom-JsonWithComments -JsonText $jsonContent
            if (-not $settings -or -not $settings.profiles -or -not $settings.profiles.list) {
                continue
            }

            $originalProfiles = @($settings.profiles.list)
            $removedNames = @()
            $removedGuids = @()
            $kept = @()
            # $profile は PowerShell の組み込み自動変数のため、$wtProfile を使用して変数名の衝突を回避
            foreach ($wtProfile in $originalProfiles) {
                $guid = if ($wtProfile.PSObject.Properties.Match("guid").Count -gt 0) { [string]$wtProfile.guid } else { "" }
                $commandline = if ($wtProfile.PSObject.Properties.Match("commandline").Count -gt 0) { [string]$wtProfile.commandline } else { "" }
                $icon = if ($wtProfile.PSObject.Properties.Match("icon").Count -gt 0) { [string]$wtProfile.icon } else { "" }
                $startingDirectory = if ($wtProfile.PSObject.Properties.Match("startingDirectory").Count -gt 0) { [string]$wtProfile.startingDirectory } else { "" }

                $matchesRoot = (Test-PathUnderRoot -PathValue $commandline -Root $Root) -or
                    (Test-PathUnderRoot -PathValue $icon -Root $Root) -or
                    (Test-PathUnderRoot -PathValue $startingDirectory -Root $Root)
                $matchesKnownGuid = Test-DevbinWindowsTerminalProfileGuid -GuidValue $guid

                if ($matchesRoot -or $matchesKnownGuid) {
                    $profileName = if ($wtProfile.PSObject.Properties.Match("name").Count -gt 0) { [string]$wtProfile.name } else { $guid }
                    $removedNames += $profileName
                    if ($guid) {
                        $removedGuids += $guid
                    }
                } else {
                    $kept += $wtProfile
                }
            }

            if ($removedNames.Count -eq 0) {
                continue
            }

            $settings.profiles.list = [object[]]$kept
            if ($settings.PSObject.Properties.Match("defaultProfile").Count -gt 0) {
                $defaultProfile = [string]$settings.defaultProfile
                $defaultRemoved = $false
                foreach ($removedGuid in $removedGuids) {
                    if ([string]::Equals($defaultProfile, $removedGuid, [StringComparison]::OrdinalIgnoreCase)) {
                        $defaultRemoved = $true
                        break
                    }
                }
                if ($defaultRemoved) {
                    if ($kept.Count -gt 0 -and $kept[0].PSObject.Properties.Match("guid").Count -gt 0) {
                        $settings.defaultProfile = [string]$kept[0].guid
                    }
                }
            }

            # 変更反映の直前にバックアップを作成 (変更がない場合や解析失敗時のバックアップ作成を防止)
            $backupPath = $settingsPath + "." + (Get-Date -Format "yyMMddHHmmss")
            Copy-Item -Path $settingsPath -Destination $backupPath -Force

            $jsonOutput = $settings | ConvertTo-Json -Depth 20
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText($settingsPath, $jsonOutput, $utf8NoBom)
            foreach ($name in $removedNames) {
                Write-Host "  Removed Windows Terminal profile: $name"
            }
            Write-Host "  Backup: $backupPath"
        } catch {
            Write-Host "Warning: Failed to clean Windows Terminal profiles ($settingsPath): $($_.Exception.Message)" -ForegroundColor Yellow
            if ($backupPath -and (Test-Path $backupPath)) {
                Write-Host "  To restore: Copy-Item -Path '$backupPath' -Destination '$settingsPath' -Force" -ForegroundColor Yellow
            }
        }
    }
}
