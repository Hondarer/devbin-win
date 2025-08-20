# Binary extraction script
# Extracts binaries from packages folder to bin directory

# Clean bin directory at startup
Write-Host "Cleaning bin directory..." -ForegroundColor Yellow
if (Test-Path "bin") {
    Remove-Item -Path "bin" -Recurse -Force
    Write-Host "Removed existing bin directory." -ForegroundColor Green
}

# Global cache for duplicate file tracking
$global:DuplicateFiles = @{}
$global:PackageFileMapping = @{}

function Get-PackageShortName {
    param([string]$PackageName)
    
    # Extract short names from package names
    if ($PackageName -match "Node\.js") { return "nodejs" }
    if ($PackageName -match "Pandoc") { return "pandoc" }
    if ($PackageName -match "pandoc-crossref") { return "pandoc-crossref" }
    if ($PackageName -match "Doxygen") { return "doxygen" }
    if ($PackageName -match "doxybook2") { return "doxybook2" }
    if ($PackageName -match "Microsoft JDK") { return "jdk" }
    if ($PackageName -match "PlantUML") { return "plantuml" }
    # Add more package name mappings as needed
    return $PackageName.ToLower() -replace '[^a-z0-9]', ''
}

function Test-SpecialPackageHandling {
    param([string]$PackageName)
    
    # Check if package requires special handling
    if ($PackageName -match "Microsoft JDK") {
        return $true
    }
    if ($PackageName -match "PlantUML") {
        return $true
    }
    return $false
}

function Get-ResolvedFileName {
    param(
        [string]$OriginalPath,
        [string]$PackageName,
        [string]$BinDir
    )
    
    $fileName = Split-Path $OriginalPath -Leaf
    $relativePath = $OriginalPath
    $packageShortName = Get-PackageShortName $PackageName
    
    # Check if this file already exists in bin directory or is marked as duplicate
    $fullDestinationPath = Join-Path $BinDir $relativePath
    
    if ($global:DuplicateFiles.ContainsKey($fileName)) {
        # This filename is already marked as duplicate, rename all instances
        $fileNameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
        $extension = [System.IO.Path]::GetExtension($fileName)
        
        $newFileName = "${fileNameWithoutExt}_${packageShortName}${extension}"
        $newRelativePath = $relativePath -replace [regex]::Escape($fileName), $newFileName
        
        Write-Host "  Renaming duplicate file: $fileName -> $newFileName" -ForegroundColor Yellow
        return $newRelativePath
    }
    elseif (Test-Path $fullDestinationPath) {
        # File exists, mark as duplicate and rename both
        Write-Host "  Duplicate file detected: $fileName" -ForegroundColor Yellow
        
        # Mark as duplicate
        $global:DuplicateFiles[$fileName] = $true
        
        # Rename existing file if it hasn't been renamed yet
        $existingPackage = $global:PackageFileMapping[$fileName]
        if ($existingPackage) {
            $existingShortName = Get-PackageShortName $existingPackage
            $fileNameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
            $extension = [System.IO.Path]::GetExtension($fileName)
            
            $existingNewFileName = "${fileNameWithoutExt}_${existingShortName}${extension}"
            $existingNewPath = Join-Path $BinDir $existingNewFileName
            
            if ((Test-Path $fullDestinationPath) -and !(Test-Path $existingNewPath)) {
                Move-Item -Path $fullDestinationPath -Destination $existingNewPath
                Write-Host "  Renamed existing file: $fileName -> $existingNewFileName" -ForegroundColor Yellow
            }
        }
        
        # Return renamed path for current file
        $fileNameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
        $extension = [System.IO.Path]::GetExtension($fileName)
        $newFileName = "${fileNameWithoutExt}_${packageShortName}${extension}"
        $newRelativePath = $relativePath -replace [regex]::Escape($fileName), $newFileName
        
        return $newRelativePath
    }
    else {
        # No conflict, track the file-package mapping
        $global:PackageFileMapping[$fileName] = $PackageName
        return $relativePath
    }
}

