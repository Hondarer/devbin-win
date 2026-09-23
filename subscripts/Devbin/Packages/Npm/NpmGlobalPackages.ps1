# NpmGlobalPackages.ps1
# npm install -g / npm uninstall -g の実行と、npm のグローバル ツリーの参照
#
# devbin の bin は npm のグローバル prefix そのものです。
# 導入と削除は npm に実行させ、状態は bin\node_modules の実物から読み取ります。
# npm はグローバル ツリーにロックファイルを持たず、最上位のパッケージをそれぞれ独立した導入として扱います。
# このため、利用者が npm -g で追加、削除、更新した結果と、Manage-Bin の操作結果は同じ状態になります。
# see: https://docs.npmjs.com/cli/v11/configuring-npm/folders#global-installation

function Write-NpmNativeOutput {
    param([object[]]$Output)

    foreach ($item in @($Output)) {
        $text = [string]$item
        if ([string]::IsNullOrWhiteSpace($text)) {
            continue
        }

        # 標準エラー出力 (2>&1) の ErrorRecord によるコンソール赤字化を防ぎ、テキストのみを手順の詳細として字下げして出力します。
        Write-Host "    $text"
    }
}

# npm を実行し、出力を字下げして表示したうえで終了コードを返します。
function Invoke-NpmCli {
    param(
        [Parameter(Mandatory)][string]$NpmCommandPath,
        [Parameter(Mandatory)][string[]]$Arguments
    )

    $output = @(& $NpmCommandPath @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    Write-NpmNativeOutput -Output $output
    if ($null -eq $exitCode) {
        return 0
    }
    return [int]$exitCode
}

# グローバル操作に共通の引数です。監査、寄付の案内、更新の通知は、オフライン操作の妨げになるため無効化します。
function Get-NpmGlobalArguments {
    param(
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory)][string]$Prefix
    )

    return @($Command, "-g", "--prefix", $Prefix, "--no-audit", "--no-fund", "--update-notifier=false")
}

# 導入時スクリプトの扱いを指定する引数です。
# 既定ではすべて止めます。NpmIgnoreScripts = $false のコンポーネントは、要求したパッケージのスクリプトだけを許可します。
# npm 11 は許可されていない導入時スクリプトを警告付きで実行し、strict-allow-scripts では導入を失敗させます。
# allow-scripts を知らない古い npm は、未知の設定として警告するだけで導入を続けます。
# see: https://docs.npmjs.com/cli/v11/using-npm/config#allow-scripts
function Get-NpmScriptArguments {
    param([Parameter(Mandatory)][hashtable]$PackageConfig)

    $ignoreScripts = if ($PackageConfig.ContainsKey("NpmIgnoreScripts")) { [bool]$PackageConfig.NpmIgnoreScripts } else { $true }
    if ($ignoreScripts) {
        return @("--ignore-scripts")
    }
    return @("--allow-scripts=" + (@(Get-NpmRequestedPackageNames -PackageConfig $PackageConfig) -join ","))
}

