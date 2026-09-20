# HomeDirectory.ps1
# HOME および XDG ディレクトリの構成管理
#
# 新規作成と、既存 HOME に対する不足項目の補完を同一のレイアウト定義で処理します。

# HOME 未設定時はユーザー単位の data ディレクトリを使用します。

# HOME 配下に配置するディレクトリのレイアウト定義を取得
# 戻り値: EnvName (環境変数名)、Path (対象パス)、Label (表示名)、ShortNames (この保存先を使うコンポーネント) を持つオブジェクト配列
# ShortNames が空の項目は特定のコンポーネントに属さないため、Manage の開始時にまとめて設定します。
function Get-DevbinHomeLayout {
    param([string]$HomePath)

    return @(
        [PSCustomObject]@{ EnvName = "CONTINUE_GLOBAL_DIR"; Path = (Join-Path $HomePath "continue");      Label = "continue";   ShortNames = @() }
        [PSCustomObject]@{ EnvName = "XDG_CONFIG_HOME";     Path = (Join-Path $HomePath ".config");       Label = "XDG config"; ShortNames = @() }
        [PSCustomObject]@{ EnvName = "XDG_CACHE_HOME";      Path = (Join-Path $HomePath ".cache");        Label = "XDG cache";  ShortNames = @() }
        [PSCustomObject]@{ EnvName = "XDG_DATA_HOME";       Path = (Join-Path $HomePath ".local\share");  Label = "XDG data";   ShortNames = @() }
        [PSCustomObject]@{ EnvName = "XDG_STATE_HOME";      Path = (Join-Path $HomePath ".local\state");  Label = "XDG state";  ShortNames = @() }
        [PSCustomObject]@{ EnvName = "GH_CONFIG_DIR"; Path = (Join-Path $HomePath 'gh'); Label = 'GitHub CLI'; ShortNames = @('gh') }
        [PSCustomObject]@{ EnvName = "GLAB_CONFIG_DIR"; Path = (Join-Path $HomePath 'glab'); Label = 'GitLab CLI'; ShortNames = @('glab') }
        [PSCustomObject]@{ EnvName = "COPILOT_HOME"; Path = (Join-Path $HomePath 'copilot'); Label = 'Copilot CLI'; ShortNames = @('copilot') }
        [PSCustomObject]@{ EnvName = "COPILOT_CACHE_HOME"; Path = (Join-Path $HomePath 'copilot\cache'); Label = 'Copilot CLI cache'; ShortNames = @('copilot') }
        [PSCustomObject]@{ EnvName = "INKSCAPE_PROFILE_DIR"; Path = (Join-Path $HomePath 'inkscape'); Label = 'Inkscape'; ShortNames = @('inkscape') }
        [PSCustomObject]@{ EnvName = "DOTNET_CLI_HOME"; Path = (Join-Path $HomePath 'dotnet'); Label = '.NET CLI'; ShortNames = @('dotnet10sdk') }
        [PSCustomObject]@{ EnvName = "NUGET_PACKAGES"; Path = (Join-Path $HomePath 'nuget\packages'); Label = 'NuGet packages'; ShortNames = @('nuget', 'dotnet10sdk') }
        [PSCustomObject]@{ EnvName = "NUGET_HTTP_CACHE_PATH"; Path = (Join-Path $HomePath 'nuget\http-cache'); Label = 'NuGet HTTP cache'; ShortNames = @('nuget', 'dotnet10sdk') }
        [PSCustomObject]@{ EnvName = "NUGET_PLUGINS_CACHE_PATH"; Path = (Join-Path $HomePath 'nuget\plugins-cache'); Label = 'NuGet plugins cache'; ShortNames = @('nuget', 'dotnet10sdk') }
        [PSCustomObject]@{ EnvName = "NPM_CONFIG_CACHE"; Path = (Join-Path $HomePath 'npm\cache'); Label = 'npm cache'; ShortNames = @('nodejs') }
        [PSCustomObject]@{ EnvName = "NPM_CONFIG_USERCONFIG"; Path = (Join-Path $HomePath 'npm\npmrc'); Label = 'npm config'; IsFile = $true; ShortNames = @('nodejs') }
        [PSCustomObject]@{ EnvName = "PUPPETEER_CACHE_DIR"; Path = (Join-Path $HomePath 'puppeteer\cache'); Label = 'Puppeteer cache'; ShortNames = @('puppeteer', 'marp-cli', 'mermaid-cli') }
        [PSCustomObject]@{ EnvName = "PIP_CACHE_DIR"; Path = (Join-Path $HomePath 'pip\cache'); Label = 'pip cache'; ShortNames = @('python') }
        [PSCustomObject]@{ EnvName = "PIP_CONFIG_FILE"; Path = (Join-Path $HomePath 'pip\pip.ini'); Label = 'pip config'; IsFile = $true; ShortNames = @('python') }
        [PSCustomObject]@{ EnvName = "PYTHONUSERBASE"; Path = (Join-Path $HomePath 'python'); Label = 'Python user base'; ShortNames = @('python') }
    )
}

