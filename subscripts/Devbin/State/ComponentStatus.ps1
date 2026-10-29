# ComponentStatus.ps1
# バージョン比較ロジックおよびコンポーネントの総合状態判定

# バージョン文字列を比較用トークン配列へ分割
function Get-VersionTokens {
    param([string]$Version)

    if ([string]::IsNullOrWhiteSpace($Version)) {
        return $null
    }

    $tokens = [regex]::Split($Version.Trim(), '[.-]') | Where-Object { $_ -ne "" }
    if (-not $tokens -or $tokens.Count -eq 0) {
        return $null
    }

    return @($tokens)
}

# 2 つのバージョン文字列をセマンティックに比較
# 戻り値: 1 (左辺が新しい)、0 (等しい)、-1 (右辺が新しい)、$null (比較不能)
function Compare-PackageVersion {
    param(
        [string]$LeftVersion,
        [string]$RightVersion
    )

    $leftTokens = Get-VersionTokens -Version $LeftVersion
    $rightTokens = Get-VersionTokens -Version $RightVersion

    if (-not $leftTokens -or -not $rightTokens) {
        return $null
    }

    $maxCount = [Math]::Max($leftTokens.Count, $rightTokens.Count)
    for ($i = 0; $i -lt $maxCount; $i++) {
        $leftExists = $i -lt $leftTokens.Count
        $rightExists = $i -lt $rightTokens.Count

        if (-not $leftExists -and -not $rightExists) {
            continue
        }

        if (-not $leftExists) {
            $rightToken = $rightTokens[$i]
            if ($rightToken -match '^\d+$') {
                if ([int64]$rightToken -eq 0) {
                    continue
                }
                return -1
            }
            return $null
        }

        if (-not $rightExists) {
            $leftToken = $leftTokens[$i]
            if ($leftToken -match '^\d+$') {
                if ([int64]$leftToken -eq 0) {
                    continue
                }
                return 1
            }
            return $null
        }

        $leftToken = $leftTokens[$i]
        $rightToken = $rightTokens[$i]
        $leftIsNumeric = $leftToken -match '^\d+$'
        $rightIsNumeric = $rightToken -match '^\d+$'

        if ($leftIsNumeric -and $rightIsNumeric) {
            $leftNumber = [int64]$leftToken
            $rightNumber = [int64]$rightToken
            if ($leftNumber -gt $rightNumber) { return 1 }
            if ($leftNumber -lt $rightNumber) { return -1 }
            continue
        }

        if ($leftIsNumeric -ne $rightIsNumeric) {
            return $null
        }

        $cmp = [string]::Compare($leftToken, $rightToken, $true)
        if ($cmp -gt 0) { return 1 }
        if ($cmp -lt 0) { return -1 }
    }

    return 0
}

# パッケージ定義のバージョンがインストール済みバージョンより新しいかを判定
function Test-ComponentUpdateable {
    param(
        [hashtable]$Manifest,
        [hashtable]$PackageConfig,
        [string]$PackagesDir = ""
    )

    $shortName = $PackageConfig.ShortName
    if (-not $Manifest.components.ContainsKey($shortName)) {
        return $false
    }

    # 自己更新するコンポーネントは、マニフェストの記録版と実物が一致しないため更新判定の対象外とします。
    # 定義の版で入れ直す場合は、利用者が明示的に再インストールを選択します。
    if ($PackageConfig.ContainsKey("SelfUpdating") -and [bool]$PackageConfig.SelfUpdating) {
        return $false
    }

    $installedComponent = $Manifest.components[$shortName]
    $installedVersion = if ($installedComponent.ContainsKey("version")) { [string]$installedComponent.version } else { "" }
    $packageVersion = Resolve-PackageVersion -PackageConfig $PackageConfig -PackagesDir $PackagesDir

    if ([string]::IsNullOrWhiteSpace($packageVersion)) {
        return $false
    }

    $comparison = Compare-PackageVersion -LeftVersion $packageVersion -RightVersion $installedVersion
    return $comparison -eq 1
}

