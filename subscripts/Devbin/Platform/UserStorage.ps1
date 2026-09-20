# ユーザー単位のデータ・ログ保存先。製品ルート (%ProgramData%\%USERNAME%\devbin-win) 配下に集約します。
function Get-DevbinUserEnvironmentValue {
    param([string]$Name)
    return [Environment]::GetEnvironmentVariable($Name, 'User')
}

function Set-DevbinUserEnvironmentValue {
    param([string]$Name, [string]$Value)
    [Environment]::SetEnvironmentVariable($Name, $Value, 'User')
}

function Get-DevbinUserStorageRoot {
    if ([string]::IsNullOrWhiteSpace($env:ProgramData) -or
        [string]::IsNullOrWhiteSpace($env:USERNAME) -or
        $env:USERNAME -match '[\\/]' -or $env:USERNAME -in @('.', '..')) {
        throw "ProgramData / USERNAME cannot determine a safe storage root."
    }
    return [IO.Path]::GetFullPath((Join-Path $env:ProgramData "$env:USERNAME\devbin-win"))
}

function Get-DevbinDataDirectory {
    return Join-Path (Get-DevbinUserStorageRoot) 'data'
}

function Get-DevbinLogDirectory {
    return Join-Path (Get-DevbinUserStorageRoot) 'log'
}

# 共通の保存先を用意します。個々のコンポーネントの導入より前に呼び出します。
function Initialize-DevbinUserStorage {
    foreach ($path in @((Get-DevbinDataDirectory), (Get-DevbinLogDirectory))) {
        if (-not (Test-Path -LiteralPath $path)) {
            New-Item -ItemType Directory -Path $path -Force -ErrorAction Stop | Out-Null
        }
    }
    return (Get-DevbinUserStorageRoot)
}

# bin / data / log とその祖先・内部に再解析ポイントがある場合は削除を拒否します。
function Assert-DevbinStorageTreeSafe {
    param([string]$Path)
    $fullPath = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $allowed = @(
        (Join-Path (Get-DevbinUserStorageRoot) 'bin'),
        (Get-DevbinDataDirectory),
        (Get-DevbinLogDirectory)
    ) | ForEach-Object { [IO.Path]::GetFullPath($_).TrimEnd('\') }
    if ($allowed -notcontains $fullPath) { throw "Unexpected cleanup path: $Path" }
    $ancestor = $fullPath
    while ($ancestor) {
        if (Test-Path -LiteralPath $ancestor) {
            $item = Get-Item -LiteralPath $ancestor -Force -ErrorAction Stop
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Cleanup refuses reparse points: $ancestor"
            }
        }
        $ancestor = Split-Path -Parent $ancestor
    }
    if (Test-Path -LiteralPath $fullPath) {
        $pending = New-Object 'System.Collections.Generic.Stack[string]'
        $pending.Push($fullPath)
        while ($pending.Count -gt 0) {
            foreach ($item in Get-ChildItem -LiteralPath $pending.Pop() -Force -ErrorAction Stop) {
                if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                    throw "Cleanup refuses reparse points: $($item.FullName)"
                }
                if ($item.PSIsContainer) { $pending.Push($item.FullName) }
            }
        }
    }
}

function Remove-DevbinUserStorage {
    param([switch]$RemoveData, [switch]$RemoveLogs)
    $targets = @()
    if ($RemoveData) { $targets += Get-DevbinDataDirectory }
    if ($RemoveLogs) { $targets += Get-DevbinLogDirectory }
    # 全対象を検証してから削除します。
    foreach ($target in $targets) { Assert-DevbinStorageTreeSafe -Path $target }
    foreach ($target in $targets) {
        if (-not (Test-Path -LiteralPath $target)) { continue }
        if ($target -eq (Get-DevbinLogDirectory)) {
            foreach ($item in Get-ChildItem -LiteralPath $target -Force -ErrorAction Stop) {
                if ($script:DevbinOperationLogState.Started -and
                    $item.FullName -eq $script:DevbinOperationLogState.Path) { continue }
                Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
            }
        } else {
            Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction Stop
        }
    }
}
