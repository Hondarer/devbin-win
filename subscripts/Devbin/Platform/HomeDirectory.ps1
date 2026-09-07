# HomeDirectory.ps1
# HOME と XDG ディレクトリの構成
#
# 初期作成と、既に HOME がある場合の不足項目の補完を同じ定義で扱う。

# HOME 未設定時の既定の配置先
$script:DevbinDefaultHomeRoot = "C:\ProgramData\home"

# HOME 配下に用意する項目の定義を返す
# 各項目は環境変数名、パス、表示名を持つ
function Get-DevbinHomeLayout {
    param([string]$HomePath)

    return @(
        [PSCustomObject]@{ EnvName = "CONTINUE_GLOBAL_DIR"; Path = (Join-Path $HomePath ".continue");     Label = "continue" }
        [PSCustomObject]@{ EnvName = "XDG_CONFIG_HOME";     Path = (Join-Path $HomePath ".config");       Label = "XDG config" }
        [PSCustomObject]@{ EnvName = "XDG_CACHE_HOME";      Path = (Join-Path $HomePath ".cache");        Label = "XDG cache" }
        [PSCustomObject]@{ EnvName = "XDG_DATA_HOME";       Path = (Join-Path $HomePath ".local\share");  Label = "XDG data" }
        [PSCustomObject]@{ EnvName = "XDG_STATE_HOME";      Path = (Join-Path $HomePath ".local\state");  Label = "XDG state" }
    )
}

# 現在の状態から、必要な作業の一覧を作る
# 戻り値: HomePath / IsNewHome / Directories / EnvVars / Actions / IsEmpty
function Get-DevbinHomePlan {
    param([string]$HomeRoot = "")

    if ([string]::IsNullOrWhiteSpace($HomeRoot)) {
        $HomeRoot = $script:DevbinDefaultHomeRoot
    }

    $currentHome = [Environment]::GetEnvironmentVariable("HOME", "User")
    $isNewHome = [string]::IsNullOrWhiteSpace($currentHome)
    $homePath = if ($isNewHome) { Join-Path $HomeRoot ([Environment]::UserName) } else { $currentHome }

    $directories = @()
    $envVars = @()
    $actions = @()

    if ($isNewHome) {
        foreach ($path in @($HomeRoot, $homePath)) {
            if (-not (Test-Path $path)) {
                $directories += $path
                $actions += "  - Create directory: $path"
            }
        }
        $envVars += [PSCustomObject]@{ Name = "HOME"; Value = $homePath }
        $actions += "  - Set HOME environment variable to: $homePath"
    }

    foreach ($entry in Get-DevbinHomeLayout -HomePath $homePath) {
        # 既に環境変数が設定されている項目は、利用者の設定として尊重する
        $currentValue = [Environment]::GetEnvironmentVariable($entry.EnvName, "User")
        if (-not [string]::IsNullOrWhiteSpace($currentValue)) {
            continue
        }

        if (-not (Test-Path $entry.Path)) {
            $directories += $entry.Path
            $actions += "  - Create $($entry.Label) directory: $($entry.Path)"
        }
        $envVars += [PSCustomObject]@{ Name = $entry.EnvName; Value = $entry.Path }
        $actions += "  - Set $($entry.EnvName) environment variable to: $($entry.Path)"
    }

    return [PSCustomObject]@{
        HomePath    = $homePath
        IsNewHome   = $isNewHome
        Directories = @($directories)
        EnvVars     = @($envVars)
        Actions     = @($actions)
        IsEmpty     = ($actions.Count -eq 0)
    }
}

# 作業一覧を適用する
# 戻り値: Success / Messages
function Invoke-DevbinHomePlan {
    param([PSCustomObject]$Plan)

    $messages = @()

    foreach ($path in $Plan.Directories) {
        try {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
            $messages += "Created directory: $path"
        } catch {
            return [PSCustomObject]@{
                Success  = $false
                Messages = @($messages + "Failed to create directory ${path}: $($_.Exception.Message)")
            }
        }
    }

    foreach ($envVar in $Plan.EnvVars) {
        try {
            [Environment]::SetEnvironmentVariable($envVar.Name, $envVar.Value, "User")
            $messages += "Set $($envVar.Name) to: $($envVar.Value)"
        } catch {
            return [PSCustomObject]@{
                Success  = $false
                Messages = @($messages + "Failed to set $($envVar.Name): $($_.Exception.Message)")
            }
        }
    }

    return [PSCustomObject]@{
        Success  = $true
        Messages = @($messages)
    }
}
