# EnvironmentVariable.ps1
# レジストリに保存された環境変数の同期処理

# 指定した環境変数をレジストリから現在のプロセスに同期
function Sync-EnvironmentVariable {
    param(
        [string]$VariableName,
        [switch]$Silent = $false
    )

    try {
        if ($VariableName -eq "PATH") {
            $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
            $machinePath = [Environment]::GetEnvironmentVariable("PATH", "Machine")

            if (-not $userPath) { $userPath = "" }
            if (-not $machinePath) { $machinePath = "" }

            $combinedPath = if ($userPath -and $machinePath) {
                "$userPath;$machinePath"
            } elseif ($userPath) {
                $userPath
            } elseif ($machinePath) {
                $machinePath
            } else {
                ""
            }

            if ($combinedPath) {
                $pathEntries = $combinedPath -split ';' | Where-Object { $_.Trim() -ne "" }
                $uniqueEntries = @()
                $seenEntries = @{}

                foreach ($entry in $pathEntries) {
                    $trimmedEntry = $entry.Trim()
                    if ($trimmedEntry -and -not $seenEntries.ContainsKey($trimmedEntry.ToLower())) {
                        $uniqueEntries += $trimmedEntry
                        $seenEntries[$trimmedEntry.ToLower()] = $true
                    }
                }

                $cleanPath = $uniqueEntries -join ';'
                $env:PATH = $cleanPath

                if (-not $Silent) {
                    Write-Host "Synchronized PATH environment variable to current process"
                }
            }
        } else {
            $userValue = [Environment]::GetEnvironmentVariable($VariableName, "User")
            $machineValue = [Environment]::GetEnvironmentVariable($VariableName, "Machine")

            $finalValue = if ($userValue) { $userValue } else { $machineValue }

            if ($finalValue) {
                Set-Item -Path "Env:$VariableName" -Value $finalValue
                if (-not $Silent) {
                    Write-Host "Synchronized $VariableName environment variable to current process"
                }
            } else {
                if (Test-Path "Env:$VariableName") {
                    Remove-Item -Path "Env:$VariableName" -ErrorAction SilentlyContinue
                    if (-not $Silent) {
                        Write-Host "Removed $VariableName from current process (not set in registry)"
                    }
                }
            }
        }

        return $true
    } catch {
        if (-not $Silent) {
            Write-Host "Warning: Failed to sync $VariableName environment variable: $($_.Exception.Message)" -ForegroundColor Yellow
        }
        return $false
    }
}

# 複数の環境変数を現在のプロセスへ一括同期
function Sync-EnvironmentVariables {
    param(
        [string[]]$VariableNames = @("PATH", "DOTNET_HOME", "DOTNET_CLI_TELEMETRY_OPTOUT"),
        [switch]$Silent = $false
    )

    if (-not $Silent) {
        Write-Host "Synchronizing environment variables with current process..."
    }

    $syncCount = 0
    foreach ($varName in $VariableNames) {
        if (Sync-EnvironmentVariable -VariableName $varName -Silent:$Silent) {
            $syncCount++
        }
    }

    if (-not $Silent) {
        Write-Host "Successfully synchronized $syncCount/$($VariableNames.Count) environment variables"
    }

    return $syncCount -eq $VariableNames.Count
}