# 文字列から版を抜き出します (戻り値: 版の文字列。見つからない場合は "")。
# Pattern にキャプチャ グループがある場合は、値のあるグループを "." で連結します。
function Get-VersionFromText {
    param(
        [string]$Text,
        [string]$Pattern = ""
    )

    if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
    if ([string]::IsNullOrWhiteSpace($Pattern)) { $Pattern = '\d+(?:\.\d+)+' }

    $match = [regex]::Match($Text, $Pattern)
    if (-not $match.Success) { return "" }
    if ($match.Groups.Count -le 1) { return $match.Value }

    $parts = @()
    for ($i = 1; $i -lt $match.Groups.Count; $i++) {
        if ($match.Groups[$i].Success -and $match.Groups[$i].Value) { $parts += $match.Groups[$i].Value }
    }
    return ($parts -join ".")
}

# フォント ファイルの name テーブルから版の文字列 (nameID 5) を読み取ります (戻り値: 版の文字列。読み取れない場合は "")。
# エクスプローラーのプロパティに表示される「バージョン」と同じ値です。
function Get-FontFileVersionText {
    param([string]$Path)

    $stream = $null
    try {
        $stream = [System.IO.File]::OpenRead($Path)
        $reader = New-Object System.IO.BinaryReader($stream)
        $readUInt16 = { $b = $reader.ReadBytes(2); [int]$b[0] * 256 + $b[1] }
        $readUInt32 = { $b = $reader.ReadBytes(4); (([long]$b[0] * 256 + $b[1]) * 256 + $b[2]) * 256 + $b[3] }

        # フォント コレクション (.ttc) は、先頭のフォントを読みます。
        $fontOffset = 0
        if ([System.Text.Encoding]::ASCII.GetString($reader.ReadBytes(4)) -eq "ttcf") {
            $stream.Position = 12
            $fontOffset = & $readUInt32
        }

        $stream.Position = $fontOffset + 4
        $tableCount = & $readUInt16
        $stream.Position = $fontOffset + 12
        $nameOffset = -1
        for ($i = 0; $i -lt $tableCount; $i++) {
            $tag = [System.Text.Encoding]::ASCII.GetString($reader.ReadBytes(4))
            $null = & $readUInt32
            $offset = & $readUInt32
            $null = & $readUInt32
            if ($tag -eq "name") { $nameOffset = $offset; break }
        }
        if ($nameOffset -lt 0) { return "" }

        $stream.Position = $nameOffset + 2
        $recordCount = & $readUInt16
        $stringOffset = & $readUInt16
        $fallback = ""
        for ($i = 0; $i -lt $recordCount; $i++) {
            $platformId = & $readUInt16
            $null = & $readUInt16
            $languageId = & $readUInt16
            $nameId = & $readUInt16
            $length = & $readUInt16
            $offset = & $readUInt16
            if ($nameId -ne 5) { continue }

            $recordEnd = $stream.Position
            $stream.Position = $nameOffset + $stringOffset + $offset
            $bytes = $reader.ReadBytes($length)
            $stream.Position = $recordEnd
            # Windows (3) と Unicode (0) は UTF-16 BE、Macintosh (1) は 1 バイト文字で格納されています。
            $encoding = if ($platformId -eq 1) { [System.Text.Encoding]::ASCII } else { [System.Text.Encoding]::BigEndianUnicode }
            $text = $encoding.GetString($bytes)
            if ($platformId -eq 3 -and $languageId -eq 0x409) { return $text }
            if (-not $fallback) { $fallback = $text }
        }
        return $fallback
    } catch {
        return ""
    } finally {
        if ($stream) { $stream.Dispose() }
    }
}