# 指定コンポーネントが使用するユーザー保存先の定義を取得
function Get-DevbinComponentStorageLayout {
    param([string]$ShortName)

    if ([string]::IsNullOrWhiteSpace($ShortName)) {
        return @()
    }

    return @(Get-DevbinHomeLayout -HomePath (Get-DevbinDataDirectory) |
        Where-Object { $_.ShortNames -contains $ShortName })
}

# コンポーネントの導入時に、保存先ディレクトリを作成し環境変数を設定
# 既に値を持つ環境変数は利用者の設定として尊重し、変更しません。
# 戻り値: 設定した環境変数名の配列
function Initialize-DevbinComponentStorage {
    param([string]$ShortName)

    # コンポーネント固有の保存先が無くても、共通の data は用意します。
    New-Item -ItemType Directory -Path (Get-DevbinDataDirectory) -Force -ErrorAction Stop | Out-Null

    $applied = @()
    foreach ($entry in Get-DevbinComponentStorageLayout -ShortName $ShortName) {
        $directory = if ($entry.IsFile) { Split-Path -Parent $entry.Path } else { $entry.Path }
        New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop | Out-Null

        $current = Get-DevbinUserEnvironmentValue -Name $entry.EnvName
        if (-not [string]::IsNullOrWhiteSpace($current)) {
            continue
        }
        Set-DevbinUserEnvironmentValue -Name $entry.EnvName -Value $entry.Path
        $applied += $entry.EnvName
    }

    return @($applied)
}

# コンポーネントのアンインストール時に、devbin-win が設定した環境変数を解除
# 利用者が別の値へ変更した項目と、まだ導入済みの他コンポーネントが使う項目は残します。
# 戻り値: 解除した環境変数名の配列
function Remove-DevbinComponentStorage {
    param(
        [string]$ShortName,
        [string[]]$InstalledShortNames = @()
    )

    $removed = @()
    foreach ($entry in Get-DevbinComponentStorageLayout -ShortName $ShortName) {
        $sharedWith = @($entry.ShortNames | Where-Object { $_ -ne $ShortName -and $InstalledShortNames -contains $_ })
        if ($sharedWith.Count -gt 0) {
            continue
        }

        $current = Get-DevbinUserEnvironmentValue -Name $entry.EnvName
        if ([string]::IsNullOrWhiteSpace($current)) {
            continue
        }
        if (-not [string]::Equals($current.TrimEnd('\'), $entry.Path.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        Set-DevbinUserEnvironmentValue -Name $entry.EnvName -Value $null
        $removed += $entry.EnvName
    }

    return @($removed)
}

# HOME と、特定のコンポーネントに属さない共通項目 (XDG など) の実行計画を生成
# 戻り値: HomePath / IsNewHome / Directories / EnvVars / Actions / IsEmpty を含む計画オブジェクト
function Get-DevbinHomePlan {
    param([string]$HomeRoot = "")

    $dataPath = Get-DevbinDataDirectory
    $defaultHome = if ([string]::IsNullOrWhiteSpace($HomeRoot)) { $dataPath } else { Join-Path $HomeRoot ([Environment]::UserName) }

    $currentHome = Get-DevbinUserEnvironmentValue -Name "HOME"
    $isNewHome = [string]::IsNullOrWhiteSpace($currentHome)
    $homePath = if ($isNewHome) { $defaultHome } else { $currentHome }

    $directories = @()
    $envVars = @()
    $actions = @()

    if ($isNewHome) {
        foreach ($path in @($homePath)) {
            if (-not (Test-Path $path)) {
                $directories += $path
                $actions += "  - Create directory: $path"
            }
        }
        $envVars += [PSCustomObject]@{ Name = "HOME"; Value = $homePath }
        $actions += "  - Set HOME environment variable to: $homePath"
    }

    # コンポーネントに属する項目は、そのコンポーネントの導入時に設定します。
    $commonEntries = @(Get-DevbinHomeLayout -HomePath $dataPath | Where-Object { @($_.ShortNames).Count -eq 0 })
    foreach ($entry in $commonEntries) {
        # 既に環境変数が設定されている項目は、既存のユーザー設定を優先してスキップ
        $currentValue = Get-DevbinUserEnvironmentValue -Name $entry.EnvName
        if (-not [string]::IsNullOrWhiteSpace($currentValue)) {
            continue
        }

        $directory = if ($entry.IsFile) { Split-Path -Parent $entry.Path } else { $entry.Path }
        if (-not (Test-Path $directory)) {
            $directories += $directory
            $actions += "  - Create $($entry.Label) directory: $directory"
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

# 生成された実行計画を適用
# 戻り値: Success (ブール値) / Messages (メッセージ配列) を含む結果オブジェクト
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
            Set-DevbinUserEnvironmentValue -Name $envVar.Name -Value $envVar.Value
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
