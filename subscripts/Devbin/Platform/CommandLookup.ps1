# CommandLookup.ps1
# コマンドの実体解決および存在確認

# コマンド情報オブジェクトから実行ファイルの実体パスを取得
function Get-CommandSourcePath {
    param(
        [System.Management.Automation.CommandInfo]$CommandInfo
    )

    if ($null -eq $CommandInfo) {
        return $null
    }

    if (-not [string]::IsNullOrWhiteSpace($CommandInfo.Source)) {
        return [string]$CommandInfo.Source
    }

    if ($CommandInfo.PSObject.Properties.Match("Path").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($CommandInfo.Path)) {
        return [string]$CommandInfo.Path
    }

    return $null
}

# PATH 比較用にディレクトリパス文字列を正規化
function Get-NormalizedPathString {
    param(
        [string]$PathValue
    )

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return $null
    }

    $normalized = $null
    try {
        if (Test-Path $PathValue) {
            $normalized = (Resolve-Path $PathValue -ErrorAction Stop).Path
        } else {
            $normalized = [System.IO.Path]::GetFullPath($PathValue)
        }
    } catch {
        $normalized = $PathValue.Trim()
    }

    if ($normalized.Length -gt 3) {
        return $normalized.TrimEnd('\')
    }

    return $normalized
}

# Python コマンド候補が実体を持つ有効なインストールかを判定 (Windows Store プロキシの除外)
function Test-PythonCommandCandidate {
    param(
        [string]$CommandPath
    )

    if ([string]::IsNullOrWhiteSpace($CommandPath)) {
        return $true
    }

    if ($CommandPath -notmatch "\\WindowsApps\\") {
        return $true
    }

    # Windows Store プロキシは多くの環境に存在し毎回検出されるため、正常系の判定結果は出力しません。
    try {
        $null = Start-Process -FilePath $CommandPath -ArgumentList "--version" -NoNewWindow -Wait -PassThru -RedirectStandardError "stderr_temp.txt" -RedirectStandardOutput "stdout_temp.txt"

        $stderrContent = ""
        if (Test-Path "stderr_temp.txt") {
            $stderrContent = Get-Content "stderr_temp.txt" -Raw -ErrorAction SilentlyContinue
            Remove-Item "stderr_temp.txt" -ErrorAction SilentlyContinue
        }

        $stdoutContent = ""
        if (Test-Path "stdout_temp.txt") {
            $stdoutContent = Get-Content "stdout_temp.txt" -Raw -ErrorAction SilentlyContinue
            Remove-Item "stdout_temp.txt" -ErrorAction SilentlyContinue
        }

        if ($stderrContent -match "^Python\s*$" -or ($stderrContent -match "Python" -and -not ($stderrContent -match "\d+\.\d+" -or $stdoutContent -match "\d+\.\d+"))) {
            return $false
        }

        if ($stdoutContent -match "\d+\.\d+" -or $stderrContent -match "\d+\.\d+") {
            return $true
        }

        Write-Host "  Python proxy test failed - treating as not installed"
        return $false

    } catch {
        Write-Host "  Failed to test Python proxy: $($_.Exception.Message)"
        return $false
    } finally {
        Remove-Item "stderr_temp.txt" -ErrorAction SilentlyContinue
        Remove-Item "stdout_temp.txt" -ErrorAction SilentlyContinue
    }
}

# コマンド候補が有効に機能するかを判定
function Test-CommandCandidate {
    param(
        [string]$CommandName,
        [System.Management.Automation.CommandInfo]$CommandInfo
    )

    if ($null -eq $CommandInfo) {
        return $false
    }

    if ($CommandName -match "^python3?$") {
        return Test-PythonCommandCandidate -CommandPath (Get-CommandSourcePath -CommandInfo $CommandInfo)
    }

    return $true
}

# PATH 上の有効なコマンド候補を列挙
function Get-ValidCommandCandidates {
    param(
        [string]$CommandName
    )

    return @(Get-Command $CommandName -All -ErrorAction SilentlyContinue)
}

# コマンドが PATH 上で利用可能であるかを確認
function Test-CommandExists {
    param([string]$CommandName)

    foreach ($command in Get-ValidCommandCandidates -CommandName $CommandName) {
        if (Test-CommandCandidate -CommandName $CommandName -CommandInfo $command) {
            return $true
        }
    }

    return $false
}

# devbin-win の管理外で外部コマンドが利用可能かを確認
function Test-ExternalCommandExists {
    param(
        [string]$CommandName,
        [string]$InstallDir
    )

    $normalizedInstallDir = Get-NormalizedPathString -PathValue $InstallDir

    foreach ($command in Get-ValidCommandCandidates -CommandName $CommandName) {
        if (-not (Test-CommandCandidate -CommandName $CommandName -CommandInfo $command)) {
            continue
        }

        $commandPath = Get-CommandSourcePath -CommandInfo $command
        if ([string]::IsNullOrWhiteSpace($commandPath)) {
            return $true
        }

        $normalizedCommandPath = Get-NormalizedPathString -PathValue $commandPath
        if ([string]::IsNullOrWhiteSpace($normalizedInstallDir) -or [string]::IsNullOrWhiteSpace($normalizedCommandPath)) {
            return $true
        }

        if ($normalizedCommandPath -eq $normalizedInstallDir) {
            continue
        }

        if ($normalizedCommandPath.StartsWith("$normalizedInstallDir\", [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        return $true
    }

    return $false
}
