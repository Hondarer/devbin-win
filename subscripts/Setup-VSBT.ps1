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
    [switch]$DownloadOnly
)

$ErrorActionPreference = "Stop"
$ProgressPreference = 'SilentlyContinue' # Disable progress bar for performance

# Temporary download directory
$TempExtractPath = "temp_extract"

# URL definition
$MANIFEST_URL = if ($Preview) {
    "https://aka.ms/vs/17/pre/channel"
} else {
    "https://aka.ms/vs/17/release/channel"
}

$script:TotalDownload = 0

# Fixed Instance ID for vswhere registration
$INSTANCE_ID = "devbin-win"

function Write-ColorMessage {
    param(
        [string]$Message,
        [ConsoleColor]$Color = [ConsoleColor]::White
    )
    Write-Host $Message -ForegroundColor $Color
}

function Register-VswhereInstance {
    param(
        [string]$InstallPath,
        [string]$MsvcVersion,
        [string]$SdkVersion,
        [string[]]$Targets
    )

    try {
        $instancesPath = Join-Path $env:ProgramData "Microsoft\VisualStudio\Packages\_Instances"
        $instancePath = Join-Path $instancesPath $INSTANCE_ID

        # Create instance directory
        if (-not (Test-Path $instancePath)) {
            New-Item -ItemType Directory -Path $instancePath -Force -ErrorAction Stop | Out-Null
        }

        # Get absolute path
        $absolutePath = (Resolve-Path $InstallPath -ErrorAction Stop).Path

        # Build packages array based on targets
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

        # Create state.json
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

        Write-ColorMessage "Registered to vswhere: $instancePath" -Color Green
    }
    catch {
        Write-Warning "Failed to register vswhere instance: $_"
        Write-ColorMessage "Continuing without vswhere registration..." -Color Yellow
    }
}

