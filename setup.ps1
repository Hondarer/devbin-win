# Development Tools Setup Script
# Extracts, installs, or uninstalls development tools

param(
    [string]$InstallDir = ".\bin",
    [switch]$Extract,
    [switch]$Install,
    [switch]$Uninstall
)

# Show usage if no options specified
if (-not ($Extract -or $Install -or $Uninstall)) {
    Write-Host "Development Tools Setup Script"
    Write-Host "================================"
    Write-Host ""
    Write-Host "Usage:"
    Write-Host "  .\setup.ps1 -Extract [-InstallDir <path>]    # Extract tools only"
    Write-Host "  .\setup.ps1 -Install [-InstallDir <path>]    # Extract tools and add to PATH"
    Write-Host "  .\setup.ps1 -Uninstall [-InstallDir <path>]  # Remove tools and clean PATH"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -InstallDir <path>  Installation directory (default: .\bin)"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\setup.ps1 -Extract                         # Extract to .\bin"
    Write-Host "  .\setup.ps1 -Install -InstallDir C:\Tools    # Install to C:\Tools"
    Write-Host "  .\setup.ps1 -Uninstall                       # Uninstall from .\bin"
    exit 0
}

# Function to get PATH directories that should be added/removed
function Get-PathDirectories {
    param([string]$BaseDir)
    
    $pathDirs = @(
        $BaseDir,
        "$BaseDir\jdk-21\bin",
        "$BaseDir\python-3.13",
        "$BaseDir\git\bin",
        "$BaseDir\git\cmd",
        "$BaseDir\git\mingw64\bin",
        "$BaseDir\git\usr\bin"
    )
    
    return $pathDirs
}

# Function to check if a command is already available in PATH
function Test-CommandExists {
    param([string]$CommandName)
    try {
        Get-Command $CommandName -ErrorAction Stop | Out-Null
        return $true
    } catch {
        return $false
    }
}

# Function to add directories to user PATH
function Add-ToUserPath {
    param([string[]]$Directories)
    
    Write-Host "Adding directories to user PATH..."
    
    $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if (-not $currentPath) {
        $currentPath = ""
    }
    
    $pathChanged = $false
    foreach ($dir in $Directories) {
        $absolutePath = (Resolve-Path $dir -ErrorAction SilentlyContinue)
        if ($absolutePath -and (Test-Path $absolutePath)) {
            $dirPath = $absolutePath.Path
            $shouldSkip = $false
            
            # Check for existing commands and skip specific paths
            if ($dirPath -like "*jdk-*\bin") {
                if (Test-CommandExists "java") {
                    Write-Host "  Skipped (java.exe already available): $dirPath"
                    $shouldSkip = $true
                }
            }
            elseif ($dirPath -like "*python-*") {
                if (Test-CommandExists "python") {
                    Write-Host "  Skipped (python.exe already available): $dirPath"
                    $shouldSkip = $true
                }
            }
            elseif ($dirPath -like "*git\bin" -or $dirPath -like "*git\mingw64\bin" -or $dirPath -like "*git\usr\bin" -or $dirPath -like "*git\cmd") {
                if (Test-CommandExists "git") {
                    Write-Host "  Skipped (git.exe already available): $dirPath"
                    $shouldSkip = $true
                }
            }
            
            if (-not $shouldSkip) {
                # Since we pre-remove entries, we can directly add without duplicate check
                if ($currentPath) {
                    $currentPath = "$dirPath;$currentPath"
                } else {
                    $currentPath = $dirPath
                }
                Write-Host "  Added: $dirPath"
                $pathChanged = $true
            }
        } else {
            Write-Host "  Directory not found: $dir"
        }
    }
    
    if ($pathChanged) {
        [Environment]::SetEnvironmentVariable("PATH", $currentPath, "User")
        Write-Host "User PATH updated successfully."
        Write-Host "Note: Restart your terminal for PATH changes to take effect."
    } else {
        Write-Host "No PATH changes needed."
    }
}

