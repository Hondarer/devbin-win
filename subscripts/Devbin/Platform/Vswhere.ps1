# Vswhere.ps1
# vswhere インスタンスの登録と解除

# vswhere インスタンスを登録する関数
function Register-VswhereInstance {
    param(
        [string]$InstallPath,
        [string]$MsvcVersion,
        [string]$SdkVersion,
        [string[]]$Targets
    )

    try {
        $instancesPath = Join-Path $env:ProgramData "Microsoft\VisualStudio\Packages\_Instances"
        $instancePath = Join-Path $instancesPath $script:VSBT_INSTANCE_ID

        # インスタンスディレクトリを作成
        # 一般ユーザーでは Packages 配下が書けない。Stop だと Transcript に終了エラーが残る
        if (-not (Test-Path $instancePath)) {
            New-Item -ItemType Directory -Path $instancePath -Force -ErrorAction SilentlyContinue | Out-Null
        }
        if (-not (Test-Path $instancePath)) {
            Write-Host "Skip to register vswhere instance: You are normal user."
            Write-Host "Continuing without vswhere registration..."
            return
        }

        # 絶対パスを取得
        $absolutePath = (Resolve-Path $InstallPath -ErrorAction Stop).Path

        # ターゲットに基づいてパッケージ配列を構築
        $packagesArray = @(
            @{
                id = "Microsoft.VisualStudio.Component.VC.Tools.x86.x64"
                version = $MsvcVersion
            }
        )

        foreach ($target in $Targets) {
            $packagesArray += @{
                id = "Microsoft.VisualStudio.Component.VC.Tools.$target"
                version = $MsvcVersion
            }
        }

        # state.json を作成
        $stateJson = @{
            installationPath = $absolutePath
            installationVersion = $MsvcVersion
            installDate = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            displayName = "Visual Studio Build Tools (devbin-win)"
            description = "Portable MSVC and Windows SDK"
            channelId = "VisualStudio.17.Release"
            channelUri = "https://aka.ms/vs/17/release/channel"
            enginePath = $absolutePath
            installChannelUri = "https://aka.ms/vs/17/release/channel"
            releaseNotes = "https://docs.microsoft.com/en-us/visualstudio/releases/2022/release-notes"
            thirdPartyNotices = "https://go.microsoft.com/fwlink/?LinkId=660909"
            product = @{
                id = "Microsoft.VisualStudio.Product.BuildTools"
                version = $MsvcVersion
                localizedResources = @(
                    @{
                        language = "en-US"
                        title = "Visual Studio Build Tools (devbin-win)"
                        description = "Portable MSVC and Windows SDK"
                    }
                )
            }
            packages = $packagesArray
        } | ConvertTo-Json -Depth 10

        $stateJsonPath = Join-Path $instancePath "state.json"
        [System.IO.File]::WriteAllText($stateJsonPath, $stateJson, [System.Text.Encoding]::UTF8)

        Write-Host "Registered to vswhere: $instancePath" -ForegroundColor Green
    }
    catch {
        $isAccessDenied = $_.Exception.Message -match "(アクセスが拒否|Access.*denied|UnauthorizedAccess)"

        if ($isAccessDenied) {
            Write-Host "Skip to register vswhere instance: You are normal user."
        } else {
            Write-Host "Skip to register vswhere instance: $_"
        }

        Write-Host "Continuing without vswhere registration..."
    }
}

# vswhere インスタンスを削除する関数
function Unregister-VswhereInstance {
    try {
        $instancesPath = Join-Path $env:ProgramData "Microsoft\VisualStudio\Packages\_Instances"
        $instancePath = Join-Path $instancesPath $script:VSBT_INSTANCE_ID

        if (Test-Path $instancePath) {
            Remove-Item -Path $instancePath -Recurse -Force -ErrorAction Stop
            Write-Host "Unregistered from vswhere: $instancePath" -ForegroundColor Green
        } else {
            Write-Host "vswhere instance not found (already unregistered or never registered)" -ForegroundColor Cyan
        }
    }
    catch {
        $isAccessDenied = $_.Exception.Message -match "(アクセスが拒否|Access.*denied|UnauthorizedAccess)"

        if ($isAccessDenied) {
            Write-Warning "Failed to unregister vswhere instance: Access denied"
            Write-Host "Note: vswhere unregistration requires administrator privileges." -ForegroundColor Yellow
        } else {
            Write-Warning "Failed to unregister vswhere instance: $_"
        }

        Write-Host "Continuing anyway..." -ForegroundColor Yellow
    }
}

function Unregister-VswhereInstanceIfPointingToRoot {
    param(
        [string]$Root
    )

    try {
        $instancesPath = Join-Path $env:ProgramData "Microsoft\VisualStudio\Packages\_Instances"
        $instancePath = Join-Path $instancesPath $script:VSBT_INSTANCE_ID
        if (-not (Test-Path $instancePath)) {
            Write-Host "  vswhere instance not found (already unregistered or never registered)"
            return
        }

        $stateJsonPath = Join-Path $instancePath "state.json"
        $shouldRemove = $false
        if (-not (Test-Path $stateJsonPath)) {
            $shouldRemove = $true
        } else {
            try {
                $state = Get-Content -Path $stateJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
                $installationPath = if ($state.PSObject.Properties.Match("installationPath").Count -gt 0) {
                    [string]$state.installationPath
                } else {
                    ""
                }
                if ([string]::IsNullOrWhiteSpace($installationPath) -or (Test-PathUnderRoot -PathValue $installationPath -Root $Root)) {
                    $shouldRemove = $true
                } else {
                    Write-Host "  vswhere instance installationPath is outside product root, leaving it: $installationPath"
                }
            } catch {
                $shouldRemove = $true
            }
        }

        if ($shouldRemove) {
            Remove-Item -Path $instancePath -Recurse -Force -ErrorAction Stop
            Write-Host "  Unregistered vswhere instance: $instancePath"
        }
    } catch {
        $isAccessDenied = $_.Exception.Message -match "(アクセスが拒否|Access.*denied|UnauthorizedAccess)"
        if ($isAccessDenied) {
            Write-Host "Warning: Failed to unregister vswhere instance: Access denied" -ForegroundColor Yellow
        } else {
            Write-Host "Warning: Failed to unregister vswhere instance: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}
