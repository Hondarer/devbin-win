#Requires -Version 5.1

<#
.SYNOPSIS
    Uninstall VSBT (Visual Studio Build Tools) portable installation

.DESCRIPTION
    Removes VSBT installation, environment scripts, and vswhere registration

.PARAMETER OutputPath
    Installation path to remove (default: .\bin\vsbt)

.PARAMETER KeepCache
    Keep downloaded package cache in packages\vsbt

.PARAMETER Force
    Skip confirmation prompt

.EXAMPLE
    .\Uninstall-VSBT.ps1

.EXAMPLE
    .\Uninstall-VSBT.ps1 -OutputPath "C:\buildtools" -Force
#>

[CmdletBinding()]
param(
    [string]$OutputPath = "bin\vsbt",
    [switch]$KeepCache,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

# Fixed Instance ID for vswhere registration (8-character hash)
$INSTANCE_ID = "8f3e5d42"

function Write-ColorMessage {
    param(
        [string]$Message,
        [ConsoleColor]$Color = [ConsoleColor]::White
    )
    Write-Host $Message -ForegroundColor $Color
}

function Unregister-VswhereInstance {
    try {
        $instancesPath = Join-Path $env:ProgramData "Microsoft\VisualStudio\Packages\_Instances"
        $instancePath = Join-Path $instancesPath $INSTANCE_ID

        if (Test-Path $instancePath) {
            Remove-Item -Path $instancePath -Recurse -Force -ErrorAction Stop
            Write-ColorMessage "  Unregistered from vswhere: $instancePath" -Color Green
        } else {
            Write-ColorMessage "  No vswhere registration found" -Color Yellow
        }
    }
    catch {
        Write-Warning "Failed to unregister vswhere instance: $_"
        Write-ColorMessage "  Continuing anyway..." -Color Yellow
    }
}

try {
    Write-ColorMessage "Portable VSBT (Visual Studio Build Tools) Uninstaller"
    Write-ColorMessage ("=" * 70)

    # Confirmation
    if (-not $Force) {
        Write-Host "`nThis will remove:"
        Write-Host "  - VSBT installation: $OutputPath"

        # Get parent directory (bin) for script file location
        $scriptDir = Split-Path $OutputPath -Parent
        if (-not $scriptDir) {
            $scriptDir = "."
        }

        if (Test-Path $scriptDir) {
            $scriptFiles = Get-ChildItem -Path $scriptDir -Filter "Add-VSBT-Env-*.*" -File -ErrorAction SilentlyContinue
            if ($scriptFiles) {
                Write-Host "  - Environment scripts: Add-VSBT-Env-*.cmd, Add-VSBT-Env-*.ps1"
            }
        }

        Write-Host "  - vswhere registration"

        if (-not $KeepCache) {
            Write-Host "  - Package cache: packages\vsbt"
        }

        $response = Read-Host "`nContinue? [Y/N]"
        if ($response -notmatch '^[Yy]') {
            Write-Host "Aborted"
            return
        }
    }

    # Unregister from vswhere
    Write-ColorMessage "`nUnregistering from vswhere..."
    Unregister-VswhereInstance

    # Remove environment scripts
    Write-ColorMessage "`nRemoving environment scripts..."
    $scriptDir = Split-Path $OutputPath -Parent
    if (-not $scriptDir) {
        $scriptDir = "."
    }

    if (Test-Path $scriptDir) {
        $scriptFiles = Get-ChildItem -Path $scriptDir -Filter "Add-VSBT-Env-*.*" -File -ErrorAction SilentlyContinue
        foreach ($script in $scriptFiles) {
            Remove-Item $script.FullName -Force -ErrorAction SilentlyContinue
            Write-Host "  Removed: $($script.Name)"
        }
    }

    # Remove VSBT installation
    Write-ColorMessage "`nRemoving VSBT installation..."
    if (Test-Path $OutputPath) {
        Remove-Item $OutputPath -Recurse -Force -ErrorAction Stop
        Write-Host "  Removed: $OutputPath"
    } else {
        Write-ColorMessage "  Installation directory not found: $OutputPath" -Color Yellow
    }

    # Remove package cache
    if (-not $KeepCache) {
        Write-ColorMessage "`nRemoving package cache..."
        $cachePath = "packages\vsbt"
        if (Test-Path $cachePath) {
            Remove-Item $cachePath -Recurse -Force -ErrorAction Stop
            Write-Host "  Removed: $cachePath"
        } else {
            Write-ColorMessage "  Cache directory not found: $cachePath" -Color Yellow
        }
    } else {
        Write-ColorMessage "`nPackage cache kept: packages\vsbt" -Color Green
    }

    Write-ColorMessage "`nUninstallation completed." -Color Green

} catch {
    Write-Error "An error occurred during uninstallation: $_"
    Write-Error $_.ScriptStackTrace
    exit 1
}
