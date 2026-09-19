# ComponentEnvironment.ps1
# コンポーネントに関連する環境変数の設定および削除

# Microsoft Edge の実行ファイルパスを、PATH・標準インストール先・App Paths レジストリから解決します。
function Resolve-EdgeExecutable {
    $candidates = @()
    $command = Get-Command msedge.exe -ErrorAction SilentlyContinue
    if ($command -and $command.Source) {
        $candidates += $command.Source
    }

    $programFiles = [Environment]::GetEnvironmentVariable("ProgramFiles")
    $programFilesX86 = [Environment]::GetEnvironmentVariable("ProgramFiles(x86)")
    $localAppData = [Environment]::GetEnvironmentVariable("LOCALAPPDATA")
    foreach ($basePath in @($programFiles, $programFilesX86, $localAppData)) {
        if (-not [string]::IsNullOrWhiteSpace($basePath)) {
            $candidates += (Join-Path $basePath "Microsoft\Edge\Application\msedge.exe")
        }
    }

    # 組織向けまたはユーザー単位のインストール環境では、App Paths レジストリにのみ登録されている場合があります。
    $registryPaths = @(
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe"
    )
    foreach ($registryPath in $registryPaths) {
        $registryKey = Get-Item -LiteralPath $registryPath -ErrorAction SilentlyContinue
        if (-not $registryKey) {
            continue
        }
        $registeredPath = [string]$registryKey.GetValue("")
        if (-not [string]::IsNullOrWhiteSpace($registeredPath)) {
            $candidates += $registeredPath
        }
    }

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if (Test-Path $candidate -PathType Leaf) {
            return (Resolve-Path $candidate).Path
        }
    }

    return $null
}

# 既存の環境変数から、実在する実行ファイルパスを取得します。
function Get-ValidEnvironmentValue {
    param([string]$Name)

    $userValue = [Environment]::GetEnvironmentVariable($Name, "User")
    if (-not [string]::IsNullOrWhiteSpace($userValue) -and (Test-Path $userValue -PathType Leaf)) {
        return $userValue
    }

    $processValue = [Environment]::GetEnvironmentVariable($Name, "Process")
    if (-not [string]::IsNullOrWhiteSpace($processValue) -and (Test-Path $processValue -PathType Leaf)) {
        return $processValue
    }

    return $null
}

# EnvVars および EnvVarIsLiteral の定義に基づき、適用する環境変数の値を算出します。
# 設定処理と削除処理で整合性を保つため、値の計算ロジックを本関数に集約します。
function Get-ComponentEnvVarValues {
    param(
        [string]$InstallDir,
        [hashtable]$PackageConfig
    )

    $envVars = if ($PackageConfig.ContainsKey("EnvVars")) { $PackageConfig.EnvVars } else { @{} }
    $literalKeys = if ($PackageConfig.ContainsKey("EnvVarIsLiteral")) { @($PackageConfig.EnvVarIsLiteral) } else { @() }

    $values = @{}
    foreach ($key in $envVars.Keys) {
        $rawValue = $envVars[$key]
        $values[$key] = if ($literalKeys -contains $key) {
            $rawValue
        } elseif ($rawValue -eq "") {
            $InstallDir
        } else {
            Join-Path $InstallDir $rawValue
        }
    }

    return $values
}

# パッケージ定義において Microsoft Edge が必要とされているかを判定します。
function Test-ComponentUsesEdge {
    param([hashtable]$PackageConfig)

    return ($PackageConfig.ContainsKey("Browser") -and [string]$PackageConfig.Browser -eq "Edge")
}

# EnvVars / EnvVarIsLiteral および Browser 設定に基づいて環境変数を設定します。
function Set-ComponentEnvVars {
    param(
        [string]$InstallDir,
        [hashtable]$PackageConfig
    )

    $values = Get-ComponentEnvVarValues -InstallDir $InstallDir -PackageConfig $PackageConfig
    $appliedVars = @{}

    foreach ($key in $values.Keys) {
        $value = $values[$key]
        [Environment]::SetEnvironmentVariable($key, $value, "User")
        Write-Host "    Set $key=$value"
        $appliedVars[$key] = $value
    }

    if (Test-ComponentUsesEdge -PackageConfig $PackageConfig) {
        $edgePath = Resolve-EdgeExecutable
        $browserPath = Get-ValidEnvironmentValue -Name "BROWSER_PATH"
        $puppeteerPath = Get-ValidEnvironmentValue -Name "PUPPETEER_EXECUTABLE_PATH"

        if (-not $browserPath) { $browserPath = if ($edgePath) { $edgePath } else { $puppeteerPath } }
        if (-not $puppeteerPath) { $puppeteerPath = if ($edgePath) { $edgePath } else { $browserPath } }
        if (-not $browserPath -or -not $puppeteerPath) {
            throw "Microsoft Edge was not found. Install Edge or set a valid BROWSER_PATH/PUPPETEER_EXECUTABLE_PATH before installing $($PackageConfig.ShortName)."
        }

        [Environment]::SetEnvironmentVariable("BROWSER_PATH", $browserPath, "User")
        [Environment]::SetEnvironmentVariable("PUPPETEER_EXECUTABLE_PATH", $puppeteerPath, "User")
        Write-Host "    Set BROWSER_PATH=$browserPath"
        Write-Host "    Set PUPPETEER_EXECUTABLE_PATH=$puppeteerPath"
        $appliedVars["BROWSER_PATH"] = $browserPath
        $appliedVars["PUPPETEER_EXECUTABLE_PATH"] = $puppeteerPath
    }

    return $appliedVars
}

# コンポーネントに関連する環境変数を削除します。
function Remove-ComponentEnvVars {
    param(
        [string]$InstallDir,
        [hashtable]$PackageConfig,
        [hashtable]$AppliedEnvVars = @{},
        [string[]]$SkipKeys = @()
    )

    $expectedValues = Get-ComponentEnvVarValues -InstallDir $InstallDir -PackageConfig $PackageConfig

    if (Test-ComponentUsesEdge -PackageConfig $PackageConfig) {
        foreach ($key in @("BROWSER_PATH", "PUPPETEER_EXECUTABLE_PATH")) {
            if ($AppliedEnvVars.ContainsKey($key)) {
                $expectedValues[$key] = [string]$AppliedEnvVars[$key]
            }
        }
    }

    foreach ($key in $expectedValues.Keys) {
        if ($SkipKeys -contains $key) {
            continue
        }
        $expectedValue = $expectedValues[$key]
        $currentValue = [Environment]::GetEnvironmentVariable($key, "User")
        if ($currentValue -eq $expectedValue) {
            [Environment]::SetEnvironmentVariable($key, $null, "User")
            Write-Host "    Removed $key"
        }
    }
}
