@{
    Packages = @(
        # Node.js - Standard extraction
        @{
            Name = "Node.js"
            ShortName = "nodejs"
            Version = "25.9.0"
            ArchivePattern = "node-v.*-win-x64\.zip$"
            ExtractStrategy = "Standard"
            DownloadUrl = "https://nodejs.org/dist/v25.9.0/node-v25.9.0-win-x64.zip"
            DependsOn = @()
            PathDirs = @()
            EnvVars = @{}
            DetectFiles = @("node.exe")
            DefaultChecked = $true
        },

        # Pandoc - Standard extraction
        @{
            Name = "Pandoc"
            ShortName = "pandoc"
            Version = "3.9.0.2"
            ArchivePattern = "pandoc-.*-windows-x86_64\.zip$"
            ExtractStrategy = "Standard"
            DownloadUrl = "https://github.com/jgm/pandoc/releases/download/3.9.0.2/pandoc-3.9.0.2-windows-x86_64.zip"
            DependsOn = @()
            PathDirs = @()
            EnvVars = @{}
            DetectFiles = @("pandoc.exe")
            DefaultChecked = $true
        },

        # pandoc-crossref - Standard extraction
        @{
            Name = "pandoc-crossref"
            ShortName = "pandoc-crossref"
            Version = "0.3.23a"
            ArchivePattern = "pandoc-crossref-Windows-X64-.*\.7z$"
            ExtractStrategy = "Standard"
            DownloadUrl = "https://github.com/lierdakil/pandoc-crossref/releases/download/v0.3.23a/pandoc-crossref-Windows-X64.7z"
            DependsOn = @("pandoc")
            PathDirs = @()
            EnvVars = @{}
            DetectFiles = @("pandoc-crossref.exe")
            DefaultChecked = $true
        },

        # Doxygen - Standard extraction
        @{
            Name = "Doxygen"
            ShortName = "doxygen"
            Version = "1.15.0"
            ArchivePattern = "doxygen-.*\.windows\.x64\.bin\.zip$"
            ExtractStrategy = "Standard"
            DownloadUrl = "https://www.doxygen.nl/files/doxygen-1.15.0.windows.x64.bin.zip"
            DependsOn = @()
            PathDirs = @()
            EnvVars = @{}
            DetectFiles = @("doxygen.exe")
            DefaultChecked = $true
        },

        # doxybook2 - Subdirectory extraction
        @{
            Name = "doxybook2"
            ShortName = "doxybook2"
            Version = "1.6.1"
            ArchivePattern = "doxybook2-windows-win64-v.*\.zip$"
            ExtractStrategy = "Subdirectory"
            ExtractPath = "bin"
            DownloadUrl = "https://github.com/Antonz0/doxybook2/releases/download/v1.6.1/doxybook2-windows-win64-v1.6.1.zip"
            DependsOn = @()
            PathDirs = @()
            EnvVars = @{}
            DetectFiles = @("doxybook2.exe")
            DefaultChecked = $true
        },

        # Microsoft JDK - VersionNormalized extraction
        @{
            Name = "Microsoft JDK"
            ShortName = "jdk"
            Version = "25.0.1"
            ArchivePattern = "microsoft-jdk-.*-windows-x64\.zip$"
            ExtractStrategy = "VersionNormalized"
            VersionPattern = "^jdk-(\d+)"
            TargetDirectory = "jdk-{0}"
            DownloadUrl = "https://aka.ms/download-jdk/microsoft-jdk-25.0.1-windows-x64.zip"
            DependsOn = @()
            PathDirs = @("jdk-25\bin")
            EnvVars = @{}
            DetectFiles = @("jdk-25\bin\java.exe")
            SkipIfCommand = "java"
            DefaultChecked = $true
        },

        # Graphviz - SubdirectoryToTarget extraction
        @{
            Name = "Graphviz"
            ShortName = "graphviz"
            Version = "14.0.2"
            ArchivePattern = "windows_10_cmake_Release_Graphviz-.*-win64\.zip$"
            ExtractStrategy = "SubdirectoryToTarget"
            ExtractPath = "bin"
            TargetDirectory = "graphviz"
            DownloadUrl = "https://gitlab.com/api/v4/projects/4207231/packages/generic/graphviz-releases/14.0.2/windows_10_cmake_Release_Graphviz-14.0.2-win64.zip"
            DependsOn = @()
            PathDirs = @("graphviz")
            EnvVars = @{}
            DetectFiles = @("graphviz\dot.exe")
            DefaultChecked = $true
        },

        # PlantUML - JarWithWrapper extraction
        @{
            Name = "PlantUML"
            ShortName = "plantuml"
            Version = "1.2026.2"
            ArchivePattern = "plantuml-.*\.jar$"
            ExtractStrategy = "JarWithWrapper"
            JarName = "plantuml.jar"
            WrapperName = "plantuml.cmd"
            WrapperContent = @"
@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "JAVA_HOME=%SCRIPT_DIR%jdk-25"
"%JAVA_HOME%\bin\java.exe" -jar "%SCRIPT_DIR%plantuml.jar" %*

endlocal
"@
            DownloadUrl = "https://github.com/plantuml/plantuml/releases/download/v1.2026.2/plantuml-1.2026.2.jar"
            DependsOn = @("jdk")
            PathDirs = @()
            EnvVars = @{ "PLANTUML_HOME" = "" }
            DetectFiles = @("plantuml.jar", "plantuml.cmd")
            DefaultChecked = $true
        },

        # Python - TargetDirectory extraction with PostSetupScript
        @{
            Name = "Python"
            ShortName = "python"
            Version = "3.13.13"
            ArchivePattern = "python-(\d+\.\d+)\.\d+-embed-amd64\.zip$"
            ExtractStrategy = "TargetDirectory"
            TargetDirectory = "python-3.13"
            PostSetupScript = "python-setup.ps1"
            DownloadUrl = "https://www.python.org/ftp/python/3.13.13/python-3.13.13-embed-amd64.zip"
            DependsOn = @("get-pip")
            PathDirs = @("python-3.13")
            EnvVars = @{}
            DetectFiles = @("python-3.13\python.exe")
            SkipIfCommand = "python"
            DefaultChecked = $true
        },

        # get-pip.py (Python に関連するが独立したダウンロード)
        @{
            Name = "get-pip.py"
            ShortName = "get-pip"
            Version = "26.0.1"
            ArchivePattern = "get-pip-26\.0\.1\.py$"
            ExtractStrategy = "CopyToPackages"
            DownloadUrl = "https://bootstrap.pypa.io/pip/26.0.1/get-pip.py"
            DependsOn = @()
            PathDirs = @()
            EnvVars = @{}
            DetectFiles = @()
            Hidden = $true
        },

        # .NET SDK - TargetDirectory extraction
        @{
            Name = ".NET SDK"
            ShortName = "dotnet10sdk"
            Version = "10.0.202"
            ArchivePattern = "dotnet-sdk-.*-win-x64\.zip$"
            ExtractStrategy = "TargetDirectory"
            TargetDirectory = "dotnet10sdk"
            DownloadUrl = "https://builds.dotnet.microsoft.com/dotnet/Sdk/10.0.202/dotnet-sdk-10.0.202-win-x64.zip"
            DependsOn = @()
            PathDirs = @("dotnet10sdk")
            EnvVars = @{ "DOTNET_HOME" = "dotnet10sdk"; "DOTNET_CLI_TELEMETRY_OPTOUT" = "1" }
            EnvVarIsLiteral = @("DOTNET_CLI_TELEMETRY_OPTOUT")
            DetectFiles = @("dotnet10sdk\dotnet.exe")
            SkipIfCommand = "dotnet"
            DefaultChecked = $true
        },

        # Portable Git - SelfExtractingArchive extraction
        @{
            Name = "Portable Git"
            ShortName = "git"
            Version = "2.54.0"
            ArchivePattern = "PortableGit-.*-64-bit\.7z\.exe$"
            ExtractStrategy = "SelfExtractingArchive"
            TargetDirectory = "git"
            ExtractArgs = @("-y", "-o{TargetPath}")
            DownloadUrl = "https://sourceforge.net/projects/git-for-windows.mirror/files/v2.54.0.windows.1/PortableGit-2.54.0-64-bit.7z.exe/download"
            PostExtract = @{
                CopyFiles = @(
                    @{ Source = "packages\Add-MinGW-Path.cmd"; Destination = "Add-MinGW-Path.cmd" },
                    @{ Source = "packages\Add-MinGW-Path.ps1"; Destination = "Add-MinGW-Path.ps1" },
                    @{ Source = "packages\Remove-MinGW-Path.cmd"; Destination = "Remove-MinGW-Path.cmd" },
                    @{ Source = "packages\Remove-MinGW-Path.ps1"; Destination = "Remove-MinGW-Path.ps1" }
                )
            }
            DependsOn = @()
            PathDirs = @("git", "git\bin", "git\cmd")
            EnvVars = @{}
            DetectFiles = @("git\bin\git.exe")
            SkipIfCommand = "git"
            DisableIfCommand = "git"
            DefaultChecked = $false
        },

        # VS Code - TargetDirectory extraction
        @{
            Name = "VS Code"
            ShortName = "vscode"
            Version = "1.117.0"
            ArchivePattern = "VSCode-win32-x64-.*\.zip$"
            ExtractStrategy = "TargetDirectory"
            TargetDirectory = "vscode"
            DownloadUrl = "https://update.code.visualstudio.com/1.117.0/win32-x64-archive/stable"
            DownloadFileName = "VSCode-win32-x64-1.117.0.zip"
            PostExtract = @{
                CreateDirectories = @("data")
            }
            DependsOn = @()
            PathDirs = @("vscode\bin")
            EnvVars = @{}
            DetectFiles = @("vscode\Code.exe")
            SkipIfCommand = "code"
            DisableIfCommand = "code"
            DefaultChecked = $false
        },

        # mingw-w64-x86_64-gcc-libs - Subdirectory extraction (MinGW package, make の依存)
        @{
            Name = "mingw-w64-x86_64-gcc-libs"
            ShortName = "mingw64-gcc-libs"
            Version = "15.2.0-14"
            ArchivePattern = "^mingw-w64-x86_64-gcc-libs-.*\.pkg\.tar\.zst$"
            ExtractStrategy = "Subdirectory"
            ExtractPath = "bin"
            FilePattern = "\.dll$"
            DownloadUrl = "https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-gcc-libs-15.2.0-14-any.pkg.tar.zst"
            DependsOn = @()
            PathDirs = @()
            EnvVars = @{}
            DetectFiles = @("libgcc_s_seh-1.dll")
            Hidden = $true
        },

        # mingw-w64-x86_64-libiconv - Subdirectory extraction (MinGW package, make の依存)
        @{
            Name = "mingw-w64-x86_64-libiconv"
            ShortName = "mingw64-libiconv"
            Version = "1.19-1"
            ArchivePattern = "^mingw-w64-x86_64-libiconv-.*\.pkg\.tar\.zst$"
            ExtractStrategy = "Subdirectory"
            ExtractPath = "bin"
            FilePattern = "\.dll$"
            DownloadUrl = "https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-libiconv-1.19-1-any.pkg.tar.zst"
            DependsOn = @()
            PathDirs = @()
            EnvVars = @{}
            DetectFiles = @("libiconv-2.dll")
            Hidden = $true
        },

        # mingw-w64-x86_64-gettext-runtime - Subdirectory extraction (MinGW package, make の依存)
        @{
            Name = "mingw-w64-x86_64-gettext-runtime"
            ShortName = "mingw64-gettext-runtime"
            Version = "1.0-1"
            ArchivePattern = "^mingw-w64-x86_64-gettext-runtime-.*\.pkg\.tar\.zst$"
            ExtractStrategy = "Subdirectory"
            ExtractPath = "bin"
            FilePattern = "\.dll$"
            DownloadUrl = "https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-gettext-runtime-1.0-1-any.pkg.tar.zst"
            DependsOn = @()
            PathDirs = @()
            EnvVars = @{}
            DetectFiles = @("libintl-8.dll")
            Hidden = $true
        },

        # iconv - Subdirectory extraction (mingw-w64-x86_64-iconv パッケージの iconv.exe を抽出)
        @{
            Name = "iconv"
            ShortName = "iconv"
            Version = "1.19-1"
            ArchivePattern = "^mingw-w64-x86_64-iconv-.*\.pkg\.tar\.zst$"
            ExtractStrategy = "Subdirectory"
            ExtractPath = "bin"
            FilePattern = "^iconv\.exe$"
            DownloadUrl = "https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-iconv-1.19-1-any.pkg.tar.zst"
            DependsOn = @("mingw64-libiconv")
            PathDirs = @()
            EnvVars = @{}
            DetectFiles = @("iconv.exe")
            DefaultChecked = $true
        },

        # GNU Make - Subdirectory extraction (MinGW package)
        @{
            Name = "GNU Make"
            ShortName = "make"
            Version = "4.4.1-4"
            ArchivePattern = "^mingw-w64-x86_64-make-.*\.pkg\.tar\.zst$"
            ExtractStrategy = "Subdirectory"
            ExtractPath = "bin"
            FilePattern = "^mingw32-make\.exe$"
            RenameFiles = @{ "mingw32-make.exe" = "make.exe" }
            DownloadUrl = "https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-make-4.4.1-4-any.pkg.tar.zst"
            DependsOn = @("mingw64-gcc-libs", "mingw64-libiconv", "mingw64-gettext-runtime")
            PathDirs = @()
            EnvVars = @{}
            DetectFiles = @("make.exe")
            DefaultChecked = $true
        },

        # CMake - Subdirectory extraction
        @{
            Name = "CMake"
            ShortName = "cmake"
            Version = "4.3.1"
            ArchivePattern = "cmake-.*-windows-x86_64\.zip$"
            ExtractStrategy = "Subdirectory"
            ExtractPath = "bin"
            DownloadUrl = "https://github.com/Kitware/CMake/releases/download/v4.3.1/cmake-4.3.1-windows-x86_64.zip"
            DependsOn = @()
            PathDirs = @()
            EnvVars = @{}
            DetectFiles = @("cmake.exe")
            DefaultChecked = $true
        },

        # NuGet - SingleExecutable extraction
        @{
            Name = "NuGet"
            ShortName = "nuget"
            Version = "7.3.1"
            ArchivePattern = "nuget-.*\.exe$"
            ExtractStrategy = "SingleExecutable"
            TargetName = "nuget.exe"
            DownloadUrl = "https://dist.nuget.org/win-x86-commandline/v7.3.1/nuget.exe"
            DependsOn = @()
            PathDirs = @()
            EnvVars = @{}
            DetectFiles = @("nuget.exe")
            DefaultChecked = $true
        },

        # cloc - SingleExecutable extraction
        @{
            Name = "cloc"
            ShortName = "cloc"
            Version = "2.08"
            ArchivePattern = "^cloc-\d+\.\d+\.exe$"
            ExtractStrategy = "SingleExecutable"
            TargetName = "cloc.exe"
            DownloadUrl = "https://github.com/AlDanial/cloc/releases/download/v2.08/cloc-2.08.exe"
            DependsOn = @()
            PathDirs = @()
            EnvVars = @{}
            DetectFiles = @("cloc.exe")
            DefaultChecked = $true
        },

        # vswhere - SingleExecutable extraction
        @{
            Name = "vswhere"
            ShortName = "vswhere"
            Version = "3.1.7"
            ArchivePattern = "vswhere-.*\.exe$"
            ExtractStrategy = "SingleExecutable"
            TargetName = "vswhere.exe"
            DownloadUrl = "https://github.com/microsoft/vswhere/releases/download/3.1.7/vswhere.exe"
            DependsOn = @()
            PathDirs = @()
            EnvVars = @{}
            DetectFiles = @("vswhere.exe")
            DefaultChecked = $true
        },

        # nkf - Subdirectory extraction
        @{
            Name = "nkf"
            ShortName = "nkf"
            Version = "2.1.5"
            ArchivePattern = "nkf-bin-.*\.zip$"
            ExtractStrategy = "Subdirectory"
            ExtractPath = "bin\mingw64"
            DownloadUrl = "https://github.com/Hondarer/nkf-bin/archive/refs/tags/v2.1.5-96c3371.zip"
            DependsOn = @()
            PathDirs = @()
            EnvVars = @{}
            DetectFiles = @("nkf.exe")
            DefaultChecked = $true
        },

        # innoextract - Subdirectory extraction
        @{
            Name = "innoextract"
            ShortName = "innoextract"
            Version = "1.9"
            ArchivePattern = "innoextract-.*-windows\.zip$"
            ExtractStrategy = "Subdirectory"
            ExtractPath = ""
            FilePattern = "^innoextract\.exe$"
            DownloadUrl = "https://github.com/dscharrer/innoextract/releases/download/1.9/innoextract-1.9-windows.zip"
            DependsOn = @()
            PathDirs = @()
            EnvVars = @{}
            DetectFiles = @("innoextract.exe")
            DefaultChecked = $true
        },

        # OpenCppCoverage - InnoSetup extraction (requires innoextract)
        @{
            Name = "OpenCppCoverage"
            ShortName = "opencppcoverage"
            Version = "0.9.9.0"
            ArchivePattern = "OpenCppCoverageSetup-x64-.*\.exe$"
            ExtractStrategy = "InnoSetup"
            ExtractPath = "app"
            TargetDirectory = "OpenCppCoverage"
            DownloadUrl = "https://github.com/OpenCppCoverage/OpenCppCoverage/releases/download/release-0.9.9.0/OpenCppCoverageSetup-x64-0.9.9.0.exe"
            DependsOn = @("innoextract")
            PathDirs = @("OpenCppCoverage")
            EnvVars = @{}
            DetectFiles = @("OpenCppCoverage\OpenCppCoverage.exe")
            DefaultChecked = $true
        },

        # ReportGenerator - SubdirectoryToTarget extraction
        @{
            Name = "ReportGenerator"
            ShortName = "reportgenerator"
            Version = "5.5.1"
            ArchivePattern = "ReportGenerator_.*\.zip$"
            ExtractStrategy = "SubdirectoryToTarget"
            ExtractPath = "net47"
            TargetDirectory = "ReportGenerator"
            DownloadUrl = "https://github.com/danielpalme/ReportGenerator/releases/download/v5.5.1/ReportGenerator_5.5.1.zip"
            DependsOn = @()
            PathDirs = @("ReportGenerator")
            EnvVars = @{}
            DetectFiles = @("ReportGenerator\ReportGenerator.exe")
            DefaultChecked = $true
        },

        # Visual Studio Build Tools - VSBuildTools extraction
        @{
            Name = "Visual Studio Build Tools"
            DisplayName = "VS 2022 C++ toolset 14.44 & Windows SDK v26100"
            ShortName = "vsbt"
            Version = "14.44"
            ArchivePattern = "^vsbt$"
            ExtractStrategy = "VSBuildTools"
            ExtractedName = "vsbt"
            VSBTConfig = @{
                MSVCVersion = "14.44"
                SDKVersion = "26100"
                Target = "x64"
                HostArch = "x64"
            }
            DependsOn = @("vswhere")
            PathDirs = @()
            EnvVars = @{}
            DetectFiles = @("vsbt")
            DefaultChecked = $true
        }
    )
}
