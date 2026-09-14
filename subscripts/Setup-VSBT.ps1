#Requires -Version 5.1

<#
.SYNOPSIS
    Download and extract MSVC and Windows SDK in portable format

.DESCRIPTION
    portable-vsbt retrieves Visual Studio Build Tools components in portable format

.PARAMETER OutputPath
    Extraction destination path (default: .\bin\vsbt)

.PARAMETER DownloadsPath
    Download cache path (default: .\packages\vsbt)

.PARAMETER MSVCVersion
    MSVC version (latest if omitted)

.PARAMETER SDKVersion
    Windows SDK version (latest if omitted)

.PARAMETER HostArch
    Host architecture (x64, x86, arm64)

.PARAMETER Target
    Target architecture (comma-separated: x64, x86, arm, arm64)

.PARAMETER ShowVersions
    Display available versions

.PARAMETER AcceptLicense
    Automatically accept license

.PARAMETER Preview
    Use preview version

.PARAMETER OfflineMode
    Run in offline mode (use cached manifests)

.PARAMETER DownloadOnly
    Download packages only without extraction

.EXAMPLE
    .\portable-vsbt.ps1 -AcceptLicense

.EXAMPLE
    .\portable-vsbt.ps1 -ShowVersions

.EXAMPLE
    .\portable-vsbt.ps1 -MSVCVersion "14.40" -SDKVersion "26100" -Target "x64,arm64"
#>

[CmdletBinding()]
param(
    [string]$OutputPath = "bin\vsbt",
    [string]$DownloadsPath = "packages\vsbt",
    [string]$MSVCVersion = "",
    [string]$SDKVersion = "",
    [ValidateSet("x64", "x86", "arm64")]
    [string]$HostArch = "x64",
    [string]$Target = "x64",
    [switch]$ShowVersions,
    [switch]$AcceptLicense,
    [switch]$Preview,
    [switch]$OfflineMode,
    [switch]$DownloadOnly,
    [Parameter(DontShow = $true)]
    [switch]$SkipDevbinModuleImport
)

$ErrorActionPreference = "Stop"
$ProgressPreference = 'SilentlyContinue' # Disable progress bar for performance

