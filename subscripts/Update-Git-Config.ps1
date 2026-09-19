# Git のグローバル設定 (ユーザーのホームにある .gitconfig) を devbin-win の推奨値へそろえるスクリプト
# 既に値が設定されている項目は変更しません。アンインストール時の復元は行いません。
param(
    [switch]$Install,           # 設定の適用
    [string]$InstallDir = ""    # devbin-win の bin ディレクトリ
)

$ScriptDir = if ($PSScriptRoot) {
    $PSScriptRoot
} else {
    Split-Path -Parent $MyInvocation.MyCommand.Path
}

# コマンドラインの使用方法を表示
function Show-Usage {
    Write-Host "`n=== Git Global Config Manager ==="
    Write-Host "`nUsage:"
    Write-Host "  .\Update-Git-Config.ps1 -Install                      # Apply recommended git settings"
    Write-Host "  .\Update-Git-Config.ps1 -Install -InstallDir <path>   # Use git and code in the given bin directory"
    Write-Host "`nOptions:"
    Write-Host "  -Install     Apply the recommended settings that are not set yet"
    Write-Host "  -InstallDir  devbin-win bin directory (used to locate git.exe and code.cmd)`n"
}

# 使用する git.exe を決定します。devbin-win が導入した Portable Git を優先します。
function Get-GitCommandPath {
    param([string]$BinDir)

    if (-not [string]::IsNullOrWhiteSpace($BinDir)) {
        $portableGit = Join-Path $BinDir "git\cmd\git.exe"
        if (Test-Path $portableGit -PathType Leaf) {
            return $portableGit
        }
    }

    $command = Get-Command git -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    return ""
}

# core.editor に設定する VS Code のコマンドを決定します。見つからない場合は空文字列を返します。
function Get-VSCodeEditorCommand {
    param([string]$BinDir)

    if (-not [string]::IsNullOrWhiteSpace($BinDir)) {
        $portableCode = Join-Path $BinDir "vscode\bin\code.cmd"
        if (Test-Path $portableCode -PathType Leaf) {
            return "code --wait"
        }
    }

    if (Get-Command code -ErrorAction SilentlyContinue) {
        return "code --wait"
    }

    return ""
}

# 未設定の場合のみ git のグローバル設定を書き込みます。
function Set-GitConfigValueIfEmpty {
    param(
        [string]$GitPath,
        [string]$Name,
        [string]$Value
    )

    $current = & $GitPath config --global --get $Name 2>$null
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($current)) {
        Write-Host "    Skipped ${Name}: already set to $current"
        return
    }

    & $GitPath config --global $Name $Value
    if ($LASTEXITCODE -ne 0) {
        Write-Host "    Warning: Failed to set ${Name}" -ForegroundColor Yellow
        return
    }

    Write-Host "    Set ${Name}=$Value"
}

if (-not $Install) {
    Show-Usage
    exit 0
}

$gitPath = Get-GitCommandPath -BinDir $InstallDir
if ([string]::IsNullOrWhiteSpace($gitPath)) {
    Write-Host "    Skipped git config: git.exe not found"
    exit 0
}

# core.editor は VS Code が利用できる場合にのみ設定します。
# Git と VS Code を同時に導入する場合に備えて、VS Code 側の後処理からもこのスクリプトを実行します。
$editorCommand = Get-VSCodeEditorCommand -BinDir $InstallDir
if ([string]::IsNullOrWhiteSpace($editorCommand)) {
    Write-Host "    Skipped core.editor: code command not found"
} else {
    Set-GitConfigValueIfEmpty -GitPath $gitPath -Name "core.editor" -Value $editorCommand
}

Set-GitConfigValueIfEmpty -GitPath $gitPath -Name "http.sslBackend" -Value "openssl"
Set-GitConfigValueIfEmpty -GitPath $gitPath -Name "core.autocrlf" -Value "false"

exit 0
