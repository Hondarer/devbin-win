# PackageDependency.ps1
# 依存関係の解決: 導入順、削除順、逆依存の列挙

# 依存を再帰的に解決し、トポロジカルソート順で返す
# 戻り値: ShortName の配列 (依存先が先、対象が最後)
# 循環依存と未定義の依存先は $Problems (Cycles / Missing) に記録する
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

# 複数の ShortName について導入順を解決し、成否と併せて返す
# 戻り値: Success / Order / Errors を持つオブジェクト
# 循環依存または未定義の依存先がある場合は Success = $false となり、Order は使用しない
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

# 指定コンポーネントに依存しているインストール済みコンポーネントの一覧を返す
function Get-Dependents {
    param(
        [string]$ShortName,
        [array]$Packages,
        [hashtable]$Manifest
    )

    $dependents = @()

    foreach ($pkg in $Packages) {
        # 自分自身はスキップ
        if ($pkg.ShortName -eq $ShortName) {
            continue
        }
        # インストール済みのみ対象
        if (-not (Test-ComponentInstalled -Manifest $Manifest -ShortName $pkg.ShortName)) {
            continue
        }

        $deps = if ($pkg.ContainsKey("DependsOn")) { @($pkg.DependsOn) } else { @() }
        if ($deps -contains $ShortName) {
            $dependents += $pkg.ShortName
        }
    }

    return $dependents
}

# 削除対象を依存元から依存先の順に並べ替える
# 残る対象が依存しているものは後回しにし、解決できない残りは末尾に置く
function Get-UninstallOrder {
    [CmdletBinding()]
    param(
        [string[]]$ShortNames,
        [array]$Packages,
        [hashtable]$Manifest
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
            $dependents = @(Get-Dependents -ShortName $name -Packages $Packages -Manifest $Manifest)
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
