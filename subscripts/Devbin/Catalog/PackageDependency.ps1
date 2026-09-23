# PackageDependency.ps1
# パッケージの依存関係解決 (インストール順序、アンインストール順序、逆依存の列挙)

# 依存関係を再帰的に解決し、トポロジカルソート順で返却
# 戻り値: ShortName の配列 (依存先を先行させ、対象自身を末尾に配置)
# 循環依存および未定義の依存先は $Problems (Cycles / Missing) に記録
function Resolve-Dependencies {
    param(
        [string]$ShortName,
        [array]$Packages,
        [hashtable]$Visited = @{},
        [hashtable]$InStack = @{},
        [hashtable]$Problems = $null
    )

    if ($InStack.ContainsKey($ShortName)) {
        if ($Problems) { $Problems.Cycles += $ShortName }
        return @()
    }

    if ($Visited.ContainsKey($ShortName)) {
        return @()
    }

    $InStack[$ShortName] = $true

    $pkg = Get-PackageByShortName -ShortName $ShortName -Packages $Packages
    if (-not $pkg) {
        if ($Problems) { $Problems.Missing += $ShortName }
        $InStack.Remove($ShortName)
        return @()
    }

    $result = @()
    $deps = if ($pkg.ContainsKey("DependsOn")) { @($pkg.DependsOn) } else { @() }

    foreach ($dep in $deps) {
        $subDeps = Resolve-Dependencies -ShortName $dep -Packages $Packages -Visited $Visited -InStack $InStack -Problems $Problems
        $result += $subDeps
    }

    $result += $ShortName
    $Visited[$ShortName] = $true
    $InStack.Remove($ShortName)

    return $result
}

# 指定された複数の ShortName についてインストール順序を解決し、検証結果とあわせて返却
# 戻り値: Success / Order / Errors を持つオブジェクト
# 循環依存または未定義パッケージが検出された場合は Success = $false となり、Order は空配列となります
function Resolve-DependencyOrder {
    param(
        [string[]]$ShortNames,
        [array]$Packages
    )

    $problems = @{ Cycles = @(); Missing = @() }
    $visited = @{}
    $order = @()

    foreach ($name in @($ShortNames)) {
        $order += @(Resolve-Dependencies -ShortName $name -Packages $Packages -Visited $visited -InStack @{} -Problems $problems)
    }

    $errors = @()
    foreach ($cycle in @($problems.Cycles | Select-Object -Unique)) {
        $errors += "循環依存を検出しました: $cycle"
    }
    foreach ($missing in @($problems.Missing | Select-Object -Unique)) {
        $errors += "依存先のパッケージ定義が見つかりません: $missing"
    }

    return [PSCustomObject]@{
        Success = ($errors.Count -eq 0)
        Order   = @($order)
        Errors  = @($errors)
    }
}

# 指定コンポーネントに依存しているインストール済みコンポーネント (逆依存) の一覧を取得
function Get-Dependents {
    param(
        [string]$ShortName,
        [array]$Packages,
        [hashtable]$Manifest,
        # 指定した場合、NpmInstall コンポーネントは npm のグローバル ツリーの実物で導入済みかを判定します。
        [string]$InstallDir = ""
    )

    $dependents = @()

    foreach ($pkg in $Packages) {
        # 自己参照はスキップ
        if ($pkg.ShortName -eq $ShortName) {
            continue
        }
        # インストール済みコンポーネントのみを対象とする
        if (-not (Test-ComponentInstalled -Manifest $Manifest -ShortName $pkg.ShortName -Packages $Packages -InstallDir $InstallDir)) {
            continue
        }

        $deps = if ($pkg.ContainsKey("DependsOn")) { @($pkg.DependsOn) } else { @() }
        if ($deps -contains $ShortName) {
            $dependents += $pkg.ShortName
        }
    }

    return $dependents
}

# 削除対象コンポーネントを安全なアンインストール順序 (依存元から依存先の順) に並び替え
# 他の削除対象から依存されているコンポーネントは後回しにし、依存解消順に抽出
function Get-UninstallOrder {
    [CmdletBinding()]
    param(
        [string[]]$ShortNames,
        [array]$Packages,
        [hashtable]$Manifest,
        [string]$InstallDir = ""
    )

    $remaining = [System.Collections.Generic.List[string]]::new()
    foreach ($name in @($ShortNames)) {
        if (-not [string]::IsNullOrWhiteSpace($name)) {
            $remaining.Add([string]$name)
        }
    }

    $ordered = @()
    $maxPasses = $remaining.Count + 1
    $pass = 0

    while ($remaining.Count -gt 0 -and $pass -lt $maxPasses) {
        $pass++
        $progress = $false
        for ($idx = $remaining.Count - 1; $idx -ge 0; $idx--) {
            $name = $remaining[$idx]
            $dependents = @(Get-Dependents -ShortName $name -Packages $Packages -Manifest $Manifest -InstallDir $InstallDir)
            $blockedBy = @($dependents | Where-Object { $remaining -contains $_ })
            if ($blockedBy.Count -eq 0) {
                $ordered += $name
                $remaining.RemoveAt($idx)
                $progress = $true
            }
        }
        if (-not $progress) { break }
    }

    $ordered += @($remaining)
    return @($ordered)
}
