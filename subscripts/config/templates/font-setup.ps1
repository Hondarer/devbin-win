#Requires -Version 5.1
param(
    [Parameter(Mandatory = $true)]
    [string]$TargetPath
)

$targetFonts = @(
    @{
        FileName = "UDEVGothicHSRFJPDOC-Bold.ttf"
        RegistryName = "UDEV Gothic HSRFJPDOC Bold (TrueType)"
    },
    @{
        FileName = "UDEVGothicHSRFJPDOC-BoldItalic.ttf"
        RegistryName = "UDEV Gothic HSRFJPDOC Bold Italic (TrueType)"
    },
    @{
        FileName = "UDEVGothicHSRFJPDOC-Italic.ttf"
        RegistryName = "UDEV Gothic HSRFJPDOC Italic (TrueType)"
    },
    @{
        FileName = "UDEVGothicHSRFJPDOC-Regular.ttf"
        RegistryName = "UDEV Gothic HSRFJPDOC (TrueType)"
    }
)
$targetFontNames = @($targetFonts | ForEach-Object { $_.FileName })

Write-Host "Running font post-setup..."

foreach ($font in $targetFonts) {
    $found = Get-ChildItem -Path $TargetPath -Recurse -File -Filter $font.FileName -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $found) {
        Write-Host "Warning: Font file not found: $($font.FileName)" -ForegroundColor Yellow
        continue
    }

    $destinationPath = Join-Path $TargetPath $font.FileName
    if ($found.FullName -ne $destinationPath) {
        Move-Item -LiteralPath $found.FullName -Destination $destinationPath -Force
        Write-Host "Moved: $($font.FileName)"
    }
}

Get-ChildItem -Path $TargetPath -Recurse -Force | Sort-Object FullName -Descending | ForEach-Object {
    if ($_.PSIsContainer) {
        if ((Get-ChildItem -Path $_.FullName -Force -ErrorAction SilentlyContinue | Measure-Object).Count -eq 0) {
            Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
        }
        return
    }

    if ($targetFontNames -notcontains $_.Name) {
        Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
        Write-Host "Removed: $($_.Name)"
    }
}

$regPath = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
if (-not (Test-Path $regPath)) {
    New-Item -Path $regPath -Force | Out-Null
}

foreach ($font in $targetFonts) {
    $fullPath = Join-Path $TargetPath $font.FileName
    if (-not (Test-Path $fullPath)) {
        Write-Host "Warning: Missing font file for registration: $($font.FileName)" -ForegroundColor Yellow
        continue
    }

    Set-ItemProperty -Path $regPath -Name $font.RegistryName -Value $fullPath
    Write-Host "Registered: $($font.RegistryName)"
}

Write-Host "Font post-setup completed."