function Unregister-VswhereInstance {
    try {
        $instancesPath = Join-Path $env:ProgramData "Microsoft\VisualStudio\Packages\_Instances"
        $instancePath = Join-Path $instancesPath $INSTANCE_ID

        if (Test-Path $instancePath) {
            Remove-Item -Path $instancePath -Recurse -Force -ErrorAction Stop
            Write-ColorMessage "Unregistered from vswhere: $instancePath" -Color Green
        }
    }
    catch {
        Write-Warning "Failed to unregister vswhere instance: $_"
        Write-ColorMessage "Continuing anyway..." -Color Yellow
    }
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

    # Build temp path in temp_extract
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

        # Clean up temp_extract, batch files, and final output
        if (Test-Path $TempExtractPath) {
            Write-ColorMessage "`nCleaning up temporary download folder..."
            Remove-Item $TempExtractPath -Recurse -Force -ErrorAction SilentlyContinue
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
        $response = Read-Host "Do you accept the license? [Y/N]"
        if ($response -notmatch '^[Yy]') {
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
                    Remove-Item $cachedFile.FullName -Force -ErrorAction SilentlyContinue
                    $cleanedCount++
                    $cleanedSize += $fileSize
                    Write-Host "  Removed: $relativePath"
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
        # Generate batch file (CMD)
        $cmdContent = @"
@echo off
setlocal enabledelayedexpansion

REM VSBT PATH 動的追加スクリプト
REM MSVC と Windows SDK を現在のセッションの環境変数に追加します

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "VSBT_BASE=%SCRIPT_DIR%\vsbt"

set "MSVC_BIN=%VSBT_BASE%\VC\Tools\MSVC\$msvcVersionPath\bin\Host$HostArch\$t"
set "SDK_BIN=%VSBT_BASE%\Windows Kits\10\bin\$sdkVersionPath\$HostArch"
set "SDK_UCRT_BIN=%VSBT_BASE%\Windows Kits\10\bin\$sdkVersionPath\$HostArch\ucrt"
set "DIA_BIN=%VSBT_BASE%\DIA SDK\bin"

set "MSVC_INCLUDE=%VSBT_BASE%\VC\Tools\MSVC\$msvcVersionPath\include"
set "SDK_UCRT_INCLUDE=%VSBT_BASE%\Windows Kits\10\Include\$sdkVersionPath\ucrt"
set "SDK_SHARED_INCLUDE=%VSBT_BASE%\Windows Kits\10\Include\$sdkVersionPath\shared"
set "SDK_UM_INCLUDE=%VSBT_BASE%\Windows Kits\10\Include\$sdkVersionPath\um"
set "SDK_WINRT_INCLUDE=%VSBT_BASE%\Windows Kits\10\Include\$sdkVersionPath\winrt"
set "SDK_CPPWINRT_INCLUDE=%VSBT_BASE%\Windows Kits\10\Include\$sdkVersionPath\cppwinrt"
set "DIA_INCLUDE=%VSBT_BASE%\DIA SDK\include"

set "MSVC_LIB=%VSBT_BASE%\VC\Tools\MSVC\$msvcVersionPath\lib\$t"
set "SDK_UCRT_LIB=%VSBT_BASE%\Windows Kits\10\Lib\$sdkVersionPath\ucrt\$t"
set "SDK_UM_LIB=%VSBT_BASE%\Windows Kits\10\Lib\$sdkVersionPath\um\$t"
set "DIA_LIB=%VSBT_BASE%\DIA SDK\lib"

REM MSVC パスの存在確認
if not exist "%MSVC_BIN%" (
    echo Error: MSVC path not found: %MSVC_BIN%
    exit /b 1
)

REM 環境変数を設定 (常に上書き)
set "VSCMD_ARG_HOST_ARCH=$HostArch"
set "VSCMD_ARG_TGT_ARCH=$t"
set "VCToolsVersion=$msvcVersionPath"
set "WindowsSDKVersion=$sdkVersionPath"
set "VCToolsInstallDir=%VSBT_BASE%\VC\Tools\MSVC\$msvcVersionPath"
set "WindowsSdkBinPath=%VSBT_BASE%\Windows Kits\10\bin"

set "PATH_CHANGED=0"

REM PATH に追加 (重複チェック)
echo %PATH% | findstr /C:"%MSVC_BIN%" >nul
if %ERRORLEVEL% neq 0 (
    set "PATH=%MSVC_BIN%;%PATH%"
    set "PATH_CHANGED=1"
)

echo %PATH% | findstr /C:"%SDK_BIN%" >nul
if %ERRORLEVEL% neq 0 (
    set "PATH=%SDK_BIN%;%PATH%"
    set "PATH_CHANGED=1"
)

echo %PATH% | findstr /C:"%SDK_UCRT_BIN%" >nul
if %ERRORLEVEL% neq 0 (
    set "PATH=%SDK_UCRT_BIN%;%PATH%"
    set "PATH_CHANGED=1"
)

echo %PATH% | findstr /C:"%DIA_BIN%" >nul
if %ERRORLEVEL% neq 0 (
    set "PATH=%DIA_BIN%;%PATH%"
    set "PATH_CHANGED=1"
)

REM INCLUDE に追加 (常に上書き)
set "INCLUDE=%MSVC_INCLUDE%;%SDK_UCRT_INCLUDE%;%SDK_SHARED_INCLUDE%;%SDK_UM_INCLUDE%;%SDK_WINRT_INCLUDE%;%SDK_CPPWINRT_INCLUDE%;%DIA_INCLUDE%"

REM LIB に追加 (常に上書き)
set "LIB=%MSVC_LIB%;%SDK_UCRT_LIB%;%SDK_UM_LIB%;%DIA_LIB%"

if %PATH_CHANGED%==1 (
    echo VSBT PATH addition completed.
) else (
    echo VSBT PATH already set.
)

endlocal & set "PATH=%PATH%" & set "INCLUDE=%INCLUDE%" & set "LIB=%LIB%" & set "VSCMD_ARG_HOST_ARCH=%VSCMD_ARG_HOST_ARCH%" & set "VSCMD_ARG_TGT_ARCH=%VSCMD_ARG_TGT_ARCH%" & set "VCToolsVersion=%VCToolsVersion%" & set "WindowsSDKVersion=%WindowsSDKVersion%" & set "VCToolsInstallDir=%VCToolsInstallDir%" & set "WindowsSdkBinPath=%WindowsSdkBinPath%"
"@

        $cmdPath = Join-Path $scriptDir "Add-VSBT-Env-$t.cmd"
        $utf8 = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($cmdPath, $cmdContent, $utf8)
        Write-Host "  Generated: Add-VSBT-Env-$t.cmd"

        # Generate PowerShell script
        $ps1Content = @"
# VSBT PATH 動的追加スクリプト (PowerShell)
# MSVC と Windows SDK を現在のセッションの環境変数に追加します
# vswhere を使用してインスタンスを自動検出します

`$ErrorActionPreference = "Stop"
`$TargetArch = "$t"
`$HostArch = "$HostArch"

# vswhere.exe を探す
`$vswherePaths = @(
    "`${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe",
    (Join-Path (Split-Path -Parent `$MyInvocation.MyCommand.Path) "vswhere.exe"),
    "vswhere.exe"
)

`$vswhere = `$null
foreach (`$path in `$vswherePaths) {
    if (Test-Path `$path -ErrorAction SilentlyContinue) {
        `$vswhere = `$path
        break
    }
    # PATH 上の vswhere を試す
    if (`$path -eq "vswhere.exe") {
        try {
            `$null = Get-Command vswhere.exe -ErrorAction Stop
            `$vswhere = "vswhere.exe"
            break
        } catch { }
    }
}

`$vsbtBase = `$null
`$msvcVersionPath = `$null
`$sdkVersionPath = `$null

# vswhere でインスタンスを検索
if (`$vswhere) {
    try {
        `$instances = & `$vswhere -products Microsoft.VisualStudio.Product.BuildTools ``
            -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 ``
            -format json | ConvertFrom-Json

        if (`$instances -and `$instances.Count -gt 0) {
            # 最初に見つかったインスタンスを使用
            `$instance = if (`$instances -is [Array]) { `$instances[0] } else { `$instances }
            `$vsbtBase = `$instance.installationPath

            # MSVC バージョンを検出
            `$msvcToolsPath = Join-Path `$vsbtBase "VC\Tools\MSVC"
            if (Test-Path `$msvcToolsPath) {
                `$msvcVersionPath = Get-ChildItem `$msvcToolsPath | Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty Name
            }

            # Windows SDK バージョンを検出
            `$sdkBinPath = Join-Path `$vsbtBase "Windows Kits\10\bin"
            if (Test-Path `$sdkBinPath) {
                `$sdkVersionPath = Get-ChildItem `$sdkBinPath | Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty Name
            }
        }
    } catch {
        Write-Warning "vswhere failed: `$_"
    }
}

# フォールバック: スクリプトと同じディレクトリの vsbt フォルダを使用
if (-not `$vsbtBase) {
    `$scriptDir = Split-Path -Parent `$MyInvocation.MyCommand.Path
    `$vsbtBase = Join-Path `$scriptDir "vsbt"

    if (-not (Test-Path `$vsbtBase)) {
        Write-Host "Error: VSBT installation not found"
        exit 1
    }

    # MSVC バージョンを検出
    `$msvcToolsPath = Join-Path `$vsbtBase "VC\Tools\MSVC"
    if (Test-Path `$msvcToolsPath) {
        `$msvcVersionPath = Get-ChildItem `$msvcToolsPath | Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty Name
    }

    # Windows SDK バージョンを検出
    `$sdkBinPath = Join-Path `$vsbtBase "Windows Kits\10\bin"
    if (Test-Path `$sdkBinPath) {
        `$sdkVersionPath = Get-ChildItem `$sdkBinPath | Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty Name
    }
}

# バージョン検証
if (-not `$msvcVersionPath) {
    Write-Host "Error: MSVC version not detected"
    exit 1
}
if (-not `$sdkVersionPath) {
    Write-Host "Error: Windows SDK version not detected"
    exit 1
}

# パスを構築
`$msvcBin = Join-Path `$vsbtBase "VC\Tools\MSVC\`$msvcVersionPath\bin\Host`$HostArch\`$TargetArch"
`$sdkBin = Join-Path `$vsbtBase "Windows Kits\10\bin\`$sdkVersionPath\`$HostArch"
`$sdkUcrtBin = Join-Path `$vsbtBase "Windows Kits\10\bin\`$sdkVersionPath\`$HostArch\ucrt"
`$diaBin = Join-Path `$vsbtBase "DIA SDK\bin"

`$msvcInclude = Join-Path `$vsbtBase "VC\Tools\MSVC\`$msvcVersionPath\include"
`$sdkUcrtInclude = Join-Path `$vsbtBase "Windows Kits\10\Include\`$sdkVersionPath\ucrt"
`$sdkSharedInclude = Join-Path `$vsbtBase "Windows Kits\10\Include\`$sdkVersionPath\shared"
`$sdkUmInclude = Join-Path `$vsbtBase "Windows Kits\10\Include\`$sdkVersionPath\um"
`$sdkWinrtInclude = Join-Path `$vsbtBase "Windows Kits\10\Include\`$sdkVersionPath\winrt"
`$sdkCppWinrtInclude = Join-Path `$vsbtBase "Windows Kits\10\Include\`$sdkVersionPath\cppwinrt"
`$diaInclude = Join-Path `$vsbtBase "DIA SDK\include"

`$msvcLib = Join-Path `$vsbtBase "VC\Tools\MSVC\`$msvcVersionPath\lib\`$TargetArch"
`$sdkUcrtLib = Join-Path `$vsbtBase "Windows Kits\10\Lib\`$sdkVersionPath\ucrt\`$TargetArch"
`$sdkUmLib = Join-Path `$vsbtBase "Windows Kits\10\Lib\`$sdkVersionPath\um\`$TargetArch"
`$diaLib = Join-Path `$vsbtBase "DIA SDK\lib"

# MSVC パスの存在確認
if (-not (Test-Path `$msvcBin)) {
    Write-Host "Error: MSVC path not found: `$msvcBin"
    exit 1
}

# 環境変数を設定 (常に上書き)
`$env:VSCMD_ARG_HOST_ARCH = `$HostArch
`$env:VSCMD_ARG_TGT_ARCH = `$TargetArch
`$env:VCToolsVersion = `$msvcVersionPath
`$env:WindowsSDKVersion = `$sdkVersionPath
`$env:VCToolsInstallDir = Join-Path `$vsbtBase "VC\Tools\MSVC\`$msvcVersionPath"
`$env:WindowsSdkBinPath = Join-Path `$vsbtBase "Windows Kits\10\bin"

`$pathsToAdd = @(`$msvcBin, `$sdkBin, `$sdkUcrtBin, `$diaBin)
`$currentPath = `$env:PATH
`$pathChanged = `$false

foreach (`$pathToAdd in `$pathsToAdd) {
    # 既存の PATH にパスが含まれているかチェック
    `$pathExists = `$currentPath -split ';' | Where-Object { `$_ -eq `$pathToAdd }

    if (`$pathExists) {
        # Write-Host "PATH already set: `$pathToAdd"
    } else {
        # パスを先頭に追加
        `$env:PATH = "`$pathToAdd;`$env:PATH"
        `$pathChanged = `$true
    }
}

# INCLUDE と LIB は常に上書き
`$env:INCLUDE = "`$msvcInclude;`$sdkUcrtInclude;`$sdkSharedInclude;`$sdkUmInclude;`$sdkWinrtInclude;`$sdkCppWinrtInclude;`$diaInclude"
`$env:LIB = "`$msvcLib;`$sdkUcrtLib;`$sdkUmLib;`$diaLib"

if (`$pathChanged) {
    Write-Host "VSBT PATH addition completed."
} else {
    Write-Host "VSBT PATH already set."
}
"@

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
    # Clean up temp_extract (skip for ShowVersions mode)
    if (-not $ShowVersions -and (Test-Path $TempExtractPath)) {
        Write-ColorMessage "`nCleaning up temporary download folder..."
        Remove-Item $TempExtractPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}