function Extract-Package {
    param(
        [string]$ArchiveFile,
        [string]$PackageName,
        [string]$BinDir = "bin",
        [string]$TempDir = "temp_extract"
    )
    
    Write-Host "Starting $PackageName binary extraction..." -ForegroundColor Green
    
    # Check if archive file exists
    if (!(Test-Path $ArchiveFile)) {
        Write-Host "Error: $ArchiveFile not found." -ForegroundColor Red
        Write-Host "Please download $PackageName and place it in the packages folder." -ForegroundColor Yellow
        return $false
    }
    
    Write-Host "Archive file found: $ArchiveFile" -ForegroundColor Green
    
    # Special handling for PlantUML JAR files
    if ($PackageName -match "PlantUML" -and $ArchiveFile -match "\.jar$") {
        Write-Host "Detected PlantUML JAR file, applying special handling..." -ForegroundColor Yellow
        
        # Create bin directory if it doesn't exist
        if (!(Test-Path $BinDir)) {
            New-Item -ItemType Directory -Path $BinDir
            Write-Host "Created bin directory." -ForegroundColor Green
        }
        
        # Extract JAR file name
        $jarFileName = Split-Path $ArchiveFile -Leaf
        Write-Host "PlantUML JAR file: $jarFileName" -ForegroundColor Green
        
        # Copy JAR file to bin directory
        $jarDestination = Join-Path $BinDir $jarFileName
        Copy-Item -Path $ArchiveFile -Destination $jarDestination -Force
        Write-Host "Copied $jarFileName to bin directory" -ForegroundColor Green
        
        # Create plantuml.cmd batch file
        $cmdContent = @"
@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "JAVA_HOME=%SCRIPT_DIR%jdk-21"
"%JAVA_HOME%\bin\java.exe" -jar "%SCRIPT_DIR%$jarFileName" %*

endlocal
"@
        
        $cmdPath = Join-Path $BinDir "plantuml.cmd"
        $cmdContent | Out-File -FilePath $cmdPath -Encoding ASCII
        Write-Host "Created plantuml.cmd wrapper script" -ForegroundColor Green
        Write-Host "PlantUML can be run with: plantuml.cmd" -ForegroundColor Cyan
        
        Write-Host "$PackageName binary extraction completed." -ForegroundColor Green
        return $true
    }
    
    # Create bin directory
    if (!(Test-Path $BinDir)) {
        New-Item -ItemType Directory -Path $BinDir
        Write-Host "Created bin directory." -ForegroundColor Green
    }
    
    # Create temporary directory
    if (Test-Path $TempDir) {
        Remove-Item -Path $TempDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $TempDir
    
    try {
        Write-Host "Extracting archive file..." -ForegroundColor Yellow
        
        # Determine file type and extract accordingly
        $fileExtension = [System.IO.Path]::GetExtension($ArchiveFile).ToLower()
        
        if ($fileExtension -eq ".zip") {
            # Extract ZIP file to temporary directory
            Expand-Archive -Path $ArchiveFile -DestinationPath $TempDir -Force
        }
        elseif ($fileExtension -eq ".7z") {
            # Extract 7z file using Windows built-in tar.exe (libarchive)
            try {
                $tarPath = "$env:WINDIR\System32\tar.exe"
                if (Test-Path $tarPath) {
                    Write-Host "Using Windows built-in tar.exe (libarchive) for .7z extraction..." -ForegroundColor Yellow
                    
                    # Use tar.exe with libarchive to extract .7z file
                    $absoluteArchive = (Resolve-Path $ArchiveFile).Path
                    $absoluteTempDir = (Resolve-Path $TempDir).Path
                    
                    & $tarPath -xf $absoluteArchive -C $absoluteTempDir
                    
                    if ($LASTEXITCODE -ne 0) {
                        throw "tar.exe extraction failed with exit code: $LASTEXITCODE"
                    }
                    
                    Write-Host "Successfully extracted .7z file using tar.exe" -ForegroundColor Green
                } else {
                    throw "tar.exe not found at expected location: $tarPath"
                }
            }
            catch {
                Write-Host "Error: 7z extraction failed using tar.exe." -ForegroundColor Red
                Write-Host "Details: $($_.Exception.Message)" -ForegroundColor Red
                
                # Fallback: Try 7z command if available
                if (Get-Command "7z" -ErrorAction SilentlyContinue) {
                    Write-Host "Trying fallback with 7z command..." -ForegroundColor Yellow
                    try {
                        & 7z x $ArchiveFile -o"$TempDir" -y | Out-Null
                        if ($LASTEXITCODE -eq 0) {
                            Write-Host "Successfully extracted using 7z fallback." -ForegroundColor Green
                        } else {
                            throw "7z fallback failed"
                        }
                    }
                    catch {
                        Write-Host "Error: All 7z extraction methods failed." -ForegroundColor Red
                        Write-Host "Please install 7-Zip: https://www.7-zip.org/" -ForegroundColor Yellow
                        return $false
                    }
                } else {
                    Write-Host "No fallback available. Please install 7-Zip: https://www.7-zip.org/" -ForegroundColor Yellow
                    return $false
                }
            }
        }
        else {
            Write-Host "Error: Unsupported file type: $fileExtension" -ForegroundColor Red
            return $false
        }
        
        # Find extracted folder or files
        $extractedItems = Get-ChildItem -Path $TempDir
        $extractedFolder = $extractedItems | Where-Object { $_.PSIsContainer } | Select-Object -First 1
        
        # If no folder found, check if there are files directly in temp directory
        if (-not $extractedFolder -and ($extractedItems | Where-Object { -not $_.PSIsContainer })) {
            # Files are directly in temp directory, use temp directory as source
            $sourcePath = $TempDir
            Write-Host "Files extracted directly to temp directory: $sourcePath" -ForegroundColor Green
        }
        elseif ($extractedFolder) {
            $sourcePath = $extractedFolder.FullName
            Write-Host "Extracted folder: $sourcePath" -ForegroundColor Green
        }
        
        if ($sourcePath) {
            # Check if this package requires special handling
            $isSpecialPackage = Test-SpecialPackageHandling -PackageName $PackageName
            
            if ($isSpecialPackage -and $PackageName -match "Microsoft JDK") {
                # Special handling for Microsoft JDK
                Write-Host "Applying special JDK handling..." -ForegroundColor Yellow
                
                # Find the JDK folder (e.g., jdk-21.0.8+9)
                # Check if the sourcePath itself is a JDK folder
                if ((Split-Path $sourcePath -Leaf) -match "^jdk-\d+") {
                    # The extracted folder is the JDK folder itself
                    $jdkFolder = Get-Item $sourcePath
                    Write-Host "Source path is JDK folder: $($jdkFolder.Name)" -ForegroundColor Green
                } else {
                    # Look for JDK folder inside the source path
                    $jdkFolder = Get-ChildItem -Path $sourcePath -Directory | Where-Object { $_.Name -match "^jdk-\d+" } | Select-Object -First 1
                }
                
                if ($jdkFolder) {
                    Write-Host "Found JDK folder: $($jdkFolder.Name)" -ForegroundColor Green
                    
                    # Extract major version and create target folder name (e.g., jdk-21)
                    if ($jdkFolder.Name -match "^jdk-(\d+)") {
                        $majorVersion = $matches[1]
                        $targetFolderName = "jdk-$majorVersion"
                        $targetPath = Join-Path $BinDir $targetFolderName
                        
                        Write-Host "Creating target directory: $targetFolderName" -ForegroundColor Green
                        
                        # Create target directory
                        if (!(Test-Path $targetPath)) {
                            New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
                        }
                        
                        # Copy JDK folder contents to target directory
                        Get-ChildItem -Path $jdkFolder.FullName -Recurse | ForEach-Object {
                            $relativePath = $_.FullName.Substring($jdkFolder.FullName.Length + 1)
                            $destinationPath = Join-Path $targetPath $relativePath
                            
                            if ($_.PSIsContainer) {
                                if (!(Test-Path $destinationPath)) {
                                    New-Item -ItemType Directory -Path $destinationPath -Force | Out-Null
                                }
                            } else {
                                $destinationDir = Split-Path $destinationPath -Parent
                                if ($destinationDir -and !(Test-Path $destinationDir)) {
                                    New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
                                }
                                Copy-Item -Path $_.FullName -Destination $destinationPath -Force
                            }
                        }
                        
                        Write-Host "JDK installed to: $targetPath" -ForegroundColor Green
                    } else {
                        Write-Host "Warning: Could not extract major version from JDK folder name: $($jdkFolder.Name)" -ForegroundColor Yellow
                    }
                } else {
                    Write-Host "Warning: JDK folder not found in extracted archive" -ForegroundColor Yellow
                }
            } else {
                # Standard handling for other packages
                Get-ChildItem -Path $sourcePath -Recurse | ForEach-Object {
                    if ($sourcePath -eq $TempDir) {
                        # Files are directly in temp directory
                        $relativePath = $_.Name
                    } else {
                        # Files are in a subdirectory
                        $relativePath = $_.FullName.Substring($sourcePath.Length + 1)
                    }
                    
                    if ($_.PSIsContainer) {
                        # Directory case - no renaming needed for directories
                        $destinationPath = Join-Path $BinDir $relativePath
                        if (!(Test-Path $destinationPath)) {
                            New-Item -ItemType Directory -Path $destinationPath -Force | Out-Null
                        }
                    } else {
                        # File case - check for duplicates and resolve
                        $resolvedPath = Get-ResolvedFileName -OriginalPath $relativePath -PackageName $PackageName -BinDir $BinDir
                        $destinationPath = Join-Path $BinDir $resolvedPath
                        
                        $destinationDir = Split-Path $destinationPath -Parent
                        if ($destinationDir -and !(Test-Path $destinationDir)) {
                            New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
                        }
                        Copy-Item -Path $_.FullName -Destination $destinationPath -Force
                    }
                }
            }
            
            Write-Host "$PackageName binary extraction completed." -ForegroundColor Green
            return $true
        } else {
            Write-Host "Error: Extracted folder not found." -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "Error: Failed to extract archive file." -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        return $false
    } finally {
        # Clean up temporary directory
        if (Test-Path $TempDir) {
            Remove-Item -Path $TempDir -Recurse -Force
            Write-Host "Temporary directory cleaned up." -ForegroundColor Green
        }
    }
}

# Extract packages
Write-Host "Starting package extraction process..." -ForegroundColor Cyan

$extractionResults = @()

# Extract Node.js
$nodeResult = Extract-Package -ArchiveFile "packages\node-v22.18.0-win-x64.zip" -PackageName "Node.js v22.18.0"
$extractionResults += $nodeResult

# Extract Pandoc
$pandocResult = Extract-Package -ArchiveFile "packages\pandoc-3.7.0.2-windows-x86_64.zip" -PackageName "Pandoc 3.7.0.2"
$extractionResults += $pandocResult

# Extract pandoc-crossref
$crossrefResult = Extract-Package -ArchiveFile "packages\pandoc-crossref-Windows-X64.7z" -PackageName "pandoc-crossref"
$extractionResults += $crossrefResult

# Extract Doxygen
$doxygenResult = Extract-Package -ArchiveFile "packages\doxygen-1.14.0.windows.x64.bin.zip" -PackageName "Doxygen 1.14.0"
$extractionResults += $doxygenResult

# Extract doxybook2
$doxybook2Result = Extract-Package -ArchiveFile "packages\doxybook2-windows-win64-v1.6.1.zip" -PackageName "doxybook2 v1.6.1"
$extractionResults += $doxybook2Result

# Extract Microsoft JDK
$jdkResult = Extract-Package -ArchiveFile "packages\microsoft-jdk-21.0.8-windows-x64.zip" -PackageName "Microsoft JDK 21.0.8"
$extractionResults += $jdkResult

# Extract PlantUML
$plantumlResult = Extract-Package -ArchiveFile "packages\plantuml-1.2025.4.jar" -PackageName "PlantUML 1.2025.4"
$extractionResults += $plantumlResult

# Check overall result
$successfulExtractions = ($extractionResults | Where-Object { $_ -eq $true }).Count
$totalPackages = $extractionResults.Count

Write-Host "`nExtraction Summary:" -ForegroundColor Cyan
Write-Host "Successful: $successfulExtractions / $totalPackages" -ForegroundColor Green

if ($successfulExtractions -eq $totalPackages) {
    Write-Host "All packages extracted successfully." -ForegroundColor Green
} else {
    Write-Host "Some packages failed to extract." -ForegroundColor Red
    exit 1
}
