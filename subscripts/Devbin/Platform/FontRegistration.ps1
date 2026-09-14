# FontRegistration.ps1
# 製品ルートを指すフォント登録の解除

function Remove-FontRegistrationsPointingToRoot {
    param(
        [string]$Root
    )

    $regPath = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
    if (-not (Test-Path $regPath)) {
        return
    }

    try {
        $fontProps = Get-ItemProperty -Path $regPath -ErrorAction Stop
        $skipNames = @("PSPath", "PSParentPath", "PSChildName", "PSDrive", "PSProvider")
        foreach ($prop in $fontProps.PSObject.Properties) {
            if ($skipNames -contains $prop.Name) {
                continue
            }

            $value = [string]$prop.Value
            if (Test-PathUnderRoot -PathValue $value -Root $Root) {
                Remove-ItemProperty -Path $regPath -Name $prop.Name -ErrorAction SilentlyContinue
                Write-Host "  Removed font registration: $($prop.Name)"
            }
        }
    } catch {
        Write-Host "Warning: Failed to scan font registrations: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}