# 実行ファイルまたはフォント ファイルから版の読み取りを開始します。
# ファイル内の版情報で読み取れた場合は Version に結果を格納し、プロセスを起動した場合は Process に格納します。
# 複数の読み取りを並列に進めるため、プロセスの終了は Wait-VersionProbe で待ちます。
function Start-VersionProbe {
    param(
        [string]$Path,
        [string[]]$Arguments = @(),
        [string]$Pattern = ""
    )

    $probe = @{ Version = ""; Process = $null; Pattern = $Pattern; StdoutTask = $null; StderrTask = $null }
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $probe
    }

    if ([System.IO.Path]::GetExtension($Path) -in @(".ttf", ".otf", ".ttc")) {
        $probe.Version = Get-VersionFromText -Text (Get-FontFileVersionText -Path $Path) -Pattern $Pattern
        return $probe
    }

    $info = (Get-Item -LiteralPath $Path).VersionInfo
    foreach ($candidate in @($info.ProductVersion, $info.FileVersion)) {
        $version = Get-VersionFromText -Text ([string]$candidate) -Pattern $Pattern
        if ($version) {
            $probe.Version = $version
            return $probe
        }
    }

    if (-not $Arguments -or $Arguments.Count -eq 0) {
        return $probe
    }

    try {
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = $Path
        $startInfo.Arguments = ($Arguments -join " ")
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardInput = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $process = [System.Diagnostics.Process]::Start($startInfo)
        # 標準入力からプロンプトを読むツールが入力待ちにならないよう、すぐに閉じます。
        $process.StandardInput.Close()
        $probe.StdoutTask = $process.StandardOutput.ReadToEndAsync()
        $probe.StderrTask = $process.StandardError.ReadToEndAsync()
        $probe.Process = $process
    } catch {
        # 実行できない場合は版不明として扱います。
    }
    return $probe
}

# Start-VersionProbe で起動したプロセスの終了を待ち、出力から版を抜き出します (戻り値: 版の文字列。読み取れない場合は "")。
# 期限 (UTC) を過ぎても終了しないプロセスは強制終了します。
function Wait-VersionProbe {
    param(
        [hashtable]$Probe,
        [datetime]$DeadlineUtc
    )

    if ($null -eq $Probe) { return "" }
    $process = $Probe.Process
    if ($null -eq $process) { return [string]$Probe.Version }

    try {
        $remaining = [int][Math]::Max(0, ($DeadlineUtc - [datetime]::UtcNow).TotalMilliseconds)
        if (-not $process.WaitForExit($remaining)) {
            try { $process.Kill(); $null = $process.WaitForExit(1000) } catch { }
            return ""
        }
        $output = $Probe.StdoutTask.Result + "`n" + $Probe.StderrTask.Result
        return (Get-VersionFromText -Text $output -Pattern $Probe.Pattern)
    } catch {
        return ""
    } finally {
        $process.Dispose()
        $Probe.Process = $null
    }
}

# 実行ファイルまたはフォント ファイルから版を読み取ります (戻り値: 版の文字列。読み取れない場合は "")。
# ファイル内の版情報を優先し、無い場合だけ Arguments を付けて実行し、出力から版を抜き出します。
function Get-ExecutableVersion {
    param(
        [string]$Path,
        [string[]]$Arguments = @(),
        [string]$Pattern = "",
        [int]$TimeoutMilliseconds = 3000
    )

    $probe = Start-VersionProbe -Path $Path -Arguments $Arguments -Pattern $Pattern
    return (Wait-VersionProbe -Probe $probe -DeadlineUtc ([datetime]::UtcNow.AddMilliseconds($TimeoutMilliseconds)))
}

# パッケージ定義の VersionArgs と VersionOutputPattern に従って、版の読み取りを開始します。
function Start-PackageVersionProbe {
    param(
        [hashtable]$PackageConfig,
        [string]$Path
    )

    $versionArgs = if ($PackageConfig.ContainsKey("VersionArgs")) { @($PackageConfig.VersionArgs) } else { @() }
    $versionPattern = if ($PackageConfig.ContainsKey("VersionOutputPattern")) { [string]$PackageConfig.VersionOutputPattern } else { "" }
    return (Start-VersionProbe -Path $Path -Arguments $versionArgs -Pattern $versionPattern)
}

# 自己更新するコンポーネントについて、版を読み取る導入済みファイルのパスを返します (対象外の場合は "")。
function Get-SelfUpdatingVersionPath {
    param(
        [string]$InstallDir,
        [hashtable]$PackageConfig
    )

    if (-not ($PackageConfig.ContainsKey("SelfUpdating") -and [bool]$PackageConfig.SelfUpdating) -or
        [string]::IsNullOrWhiteSpace($InstallDir)) {
        return ""
    }

    $detectFiles = if ($PackageConfig.ContainsKey("DetectFiles")) { @($PackageConfig.DetectFiles) } else { @() }
    foreach ($file in $detectFiles) {
        $path = Join-Path $InstallDir $file
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            return $path
        }
    }
    return ""
}