# スクリプトのディレクトリを取得
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Devbin モジュールをインポートする。
# モジュール内部から呼ばれた場合は、実行中のモジュールを -Force で置き換えない。
if ($SkipDevbinModuleImport) {
    $expectedDevbinModulePath = [System.IO.Path]::GetFullPath((Join-Path $ScriptDir "Devbin\Devbin.psm1"))
    $loadedDevbinModule = Get-Module -Name Devbin | Where-Object {
        $_.Path -and
        [System.IO.Path]::GetFullPath($_.Path).Equals($expectedDevbinModulePath, [System.StringComparison]::OrdinalIgnoreCase)
    } | Select-Object -First 1

    if (-not $loadedDevbinModule) {
        throw "SkipDevbinModuleImport requires the repository Devbin module to be loaded: $expectedDevbinModulePath"
    }
} else {
    try {
        Import-Module (Join-Path $ScriptDir "Devbin") -Force -ErrorAction Stop
    } catch {
        Write-Host "Error importing Devbin: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

# 一時領域は実行ごとに分ける
$TempExtractPath = New-DevbinTempDirectory -Prefix "devbin-vsbt"

# URL definition
$MANIFEST_URL = if ($Preview) {
    "https://aka.ms/vs/17/pre/channel"
} else {
    "https://aka.ms/vs/17/release/channel"
}

$script:TotalDownload = 0

# 環境設定スクリプトのテンプレートを読み込み、値を差し込む
# 生成物の内容は config/templates/vsbt-env.*.template にある
function Expand-VsbtTemplate {
    param(
        [string]$TemplateName,
        [string]$TargetArch,
        [string]$MsvcVersion,
        [string]$MsvcMajorMinor,
        [string]$SdkVersion
    )

    $templatePath = Join-Path $PSScriptRoot "config\templates\$TemplateName"
    if (-not (Test-Path $templatePath -PathType Leaf)) {
        throw "Template not found: $templatePath"
    }

    $content = [System.IO.File]::ReadAllText($templatePath)
    $content = $content.Replace("{{TARGET_ARCH}}", $TargetArch)
    $content = $content.Replace("{{HOST_ARCH}}", $HostArch)
    $content = $content.Replace("{{MSVC_VERSION}}", $MsvcVersion)
    $content = $content.Replace("{{MSVC_MAJOR_MINOR}}", $MsvcMajorMinor)
    $content = $content.Replace("{{SDK_VERSION}}", $SdkVersion)

    # テンプレートファイル末尾の改行は生成物には含めない
    if ($content.EndsWith("`r`n")) {
        $content = $content.Substring(0, $content.Length - 2)
    } elseif ($content.EndsWith("`n")) {
        $content = $content.Substring(0, $content.Length - 1)
    }
    return $content
}

function Write-ColorMessage {
    param(
        [string]$Message,
        [ConsoleColor]$Color = [ConsoleColor]::White
    )
    Write-Host $Message -ForegroundColor $Color
}

function Get-FileHash256 {
    param([byte[]]$Data)
    
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $hash = $sha256.ComputeHash($Data)
    return [BitConverter]::ToString($hash).Replace("-", "").ToLower()
}

function Invoke-Download {
    param(
        [string]$Url,
        [string]$Sha256,
        [string]$FileName,
        [string]$SubFolder = ""
    )

    # Build cache path in packages/vsbt
    if ($SubFolder) {
        $cacheDir = Join-Path $DownloadsPath $SubFolder
        $cachePath = Join-Path $cacheDir $FileName
    } else {
        $cachePath = Join-Path $DownloadsPath $FileName
    }

    # Check if cached file exists with valid hash
    if (Test-Path $cachePath) {
        $data = [System.IO.File]::ReadAllBytes($cachePath)
        $hash = Get-FileHash256 -Data $data

        if ($hash -eq $Sha256.ToLower()) {
            Write-Host "`r$FileName ... OK (cached)" -NoNewline
            Write-Host ""
            return $data
        }
    }

    # Build temp path in the temporary extract directory
    if ($SubFolder) {
        $tempDir = Join-Path $TempExtractPath $SubFolder
        if (-not (Test-Path $tempDir)) {
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        }
        $tempPath = Join-Path $tempDir $FileName
    } else {
        $tempPath = Join-Path $TempExtractPath $FileName
    }

    # Download
    Write-Host "$FileName ... " -NoNewline

    try {
        $webClient = New-Object System.Net.WebClient
        $data = $webClient.DownloadData($Url)

        # Hash verification
        $hash = Get-FileHash256 -Data $data
        if ($hash -ne $Sha256.ToLower()) {
            throw "Hash mismatch: $FileName"
        }

        # Save to temp file
        [System.IO.File]::WriteAllBytes($tempPath, $data)

        # Move to cache directory
        if ($SubFolder -and -not (Test-Path $cacheDir)) {
            New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
        }
        Move-Item -Path $tempPath -Destination $cachePath -Force

        $script:TotalDownload += $data.Length

        Write-Host "OK ($([math]::Round($data.Length / 1MB, 2)) MB)"

        return $data
    } finally {
        if ($webClient) { $webClient.Dispose() }
    }
}

function Get-MSICabs {
    param([byte[]]$MsiData)
    
    $cabs = @()
    $text = [System.Text.Encoding]::ASCII.GetString($MsiData)
    $pattern = '[a-zA-Z0-9_\-]{32}\.cab'
    
    $matches = [regex]::Matches($text, $pattern)
    foreach ($match in $matches) {
        $cabs += $match.Value
    }
    
    return $cabs | Select-Object -Unique
}

# Main processing
try {
    Write-ColorMessage "Portable VSBT (Visual Studio Build Tools) Setup"
    Write-ColorMessage ("=" * 70)

    # Skip cleanup and directory creation for ShowVersions mode
    if (-not $ShowVersions) {
        # Unregister existing vswhere instance (for reinstall)
        if (-not $DownloadOnly) {
            Write-ColorMessage "`nUnregistering existing vswhere instance..."
            Unregister-VswhereInstance
        }

        # Clean up the temporary extract directory, batch files, and final output
        if (Test-Path $TempExtractPath) {
            Write-ColorMessage "`nCleaning up temporary download folder..."
            Remove-DevbinTempDirectory -Path $TempExtractPath
        }

        # Skip cleanup of output directory in DownloadOnly mode
        if (-not $DownloadOnly) {
            # Clean up batch files and PowerShell scripts in bin directory
            $batchDir = Split-Path $OutputPath -Parent
            if (-not $batchDir) {
                $batchDir = "."
            }
            if (Test-Path $batchDir) {
                $scriptFiles = Get-ChildItem -Path $batchDir -Filter "Add-VSBT-Env-*.*" -File -ErrorAction SilentlyContinue
                if ($scriptFiles) {
                    Write-ColorMessage "`nCleaning up existing script files..."
                    foreach ($script in $scriptFiles) {
                        Remove-Item $script.FullName -Force -ErrorAction SilentlyContinue
                    }
                }
            }

            # Clean up vsbt output directory
            if (Test-Path $OutputPath) {
                Write-ColorMessage "`nCleaning up existing output folder..."
                Remove-Item $OutputPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        # Create directories
        New-Item -ItemType Directory -Path $TempExtractPath -Force | Out-Null
        if (-not $DownloadOnly) {
            New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
        }
    }

    if (-not (Test-Path $DownloadsPath)) {
        New-Item -ItemType Directory -Path $DownloadsPath | Out-Null
    }

    # Manifest cache paths
    $manifestType = if ($Preview) { "preview" } else { "release" }
    $channelCachePath = Join-Path $DownloadsPath "channel_$manifestType.json"
    $manifestCachePath = Join-Path $DownloadsPath "manifest_$manifestType.json"

    # Download manifest
    $channelData = $null
    $vsManifest = $null
    $useCache = $false

    if (-not $OfflineMode) {
        try {
            Write-ColorMessage "`nChecking manifest..."
            $channelData = Invoke-RestMethod -Uri $MANIFEST_URL -UseBasicParsing -ErrorAction Stop

            # Save channel data to cache
            $channelData | ConvertTo-Json -Depth 100 | Set-Content -Path $channelCachePath -Encoding UTF8

            $itemName = if ($Preview) {
                "Microsoft.VisualStudio.Manifests.VisualStudioPreview"
            } else {
                "Microsoft.VisualStudio.Manifests.VisualStudio"
            }

            $vsItem = $channelData.channelItems | Where-Object { $_.id -eq $itemName } | Select-Object -First 1
            $manifestUrl = $vsItem.payloads[0].url

            $vsManifest = Invoke-RestMethod -Uri $manifestUrl -UseBasicParsing -ErrorAction Stop

            # Save manifest to cache
            $vsManifest | ConvertTo-Json -Depth 100 | Set-Content -Path $manifestCachePath -Encoding UTF8

        } catch {
            Write-ColorMessage "Failed to download manifest. Checking cache..."
            $useCache = $true
        }
    } else {
        Write-ColorMessage "`nOffline mode: Using cached manifest..."
        $useCache = $true
    }

    # Load from cache
    if ($useCache) {
        if ((Test-Path $channelCachePath) -and (Test-Path $manifestCachePath)) {
            Write-ColorMessage "Loading manifest from cache..."
            $channelData = Get-Content -Path $channelCachePath -Encoding UTF8 | ConvertFrom-Json
            $vsManifest = Get-Content -Path $manifestCachePath -Encoding UTF8 | ConvertFrom-Json
        } else {
            throw "Offline mode but no cached manifest found. Please run online once."
        }
    }
    
    # Organize packages
    Write-ColorMessage "Analyzing packages..."
    $packages = @{}
    foreach ($p in $vsManifest.packages) {
        $id = $p.id.ToLower()
        if (-not $packages.ContainsKey($id)) {
            $packages[$id] = @()
        }
        $packages[$id] += $p
    }

    # Detect MSVC and SDK versions
    $msvcVersions = @{}
    $sdkVersions = @{}
    
    foreach ($pkgId in $packages.Keys) {
        if ($pkgId -match '^microsoft\.vc\.(\d+\.\d+)\..*\.tools\.hostx64\.targetx64\.base$') {
            $ver = $matches[1]
            $msvcVersions[$ver] = $pkgId
        }
        elseif ($pkgId -match '^microsoft\.visualstudio\.component\.windows(?:10|11)sdk\.(\d+)$') {
            $ver = $matches[1]
            $sdkVersions[$ver] = $pkgId
        }
    }
    
    if ($ShowVersions) {
        Write-ColorMessage "`nMSVC Versions:"
        $msvcVersions.Keys | Sort-Object -Descending | ForEach-Object {
            Write-Host "  - $_"
        }

        Write-ColorMessage "`nWindows SDK Versions:"
        $sdkVersions.Keys | Sort-Object -Descending | ForEach-Object {
            Write-Host "  - $_"
        }
        return
    }

    # Determine versions
    $selectedMsvcVer = if ($MSVCVersion) {
        $MSVCVersion
    } else {
        $msvcVersions.Keys | Sort-Object -Descending | Select-Object -First 1
    }

    $selectedSdkVer = if ($SDKVersion) {
        $SDKVersion
    } else {
        $sdkVersions.Keys | Sort-Object -Descending | Select-Object -First 1
    }

    if (-not $msvcVersions.ContainsKey($selectedMsvcVer)) {
        throw "MSVC version $selectedMsvcVer not found"
    }
    if (-not $sdkVersions.ContainsKey($selectedSdkVer)) {
        throw "SDK version $selectedSdkVer not found"
    }
    
    $msvcPkgId = $msvcVersions[$selectedMsvcVer]
    $sdkPkgId = $sdkVersions[$selectedSdkVer]

    # Get full MSVC version
    $msvcFullVer = $msvcPkgId -replace '^microsoft\.vc\.(\d+\.\d+\.\d+\.\d+)\..*', '$1'

    Write-ColorMessage "`nDownloading MSVC v$msvcFullVer and Windows SDK v$selectedSdkVer"

    # License confirmation
    if (-not $AcceptLicense) {
        $tools = $channelData.channelItems | Where-Object { $_.id -eq "Microsoft.VisualStudio.Product.BuildTools" }
        $resource = $tools.localizedResources | Where-Object { $_.language -eq "en-us" }
        $licenseUrl = $resource.license

        Write-Host "`nLicense: $licenseUrl"
        if (-not (Read-ConfirmationKey -Prompt "Do you accept the license? [y/N/Esc] ")) {
            Write-Host "Aborted"
            return
        }
    }

    # Parse targets
    $targets = $Target -split ',' | ForEach-Object { $_.Trim() }

    # Track required files for cache cleanup
    $requiredFiles = @()

    # Acquire and extract MSVC packages
    Write-ColorMessage "`nAcquiring and extracting MSVC packages..."

    # Map all packages per target
    $msvcPackages = @{}
    foreach ($t in $targets) {
        $msvcPackages[$t] = @(
            "microsoft.visualcpp.dia.sdk",
            "microsoft.vc.$msvcFullVer.crt.headers.base",
            "microsoft.vc.$msvcFullVer.crt.source.base",
            "microsoft.vc.$msvcFullVer.asan.headers.base",
            "microsoft.vc.$msvcFullVer.pgo.headers.base",
            "microsoft.vc.$msvcFullVer.tools.host$HostArch.target$t.base",
            "microsoft.vc.$msvcFullVer.tools.host$HostArch.target$t.res.base",
            "microsoft.vc.$msvcFullVer.crt.$t.desktop.base",
            "microsoft.vc.$msvcFullVer.crt.$t.store.base",
            "microsoft.vc.$msvcFullVer.premium.tools.host$HostArch.target$t.base",
            "microsoft.vc.$msvcFullVer.pgo.$t.base"
        )

        if ($t -in @("x86", "x64")) {
            $msvcPackages[$t] += "microsoft.vc.$msvcFullVer.asan.$t.base"
        }
    }

    # Download packages per target
    foreach ($t in $targets) {
        $targetSubFolder = Join-Path $t (Join-Path "MSVC" $selectedMsvcVer)
        foreach ($pkg in $msvcPackages[$t] | Sort-Object) {
            $pkgLower = $pkg.ToLower()
            if (-not $packages.ContainsKey($pkgLower)) {
                Write-Host "$pkg ... !!! Not found !!!" -ForegroundColor Yellow
                continue
            }

            $p = $packages[$pkgLower] | Where-Object {
                $_.language -eq $null -or $_.language -eq "en-US"
            } | Select-Object -First 1

            foreach ($payload in $p.payloads) {
                $fileName = $payload.fileName

                # Track required file
                $requiredFilePath = Join-Path $targetSubFolder $fileName
                $requiredFiles += $requiredFilePath

                $data = Invoke-Download -Url $payload.url -Sha256 $payload.sha256 -FileName $fileName -SubFolder $targetSubFolder

                # Skip extraction in DownloadOnly mode
                if ($DownloadOnly) {
                    continue
                }

                # Extract as ZIP
                $zipPath = Join-Path (Join-Path $DownloadsPath $targetSubFolder) $fileName
                Add-Type -AssemblyName System.IO.Compression.FileSystem
                $zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)

                try {
                    foreach ($entry in $zip.Entries) {
                        if ($entry.FullName -like "Contents/*") {
                            $relativePath = $entry.FullName.Substring("Contents/".Length)
                            $outPath = Join-Path $OutputPath $relativePath

                            $outDir = Split-Path $outPath -Parent
                            if ($outDir -and -not (Test-Path $outDir)) {
                                New-Item -ItemType Directory -Path $outDir -Force | Out-Null
                            }

                            if (-not $entry.FullName.EndsWith("/")) {
                                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $outPath, $true)
                            }
                        }
                    }
                } finally {
                    $zip.Dispose()
                }
            }
        }
    }
    
    # Acquire and extract Windows SDK
    Write-ColorMessage "`nAcquiring and extracting Windows SDK..."

    # Map all SDK packages per target
    $sdkPackages = @{}
    foreach ($t in $targets) {
        $sdkPackages[$t] = @(
            "Windows SDK for Windows Store Apps Tools-x86_en-us.msi",
            "Windows SDK for Windows Store Apps Headers-x86_en-us.msi",
            "Windows SDK for Windows Store Apps Headers OnecoreUap-x86_en-us.msi",
            "Windows SDK for Windows Store Apps Libs-x86_en-us.msi",
            "Universal CRT Headers Libraries and Sources-x86_en-us.msi"
        )

        # 全アーキテクチャのヘッダー
        foreach ($arch in @("x64", "x86", "arm", "arm64")) {
            $sdkPackages[$t] += @(
                "Windows SDK Desktop Headers $arch-x86_en-us.msi",
                "Windows SDK OnecoreUap Headers $arch-x86_en-us.msi"
            )
        }

        # ターゲット固有のライブラリ
        $sdkPackages[$t] += "Windows SDK Desktop Libs $t-x86_en-us.msi"
    }

    $sdkPkgData = $packages[$sdkPkgId.ToLower()][0]

    # Handle dependencies as string array or object array
    if (-not $sdkPkgData) {
        throw "SDK package data not found: $sdkPkgId"
    }

    if (-not $sdkPkgData.dependencies -or $sdkPkgData.dependencies.Count -eq 0) {
        throw "SDK package has no dependencies: $sdkPkgId"
    }

    $sdkDep = $sdkPkgData.dependencies[0]
    if (-not $sdkDep) {
        throw "First dependency of SDK package is null"
    }

    $sdkDepId = if ($sdkDep -is [string]) {
        $sdkDep.ToLower()
    } elseif ($sdkDep -is [PSCustomObject]) {
        # For PSCustomObject, first property name is dependency ID
        $firstProp = $sdkDep.PSObject.Properties | Select-Object -First 1
        if (-not $firstProp) {
            throw "SDK dependency object has no properties"
        }
        $firstProp.Name.ToLower()
    } else {
        throw "Unknown SDK dependency type: $($sdkDep.GetType().FullName)"
    }

    if (-not $packages.ContainsKey($sdkDepId)) {
        throw "Dependency package not found: $sdkDepId"
    }

    $sdkPkgData = $packages[$sdkDepId][0]

    $msiFiles = @()

    # Download SDK packages per target
    foreach ($t in $targets) {
        $targetSdkSubFolder = Join-Path $t (Join-Path "SDK" $selectedSdkVer)
        $cabFiles = @()

        foreach ($pkg in $sdkPackages[$t] | Sort-Object) {
            $payload = $sdkPkgData.payloads | Where-Object {
                $_.fileName -eq "Installers\$pkg"
            } | Select-Object -First 1

            if (-not $payload) { continue }

            $msiPath = Join-Path (Join-Path $DownloadsPath $targetSdkSubFolder) $pkg
            $msiFiles += $msiPath

            # Track required file
            $requiredFilePath = Join-Path $targetSdkSubFolder $pkg
            $requiredFiles += $requiredFilePath

            $data = Invoke-Download -Url $payload.url -Sha256 $payload.sha256 -FileName $pkg -SubFolder $targetSdkSubFolder

            # Detect CAB files from MSI
            $cabs = Get-MSICabs -MsiData $data
            $cabFiles += $cabs
        }

        # Download CAB files (save to target subfolder)
        foreach ($cab in ($cabFiles | Select-Object -Unique)) {
            $payload = $sdkPkgData.payloads | Where-Object {
                $_.fileName -eq "Installers\$cab"
            } | Select-Object -First 1

            if ($payload) {
                # Track required file
                $requiredFilePath = Join-Path $targetSdkSubFolder $cab
                $requiredFiles += $requiredFilePath

                Invoke-Download -Url $payload.url -Sha256 $payload.sha256 -FileName $cab -SubFolder $targetSdkSubFolder | Out-Null
            }
        }
    }

    # Clean up unreferenced cached files (skip in OfflineMode)
    if (-not $OfflineMode) {
        Write-ColorMessage "`nCleaning up unreferenced cache files..."
        $cleanedCount = 0
        $cleanedSize = 0

        if (Test-Path $DownloadsPath) {
            # Resolve full path for proper relative path calculation
            $downloadsFullPath = (Resolve-Path $DownloadsPath).Path

            # Get all cached files
            $cachedFiles = Get-ChildItem -Path $DownloadsPath -Recurse -File | Where-Object {
                $_.Extension -in @('.msi', '.cab', '.zip', '.vsix')
            }

            foreach ($cachedFile in $cachedFiles) {
                # Get relative path from DownloadsPath
                $relativePath = $cachedFile.FullName.Substring($downloadsFullPath.Length + 1)

                # Check if this file is in the required list
                $isRequired = $false
                foreach ($reqFile in $requiredFiles) {
                    if ($relativePath -eq $reqFile) {
                        $isRequired = $true
                        break
                    }
                }

                # Delete if not required
                if (-not $isRequired) {
                    $fileSize = $cachedFile.Length
                    try {
                        Remove-Item $cachedFile.FullName -Force -ErrorAction Stop
                        $cleanedCount++
                        $cleanedSize += $fileSize
                        Write-Host "  Removed: $relativePath"
                    } catch {
                        Write-Host "  Warning: Failed to remove: $relativePath" -ForegroundColor Yellow
                    }
                }
            }

            # Remove empty directories
            Get-ChildItem -Path $DownloadsPath -Recurse -Directory | Sort-Object -Property FullName -Descending | ForEach-Object {
                if ((Get-ChildItem -Path $_.FullName -Force).Count -eq 0) {
                    Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
                }
            }
        }

        if ($cleanedCount -gt 0) {
            $cleanedMB = [math]::Round($cleanedSize / 1MB, 2)
            Write-ColorMessage "Removed $cleanedCount unreferenced file(s) ($cleanedMB MB)"
        } else {
            Write-ColorMessage "No unreferenced files found"
        }
    }

    # Skip extraction in DownloadOnly mode
    if ($DownloadOnly) {
        Write-ColorMessage "`nDownload completed (extraction skipped)"
        $downloadMB = [math]::Round($script:TotalDownload / 1MB, 2)
        Write-ColorMessage "Total downloaded: $downloadMB MB"
        return
    }

    # Extract MSI files
    Write-ColorMessage "`nExtracting MSI files..."

    foreach ($msi in $msiFiles) {
        $msiName = Split-Path $msi -Leaf
        Write-Host "  Extracting: $msiName"

        $targetDir = (Resolve-Path $OutputPath).Path
        $arguments = "/a `"$msi`" /quiet /qn TARGETDIR=`"$targetDir`""
        
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "msiexec.exe"
        $psi.Arguments = $arguments
        $psi.CreateNoWindow = $true
        $psi.UseShellExecute = $false
        
        $process = [System.Diagnostics.Process]::Start($psi)
        $process.WaitForExit()

        if ($process.ExitCode -ne 0) {
            Write-Warning "Failed to extract MSI: $msiName (Exit Code: $($process.ExitCode))"
        }

        # Delete extracted MSI file
        $extractedMsi = Join-Path $OutputPath $msiName
        if (Test-Path $extractedMsi) {
            Remove-Item $extractedMsi -Force
        }
    }

    # Clean up
    Write-ColorMessage "`nCleaning up..."

    # Detect versions
    $msvcVersionPath = Get-ChildItem (Join-Path $OutputPath "VC\Tools\MSVC") -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty Name
    $sdkBinPath = Join-Path $OutputPath "Windows Kits\10\bin"
    $sdkVersionPath = $null
    if (Test-Path $sdkBinPath) {
        $sdkVersionPath = Get-ChildItem $sdkBinPath -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty Name
    }

    # Verify extraction succeeded
    if (-not $msvcVersionPath) {
        throw "MSVC extraction failed: VC\Tools\MSVC folder not found"
    }
    if (-not $sdkVersionPath) {
        throw "SDK extraction failed: Windows Kits\10\bin folder not found or empty"
    }

    # Delete unnecessary files
    $cleanupPaths = @(
        "Common7",
        "VC\Tools\MSVC\$msvcVersionPath\Auxiliary"
    )

    foreach ($path in $cleanupPaths) {
        $fullPath = Join-Path $OutputPath $path
        if (Test-Path $fullPath) {
            Remove-Item $fullPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # Rename DIA SDK folder (decode URL encoding)
    $diaEncodedPath = Join-Path $OutputPath "DIA%20SDK"
    $diaDecodedPath = Join-Path $OutputPath "DIA SDK"
    if (Test-Path -LiteralPath $diaEncodedPath) {
        if (Test-Path -LiteralPath $diaDecodedPath) {
            Remove-Item -LiteralPath $diaDecodedPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        Move-Item -LiteralPath $diaEncodedPath -Destination $diaDecodedPath -Force
    }

    # Remove telemetry
    foreach ($t in $targets) {
        $vctipPath = Join-Path $OutputPath "VC\Tools\MSVC\$msvcVersionPath\bin\Host$HostArch\$t\vctip.exe"
        if (Test-Path $vctipPath) {
            Remove-Item $vctipPath -Force
        }
    }
    
    # Generate setup batch files and PowerShell scripts
    Write-ColorMessage "`nGenerating setup scripts..."

    # Get parent directory (bin) for script file placement
    $scriptDir = Split-Path $OutputPath -Parent
    if (-not $scriptDir) {
        $scriptDir = "."
    }
    if (-not (Test-Path $scriptDir)) {
        New-Item -ItemType Directory -Path $scriptDir -Force | Out-Null
    }

    foreach ($t in $targets) {
        # MSVC major.minor を抽出
        $msvcMajorMinor = if ($msvcFullVer -match '^(\d+\.\d+)') { $matches[1] } else { "" }

        # Generate batch file (CMD)
        $cmdContent = Expand-VsbtTemplate `
            -TemplateName "vsbt-env.cmd.template" `
            -TargetArch $t `
            -MsvcVersion $msvcFullVer `
            -MsvcMajorMinor $msvcMajorMinor `
            -SdkVersion $selectedSdkVer

        $cmdPath = Join-Path $scriptDir "Add-VSBT-Env-$t.cmd"
        $utf8 = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($cmdPath, $cmdContent, $utf8)
        Write-Host "  Generated: Add-VSBT-Env-$t.cmd"

        # Generate PowerShell script
        $ps1Content = Expand-VsbtTemplate `
            -TemplateName "vsbt-env.ps1.template" `
            -TargetArch $t `
            -MsvcVersion $msvcFullVer `
            -MsvcMajorMinor $msvcMajorMinor `
            -SdkVersion $selectedSdkVer

        $ps1Path = Join-Path $scriptDir "Add-VSBT-Env-$t.ps1"
        # BOM 付き UTF-8 で保存
        $utf8BOM = New-Object System.Text.UTF8Encoding $true
        [System.IO.File]::WriteAllText($ps1Path, $ps1Content, $utf8BOM)
        Write-Host "  Generated: Add-VSBT-Env-$t.ps1"
    }

    # Show statistics
    $downloadMB = [math]::Round($script:TotalDownload / 1MB, 2)
    Write-ColorMessage "`nCompleted."
    Write-ColorMessage "Total downloaded: $downloadMB MB"
    $cmdExample = Join-Path $scriptDir "Add-VSBT-Env-x64.cmd"
    $ps1Example = Join-Path $scriptDir "Add-VSBT-Env-x64.ps1"
    Write-ColorMessage "`nTo set up environment:"
    Write-ColorMessage "  CMD: $cmdExample"
    Write-ColorMessage "  PowerShell: $ps1Example"

    # Register to vswhere
    Write-ColorMessage "`nRegistering to vswhere..."
    Register-VswhereInstance -InstallPath $OutputPath -MsvcVersion $msvcFullVer -SdkVersion $selectedSdkVer -Targets $targets

} catch {
    Write-Error "An error occurred: $_"
    Write-Error $_.ScriptStackTrace
    exit 1
} finally {
    # Clean up the temporary extract directory (skip for ShowVersions mode)
    if (-not $ShowVersions) {
        Write-ColorMessage "`nCleaning up temporary download folder..."
        Remove-DevbinTempDirectory -Path $TempExtractPath
    }
}
