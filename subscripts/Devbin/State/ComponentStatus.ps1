# ComponentStatus.ps1
# 版の比較と、コンポーネントの総合ステータス判定

# バージョン文字列を比較用トークンに分割する
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

# バージョン文字列を比較する
# 戻り値: 1 (左が新しい), 0 (同じ), -1 (右が新しい), $null (比較不能)
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

# パッケージ定義のバージョンがインストール済みバージョンより新しいかを確認する
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

    $installedComponent = $Manifest.components[$shortName]
    $installedVersion = if ($installedComponent.ContainsKey("version")) { [string]$installedComponent.version } else { "" }
    $packageVersion = Resolve-PackageVersion -PackageConfig $PackageConfig -PackagesDir $PackagesDir

    if ([string]::IsNullOrWhiteSpace($packageVersion)) {
        return $false
    }

    $comparison = Compare-PackageVersion -LeftVersion $packageVersion -RightVersion $installedVersion
    return $comparison -eq 1
}

# コンポーネントの総合ステータスを返す: Installed / Updateable / NotInstalled / Broken / Legacy
function Get-ComponentStatus {
    param(
        [hashtable]$Manifest,
        [string]$InstallDir,
        [hashtable]$PackageConfig,
        [string]$PackagesDir = ""
    )

    $shortName = $PackageConfig.ShortName
    $inManifest = Test-ComponentInstalled -Manifest $Manifest -ShortName $shortName

    # DetectFiles が未指定の場合はマニフェストのみで判断
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
        # マニフェストにないがファイルが存在する = レガシーインストール
        if ($detectFiles.Count -gt 0) {
            $filesExist = Test-ComponentFiles -InstallDir $InstallDir -DetectFiles $detectFiles
            if ($filesExist) {
                return "Legacy"
            }
        }
        return "NotInstalled"
    }
}
