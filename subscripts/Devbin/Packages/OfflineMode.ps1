# OfflineMode.ps1
# packages フォルダーのマジックファイルによる完全オフラインモード判定

$script:DevbinOfflineMarkerName = "OFFLINE"

function Get-DevbinOfflineMarkerPath {
    param([string]$PackagesDir)

    if ([string]::IsNullOrWhiteSpace($PackagesDir)) {
        return $null
    }

    return (Join-Path $PackagesDir $script:DevbinOfflineMarkerName)
}

function Test-DevbinOfflineMode {
    param([string]$PackagesDir)

    $markerPath = Get-DevbinOfflineMarkerPath -PackagesDir $PackagesDir
    if ([string]::IsNullOrWhiteSpace($markerPath)) {
        return $false
    }

    return (Test-Path -LiteralPath $markerPath -PathType Leaf)
}
