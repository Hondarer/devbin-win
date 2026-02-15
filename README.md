# devbin-win

Windows 用開発バイナリの自動配置ツールです。

## インストールされるパッケージ

### Node.js

from [https://nodejs.org/en](https://nodejs.org/en)

- [https://nodejs.org/en/download/](https://nodejs.org/en/download/)
    - [node-v22.18.0-win-x64.zip](https://nodejs.org/dist/v22.18.0/node-v22.18.0-win-x64.zip)

### pandoc

from [https://github.com/jgm/pandoc](https://github.com/jgm/pandoc)

- [/releases/tag/3.8](https://github.com/jgm/pandoc/releases/tag/3.8)
    - [pandoc-3.8-windows-x86_64.zip](https://github.com/jgm/pandoc/releases/download/3.8/pandoc-3.8-windows-x86_64.zip)

### pandoc-crossref

from [lierdakil/pandoc-crossref](https://github.com/lierdakil/pandoc-crossref)

- [/releases/tag/v0.3.21](https://github.com/lierdakil/pandoc-crossref/releases/tag/v0.3.21)
    - [pandoc-crossref-Windows-X64.7z](https://github.com/lierdakil/pandoc-crossref/releases/download/v0.3.21/pandoc-crossref-Windows-X64.7z)

### doxygen

from [https://doxygen.nl/](https://doxygen.nl/)

- [doxygen-1.14.0.windows.x64.bin.zip](https://www.doxygen.nl/files/doxygen-1.14.0.windows.x64.bin.zip)

### doxybook2

from [Antonz0/doxybook2](https://github.com/Antonz0/doxybook2)

- [/releases/tag/v1.6.1](https://github.com/Antonz0/doxybook2/releases/tag/v1.6.1)
    - [doxybook2-windows-win64-v1.6.1.zip](https://github.com/Antonz0/doxybook2/releases/download/v1.6.1/doxybook2-windows-win64-v1.6.1.zip)

### Microsoft Build of OpenJDK

from [Download the Microsoft Build of OpenJDK](https://learn.microsoft.com/en-us/java/openjdk/download)

- [OpenJDK 21.0.8 LTS](https://learn.microsoft.com/en-us/java/openjdk/download#openjdk-2108-lts--see-previous-releases)
    - [microsoft-jdk-21.0.8-windows-x64.zip](https://aka.ms/download-jdk/microsoft-jdk-21.0.8-windows-x64.zip)

### Graphviz

from [Graphviz](https://graphviz.org/)

- [Download](https://graphviz.org/download/)
    - [graphviz-14.0.2 (64-bit) ZIP archive](https://gitlab.com/api/v4/projects/4207231/packages/generic/graphviz-releases/14.0.2/windows_10_cmake_Release_Graphviz-14.0.2-win64.zip)

### PlantUML

from [plantuml](https://github.com/plantuml/plantuml)

- [/releases/tag/v1.2025.4](https://github.com/plantuml/plantuml/releases/tag/v1.2025.4)
    - [plantuml-1.2025.4.jar](https://github.com/plantuml/plantuml/releases/download/v1.2025.4/plantuml-1.2025.4.jar)

### Python

from [python.org](https://www.python.org/)

- [Python Releases for Windows](https://www.python.org/downloads/windows/)
    - [Python 3.13.7](https://www.python.org/downloads/release/python-3137/)
        - [Windows embeddable package (64-bit)](https://www.python.org/ftp/python/3.13.7/python-3.13.7-embed-amd64.zip)

- [get-pip](https://bootstrap.pypa.io/get-pip.py)

完全オフライン環境での pip インストールに対応しています。pip wheel ファイルは Get-Packages.ps1 実行時に自動的に packages/pip-packages フォルダにダウンロードされます。詳細は [offline-pip-design.md](./docs-src/offline-pip-design.md) を参照してください。

### .NET SDK

from [.NET のダウンロード](https://dotnet.microsoft.com/ja-jp/download/dotnet)

- [.NET 10.0 のダウンロード](https://dotnet.microsoft.com/ja-jp/download/dotnet/10.0)
    - [dotnet-sdk-10.0.103-win-x64.zip](https://builds.dotnet.microsoft.com/dotnet/Sdk/10.0.103/dotnet-sdk-10.0.103-win-x64.zip)

### Git

from [Git](https://git-scm.com/)

- [Download for Windows](https://git-scm.com/downloads/win)
    - [Portable 2.51.0](https://github.com/git-for-windows/git/releases/download/v2.51.0.windows.1/PortableGit-2.51.0-64-bit.7z.exe)

### Visual Studio Code

from [Visual Studio Code](https://code.visualstudio.com/)

- [Download Visual Studio Code](https://code.visualstudio.com/Download)
    - [x64](https://vscode.download.prss.microsoft.com/dbazure/download/stable/e3a5acfb517a443235981655413d566533107e92/VSCode-win32-x64-1.104.2.zip)

### GNU Make for Windows

from [Make for Windows](https://gnuwin32.sourceforge.net/packages/make.htm)

- Download
    - Binaries
        - [make-3.81-bin.zip](https://sourceforge.net/projects/gnuwin32/files/make/3.81/make-3.81-bin.zip/download)
    - Dependencies
        - [make-3.81-dep.zip](https://sourceforge.net/projects/gnuwin32/files/make/3.81/make-3.81-dep.zip/download)

### CMake

from [CMake](https://cmake.org/)

- [Download](https://cmake.org/download/)
    - Latest Release (4.1.2)
        - Binary distributions
            - Windows x64 ZIP
                - [cmake-4.1.2-windows-x86_64.zip](https://github.com/Kitware/CMake/releases/download/v4.1.2/cmake-4.1.2-windows-x86_64.zip)

### NuGet

from [NuGet](https://www.nuget.org/)

- [Available NuGet Distribution Versions](https://www.nuget.org/downloads)
    - [nuget.exe - recommended latest v6.14.0](https://dist.nuget.org/win-x86-commandline/latest/nuget.exe)

### nkf

from [nkf-bin](https://github.com/Hondarer/nkf-bin)

- [/releases/tag/v2.1.5-96c3371](https://github.com/Hondarer/nkf-bin/releases/tag/v2.1.5-96c3371)
    - [nkf-bin-2.1.5-96c3371.zip](https://github.com/Hondarer/nkf-bin/archive/refs/tags/v2.1.5-96c3371.zip)

### iconv

from [MSYS2 Packages](https://packages.msys2.org/)

iconv.exe と実行に必要な DLL を MSYS2 パッケージから取得します。

- [mingw-w64-x86_64-libiconv](https://packages.msys2.org/packages/mingw-w64-x86_64-libiconv) (libiconv-2.dll, libcharset-1.dll)
    - [mingw-w64-x86_64-libiconv-1.18-1-any.pkg.tar.zst](https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-libiconv-1.18-1-any.pkg.tar.zst)
- [mingw-w64-x86_64-gettext-runtime](https://packages.msys2.org/packages/mingw-w64-x86_64-gettext-runtime) (libintl-8.dll, libasprintf-0.dll)
    - [mingw-w64-x86_64-gettext-runtime-1.0-1-any.pkg.tar.zst](https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-gettext-runtime-1.0-1-any.pkg.tar.zst)
- [mingw-w64-x86_64-iconv](https://packages.msys2.org/packages/mingw-w64-x86_64-iconv) (iconv.exe)
    - [mingw-w64-x86_64-iconv-1.18-1-any.pkg.tar.zst](https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-iconv-1.18-1-any.pkg.tar.zst)

### innoextract

from [innoextract](https://github.com/dscharrer/innoextract)

- [/releases/tag/1.9](https://github.com/dscharrer/innoextract/releases/tag/1.9)
    - [innoextract-1.9-windows.zip](https://github.com/dscharrer/innoextract/releases/download/1.9/innoextract-1.9-windows.zip)

### OpenCppCoverage

from [OpenCppCoverage](https://github.com/OpenCppCoverage/OpenCppCoverage)

- [/releases/tag/release-0.9.9.0](https://github.com/OpenCppCoverage/OpenCppCoverage/releases/tag/release-0.9.9.0)
    - [OpenCppCoverageSetup-x64-0.9.9.0.exe](https://github.com/OpenCppCoverage/OpenCppCoverage/releases/download/release-0.9.9.0/OpenCppCoverageSetup-x64-0.9.9.0.exe)

### ReportGenerator

from [ReportGenerator](https://github.com/danielpalme/ReportGenerator)

- [/releases/tag/v5.5.0](https://github.com/danielpalme/ReportGenerator/releases/tag/v5.5.0)
    - [ReportGenerator_5.5.0.zip](https://github.com/danielpalme/ReportGenerator/releases/download/v5.5.0/ReportGenerator_5.5.0.zip)

### vswhere

from [microsoft/vswhere](https://github.com/microsoft/vswhere)

- [/releases/tag/3.1.7](https://github.com/microsoft/vswhere/releases/tag/3.1.7)
    - [vswhere.exe](https://github.com/microsoft/vswhere/releases/download/3.1.7/vswhere.exe)

### Visual Studio BUild Tools (VS 2022 C++ toolset 14.44 & Windows SDK v26100)

## TODO

- VS Code などのスタート メニュー用ショートカットの作成
- HTTP_PROXY の設定
