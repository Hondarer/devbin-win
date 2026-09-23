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
