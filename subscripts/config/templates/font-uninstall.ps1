#Requires -Version 5.1
param(
    [Parameter(Mandatory = $true)]
    [string]$InstallDir
)

$regPath = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
if (-not (Test-Path $regPath)) {
    return
}

$fonts = @(
    @{
        RegistryName = "UDEV Gothic HSRFJPDOCEM Bold (TrueType)"
        RelativePath = "fonts\UDEVGothicHSRFJPDOCEM\UDEVGothicHSRFJPDOCEM-Bold.ttf"
    },
    @{
        RegistryName = "UDEV Gothic HSRFJPDOCEM BoldItalic (TrueType)"
        RelativePath = "fonts\UDEVGothicHSRFJPDOCEM\UDEVGothicHSRFJPDOCEM-BoldItalic.ttf"
    },
    @{
        RegistryName = "UDEV Gothic HSRFJPDOCEM Italic (TrueType)"
        RelativePath = "fonts\UDEVGothicHSRFJPDOCEM\UDEVGothicHSRFJPDOCEM-Italic.ttf"
    },
    @{
        RegistryName = "UDEV Gothic HSRFJPDOCEM Regular (TrueType)"
        RelativePath = "fonts\UDEVGothicHSRFJPDOCEM\UDEVGothicHSRFJPDOCEM-Regular.ttf"
    }
)

foreach ($font in $fonts) {
    $expectedPath = Join-Path $InstallDir $font.RelativePath
    $fontProps = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
    if (-not $fontProps) {
        continue
    }

    $currentValue = ($fontProps.PSObject.Properties | Where-Object { $_.Name -eq $font.RegistryName } | Select-Object -ExpandProperty Value -First 1)
    if (-not $currentValue) {
        continue
    }

    $normalizedCurrent = ""
    $normalizedExpected = ""
    try {
        $normalizedCurrent = [System.IO.Path]::GetFullPath([string]$currentValue)
        $normalizedExpected = [System.IO.Path]::GetFullPath($expectedPath)
    } catch {
        $normalizedCurrent = [string]$currentValue
        $normalizedExpected = $expectedPath
    }

    if ($normalizedCurrent -eq $normalizedExpected) {
        Remove-ItemProperty -Path $regPath -Name $font.RegistryName -ErrorAction SilentlyContinue
        Write-Host "Removed font registration: $($font.RegistryName)"
    }
}
