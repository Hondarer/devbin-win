# ComponentEnvironment.ps1
# コンポーネントの環境変数を設定・削除する

# Edge 実行ファイルを PATH、標準インストール先、App Paths から解決する
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

    # Enterprise/per-user installation may be registered only through App Paths.
    $registryPaths = @(
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe"
    )
    foreach ($registryPath in $registryPaths) {
        try {
            $registryKey = Get-Item -LiteralPath $registryPath -ErrorAction Stop
            $registeredPath = [string]$registryKey.GetValue("")
            if (-not [string]::IsNullOrWhiteSpace($registeredPath)) {
                $candidates += $registeredPath
            }
        } catch {
            # Registry access or key absence is not fatal; continue with other candidates.
        }
    }

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if (Test-Path $candidate -PathType Leaf) {
            return (Resolve-Path $candidate).Path
        }
    }

    return $null
}

# 既存の環境変数から有効な実行ファイルパスを取得する
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

# EnvVars と EnvVarIsLiteral から、実際に設定する値を求める
# 設定側と削除側が同じ値を見るよう、計算はここに一本化する
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

# パッケージ定義が Edge を必要とするかを判定する
function Test-ComponentUsesEdge {
    param([hashtable]$PackageConfig)

    return ($PackageConfig.ContainsKey("Browser") -and [string]$PackageConfig.Browser -eq "Edge")
}

# 環境変数を EnvVars/EnvVarIsLiteral と Browser 設定に基づいて設定する
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
        Write-Host "  Set $key=$value"
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
        Write-Host "  Set BROWSER_PATH=$browserPath"
        Write-Host "  Set PUPPETEER_EXECUTABLE_PATH=$puppeteerPath"
        $appliedVars["BROWSER_PATH"] = $browserPath
        $appliedVars["PUPPETEER_EXECUTABLE_PATH"] = $puppeteerPath
    }

    return $appliedVars
}

# 環境変数を削除する
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
            Write-Host "  Removed $key"
        }
    }
}
