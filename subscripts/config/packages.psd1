@{
    Packages = @(
        # PowerShell 7 - TargetDirectory extraction
        @{
            Name = "PowerShell 7"
            ShortName = "pwsh"
            MenuGroup = "基盤・ランタイム"
            Version = "7.6.6"
            ArchivePattern = "^PowerShell-\d+\.\d+\.\d+-win-x64\.zip$"
            ExtractStrategy = "TargetDirectory"
            TargetDirectory = "pwsh"
            PostSetupScript = "pwsh-setup.ps1"
            DownloadUrl = "https://github.com/PowerShell/PowerShell/releases/download/v7.6.6/PowerShell-7.6.6-win-x64.zip"
            DependsOn = @()
            PathDirs = @("pwsh")
            EnvVars = @{}
            DetectFiles = @("pwsh\pwsh.exe")
            SkipIfCommand = "pwsh"
            DisableIfCommand = "pwsh"
            DefaultChecked = $true
        },

        # Git - SelfExtractingArchive extraction (PortableGit archive)
        @{
            Name = "Git"
            ShortName = "git"
            MenuGroup = "基盤・ランタイム"
            Version = "2.56.0"
            ArchivePattern = "PortableGit-.*-64-bit\.7z\.exe$"
            ExtractStrategy = "SelfExtractingArchive"
            TargetDirectory = "git"
            ExtractArgs = @("-y", "-o{TargetPath}")
            DownloadUrl = "https://github.com/git-for-windows/git/releases/download/v2.56.0.windows.1/PortableGit-2.56.0-64-bit.7z.exe"
            PostExtract = @{
                CopyFiles = @(
                    @{ Source = "subscripts\Add-MinGW-Path.cmd"; Destination = "Add-MinGW-Path.cmd" },
                    @{ Source = "subscripts\Add-MinGW-Path.ps1"; Destination = "Add-MinGW-Path.ps1" },
                    @{ Source = "subscripts\Remove-MinGW-Path.cmd"; Destination = "Remove-MinGW-Path.cmd" },
                    @{ Source = "subscripts\Remove-MinGW-Path.ps1"; Destination = "Remove-MinGW-Path.ps1" }
                )
            }
            DependsOn = @()
            PathDirs = @("git", "git\bin", "git\cmd")
            EnvVars = @{}
            PostInstallScripts = @(
                @{
                    Path = "Update-GitBash-Profile.ps1"
                    Arguments = @("-Install", "-Force", "-InstallDir", "<InstallDir>")
                },
                @{
                    Path = "Update-MinGW-Profile.ps1"
                    Arguments = @("-Install", "-Force")
                },
                # core.editor は VS Code を先に導入している場合のみ設定されます。
                # 同時に導入する場合に備えて、VS Code 側の後処理からも同じスクリプトを実行します。
                @{
                    Path = "Update-Git-Config.ps1"
                    Arguments = @("-Install", "-InstallDir", "<InstallDir>")
                }
            )
            PostUninstallScripts = @(
                @{
                    Path = "Update-GitBash-Profile.ps1"
                    Arguments = @("-Uninstall")
                },
                @{
                    Path = "Update-MinGW-Profile.ps1"
                    Arguments = @("-Uninstall")
                }
            )
            DetectFiles = @("git\bin\git.exe")
            SkipIfCommand = "git"
            DisableIfCommand = "git"
            DefaultChecked = $true
        },

        # VS Code - TargetDirectory extraction
        @{
            Name = "VS Code"
            ShortName = "vscode"
            MenuGroup = "基盤・ランタイム"
            Version = "1.138.0"
            ArchivePattern = "VSCode-win32-x64-.*\.zip$"
            ExtractStrategy = "TargetDirectory"
            TargetDirectory = "vscode"
            DownloadUrl = "https://update.code.visualstudio.com/1.138.0/win32-x64-archive/stable"
            DownloadFileName = "VSCode-win32-x64-1.138.0.zip"
            PostSetupScript = "vscode-setup.ps1"
            DependsOn = @()
            PathDirs = @("vscode\bin")
            EnvVars = @{}
            # Git を先に導入している場合に、未設定の core.editor を設定します。
            PostInstallScripts = @(
                @{
                    Path = "Update-Git-Config.ps1"
                    Arguments = @("-Install", "-InstallDir", "<InstallDir>")
                }
            )
            DetectFiles = @("vscode\Code.exe")
            SkipIfCommand = "code"
            DisableIfCommand = "code"
            DefaultChecked = $false
        },

        # Node.js - Standard extraction
        @{
            Name = "Node.js"
            ShortName = "nodejs"
            MenuGroup = "基盤・ランタイム"
            Version = "26.9.0"
            ArchivePattern = "node-v.*-win-x64\.zip$"
            ExtractStrategy = "Standard"
            DownloadUrl = "https://nodejs.org/dist/v26.9.0/node-v26.9.0-win-x64.zip"
            DependsOn = @()
            PathDirs = @()
            EnvVars = @{}
            DetectFiles = @("node.exe")
            DefaultChecked = $true
        },

        # pip ソースアーカイブ (Python ランタイムとは独立して取得・配置)
        @{
            Name = "pip source tarball"
            ShortName = "get-pip"
            MenuGroup = "基盤・ランタイム"
            Version = "26.2.1"
            ArchivePattern = "^pip-\d+\.\d+\.\d+\.tar\.gz$"
            ExtractStrategy = "CopyToPackages"
            DownloadUrl = "https://files.pythonhosted.org/packages/ae/15/4500e320e6b101ec3b719ae85b697d9940b6cda672bc555bd6016fc60c6f/pip-26.2.1.tar.gz"
            DependsOn = @()
            PathDirs = @()
            EnvVars = @{}
            DetectFiles = @()
            Hidden = $true
        },

        # Python - TargetDirectory extraction with PostSetupScript
        @{
            Name = "Python"
            ShortName = "python"
            MenuGroup = "基盤・ランタイム"
            Version = "3.14.7"
            ArchivePattern = "python-(\d+\.\d+)\.\d+-embed-amd64\.zip$"
            ExtractStrategy = "TargetDirectory"
            TargetDirectory = "python3"
            PostSetupScript = "python-setup.ps1"
            DownloadUrl = "https://www.python.org/ftp/python/3.14.7/python-3.14.7-embed-amd64.zip"
            DependsOn = @("get-pip")
            PathDirs = @("python3", "python3\Scripts")
            EnvVars = @{}
            DetectFiles = @("python3\python.exe")
            SkipIfCommand = "python"
            DefaultChecked = $true
        },

        # Microsoft JDK - VersionNormalized extraction
        @{
            Name = "Microsoft JDK"
            ShortName = "jdk"
            MenuGroup = "基盤・ランタイム"
            Version = "25.0.4.1"
            ArchivePattern = "microsoft-jdk-.*-windows-x64\.zip$"
            ExtractStrategy = "VersionNormalized"
            VersionPattern = "^jdk-(\d+)"
            TargetDirectory = "jdk-{0}"
            DownloadUrl = "https://aka.ms/download-jdk/microsoft-jdk-25.0.4.1-windows-x64.zip"
            DependsOn = @()
            PathDirs = @("jdk-25\bin")
            EnvVars = @{}
            DetectFiles = @("jdk-25\bin\java.exe")
            SkipIfCommand = "java"
            DefaultChecked = $true
        },

        # .NET SDK - TargetDirectory extraction
        @{
            Name = ".NET SDK"
            ShortName = "dotnet10sdk"
            MenuGroup = "基盤・ランタイム"
            Version = "10.0.401"
            ArchivePattern = "dotnet-sdk-.*-win-x64\.zip$"
            ExtractStrategy = "TargetDirectory"
            TargetDirectory = "dotnet10sdk"
            DownloadUrl = "https://builds.dotnet.microsoft.com/dotnet/Sdk/10.0.401/dotnet-sdk-10.0.401-win-x64.zip"
            DependsOn = @()
            PathDirs = @("dotnet10sdk")
            EnvVars = @{ "DOTNET_HOME" = "dotnet10sdk"; "DOTNET_CLI_TELEMETRY_OPTOUT" = "1" }
            EnvVarIsLiteral = @("DOTNET_CLI_TELEMETRY_OPTOUT")
            DetectFiles = @("dotnet10sdk\dotnet.exe")
            SkipIfCommand = "dotnet"
            DefaultChecked = $true
        },

        # pnpm - npm global install
        @{
            Name = "pnpm"
            ShortName = "pnpm"
            MenuGroup = "パッケージ管理"
            Version = "12.5.1"
            ArchivePattern = "^pnpm-\d+\.\d+\.\d+\.tgz$"
            ExtractStrategy = "NpmInstall"
            NpmPackage = "pnpm"
            # pnpm 12 は導入時のスクリプト (install.js) でネイティブの実行ファイルを配置します。
            # スクリプトを止めると、Windows では起動できない仮のファイルが残るため、スクリプトを許可します。
            NpmIgnoreScripts = $false
            DependsOn = @("nodejs")
            PathDirs = @()
            EnvVars = @{}
            DetectFiles = @("pnpm.cmd", "pnpx.cmd")
            DefaultChecked = $true
        },

        # @antfu/ni - npm global install
        @{
            Name = "@antfu/ni"
            ShortName = "antfu-ni"
            MenuGroup = "パッケージ管理"
            Version = "30.5.0"
            ArchivePattern = "^antfu-ni-\d+\.\d+\.\d+\.tgz$"
            ExtractStrategy = "NpmInstall"
            NpmPackage = "@antfu/ni"
            NpmDependencies = @("fzf@^0.5.2", "package-manager-detector@^1.6.0", "tinyexec@^1.0.4", "tinyglobby@^0.2.15", "fdir@^6.5.0", "picomatch@^4.0.3")
            DependsOn = @("pnpm")
            PathDirs = @()
            EnvVars = @{}
            DetectFiles = @("ni.cmd", "nr.cmd")
            DefaultChecked = $true
        },

        # NuGet - SingleExecutable extraction
        @{
            Name = "NuGet"
            ShortName = "nuget"
            MenuGroup = "パッケージ管理"
            Version = "7.9.0"
            ArchivePattern = "nuget-.*\.exe$"
            ExtractStrategy = "SingleExecutable"
            TargetName = "nuget.exe"
            DownloadUrl = "https://dist.nuget.org/win-x86-commandline/v7.9.0/nuget.exe"
            DependsOn = @()
            PathDirs = @()
            EnvVars = @{}
            DetectFiles = @("nuget.exe")
            DefaultChecked = $true
        },

        # vswhere - SingleExecutable extraction
        @{
            Name = "vswhere"
            ShortName = "vswhere"
            MenuGroup = "C/C++・ビルド"
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

        # Visual Studio Build Tools - VSBuildTools extraction
        @{
            Name = "Visual Studio Build Tools"
            DisplayName = "VS 2022 C++ toolset 14.44 & Windows SDK v26100"
            ShortName = "vsbt"
            MenuGroup = "C/C++・ビルド"
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
            DefaultChecked = $false
        },

        # CMake - Subdirectory extraction
        @{
            Name = "CMake"
            ShortName = "cmake"
            MenuGroup = "C/C++・ビルド"
            Version = "4.3.5"
            ArchivePattern = "cmake-.*-windows-x86_64\.zip$"
            ExtractStrategy = "Subdirectory"
            ExtractPath = "bin"
            DownloadUrl = "https://github.com/Kitware/CMake/releases/download/v4.3.5/cmake-4.3.5-windows-x86_64.zip"
            DependsOn = @()
            PathDirs = @()
            EnvVars = @{}
            DetectFiles = @("cmake.exe")
            DefaultChecked = $true
        },

        # mingw-w64-x86_64-gcc-libs - サブディレクトリ抽出 (MinGW パッケージ、make の依存コンポーネント)
        @{
            Name = "mingw-w64-x86_64-gcc-libs"
            ShortName = "mingw64-gcc-libs"
            MenuGroup = "C/C++・ビルド"
            Version = "16.2.0-3"
            ArchivePattern = "^mingw-w64-x86_64-gcc-libs-.*\.pkg\.tar\.zst$"
            ExtractStrategy = "Subdirectory"
            ExtractPath = "bin"
            FilePattern = "\.dll$"
            DownloadUrl = "https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-gcc-libs-16.2.0-3-any.pkg.tar.zst"
            DependsOn = @()
            PathDirs = @()
            EnvVars = @{}
            DetectFiles = @("libgcc_s_seh-1.dll")
            Hidden = $true
        },

        # mingw-w64-x86_64-libiconv - サブディレクトリ抽出 (MinGW パッケージ、make の依存コンポーネント)
        @{
            Name = "mingw-w64-x86_64-libiconv"
            ShortName = "mingw64-libiconv"
            MenuGroup = "C/C++・ビルド"
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

        # mingw-w64-x86_64-gettext-runtime - サブディレクトリ抽出 (MinGW パッケージ、make の依存コンポーネント)
        @{
            Name = "mingw-w64-x86_64-gettext-runtime"
            ShortName = "mingw64-gettext-runtime"
            MenuGroup = "C/C++・ビルド"
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

        # GNU Make - Subdirectory extraction (MinGW package)
        @{
            Name = "GNU Make"
            ShortName = "make"
            MenuGroup = "C/C++・ビルド"
            Version = "4.4.1-5"
            ArchivePattern = "^mingw-w64-x86_64-make-.*\.pkg\.tar\.zst$"
            ExtractStrategy = "Subdirectory"
            ExtractPath = "bin"
            FilePattern = "^mingw32-make\.exe$"
            RenameFiles = @{ "mingw32-make.exe" = "make.exe" }
            DownloadUrl = "https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-make-4.4.1-5-any.pkg.tar.zst"
            DependsOn = @("mingw64-gcc-libs", "mingw64-libiconv", "mingw64-gettext-runtime")
            PathDirs = @()
            EnvVars = @{}
            DetectFiles = @("make.exe")
            DefaultChecked = $true
        },

        # WinFlexBison - TargetDirectory extraction with flex/bison aliases
        @{
            Name = "WinFlexBison"
            ShortName = "winflexbison"
            MenuGroup = "C/C++・ビルド"
            Version = "2.5.25"
            ArchivePattern = "^win_flex_bison-.*\.zip$"
            ExtractStrategy = "TargetDirectory"
            TargetDirectory = "winflexbison"
            PostSetupScript = "winflexbison-setup.ps1"
            DownloadUrl = "https://github.com/lexxmark/winflexbison/releases/download/v2.5.25/win_flex_bison-2.5.25.zip"
            DependsOn = @()
            PathDirs = @("winflexbison")
            EnvVars = @{}
            DetectFiles = @(
                "winflexbison\win_flex.exe",
                "winflexbison\win_bison.exe",
                "winflexbison\flex.exe",
                "winflexbison\bison.exe"
            )
            DefaultChecked = $true
        },

        # clang-format - Subdirectory extraction (LLVM release package)
        @{
            Name = "clang-format"
            ShortName = "clang-format"
            MenuGroup = "C/C++・ビルド"
            Version = "23.1.1"
            ArchivePattern = "^clang\+llvm-.*-x86_64-pc-windows-msvc\.tar\.xz$"
            ExtractStrategy = "Subdirectory"
            ExtractPath = "bin"
            FilePattern = "^(clang-format\.exe|git-clang-format|git-clang-format\.bat)$"
            PostSetupScript = "clang-format-setup.ps1"
            DownloadUrl = "https://github.com/llvm/llvm-project/releases/download/llvmorg-23.1.1/clang+llvm-23.1.1-x86_64-pc-windows-msvc.tar.xz"
            DependsOn = @()
            PathDirs = @()
            EnvVars = @{}
            DetectFiles = @("clang-format.exe")
            DefaultChecked = $true
        },

        # editorconfig-checker - Subdirectory extraction
        @{
            Name = "editorconfig-checker"
            ShortName = "editorconfig-checker"
            MenuGroup = "品質・計測"
            Version = "3.7.0"
            ArchivePattern = "^ec-windows-amd64-.*\.zip$"
            ExtractStrategy = "Subdirectory"
            ExtractPath = ""
            FilePattern = "^ec-windows-amd64\.exe$"
            RenameFiles = @{ "ec-windows-amd64.exe" = "editorconfig-checker.exe" }
            DownloadUrl = "https://github.com/editorconfig-checker/editorconfig-checker/releases/download/v3.7.0/ec-windows-amd64.zip"
            DependsOn = @()
            PathDirs = @()
            EnvVars = @{}
            DetectFiles = @("editorconfig-checker.exe")
            DefaultChecked = $true
        },

        # yamllint - pip install
        @{
            Name = "yamllint"
            ShortName = "yamllint"
            MenuGroup = "品質・計測"
            Version = "1.38.0"
            ArchivePattern = "^$"
            ExtractStrategy = "PipInstall"
            PipPackage = "yamllint"
            PipDependencies = @("pathspec", "pyyaml")
            DependsOn = @("python")
            PathDirs = @()
            EnvVars = @{}
            DetectFiles = @("python3\Scripts\yamllint.exe")
            DefaultChecked = $true
        },

        # textlint - npm global install
        @{
            Name = "textlint"
            ShortName = "textlint"
            MenuGroup = "品質・計測"
            Version = "15.8.0"
            ArchivePattern = "^textlint-\d+\.\d+\.\d+\.tgz$"
            ExtractStrategy = "NpmInstall"
            NpmPackage = "textlint"
            NpmDependencies = @("textlint-rule-preset-ja-technical-writing@^12.0.2", "textlint-rule-preset-ja-spacing@^3.0.3")
            DependsOn = @("nodejs")
            PathDirs = @()
            EnvVars = @{}
            DetectFiles = @("textlint.cmd")
            DefaultChecked = $true
        },

        # cloc - SingleExecutable extraction
        @{
            Name = "cloc"
            ShortName = "cloc"
            MenuGroup = "品質・計測"
            Version = "2.10"
            ArchivePattern = "^cloc-\d+\.\d+\.exe$"
            ExtractStrategy = "SingleExecutable"
            TargetName = "cloc.exe"
            DownloadUrl = "https://github.com/AlDanial/cloc/releases/download/v2.10/cloc-2.10.exe"
            DependsOn = @()
            PathDirs = @()
            EnvVars = @{}
            DetectFiles = @("cloc.exe")
            DefaultChecked = $true
        },

        # innoextract - Subdirectory extraction
        @{
            Name = "innoextract"
            ShortName = "innoextract"
            MenuGroup = "品質・計測"
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
            MenuGroup = "品質・計測"
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
            MenuGroup = "品質・計測"
            Version = "5.5.11"
            ArchivePattern = "ReportGenerator_.*\.zip$"
            ExtractStrategy = "SubdirectoryToTarget"
            ExtractPath = "net47"
            TargetDirectory = "ReportGenerator"
            DownloadUrl = "https://github.com/danielpalme/ReportGenerator/releases/download/v5.5.11/ReportGenerator_5.5.11.zip"
            DependsOn = @()
            PathDirs = @("ReportGenerator")
            EnvVars = @{}
            DetectFiles = @("ReportGenerator\ReportGenerator.exe")
            DefaultChecked = $true
        },

        # Pandoc - Standard extraction
        @{
            Name = "Pandoc"
            ShortName = "pandoc"
            MenuGroup = "ドキュメント変換・生成"
            Version = "3.11"
            ArchivePattern = "pandoc-.*-windows-x86_64\.zip$"
            ExtractStrategy = "Standard"
            DownloadUrl = "https://github.com/jgm/pandoc/releases/download/3.11/pandoc-3.11-windows-x86_64.zip"
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
            MenuGroup = "ドキュメント変換・生成"
            Version = "0.3.25a"
            ArchivePattern = "pandoc-crossref-Windows-X64-.*\.7z$"
            ExtractStrategy = "Standard"
            DownloadUrl = "https://github.com/lierdakil/pandoc-crossref/releases/download/v0.3.25a/pandoc-crossref-Windows-X64.7z"
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
            MenuGroup = "ドキュメント変換・生成"
            Version = "1.18.0"
            ArchivePattern = "doxygen-.*\.windows\.x64\.bin\.zip$"
            ExtractStrategy = "Standard"
            DownloadUrl = "https://www.doxygen.nl/files/doxygen-1.18.0.windows.x64.bin.zip"
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
            MenuGroup = "ドキュメント変換・生成"
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

        # Widdershins - npm global install with full dependency tree
        @{
            Name = "Widdershins"
            ShortName = "widdershins"
            MenuGroup = "ドキュメント変換・生成"
            Version = "4.0.1"
            ArchivePattern = "^widdershins-\d+\.\d+\.\d+\.tgz$"
            ExtractStrategy = "NpmInstall"
            NpmPackage = "widdershins"
            DependsOn = @("nodejs")
            PathDirs = @()
            EnvVars = @{}
            DetectFiles = @("widdershins.cmd")
            DefaultChecked = $true
        },

        # MarkItDown - pip install (all extras)
        @{
            Name = "MarkItDown"
            ShortName = "markitdown"
            MenuGroup = "ドキュメント変換・生成"
            Version = "0.1.8"
            ArchivePattern = "^$"
            ExtractStrategy = "PipInstall"
            PipPackage = "markitdown[all]"
            DependsOn = @("python")
            PathDirs = @()
            EnvVars = @{}
            DetectFiles = @("python3\Scripts\markitdown.exe")
            DefaultChecked = $true
        },

        # MkDocs - pip install
        @{
            Name = "MkDocs"
            ShortName = "mkdocs"
            MenuGroup = "MkDocs"
            Version = "1.6.1"
            ArchivePattern = "^$"
            ExtractStrategy = "PipInstall"
            PipPackage = "mkdocs"
            DependsOn = @("python")
            PathDirs = @()
            EnvVars = @{}
            DetectFiles = @("python3\Scripts\mkdocs.exe")
            DefaultChecked = $true
        },

        # MkDocs Material - pip install
        @{
            Name = "MkDocs Material"
            ShortName = "mkdocs-material"
            MenuGroup = "MkDocs"
            Version = "9.7.7"
            ArchivePattern = "^$"
            ExtractStrategy = "PipInstall"
            PipPackage = "mkdocs-material"
            DependsOn = @("python", "mkdocs")
            PathDirs = @()
            EnvVars = @{}
            DetectFiles = @("python3\Lib\site-packages\material\__init__.py")
            DefaultChecked = $true
        },

        # Markdown Callouts - pip install
        @{
            Name = "Markdown Callouts"
            ShortName = "markdown-callouts"
            MenuGroup = "MkDocs"
            Version = "0.4.0"
            ArchivePattern = "^$"
            ExtractStrategy = "PipInstall"
            PipPackage = "markdown-callouts"
            DependsOn = @("python")
            PathDirs = @()
            EnvVars = @{}
            DetectFiles = @("python3\Lib\site-packages\markdown_callouts\__init__.py")
            DefaultChecked = $true
        },

        # MkDocs Awesome Nav - pip install
        @{
            Name = "MkDocs Awesome Nav"
            ShortName = "mkdocs-awesome-nav"
            MenuGroup = "MkDocs"
            Version = "3.3.0"
            ArchivePattern = "^$"
            ExtractStrategy = "PipInstall"
            PipPackage = "mkdocs-awesome-nav"
            DependsOn = @("python", "mkdocs")
            PathDirs = @()
            EnvVars = @{}
            DetectFiles = @("python3\Lib\site-packages\mkdocs_awesome_nav\__init__.py")
            DefaultChecked = $true
        },

        # Marp CLI - npm global install with full dependency tree
        @{
            Name = "Marp CLI"
            ShortName = "marp-cli"
            MenuGroup = "スライド・図版・メディア"
            Version = "4.5.1"
            ArchivePattern = "^marp-team-marp-cli-\d+\.\d+\.\d+\.tgz$"
            ExtractStrategy = "NpmInstall"
            NpmPackage = "@marp-team/marp-cli"
            Browser = "Edge"
            DependsOn = @("nodejs")
            PathDirs = @()
            EnvVars = @{}
            DetectFiles = @("marp.cmd")
            DefaultChecked = $true
        },

        # Mermaid CLI - npm global install with full dependency tree
        @{
            Name = "Mermaid CLI"
            ShortName = "mermaid-cli"
            MenuGroup = "スライド・図版・メディア"
            Version = "11.17.0"
            ArchivePattern = "^mermaid-js-mermaid-cli-\d+\.\d+\.\d+\.tgz$"
            ExtractStrategy = "NpmInstall"
            NpmPackage = "@mermaid-js/mermaid-cli"
            Browser = "Edge"
            DependsOn = @("nodejs")
            PathDirs = @()
            EnvVars = @{}
            DetectFiles = @("mmdc.cmd")
            DefaultChecked = $true
        },

        # Graphviz - SubdirectoryToTarget extraction
        @{
            Name = "Graphviz"
            ShortName = "graphviz"
            MenuGroup = "スライド・図版・メディア"
            Version = "16.1.0"
            ArchivePattern = "windows_10_cmake_Release_Graphviz-.*-win64\.zip$"
            ExtractStrategy = "SubdirectoryToTarget"
            ExtractPath = "bin"
            TargetDirectory = "graphviz"
            DownloadUrl = "https://gitlab.com/api/v4/projects/4207231/packages/generic/graphviz-releases/16.1.0/windows_10_cmake_Release_Graphviz-16.1.0-win64.zip"
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
            MenuGroup = "スライド・図版・メディア"
            Version = "1.2026.8"
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
            DownloadUrl = "https://github.com/plantuml/plantuml/releases/download/v1.2026.8/plantuml-1.2026.8.jar"
            DependsOn = @("jdk")
            PathDirs = @()
            EnvVars = @{ "PLANTUML_HOME" = "" }
            DetectFiles = @("plantuml.jar", "plantuml.cmd")
            DefaultChecked = $true
        },

        # Inkscape - SubdirectoryToTarget extraction
        @{
            Name = "Inkscape"
            ShortName = "inkscape"
            MenuGroup = "スライド・図版・メディア"
            Version = "1.4.4"
            ArchivePattern = "^inkscape-.*-x64\.7z$"
            ExtractStrategy = "SubdirectoryToTarget"
            ExtractPath = ""
            TargetDirectory = "inkscape"
            DownloadUrl = "https://inkscape.org/gallery/item/59503/inkscape-1.4.4_2026-05-05_dcaf3e7-x64_mHK170m.7z"
            DownloadFileName = "inkscape-1.4.4-x64.7z"
            DownloadHeaders = @{
                "User-Agent" = "Mozilla/5.0"
                "Referer" = "https://inkscape.org/release/inkscape-1.4.4/windows/64-bit/compressed-7z/dl/"
            }
            DependsOn = @()
            PathDirs = @("inkscape\bin")
            PathPosition = "Append"
            EnvVars = @{}
            DetectFiles = @("inkscape\bin\inkscape.exe")
            SkipIfCommand = "inkscape"
            DisableIfCommand = "inkscape"
            DefaultChecked = $true
        },

        # FFmpeg - SubdirectoryToTarget extraction
        @{
            Name = "FFmpeg"
            ShortName = "ffmpeg"
            MenuGroup = "スライド・図版・メディア"
            Version = "9.0.1"
            ArchivePattern = "^ffmpeg-.*-essentials_build\.zip$"
            ExtractStrategy = "SubdirectoryToTarget"
            ExtractPath = "bin"
            TargetDirectory = "ffmpeg"
            DownloadUrl = "https://github.com/GyanD/codexffmpeg/releases/download/9.0.1/ffmpeg-9.0.1-essentials_build.zip"
            DownloadFileName = "ffmpeg-9.0.1-essentials_build.zip"
            DependsOn = @()
            PathDirs = @("ffmpeg")
            EnvVars = @{}
            DetectFiles = @("ffmpeg\ffmpeg.exe", "ffmpeg\ffprobe.exe", "ffmpeg\ffplay.exe")
            SkipIfCommand = "ffmpeg"
            DisableIfCommand = "ffmpeg"
            DefaultChecked = $true
        },

        # UDEV Gothic HSRF JPDOC EM - Font package
        @{
            Name = "UDEV Gothic HSRF JPDOC EM"
            ShortName = "udev-gothic-hsrf-jpdoc-em"
            MenuGroup = "スライド・図版・メディア"
            Version = "2.2.0.1"
            ArchivePattern = "^UDEVGothic_HSRF_EM_v\d+(?:\.\d+)+\.zip$"
            ExtractStrategy = "TargetDirectory"
            TargetDirectory = "fonts\UDEVGothicHSRFJPDOCEM"
            PostSetupScript = "font-setup.ps1"
            DownloadUrl = "https://github.com/Hondarer/udev-gothic-rf/releases/download/v2.2.0.1/UDEVGothic_HSRF_EM_v2.2.0.1.zip"
            DependsOn = @()
            PathDirs = @()
            EnvVars = @{}
            PostUninstallScripts = @(
                @{
                    Path = "config\templates\font-uninstall.ps1"
                    Arguments = @("-InstallDir", "<InstallDir>")
                }
            )
            DetectFiles = @("fonts\UDEVGothicHSRFJPDOCEM\UDEVGothicHSRFJPDOCEM-Regular.ttf")
            DisableIfFont = "UDEV Gothic HSRFJPDOCEM"
            DefaultChecked = $true
        },

        # Puppeteer - npm global install with full dependency tree
        @{
            Name = "Puppeteer"
            ShortName = "puppeteer"
            MenuGroup = "文書処理用ライブラリ"
            Version = "25.11.0"
            ArchivePattern = "^puppeteer-\d+\.\d+\.\d+\.tgz$"
            ExtractStrategy = "NpmInstall"
            NpmPackage = "puppeteer"
            Browser = "Edge"
            DependsOn = @("nodejs")
            PathDirs = @()
            EnvVars = @{
                "PUPPETEER_SKIP_DOWNLOAD" = "1"
            }
            EnvVarIsLiteral = @("PUPPETEER_SKIP_DOWNLOAD")
            DetectFiles = @("node_modules\puppeteer\package.json")
            DefaultChecked = $true
        },

        # MiniSearch - npm global install
        @{
            Name = "MiniSearch"
            ShortName = "minisearch"
            MenuGroup = "文書処理用ライブラリ"
            Version = "7.2.0"
            ArchivePattern = "^minisearch-\d+\.\d+\.\d+\.tgz$"
            ExtractStrategy = "NpmInstall"
            NpmPackage = "minisearch"
            DependsOn = @("nodejs")
            PathDirs = @()
            EnvVars = @{}
            DetectFiles = @("node_modules\minisearch\package.json")
            DefaultChecked = $true
        },

        # @plantuml/core - npm global install
        @{
            Name = "@plantuml/core"
            ShortName = "plantuml-core"
            MenuGroup = "文書処理用ライブラリ"
            Version = "1.2026.8"
            ArchivePattern = "^plantuml-core-\d+\.\d+\.\d+\.tgz$"
            ExtractStrategy = "NpmInstall"
            NpmPackage = "@plantuml/core"
            DependsOn = @("nodejs")
            PathDirs = @()
            EnvVars = @{}
            DetectFiles = @("node_modules\@plantuml\core\package.json")
            DefaultChecked = $true
        },

        # sharp - npm global install with platform optional packages
        @{
            Name = "sharp"
            ShortName = "sharp"
            MenuGroup = "文書処理用ライブラリ"
            Version = "0.35.4"
            ArchivePattern = "^sharp-\d+\.\d+\.\d+\.tgz$"
            ExtractStrategy = "NpmInstall"
            NpmPackage = "sharp"
            DependsOn = @("nodejs")
            PathDirs = @()
            EnvVars = @{}
            DetectFiles = @("node_modules\sharp\package.json")
            DefaultChecked = $true
        },

        # minimist - npm global install
        @{
            Name = "minimist"
            ShortName = "minimist"
            MenuGroup = "文書処理用ライブラリ"
            Version = "1.2.8"
            ArchivePattern = "^minimist-\d+\.\d+\.\d+\.tgz$"
            ExtractStrategy = "NpmInstall"
            NpmPackage = "minimist"
            DependsOn = @("nodejs")
            PathDirs = @()
            EnvVars = @{}
            DetectFiles = @("node_modules\minimist\package.json")
            DefaultChecked = $true
        },

        # gh - Subdirectory extraction (GitHub CLI)
        @{
            Name = "GitHub CLI"
            ShortName = "gh"
            MenuGroup = "Git ホスティング・AI"
            Version = "2.101.0"
            ArchivePattern = "^gh_.*_windows_amd64\.zip$"
            ExtractStrategy = "Subdirectory"
            ExtractPath = ""
            FilePattern = "^gh\.exe$"
            DownloadUrl = "https://github.com/cli/cli/releases/download/v2.101.0/gh_2.101.0_windows_amd64.zip"
            DependsOn = @()
            PathDirs = @()
            EnvVars = @{}
            DetectFiles = @("gh.exe")
            DefaultChecked = $true
        },

        # glab - Subdirectory extraction (GitLab CLI)
        @{
            Name = "GitLab CLI"
            ShortName = "glab"
            MenuGroup = "Git ホスティング・AI"
            Version = "1.118.0"
            ArchivePattern = "^glab_.*_windows_amd64\.zip$"
            ExtractStrategy = "Subdirectory"
            ExtractPath = ""
            FilePattern = "^glab\.exe$"
            DownloadUrl = "https://gitlab.com/gitlab-org/cli/-/releases/v1.118.0/downloads/glab_1.118.0_windows_amd64.zip"
            DependsOn = @()
            PathDirs = @()
            EnvVars = @{}
            DetectFiles = @("glab.exe")
            DefaultChecked = $true
        },

        # GitHub Copilot CLI - Subdirectory extraction
        @{
            Name = "GitHub Copilot CLI"
            ShortName = "copilot"
            MenuGroup = "Git ホスティング・AI"
            Version = "1.0.86"
            ArchivePattern = "^copilot-win32-x64-.*\.zip$"
            ExtractStrategy = "Subdirectory"
            ExtractPath = ""
            FilePattern = "^copilot\.exe$"
            DownloadUrl = "https://github.com/github/copilot-cli/releases/download/v1.0.86/copilot-win32-x64.zip"
            DownloadFileName = "copilot-win32-x64-1.0.86.zip"
            DependsOn = @("pwsh")
            PathDirs = @()
            EnvVars = @{}
            DetectFiles = @("copilot.exe")
            DisableIfCommand = "copilot"
            # 導入後は copilot.exe 自身が自己更新するため、Version は初回導入および明示的な再インストールで使用する版を示します。
            SelfUpdating = $true
            # 自己更新時に旧版を copilot.exe.old-<数値>-<数値> へ退避するため、アンインストールおよび再インストール時に削除します。
            CleanupPatterns = @("copilot.exe.old-*")
            DefaultChecked = $false
        },

        # Antigravity CLI - Subdirectory extraction
        @{
            Name = "Antigravity CLI"
            ShortName = "agy"
            MenuGroup = "Git ホスティング・AI"
            Version = "1.2.7"
            ArchivePattern = "^agy_cli_windows_x64-.*\.zip$"
            ExtractStrategy = "Subdirectory"
            ExtractPath = ""
            FilePattern = "^antigravity\.exe$"
            # 公式インストーラーと同じく agy.exe の名前で配置します。
            RenameFiles = @{ "antigravity.exe" = "agy.exe" }
            DownloadUrl = "https://github.com/google-antigravity/antigravity-cli/releases/download/1.2.7/agy_cli_windows_x64.zip"
            DownloadFileName = "agy_cli_windows_x64-1.2.7.zip"
            DependsOn = @()
            PathDirs = @()
            EnvVars = @{}
            DetectFiles = @("agy.exe")
            DisableIfCommand = "agy"
            # 導入後は agy.exe 自身が自己更新するため、Version は初回導入および明示的な再インストールで使用する版を示します。
            SelfUpdating = $true
            # 自己更新時に旧版を agy.exe.<数値>.old へ退避するため、アンインストールおよび再インストール時に削除します。
            CleanupPatterns = @("agy.exe.*.old")
            DefaultChecked = $false
        },

        # PsTools - TargetDirectory extraction
        @{
            Name = "PsTools"
            ShortName = "pstools"
            MenuGroup = "システム・文字コード"
            Version = ""
            DownloadVersion = "2.52"
            ArchivePattern = "^PSTools-.*\.zip$"
            ExtractStrategy = "TargetDirectory"
            TargetDirectory = "pstools"
            DownloadUrl = "https://download.sysinternals.com/files/PSTools.zip"
            DownloadFileName = "PSTools-2.52.zip"
            VersionSource = @{
                Type = "ZipEntry"
                Path = "psversion.txt"
                Pattern = "\d+(?:\.\d+)+"
            }
            DependsOn = @()
            PathDirs = @("pstools")
            EnvVars = @{}
            PostInstallScripts = @(
                @{
                    Path = "config\templates\pstools-accept-eula.ps1"
                    Arguments = @("-InstallDir", "<InstallDir>")
                }
            )
            DetectFiles = @("pstools\PsExec.exe", "pstools\PsPing.exe")
            DefaultChecked = $true
        },

        # nkf - Subdirectory extraction
        @{
            Name = "nkf"
            ShortName = "nkf"
            MenuGroup = "システム・文字コード"
            Version = "2.1.5"
            ArchivePattern = "nkf-bin-.*-windows\.zip$"
            ExtractStrategy = "Subdirectory"
            ExtractPath = ""
            FilePattern = "^nkf\.exe$"
            DownloadUrl = "https://github.com/Hondarer/nkf-bin/releases/download/v2_1_5/nkf-bin-v2_1_5-windows.zip"
            DependsOn = @()
            PathDirs = @()
            EnvVars = @{}
            DetectFiles = @("nkf.exe")
            DefaultChecked = $true
        },

        # iconv - サブディレクトリ抽出 (mingw-w64-x86_64-iconv パッケージから iconv.exe を抽出)
        @{
            Name = "iconv"
            ShortName = "iconv"
            MenuGroup = "システム・文字コード"
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
        }
    )
}
