# ProductRoot.ps1
# 製品ルートパスの解決、および該当ルートを参照する環境変数・PATH エントリの判定と除去

function Get-DevbinProductRoot {
    param(
        [string]$InstallDir
    )

    if ([string]::IsNullOrWhiteSpace($InstallDir)) {
        throw "InstallDir is required"
    }

    $fullPath = $null
    try {
        $fullPath = [System.IO.Path]::GetFullPath($InstallDir)
    } catch {
        $fullPath = $InstallDir.Trim()
    }

    $leaf = Split-Path -Path $fullPath -Leaf
    $parent = Split-Path -Path $fullPath -Parent
    if ($parent -and $leaf -eq "bin") {
        $parentLeaf = Split-Path -Path $parent -Leaf
        if ($parentLeaf -eq "devbin-win") {
            $normalizedParent = Get-NormalizedPathString -PathValue $parent
            if ($normalizedParent) {
                return $normalizedParent
            }
            return $parent.TrimEnd('\')
        }
    }

    $normalized = Get-NormalizedPathString -PathValue $fullPath
    if ($normalized) {
        return $normalized
    }
    return $fullPath.TrimEnd('\')
}

# 完全アンインストールが許可される規定の製品ルートパスを取得
function Get-DevbinExpectedProductRoot {
    $expected = Join-Path $env:ProgramData "$env:USERNAME\devbin-win"
    $normalized = Get-NormalizedPathString -PathValue $expected
    if ($normalized) {
        return $normalized
    }
    return $expected.TrimEnd('\')
}

# 指定された製品ルートが完全アンインストールの対象として妥当であるかを検証
function Test-DevbinProductRootAllowed {
    param(
        [string]$ProductRoot
    )

    $normalized = Get-NormalizedPathString -PathValue $ProductRoot
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return $false
    }

    return [string]::Equals($normalized, (Get-DevbinExpectedProductRoot), [StringComparison]::OrdinalIgnoreCase)
}

function Test-PathUnderRoot {
    param(
        [string]$PathValue,
        [string]$Root
    )

    if ([string]::IsNullOrWhiteSpace($PathValue) -or [string]::IsNullOrWhiteSpace($Root)) {
        return $false
    }

    $normalizedRoot = Get-NormalizedPathString -PathValue $Root
    if ([string]::IsNullOrWhiteSpace($normalizedRoot)) {
        $normalizedRoot = $Root.Trim().TrimEnd('\')
    }

    $candidates = New-Object System.Collections.Generic.List[string]
    $raw = $PathValue.Trim()
    if ($raw.StartsWith('"') -and $raw.EndsWith('"') -and $raw.Length -ge 2) {
        $raw = $raw.Substring(1, $raw.Length - 2)
    }
    $candidates.Add($raw) | Out-Null
    try {
        $expanded = [Environment]::ExpandEnvironmentVariables($raw)
        if (-not [string]::IsNullOrWhiteSpace($expanded)) {
            $candidates.Add($expanded) | Out-Null
        }
    } catch {
    }

    if ($PathValue -match '^\s*"([^"]+)"') {
        $candidates.Add($Matches[1]) | Out-Null
    } elseif ($raw -match '^([^\s]+)') {
        $candidates.Add($Matches[1]) | Out-Null
    }

    foreach ($candidate in @($candidates | Select-Object -Unique)) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }

        $normalized = Get-NormalizedPathString -PathValue $candidate
        if ([string]::IsNullOrWhiteSpace($normalized)) {
            continue
        }

        if ([string]::Equals($normalized, $normalizedRoot, [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }

        $rootPrefix = $normalizedRoot.TrimEnd('\') + '\'
        if ($normalized.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    $searchText = $PathValue
    try {
        $searchText = [Environment]::ExpandEnvironmentVariables($PathValue)
    } catch {
        $searchText = $PathValue
    }

    $rootToken = $normalizedRoot.TrimEnd('\')
    $index = $searchText.IndexOf($rootToken, [StringComparison]::OrdinalIgnoreCase)
    if ($index -lt 0) {
        return $false
    }

    $after = $index + $rootToken.Length
    if ($after -ge $searchText.Length) {
        return $true
    }

    $nextChar = $searchText[$after]
    return ($nextChar -eq '\' -or $nextChar -eq '/' -or $nextChar -eq '"' -or $nextChar -eq "'" -or [char]::IsWhiteSpace($nextChar))
}

# セミコロン (;) 区切りの文字列を、製品ルート配下のパスとそれ以外のパスに分割
function Split-RootEntriesFromValue {
    param(
        [string]$Value,
        [string]$Root
    )

    $kept = @()
    $removed = @()

    if (-not [string]::IsNullOrWhiteSpace($Value)) {
        foreach ($entry in ($Value -split ';')) {
            if ([string]::IsNullOrWhiteSpace($entry)) {
                continue
            }

            $trimmed = $entry.Trim()
            if (Test-PathUnderRoot -PathValue $trimmed -Root $Root) {
                $removed += $trimmed
            } else {
                $kept += $trimmed
            }
        }
    }

    return [PSCustomObject]@{
        Kept    = @($kept)
        Removed = @($removed)
    }
}

function Remove-UserEnvVarsPointingToRoot {
    param(
        [string]$Root
    )

    $changed = @()
    try {
        $userVars = [Environment]::GetEnvironmentVariables("User")
        foreach ($key in @($userVars.Keys)) {
            if ([string]::Equals([string]$key, "PATH", [StringComparison]::OrdinalIgnoreCase)) {
                continue
            }

            $value = [string]$userVars[$key]
            $split = Split-RootEntriesFromValue -Value $value -Root $Root
            if ($split.Removed.Count -eq 0) {
                continue
            }

            # 製品ルート配下のエントリのみを除去し、他の値が存在する場合は更新した文字列で保持
            if ($split.Kept.Count -eq 0) {
                [Environment]::SetEnvironmentVariable([string]$key, $null, "User")
                Write-Host "  Removed environment variable: $key"
            } else {
                [Environment]::SetEnvironmentVariable([string]$key, ($split.Kept -join ';'), "User")
                Write-Host "  Updated environment variable: $key"
                foreach ($removedEntry in $split.Removed) {
                    Write-Host "    Removed entry: $removedEntry"
                }
            }

            $changed += [string]$key
        }
    } catch {
        Write-Host "Warning: Failed to scan user environment variables: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    return @($changed)
}

function Remove-UserPathEntriesPointingToRoot {
    param(
        [string]$Root
    )

    try {
        $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
        if ([string]::IsNullOrWhiteSpace($currentPath)) {
            return
        }

        $split = Split-RootEntriesFromValue -Value $currentPath -Root $Root
        if ($split.Removed.Count -eq 0) {
            return
        }

        [Environment]::SetEnvironmentVariable("PATH", ($split.Kept -join ';'), "User")
        foreach ($removedEntry in $split.Removed) {
            Write-Host "  Removed PATH entry: $removedEntry"
        }
    } catch {
        Write-Host "Warning: Failed to clean user PATH: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}