# インストール済みの版を取得します (戻り値: 版の文字列。不明な場合は "")。
# ExecutableVersion には、自己更新するコンポーネントの実行ファイルから読み取った版を渡します。
# 渡された版が空の場合は、マニフェストの記録値を返します。
function Get-ComponentInstalledVersion {
    param(
        [hashtable]$Manifest,
        [string]$InstallDir,
        [hashtable]$PackageConfig,
        [string]$ExecutableVersion = ""
    )

    $shortName = $PackageConfig.ShortName

    if ([string]$PackageConfig.ExtractStrategy -eq "NpmInstall" -and $PackageConfig.ContainsKey("NpmPackage") -and
        -not [string]::IsNullOrWhiteSpace($InstallDir)) {
        return (Get-NpmGlobalPackageVersion -BinDir $InstallDir -PackageName ([string]$PackageConfig.NpmPackage))
    }

    if ($ExecutableVersion) {
        return $ExecutableVersion
    }

    if ($null -ne $Manifest -and $Manifest.components.ContainsKey($shortName)) {
        $component = $Manifest.components[$shortName]
        if ($component.ContainsKey("version")) {
            return [string]$component.version
        }
    }
    return ""
}

# コンポーネントの総合状態を判定 (戻り値: Installed / Updateable / NotInstalled / Broken / Legacy)
function Get-ComponentStatus {
    param(
        [hashtable]$Manifest,
        [string]$InstallDir,
        [hashtable]$PackageConfig,
        [string]$PackagesDir = ""
    )

    $shortName = $PackageConfig.ShortName

    # NpmInstall は、devbin が最後に操作した結果 (マニフェスト) ではなく、npm のグローバル ツリーの実物で判定します。
    # 利用者が npm -g で追加、削除、更新した結果を、マニフェストを変更せずに表示へ反映するためです。
    if ([string]$PackageConfig.ExtractStrategy -eq "NpmInstall" -and $PackageConfig.ContainsKey("NpmPackage") -and
        -not [string]::IsNullOrWhiteSpace($InstallDir)) {
        $installedVersion = Get-NpmGlobalPackageVersion -BinDir $InstallDir -PackageName ([string]$PackageConfig.NpmPackage)
        if ([string]::IsNullOrWhiteSpace($installedVersion)) {
            return "NotInstalled"
        }
        $packageVersion = Resolve-PackageVersion -PackageConfig $PackageConfig -PackagesDir $PackagesDir
        if (-not [string]::IsNullOrWhiteSpace($packageVersion) -and
            (Compare-PackageVersion -LeftVersion $packageVersion -RightVersion $installedVersion) -eq 1) {
            return "Updateable"
        }
        return "Installed"
    }

    $inManifest = Test-ComponentInstalled -Manifest $Manifest -ShortName $shortName

    # DetectFiles が未指定の場合はマニフェストの登録情報のみで判定
    $detectFiles = if ($PackageConfig.ContainsKey("DetectFiles")) { @($PackageConfig.DetectFiles) } else { @() }

    if ($inManifest) {
        if ($detectFiles.Count -eq 0) {
            if (Test-ComponentUpdateable -Manifest $Manifest -PackageConfig $PackageConfig -PackagesDir $PackagesDir) {
                return "Updateable"
            }
            return "Installed"
        }
        $filesExist = Test-ComponentFiles -InstallDir $InstallDir -DetectFiles $detectFiles
        if ($filesExist) {
            if (Test-ComponentUpdateable -Manifest $Manifest -PackageConfig $PackageConfig -PackagesDir $PackagesDir) {
                return "Updateable"
            }
            return "Installed"
        } else {
            return "Broken"
        }
    } else {
        # マニフェスト未登録かつファイルが存在する場合はレガシー導入状態と判定
        if ($detectFiles.Count -gt 0) {
            $filesExist = Test-ComponentFiles -InstallDir $InstallDir -DetectFiles $detectFiles
            if ($filesExist) {
                return "Legacy"
            }
        }
        return "NotInstalled"
    }
}
