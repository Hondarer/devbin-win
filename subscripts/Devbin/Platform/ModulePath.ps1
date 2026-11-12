# ModulePath.ps1
# Windows PowerShell 5.1 のモジュール検索パス (PSModulePath) の整合性を保つヘルパー
#
# PowerShell 7 のターミナルから powershell.exe (5.1) を起動すると、PSModulePath が引き継がれ、
# PowerShell 7 同梱のモジュール (Microsoft.PowerShell.Archive 1.2.x など) が 5.1 に読み込まれることがあります。
# これらは .NET Framework に存在しない API を呼び出すため、5.1 では動作しません。

# PSModulePath の値から PowerShell 7 用のモジュール検索パスを取り除いた値を返却
function Get-WindowsPowerShellModulePath {
    param([string]$ModulePath)

    if ([string]::IsNullOrWhiteSpace($ModulePath)) {
        return ""
    }

    # 例: ...\Documents\PowerShell\Modules, C:\Program Files\PowerShell\Modules, C:\Program Files\PowerShell\7\Modules
    #     ...\WindowsApps\Microsoft.PowerShell_7.x...\Modules
    # WindowsPowerShell\Modules は直前に区切り文字がないため一致しない
    $pwshPatterns = @(
        '(?i)[\\/]PowerShell[\\/](7[^\\/]*[\\/])?Modules[\\/]?$',
        '(?i)[\\/]WindowsApps[\\/]Microsoft\.PowerShell'
    )

    $kept = foreach ($entry in ($ModulePath -split ';')) {
        if ([string]::IsNullOrWhiteSpace($entry)) { continue }
        $isPwsh = $false
        foreach ($pattern in $pwshPatterns) {
            if ($entry -match $pattern) { $isPwsh = $true; break }
        }
        if (-not $isPwsh) { $entry }
    }

    return (@($kept) -join ';')
}

# Windows PowerShell 5.1 で実行中の場合のみ、現在のプロセスの PSModulePath から PowerShell 7 用のパスを除去 (変更時は $true)
function Reset-WindowsPowerShellModulePath {
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        return $false
    }

    $current = $env:PSModulePath
    $cleaned = Get-WindowsPowerShellModulePath -ModulePath $current
    if ($cleaned -eq $current) {
        return $false
    }

    $env:PSModulePath = $cleaned
    return $true
}