function Get-NpmGlobalPackageDirectory {
    param(
        [Parameter(Mandatory)][string]$BinDir,
        [Parameter(Mandatory)][string]$PackageName
    )

    return (Join-Path (Join-Path $BinDir "node_modules") ($PackageName -replace '/', '\'))
}

# グローバル ツリーに導入されているパッケージの版を返します。導入されていなければ空文字を返します。
function Get-NpmGlobalPackageVersion {
    param(
        [Parameter(Mandatory)][string]$BinDir,
        [Parameter(Mandatory)][string]$PackageName
    )

    $manifestPath = Join-Path (Get-NpmGlobalPackageDirectory -BinDir $BinDir -PackageName $PackageName) "package.json"
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        return ""
    }
    try {
        $json = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if (@($json.PSObject.Properties.Name) -contains "version") {
            return [string]$json.version
        }
    } catch {
        # 壊れた package.json は未導入として扱います。
    }
    return ""
}

# コンポーネントが要求したパッケージのうち、グローバル ツリーに存在するもののディレクトリを bin からの相対パスで返します。
# マニフェストへ記録し、他のコンポーネントの削除処理が node_modules を巻き込まないようにするために使います。
function Get-NpmComponentOwnedPaths {
    param(
        [Parameter(Mandatory)][string]$BinDir,
        [Parameter(Mandatory)][hashtable]$PackageConfig
    )

    $paths = @()
    foreach ($name in @(Get-NpmRequestedPackageNames -PackageConfig $PackageConfig)) {
        if (-not [string]::IsNullOrWhiteSpace((Get-NpmGlobalPackageVersion -BinDir $BinDir -PackageName $name))) {
            $paths += Join-Path "node_modules" ($name -replace '/', '\')
        }
    }
    return $paths
}

# 保存済みの npm キャッシュから、npm install -g --offline でコンポーネントを導入します。
function Invoke-NpmInstallFromCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$NpmCommandPath,

        [Parameter(Mandatory)]
        [string]$BinDir,

        [Parameter(Mandatory)]
        [string]$PackagesDir,

        [Parameter(Mandatory)]
        [hashtable]$PackageConfig
    )

    $status = Get-NpmCacheStatus -PackageConfig $PackageConfig -PackagesDir $PackagesDir
    if (-not $status.IsValid) {
        Write-Host "    Error: npm cache is incomplete for '$($PackageConfig.ShortName)'" -ForegroundColor Red
        if ($status.Missing.Count -gt 0) {
            Write-Host "      Missing: $($status.Missing -join ', ')" -ForegroundColor Red
        }
        if ($status.Invalid.Count -gt 0) {
            Write-Host "      Invalid: $($status.Invalid -join ', ')" -ForegroundColor Red
        }
        return $false
    }

    $robocopy = Get-Command robocopy.exe -ErrorAction SilentlyContinue
    if (-not $robocopy) {
        Write-Host "    Error: robocopy.exe is required to prepare the npm cache" -ForegroundColor Red
        return $false
    }

    # npm はオフラインでもキャッシュへ索引やログを書き込むため、packages のキャッシュは一時ディレクトリへ複製して使います。
    $workDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("devbin-npm-install-" + [guid]::NewGuid().ToString("N"))
    $tempCacheDirectory = Join-Path $workDirectory "cache"
    $logsDirectory = Join-Path $workDirectory "logs"
    $previousSkip = $env:PUPPETEER_SKIP_DOWNLOAD
    try {
        New-Item -ItemType Directory -Path $logsDirectory -Force | Out-Null
        & $robocopy.Source $status.ContentDirectory $tempCacheDirectory '/E' '/NFL' '/NDL' '/NJH' '/NJS' '/NP' | Out-Null
        if ($LASTEXITCODE -gt 7) {
            Write-Host "    Error: failed to copy the npm cache (robocopy exit code: $LASTEXITCODE)" -ForegroundColor Red
            return $false
        }

        # 導入時のブラウザー バイナリの自動ダウンロードを抑止します (Microsoft Edge を使用)。
        $env:PUPPETEER_SKIP_DOWNLOAD = "1"
        $arguments = @(Get-NpmGlobalArguments -Command "install" -Prefix $BinDir) + @("--offline", "--cache", $tempCacheDirectory, "--logs-dir", $logsDirectory)
        $arguments += @(Get-NpmScriptArguments -PackageConfig $PackageConfig)
        $arguments += @(Get-NpmPackageSpecs -PackageConfig $PackageConfig)

        Write-Host "    Installing $($PackageConfig.ShortName) with npm install -g from the offline npm cache..."
        $exitCode = Invoke-NpmCli -NpmCommandPath $NpmCommandPath -Arguments $arguments
        if ($exitCode -ne 0) {
            Write-Host "    Error: npm install -g failed for '$($PackageConfig.ShortName)' (exit code: $exitCode)" -ForegroundColor Red
            return $false
        }

        $rootPackage = [string]$PackageConfig.NpmPackage
        $expectedVersion = if ($PackageConfig.ContainsKey("Version")) { [string]$PackageConfig.Version } else { "" }
        $installedVersion = Get-NpmGlobalPackageVersion -BinDir $BinDir -PackageName $rootPackage
        if ([string]::IsNullOrWhiteSpace($installedVersion)) {
            Write-Host "    Error: installed npm package was not found: $rootPackage" -ForegroundColor Red
            return $false
        }
        if (-not [string]::IsNullOrWhiteSpace($expectedVersion) -and $installedVersion -ne $expectedVersion) {
            Write-Host "    Error: installed npm version mismatch for '$rootPackage': expected $expectedVersion, got $installedVersion" -ForegroundColor Red
            return $false
        }

        Write-Host "    $($PackageConfig.Name) installation completed."
        return $true
    } catch {
        Write-Host "    Error: Failed to install $($PackageConfig.Name): $($_.Exception.Message)" -ForegroundColor Red
        return $false
    } finally {
        if ($null -eq $previousSkip) {
            Remove-Item Env:\PUPPETEER_SKIP_DOWNLOAD -ErrorAction SilentlyContinue
        } else {
            $env:PUPPETEER_SKIP_DOWNLOAD = $previousSkip
        }
        Remove-Item -LiteralPath $workDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# パッケージの package.json の bin から、npm が prefix 直下に作るコマンド名を返します。
function Get-NpmPackageBinNames {
    param([Parameter(Mandatory)][string]$PackageDirectory)

    $manifestPath = Join-Path $PackageDirectory "package.json"
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        return @()
    }
    try {
        $json = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        return @()
    }
    $properties = @($json.PSObject.Properties.Name)
    if ($properties -notcontains "bin" -or $null -eq $json.bin) {
        return @()
    }
    if ($json.bin -is [string]) {
        # bin が文字列の場合、コマンド名はスコープを除いたパッケージ名です。
        return @(([string]$json.name -split '/')[-1])
    }
    return @($json.bin.PSObject.Properties.Name)
}

# npm uninstall -g と同じ結果になるよう、パッケージのディレクトリと、そのパッケージを指す shim を削除します。
# npm を実行できない場合 (Node.js が先に削除された場合など) に使います。
function Remove-NpmGlobalPackageFiles {
    param(
        [Parameter(Mandatory)][string]$BinDir,
        [Parameter(Mandatory)][string]$PackageName
    )

    $packageDirectory = Get-NpmGlobalPackageDirectory -BinDir $BinDir -PackageName $PackageName
    if (-not (Test-Path -LiteralPath $packageDirectory -PathType Container)) {
        return
    }

    $packageReferences = @(
        "node_modules\" + ($PackageName -replace '/', '\') + "\"
        "node_modules/" + $PackageName + "/"
    )
    foreach ($binName in @(Get-NpmPackageBinNames -PackageDirectory $packageDirectory)) {
        foreach ($shimName in @($binName, "$binName.cmd", "$binName.ps1")) {
            $shimPath = Join-Path $BinDir $shimName
            if (-not (Test-Path -LiteralPath $shimPath -PathType Leaf)) {
                continue
            }
            # 同名のコマンドを別のパッケージが提供している場合は残します。
            $content = [IO.File]::ReadAllText($shimPath)
            if (@($packageReferences | Where-Object { $content.IndexOf($_, [StringComparison]::OrdinalIgnoreCase) -ge 0 }).Count -gt 0) {
                Remove-Item -LiteralPath $shimPath -Force
            }
        }
    }

    Remove-Item -LiteralPath $packageDirectory -Recurse -Force
    $scopeDirectory = Split-Path $packageDirectory -Parent
    if ((Split-Path $scopeDirectory -Leaf).StartsWith("@") -and
        -not [System.IO.Directory]::EnumerateFileSystemEntries($scopeDirectory).GetEnumerator().MoveNext()) {
        Remove-Item -LiteralPath $scopeDirectory -Force
    }
}

# グローバル ツリーからパッケージを削除します。npm uninstall -g を優先し、npm を実行できない場合はファイルを直接削除します。
function Uninstall-NpmGlobalPackages {
    param(
        [string]$NpmCommandPath = "",
        [Parameter(Mandatory)][string]$BinDir,
        [Parameter(Mandatory)][string[]]$PackageNames
    )

    $installed = @($PackageNames | Where-Object {
        -not [string]::IsNullOrWhiteSpace((Get-NpmGlobalPackageVersion -BinDir $BinDir -PackageName $_))
    })
    if ($installed.Count -eq 0) {
        return $true
    }

    if (-not [string]::IsNullOrWhiteSpace($NpmCommandPath) -and (Test-Path -LiteralPath $NpmCommandPath -PathType Leaf)) {
        Write-Host "  npm uninstall -g を実行中: $($installed -join ', ')"
        $exitCode = Invoke-NpmCli -NpmCommandPath $NpmCommandPath -Arguments (@(Get-NpmGlobalArguments -Command "uninstall" -Prefix $BinDir) + $installed)
        if ($exitCode -ne 0) {
            Write-Host "    Warning: npm uninstall -g exited with code $exitCode" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  npm を実行できないため、パッケージのファイルを直接削除します: $($installed -join ', ')" -ForegroundColor Yellow
    }

    $result = $true
    foreach ($name in $installed) {
        if ([string]::IsNullOrWhiteSpace((Get-NpmGlobalPackageVersion -BinDir $BinDir -PackageName $name))) {
            continue
        }
        try {
            Remove-NpmGlobalPackageFiles -BinDir $BinDir -PackageName $name
        } catch {
            Write-Host "    Warning: Failed to remove '$name': $($_.Exception.Message)" -ForegroundColor Yellow
            $result = $false
        }
    }
    return $result
}
