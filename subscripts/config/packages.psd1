@{
    Packages = @(
        # Node.js - Standard extraction
        @{
            Name = "Node.js"
            ShortName = "nodejs"
            ArchivePattern = "node-v.*-win-x64\.zip$"
            ExtractStrategy = "Standard"
            DownloadUrl = "https://nodejs.org/dist/v22.18.0/node-v22.18.0-win-x64.zip"
        },

        # Pandoc - Standard extraction
        @{
            Name = "Pandoc"
            ShortName = "pandoc"
            ArchivePattern = "pandoc-.*-windows-x86_64\.zip$"
            ExtractStrategy = "Standard"
            DownloadUrl = "https://github.com/jgm/pandoc/releases/download/3.8/pandoc-3.8-windows-x86_64.zip"
        },

        # pandoc-crossref - Standard extraction
        @{
            Name = "pandoc-crossref"
            ShortName = "pandoc-crossref"
            ArchivePattern = "pandoc-crossref-Windows-X64\.7z$"
            ExtractStrategy = "Standard"
            DownloadUrl = "https://github.com/lierdakil/pandoc-crossref/releases/download/v0.3.21/pandoc-crossref-Windows-X64.7z"
        },

        # Doxygen - Standard extraction
        @{
            Name = "Doxygen"
            ShortName = "doxygen"
            ArchivePattern = "doxygen-.*\.windows\.x64\.bin\.zip$"
            ExtractStrategy = "Standard"
            DownloadUrl = "https://www.doxygen.nl/files/doxygen-1.14.0.windows.x64.bin.zip"
        },

        # doxybook2 - Subdirectory extraction
        @{
            Name = "doxybook2"
            ShortName = "doxybook2"
            ArchivePattern = "doxybook2-windows-win64-v.*\.zip$"
            ExtractStrategy = "Subdirectory"
            ExtractPath = "bin"
            DownloadUrl = "https://github.com/Antonz0/doxybook2/releases/download/v1.6.1/doxybook2-windows-win64-v1.6.1.zip"
        },

        # Microsoft JDK - VersionNormalized extraction
        @{
            Name = "Microsoft JDK"
            ShortName = "jdk"
            ArchivePattern = "microsoft-jdk-.*-windows-x64\.zip$"
            ExtractStrategy = "VersionNormalized"
            VersionPattern = "^jdk-(\d+)"
            TargetDirectory = "jdk-{0}"
            DownloadUrl = "https://aka.ms/download-jdk/microsoft-jdk-21.0.8-windows-x64.zip"
        },

        # Graphviz - SubdirectoryToTarget extraction
        @{
            Name = "Graphviz"
            ShortName = "graphviz"
            ArchivePattern = "windows_10_cmake_Release_Graphviz-.*-win64\.zip$"
            ExtractStrategy = "SubdirectoryToTarget"
            ExtractPath = "bin"
            TargetDirectory = "graphviz"
            DownloadUrl = "https://gitlab.com/api/v4/projects/4207231/packages/generic/graphviz-releases/14.0.2/windows_10_cmake_Release_Graphviz-14.0.2-win64.zip"
        },

        # PlantUML - JarWithWrapper extraction
        @{
            Name = "PlantUML"
            ShortName = "plantuml"
            ArchivePattern = "plantuml-.*\.jar$"
            ExtractStrategy = "JarWithWrapper"
            JarName = "plantuml.jar"
            WrapperName = "plantuml.cmd"
            WrapperContent = @"
@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "JAVA_HOME=%SCRIPT_DIR%jdk-21"
"%JAVA_HOME%\bin\java.exe" -jar "%SCRIPT_DIR%plantuml.jar" %*

endlocal
"@
            DownloadUrl = "https://github.com/plantuml/plantuml/releases/download/v1.2025.4/plantuml-1.2025.4.jar"
        },

        # Python - TargetDirectory extraction with PostSetupScript
        @{
            Name = "Python"
            ShortName = "python"
            ArchivePattern = "python-(\d+\.\d+)\.\d+-embed-amd64\.zip$"
            ExtractStrategy = "TargetDirectory"
            TargetDirectory = "python-3.13"
            PostSetupScript = "python-setup.ps1"
            DownloadUrl = "https://www.python.org/ftp/python/3.13.7/python-3.13.7-embed-amd64.zip"
        },

        # get-pip.py (Python に関連するが独立したダウンロード)
        @{
            Name = "get-pip.py"
            ShortName = "get-pip"
            ArchivePattern = "get-pip\.py$"
            ExtractStrategy = "CopyToPackages"
            DownloadUrl = "https://bootstrap.pypa.io/get-pip.py"
        },

        # .NET SDK - TargetDirectory extraction
        @{
            Name = ".NET SDK"
            ShortName = "dotnet10sdk"
            ArchivePattern = "dotnet-sdk-.*-win-x64\.zip$"
            ExtractStrategy = "TargetDirectory"
            TargetDirectory = "dotnet10sdk"
            DownloadUrl = "https://builds.dotnet.microsoft.com/dotnet/Sdk/10.0.103/dotnet-sdk-10.0.103-win-x64.zip"
        },

        # Portable Git - SelfExtractingArchive extraction
        @{
            Name = "Portable Git"
            ShortName = "git"
            ArchivePattern = "PortableGit-.*-64-bit\.7z\.exe$"
            ExtractStrategy = "SelfExtractingArchive"
            TargetDirectory = "git"
            ExtractArgs = @("-y", "-o{TargetPath}")
            DownloadUrl = "https://github.com/git-for-windows/git/releases/download/v2.51.0.windows.1/PortableGit-2.51.0-64-bit.7z.exe"
            PostExtract = @{
                CopyFiles = @(
                    @{ Source = "packages\Add-MinGW-Path.cmd"; Destination = "Add-MinGW-Path.cmd" },
                    @{ Source = "packages\Add-MinGW-Path.ps1"; Destination = "Add-MinGW-Path.ps1" },
                    @{ Source = "packages\Remove-MinGW-Path.cmd"; Destination = "Remove-MinGW-Path.cmd" },
                    @{ Source = "packages\Remove-MinGW-Path.ps1"; Destination = "Remove-MinGW-Path.ps1" }
                )
            }
        },

        # VS Code - TargetDirectory extraction
        @{
            Name = "VS Code"
            ShortName = "vscode"
            ArchivePattern = "VSCode-win32-x64-.*\.zip$"
            ExtractStrategy = "TargetDirectory"
            TargetDirectory = "vscode"
            DownloadUrl = "https://vscode.download.prss.microsoft.com/dbazure/download/stable/e3a5acfb517a443235981655413d566533107e92/VSCode-win32-x64-1.104.2.zip"
            PostExtract = @{
                CreateDirectories = @("data")
            }
        },

        # mingw-w64-x86_64-gcc-libs - Subdirectory extraction (MinGW package, make の依存)
        @{
            Name = "mingw-w64-x86_64-gcc-libs"
            ShortName = "mingw64-gcc-libs"
            ArchivePattern = "^mingw-w64-x86_64-gcc-libs-.*\.pkg\.tar\.zst$"
            ExtractStrategy = "Subdirectory"
            ExtractPath = "bin"
            FilePattern = "\.dll$"
            DownloadUrl = "https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-gcc-libs-15.2.0-11-any.pkg.tar.zst"
        },

        # mingw-w64-x86_64-libiconv - Subdirectory extraction (MinGW package, make の依存)
        @{
            Name = "mingw-w64-x86_64-libiconv"
            ShortName = "mingw64-libiconv"
            ArchivePattern = "^mingw-w64-x86_64-libiconv-.*\.pkg\.tar\.zst$"
            ExtractStrategy = "Subdirectory"
            ExtractPath = "bin"
            FilePattern = "\.dll$"
            DownloadUrl = "https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-libiconv-1.18-1-any.pkg.tar.zst"
        },

        # mingw-w64-x86_64-gettext-runtime - Subdirectory extraction (MinGW package, make の依存)
        @{
            Name = "mingw-w64-x86_64-gettext-runtime"
            ShortName = "mingw64-gettext-runtime"
            ArchivePattern = "^mingw-w64-x86_64-gettext-runtime-.*\.pkg\.tar\.zst$"
            ExtractStrategy = "Subdirectory"
            ExtractPath = "bin"
            FilePattern = "\.dll$"
            DownloadUrl = "https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-gettext-runtime-1.0-1-any.pkg.tar.zst"
        },

        # iconv - Subdirectory extraction (mingw-w64-x86_64-iconv パッケージの iconv.exe を抽出)
        @{
            Name = "iconv"
            ShortName = "iconv"
            ArchivePattern = "^mingw-w64-x86_64-iconv-.*\.pkg\.tar\.zst$"
            ExtractStrategy = "Subdirectory"
            ExtractPath = "bin"
            FilePattern = "^iconv\.exe$"
            DownloadUrl = "https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-iconv-1.18-1-any.pkg.tar.zst"
        },

        # GNU Make - Subdirectory extraction (MinGW package)
        @{
            Name = "GNU Make"
            ShortName = "make"
            ArchivePattern = "^mingw-w64-x86_64-make-.*\.pkg\.tar\.zst$"
            ExtractStrategy = "Subdirectory"
            ExtractPath = "bin"
            FilePattern = "^mingw32-make\.exe$"
            RenameFiles = @{ "mingw32-make.exe" = "make.exe" }
            DownloadUrl = "https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-make-4.4.1-4-any.pkg.tar.zst"
        },

        # CMake - Subdirectory extraction
        @{
            Name = "CMake"
            ShortName = "cmake"
            ArchivePattern = "cmake-.*-windows-x86_64\.zip$"
            ExtractStrategy = "Subdirectory"
            ExtractPath = "bin"
            DownloadUrl = "https://github.com/Kitware/CMake/releases/download/v4.1.2/cmake-4.1.2-windows-x86_64.zip"
        },

        # NuGet - SingleExecutable extraction
        @{
            Name = "NuGet"
            ShortName = "nuget"
            ArchivePattern = "nuget\.exe$"
            ExtractStrategy = "SingleExecutable"
            TargetName = "nuget.exe"
            DownloadUrl = "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe"
        },

        # vswhere - SingleExecutable extraction
        @{
            Name = "vswhere"
            ShortName = "vswhere"
            ArchivePattern = "vswhere\.exe$"
            ExtractStrategy = "SingleExecutable"
            TargetName = "vswhere.exe"
            DownloadUrl = "https://github.com/microsoft/vswhere/releases/download/3.1.7/vswhere.exe"
        },

        # nkf - Subdirectory extraction
        @{
            Name = "nkf"
            ShortName = "nkf"
            ArchivePattern = "nkf-bin-.*\.zip$"
            ExtractStrategy = "Subdirectory"
            ExtractPath = "bin\mingw64"
            DownloadUrl = "https://github.com/Hondarer/nkf-bin/archive/refs/tags/v2.1.5-96c3371.zip"
        },

        # innoextract - Subdirectory extraction
        @{
            Name = "innoextract"
            ShortName = "innoextract"
            ArchivePattern = "innoextract-.*-windows\.zip$"
            ExtractStrategy = "Subdirectory"
            ExtractPath = ""
            FilePattern = "^innoextract\.exe$"
            DownloadUrl = "https://github.com/dscharrer/innoextract/releases/download/1.9/innoextract-1.9-windows.zip"
        },

        # OpenCppCoverage - InnoSetup extraction (requires innoextract)
        @{
            Name = "OpenCppCoverage"
            ShortName = "opencppcoverage"
            ArchivePattern = "OpenCppCoverageSetup-x64-.*\.exe$"
            ExtractStrategy = "InnoSetup"
            ExtractPath = "app"
            TargetDirectory = "OpenCppCoverage"
            DownloadUrl = "https://github.com/OpenCppCoverage/OpenCppCoverage/releases/download/release-0.9.9.0/OpenCppCoverageSetup-x64-0.9.9.0.exe"
        },

        # ReportGenerator - SubdirectoryToTarget extraction
        @{
            Name = "ReportGenerator"
            ShortName = "reportgenerator"
            ArchivePattern = "ReportGenerator_.*\.zip$"
            ExtractStrategy = "SubdirectoryToTarget"
            ExtractPath = "net47"
            TargetDirectory = "ReportGenerator"
            DownloadUrl = "https://github.com/danielpalme/ReportGenerator/releases/download/v5.5.0/ReportGenerator_5.5.0.zip"
        },

        # Visual Studio Build Tools - VSBuildTools extraction
        @{
            Name = "Visual Studio Build Tools"
            DisplayName = "VS 2022 C++ toolset 14.44 & Windows SDK v26100"
            ShortName = "vsbt"
            ArchivePattern = "^vsbt$"
            ExtractStrategy = "VSBuildTools"
            ExtractedName = "vsbt"
            VSBTConfig = @{
                MSVCVersion = "14.44"
                SDKVersion = "26100"
                Target = "x64"
                HostArch = "x64"
            }
        }
    )
}