# Function to remove directories from user PATH
function Remove-FromUserPath {
    param([string[]]$Directories)
    
    Write-Host "Removing directories from user PATH..."
    
    $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if (-not $currentPath) {
        Write-Host "User PATH is empty."
        return
    }
    
    $pathChanged = $false
    $pathEntries = $currentPath -split ';'
    $newPathEntries = @()
    
    foreach ($entry in $pathEntries) {
        $shouldRemove = $false
        foreach ($dir in $Directories) {
            $absolutePath = (Resolve-Path $dir -ErrorAction SilentlyContinue)
            if ($absolutePath -and ($entry -eq $absolutePath.Path)) {
                Write-Host "  Removed: $entry"
                $shouldRemove = $true
                $pathChanged = $true
                break
            }
        }
        if (-not $shouldRemove -and $entry.Trim() -ne "") {
            $newPathEntries += $entry
        }
    }
    
    if ($pathChanged) {
        $newPath = $newPathEntries -join ';'
        [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
        Write-Host "User PATH updated successfully."
    } else {
        Write-Host "No matching directories found in PATH."
    }
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
    if ($PackageName -match "Python") { return "python" }
    
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
    if ($PackageName -match "Python") {
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
        
        Write-Host "  Renaming duplicate file: $fileName -> $newFileName"
        return $newRelativePath
    }
    elseif (Test-Path $fullDestinationPath) {
        # File exists, mark as duplicate and rename both
        Write-Host "  Duplicate file detected: $fileName"
        
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
                Write-Host "  Renamed existing file: $fileName -> $existingNewFileName"
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
        [string]$BinDir = $InstallDir,
        [string]$TempDir = "temp_extract"
    )
    
    Write-Host "Starting $PackageName binary extraction..."
    
    # Check if archive file exists
    if (!(Test-Path $ArchiveFile)) {
        Write-Host "Error: $ArchiveFile not found."
        Write-Host "Please download $PackageName and place it in the packages folder."
        return $false
    }
    
    Write-Host "Archive file found: $ArchiveFile"
    
    # Unblock the archive file to prevent security restrictions
    try {
        Unblock-File -Path $ArchiveFile -ErrorAction SilentlyContinue
    } catch {
        # Silently continue if unblocking fails
    }
    
    # Special handling for PlantUML JAR files
    if ($PackageName -match "PlantUML" -and $ArchiveFile -match "\.jar$") {
        Write-Host "Detected PlantUML JAR file, applying special handling..."
        
        # Create bin directory if it doesn't exist
        if (!(Test-Path $BinDir)) {
            New-Item -ItemType Directory -Path $BinDir
            Write-Host "Created bin directory."
        }
        
        # Extract JAR file name
        $jarFileName = Split-Path $ArchiveFile -Leaf
        Write-Host "PlantUML JAR file: $jarFileName"
        
        # Copy JAR file to bin directory with generic name
        $jarDestination = Join-Path $BinDir "plantuml.jar"
        Copy-Item -Path $ArchiveFile -Destination $jarDestination -Force
        Write-Host "Copied $jarFileName to bin directory as plantuml.jar"
        
        # Create plantuml.cmd batch file
        $cmdContent = @"
@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "JAVA_HOME=%SCRIPT_DIR%jdk-21"
"%JAVA_HOME%\bin\java.exe" -jar "%SCRIPT_DIR%plantuml.jar" %*

endlocal
"@
        
        $cmdPath = Join-Path $BinDir "plantuml.cmd"
        $cmdContent | Out-File -FilePath $cmdPath -Encoding ASCII
        Write-Host "Created plantuml.cmd wrapper script"
        Write-Host "PlantUML can be run with: plantuml.cmd"
        
        Write-Host "$PackageName binary extraction completed."
        return $true
    }
    
    # Create bin directory
    if (!(Test-Path $BinDir)) {
        New-Item -ItemType Directory -Path $BinDir
        Write-Host "Created bin directory."
    }
    
    # Create temporary directory
    if (Test-Path $TempDir) {
        Remove-Item -Path $TempDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $TempDir
    
    try {
        Write-Host "Extracting archive file..."
        
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
                    Write-Host "Using Windows built-in tar.exe (libarchive) for .7z extraction..."
                    
                    # Use tar.exe with libarchive to extract .7z file
                    $absoluteArchive = (Resolve-Path $ArchiveFile).Path
                    $absoluteTempDir = (Resolve-Path $TempDir).Path
                    
                    & $tarPath -xf $absoluteArchive -C $absoluteTempDir
                    
                    if ($LASTEXITCODE -ne 0) {
                        throw "tar.exe extraction failed with exit code: $LASTEXITCODE"
                    }
                    
                    Write-Host "Successfully extracted .7z file using tar.exe"
                } else {
                    throw "tar.exe not found at expected location: $tarPath"
                }
            }
            catch {
                Write-Host "Error: 7z extraction failed using tar.exe."
                Write-Host "Details: $($_.Exception.Message)"
                
                # Fallback: Try 7z command if available
                if (Get-Command "7z" -ErrorAction SilentlyContinue) {
                    Write-Host "Trying fallback with 7z command..."
                    try {
                        & 7z x $ArchiveFile -o"$TempDir" -y | Out-Null
                        if ($LASTEXITCODE -eq 0) {
                            Write-Host "Successfully extracted using 7z fallback."
                        } else {
                            throw "7z fallback failed"
                        }
                    }
                    catch {
                        Write-Host "Error: All 7z extraction methods failed."
                        Write-Host "Please install 7-Zip: https://www.7-zip.org/"
                        return $false
                    }
                } else {
                    Write-Host "No fallback available. Please install 7-Zip: https://www.7-zip.org/"
                    return $false
                }
            }
        }
        else {
            Write-Host "Error: Unsupported file type: $fileExtension"
            return $false
        }
        
        # Find extracted folder or files
        $extractedItems = Get-ChildItem -Path $TempDir
        $extractedFolder = $extractedItems | Where-Object { $_.PSIsContainer } | Select-Object -First 1
        
        # If no folder found, check if there are files directly in temp directory
        if (-not $extractedFolder -and ($extractedItems | Where-Object { -not $_.PSIsContainer })) {
            # Files are directly in temp directory, use temp directory as source
            $sourcePath = $TempDir
            Write-Host "Files extracted directly to temp directory: $sourcePath"
        }
        elseif ($extractedFolder) {
            $sourcePath = $extractedFolder.FullName
            Write-Host "Extracted folder: $sourcePath"
        }
        
        if ($sourcePath) {
            # Check if this package requires special handling
            $isSpecialPackage = Test-SpecialPackageHandling -PackageName $PackageName
            
            if ($isSpecialPackage -and $PackageName -match "Microsoft JDK") {
                # Special handling for Microsoft JDK
                Write-Host "Applying special JDK handling..."
                
                # Find the JDK folder (e.g., jdk-21.0.8+9)
                # Check if the sourcePath itself is a JDK folder
                if ((Split-Path $sourcePath -Leaf) -match "^jdk-\d+") {
                    # The extracted folder is the JDK folder itself
                    $jdkFolder = Get-Item $sourcePath
                    Write-Host "Source path is JDK folder: $($jdkFolder.Name)"
                } else {
                    # Look for JDK folder inside the source path
                    $jdkFolder = Get-ChildItem -Path $sourcePath -Directory | Where-Object { $_.Name -match "^jdk-\d+" } | Select-Object -First 1
                }
                
                if ($jdkFolder) {
                    Write-Host "Found JDK folder: $($jdkFolder.Name)"
                    
                    # Extract major version and create target folder name (e.g., jdk-21)
                    if ($jdkFolder.Name -match "^jdk-(\d+)") {
                        $majorVersion = $matches[1]
                        $targetFolderName = "jdk-$majorVersion"
                        $targetPath = Join-Path $BinDir $targetFolderName
                        
                        Write-Host "Creating target directory: $targetFolderName"
                        
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
                        
                        Write-Host "JDK installed to: $targetPath"
                    } else {
                        Write-Host "Warning: Could not extract major version from JDK folder name: $($jdkFolder.Name)"
                    }
                } else {
                    Write-Host "Warning: JDK folder not found in extracted archive"
                }
            }
            elseif ($isSpecialPackage -and $PackageName -match "Python") {
                # Special handling for Python embeddable package
                Write-Host "Applying special Python embeddable package handling..."
                
                # Extract major.minor version from package name or archive name
                $pythonVersion = "3.13"  # Default version
                if ($ArchiveFile -match "python-(\d+\.\d+)") {
                    $pythonVersion = $matches[1]
                }
                
                $targetFolderName = "python-$pythonVersion"
                $targetPath = Join-Path $BinDir $targetFolderName
                
                Write-Host "Creating target directory: $targetFolderName"
                
                # Create target directory
                if (!(Test-Path $targetPath)) {
                    New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
                }
                
                # Copy Python files to target directory
                # For Python embeddable package, files might be directly in sourcePath or in a subdirectory
                if ($sourcePath -eq $TempDir) {
                    # Files are directly in temp directory
                    Get-ChildItem -Path $sourcePath -File | ForEach-Object {
                        $destinationPath = Join-Path $targetPath $_.Name
                        Copy-Item -Path $_.FullName -Destination $destinationPath -Force
                    }
                } else {
                    # Files are in a subdirectory
                    Get-ChildItem -Path $sourcePath -Recurse | ForEach-Object {
                        $relativePath = $_.FullName.Substring($sourcePath.Length + 1)
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
                }
                
                Write-Host "Python installed to: $targetPath"
                
                # Copy get-pip.py if it exists
                $getPipPath = "packages\get-pip.py"
                if (Test-Path $getPipPath) {
                    $getPipDestination = Join-Path $targetPath "get-pip.py"
                    Copy-Item -Path $getPipPath -Destination $getPipDestination -Force
                    Write-Host "Copied get-pip.py to Python directory"
                    
                    # Patch pth file to enable site-packages
                    $pthFiles = Get-ChildItem -Path $targetPath -Filter "*._pth"
                    foreach ($pthFile in $pthFiles) {
                        Write-Host "Patching pth file: $($pthFile.Name)"
                        
                        $pthContent = Get-Content $pthFile.FullName
                        $newContent = @()
                        $sitePackagesAdded = $false
                        
                        foreach ($line in $pthContent) {
                            # Skip comment lines about import site
                            if ($line -match "^#.*import.*site") {
                                continue
                            }
                            # Skip "Uncomment to run site.main()" comment
                            elseif ($line -match "^#.*Uncomment.*site\.main") {
                                continue
                            }
                            # Skip existing import site line to add it at the end
                            elseif ($line -match "^import\s+site") {
                                continue
                            } else {
                                $newContent += $line
                            }
                            
                            # Check if site-packages is already present
                            if ($line -match "Lib\\site-packages") {
                                $sitePackagesAdded = $true
                            }
                        }
                        
                        # Add standard library zip first
                        $zipFiles = Get-ChildItem -Path $targetPath -Filter "python*.zip"
                        if ($zipFiles) {
                            $zipFile = $zipFiles[0].Name
                            if (-not ($newContent -contains $zipFile)) {
                                $newContent = @($zipFile) + $newContent
                                Write-Host "  Added standard library: $zipFile"
                            }
                        }
                        
                        # Add site-packages if not found
                        if (-not $sitePackagesAdded) {
                            $newContent += "Lib\site-packages"
                            Write-Host "  Added Lib\site-packages path"
                        }
                        
                        # Add import site at the end (with proper comment)
                        $newContent += ""
                        $newContent += "# Uncomment to run site.main() automatically"
                        $newContent += "import site"
                        Write-Host "  Enabled 'import site'"
                        
                        # Write back the modified content (UTF-8 without BOM)
                        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
                        [System.IO.File]::WriteAllText($pthFile.FullName, ($newContent -join "`r`n"), $utf8NoBom)
                    }
                    
                    # Install pip
                    Write-Host "Installing pip..."
                    $pythonExe = Join-Path $targetPath "python.exe"
                    if (Test-Path $pythonExe) {
                        try {
                            & $pythonExe $getPipDestination --no-warn-script-location
                            if ($LASTEXITCODE -eq 0) {
                                Write-Host "pip installed successfully"
                            } else {
                                Write-Host "Warning: pip installation may have issues (exit code: $LASTEXITCODE)"
                            }
                        } catch {
                            Write-Host "Warning: Failed to install pip: $($_.Exception.Message)"
                        } finally {
                            # Clean up environment variables
                            Remove-Item Env:PYTHONHOME -ErrorAction SilentlyContinue
                            Remove-Item Env:PYTHONPATH -ErrorAction SilentlyContinue
                        }
                    } else {
                        Write-Host "Warning: python.exe not found, skipping pip installation"
                    }
                } else {
                    Write-Host "Warning: get-pip.py not found, skipping pip installation"
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
            
            Write-Host "$PackageName binary extraction completed."
            return $true
        } else {
            Write-Host "Error: Extracted folder not found."
            return $false
        }
    } catch {
        Write-Host "Error: Failed to extract archive file."
        Write-Host $_.Exception.Message
        return $false
    } finally {
        # Clean up temporary directory
        if (Test-Path $TempDir) {
            Remove-Item -Path $TempDir -Recurse -Force
            Write-Host "Temporary directory cleaned up."
        }
    }
}

# Main execution based on options
if ($Uninstall) {
    # Uninstall: Remove directories and clean PATH
    Write-Host "Starting uninstall process..."
    
    # Remove from PATH first
    $pathDirs = Get-PathDirectories -BaseDir $InstallDir
    Remove-FromUserPath -Directories $pathDirs
    
    # Remove installation directory
    if (Test-Path $InstallDir) {
        Write-Host "Removing installation directory: $InstallDir"
        Remove-Item -Path $InstallDir -Recurse -Force
        Write-Host "Installation directory removed."
    } else {
        Write-Host "Installation directory not found: $InstallDir"
    }
    
    Write-Host "Uninstall completed." -ForegroundColor Green
    exit 0
}

# For Extract or Install, perform extraction
if ($Extract -or $Install) {
    # Clean bin directory at startup
    Write-Host "Cleaning installation directory: $InstallDir"
    if (Test-Path $InstallDir) {
        Remove-Item -Path $InstallDir -Recurse -Force
        Write-Host "Removed existing installation directory."
    }
    
    # Unblock all package files first
    Write-Host "Unblocking package files..."
    $packageFiles = Get-ChildItem -Path "packages" -File
    foreach ($packageFile in $packageFiles) {
        try {
            # Try to unblock the file directly (safer approach)
            $beforeAttribs = (Get-Item $packageFile.FullName).Attributes
            Unblock-File -Path $packageFile.FullName -ErrorAction SilentlyContinue
            $afterAttribs = (Get-Item $packageFile.FullName).Attributes
            
            # If attributes changed, the file was likely blocked
            if ($beforeAttribs -ne $afterAttribs) {
                Write-Host "Unblocked: $($packageFile.Name)"
            }
        } catch {
            # Silently continue if unblocking fails
        }
    }
    Write-Host "Package file unblocking completed."

    # Extract packages
    Write-Host "Starting package extraction process..."

    $extractionResults = @()

    # Extract Node.js
    $nodeOutput = Extract-Package -ArchiveFile "packages\node-v22.18.0-win-x64.zip" -PackageName "Node.js v22.18.0" -BinDir $InstallDir
    $extractionResults += @($nodeOutput[-1])

    # Extract Pandoc  
    $pandocOutput = Extract-Package -ArchiveFile "packages\pandoc-3.7.0.2-windows-x86_64.zip" -PackageName "Pandoc 3.7.0.2" -BinDir $InstallDir
    $extractionResults += @($pandocOutput[-1])

    # Extract pandoc-crossref
    $crossrefOutput = Extract-Package -ArchiveFile "packages\pandoc-crossref-Windows-X64.7z" -PackageName "pandoc-crossref" -BinDir $InstallDir
    $extractionResults += @($crossrefOutput[-1])

    # Extract Doxygen
    $doxygenOutput = Extract-Package -ArchiveFile "packages\doxygen-1.14.0.windows.x64.bin.zip" -PackageName "Doxygen 1.14.0" -BinDir $InstallDir
    $extractionResults += @($doxygenOutput[-1])

    # Extract doxybook2
    $doxybook2Output = Extract-Package -ArchiveFile "packages\doxybook2-windows-win64-v1.6.1.zip" -PackageName "doxybook2 v1.6.1" -BinDir $InstallDir
    $extractionResults += @($doxybook2Output[-1])

    # Extract Microsoft JDK
    $jdkOutput = Extract-Package -ArchiveFile "packages\microsoft-jdk-21.0.8-windows-x64.zip" -PackageName "Microsoft JDK 21.0.8" -BinDir $InstallDir
    $extractionResults += @($jdkOutput[-1])

    # Extract PlantUML
    $plantumlOutput = Extract-Package -ArchiveFile "packages\plantuml-1.2025.4.jar" -PackageName "PlantUML 1.2025.4" -BinDir $InstallDir
    $extractionResults += @($plantumlOutput[-1])

    # Extract Python
    $pythonOutput = Extract-Package -ArchiveFile "packages\python-3.13.7-embed-amd64.zip" -PackageName "Python 3.13.7" -BinDir $InstallDir
    $extractionResults += @($pythonOutput[-1])

    # Extract Portable Git
    Write-Host "Starting Portable Git extraction..."
    $gitArchiveFile = "packages\PortableGit-2.51.0-64-bit.7z.exe"
    if (Test-Path $gitArchiveFile) {
        Write-Host "Archive file found: $gitArchiveFile"
        
        # Create git directory in bin folder
        $gitBinDir = "$InstallDir\git"
        if (!(Test-Path $gitBinDir)) {
            New-Item -ItemType Directory -Path $gitBinDir -Force | Out-Null
            Write-Host "Created git directory: $gitBinDir"
        }
        
        # Extract using the self-extracting executable (wait for completion)
        Write-Host "Extracting Portable Git (this may take a moment)..."
        $process = Start-Process -FilePath $gitArchiveFile -ArgumentList "-y", "-o$(Resolve-Path $gitBinDir)" -Wait -PassThru
        
        if ($process.ExitCode -eq 0) {
            Write-Host "Portable Git extracted successfully to: $gitBinDir"
            $extractionResults += @($true)
        } else {
            Write-Host "Error: Portable Git extraction failed with exit code: $($process.ExitCode)"
            $extractionResults += @($false)
        }
    } else {
        Write-Host "Error: $gitArchiveFile not found."
        Write-Host "Please download Portable Git and place it in the packages folder."
        $extractionResults += @($false)
    }

    # Check overall result
    $successfulExtractions = ($extractionResults | Where-Object { $_ -eq $true }).Count
    $totalPackages = $extractionResults.Count

    Write-Host "`nExtraction Summary:"
    Write-Host "Success: $successfulExtractions / $totalPackages"

    if ($successfulExtractions -eq $totalPackages) {
        Write-Host "`nAll packages extracted successfully."
        
        # If Install option, add to PATH
        if ($Install) {
            Write-Host "`nManaging PATH environment variables..."
            $pathDirs = Get-PathDirectories -BaseDir $InstallDir
            
            # Remove existing entries first (for reinstall scenarios)
            Write-Host "Removing any existing PATH entries..."
            Remove-FromUserPath -Directories $pathDirs
            
            # Add fresh entries
            Write-Host "Adding tools to PATH..."
            Add-ToUserPath -Directories $pathDirs
            Write-Host "Installation completed." -ForegroundColor Green
        } else {
            Write-Host "Extraction completed." -ForegroundColor Green
        }
    } else {
        Write-Host "`nSome packages failed to extract." -ForegroundColor Yellow
        exit 1
    }
}
