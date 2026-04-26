# devbin-win

Windows 用開発バイナリの自動配置ツールです。

## インストールされるパッケージ

### Node.js

from [https://nodejs.org/en](https://nodejs.org/en)

- [https://nodejs.org/en/download/](https://nodejs.org/en/download/)
    - [node-v25.9.0-win-x64.zip](https://nodejs.org/dist/v25.9.0/node-v25.9.0-win-x64.zip)

### pandoc

from [https://github.com/jgm/pandoc](https://github.com/jgm/pandoc)

- [/releases/tag/3.9](https://github.com/jgm/pandoc/releases/tag/3.9)
    - [pandoc-3.9-windows-x86_64.zip](https://github.com/jgm/pandoc/releases/download/3.9/pandoc-3.9-windows-x86_64.zip)

### pandoc-crossref

from [lierdakil/pandoc-crossref](https://github.com/lierdakil/pandoc-crossref)

- [/releases/tag/v0.3.23a](https://github.com/lierdakil/pandoc-crossref/releases/tag/v0.3.23a)
    - [pandoc-crossref-Windows-X64.7z](https://github.com/lierdakil/pandoc-crossref/releases/download/v0.3.23a/pandoc-crossref-Windows-X64.7z)

### doxygen

from [https://doxygen.nl/](https://doxygen.nl/)

- [doxygen-1.15.0.windows.x64.bin.zip](https://www.doxygen.nl/files/doxygen-1.15.0.windows.x64.bin.zip)

### doxybook2

from [Antonz0/doxybook2](https://github.com/Antonz0/doxybook2)

- [/releases/tag/v1.6.1](https://github.com/Antonz0/doxybook2/releases/tag/v1.6.1)
    - [doxybook2-windows-win64-v1.6.1.zip](https://github.com/Antonz0/doxybook2/releases/download/v1.6.1/doxybook2-windows-win64-v1.6.1.zip)

### Microsoft Build of OpenJDK

from [Download the Microsoft Build of OpenJDK](https://learn.microsoft.com/en-us/java/openjdk/download)

- [OpenJDK 25.0.1 LTS](https://learn.microsoft.com/en-us/java/openjdk/download#openjdk-2501-lts--see-previous-releases)
    - [microsoft-jdk-25.0.1-windows-x64.zip](https://aka.ms/download-jdk/microsoft-jdk-25.0.1-windows-x64.zip)

### Graphviz

from [Graphviz](https://graphviz.org/)

- [Download](https://graphviz.org/download/)
    - [graphviz-14.0.2 (64-bit) ZIP archive](https://gitlab.com/api/v4/projects/4207231/packages/generic/graphviz-releases/14.0.2/windows_10_cmake_Release_Graphviz-14.0.2-win64.zip)

### PlantUML

from [plantuml](https://github.com/plantuml/plantuml)

- [/releases/tag/v1.2026.2](https://github.com/plantuml/plantuml/releases/tag/v1.2026.2)
    - [plantuml-1.2026.2.jar](https://github.com/plantuml/plantuml/releases/download/v1.2026.2/plantuml-1.2026.2.jar)

### Python

from [python.org](https://www.python.org/)

- [Python Releases for Windows](https://www.python.org/downloads/windows/)
    - [Python 3.13.13](https://www.python.org/downloads/release/python-31313/)
        - [Windows embeddable package (64-bit)](https://www.python.org/ftp/python/3.13.13/python-3.13.13-embed-amd64.zip)

- [get-pip 26.0.1](https://bootstrap.pypa.io/pip/26.0.1/get-pip.py)

完全オフライン環境での pip インストールに対応しています。pip wheel ファイルは Get-Packages.ps1 実行時に自動的に packages/pip-packages フォルダにダウンロードされます。詳細は [offline-pip-design.md](./docs-src/offline-pip-design.md) を参照してください。

### .NET SDK

from [.NET のダウンロード](https://dotnet.microsoft.com/ja-jp/download/dotnet)

- [.NET 10.0 のダウンロード](https://dotnet.microsoft.com/ja-jp/download/dotnet/10.0)
    - [dotnet-sdk-10.0.202-win-x64.zip](https://builds.dotnet.microsoft.com/dotnet/Sdk/10.0.202/dotnet-sdk-10.0.202-win-x64.zip)

### Git

from [Git](https://git-scm.com/)

- [Install for Windows](https://git-scm.com/install/windows)
    - [Portable 2.54.0](https://sourceforge.net/projects/git-for-windows.mirror/files/v2.54.0.windows.1/PortableGit-2.54.0-64-bit.7z.exe/download)

### Visual Studio Code

from [Visual Studio Code](https://code.visualstudio.com/)

- [Download Visual Studio Code](https://code.visualstudio.com/Download)
    - [x64 archive 1.117.0](https://update.code.visualstudio.com/1.117.0/win32-x64-archive/stable)

### GNU Make

from [MSYS2 Packages](https://packages.msys2.org/)

make.exe と実行に必要な DLL を MSYS2 MinGW パッケージから取得します。mingw32-make.exe を make.exe にリネームして配置します。

- [mingw-w64-x86_64-gcc-libs](https://packages.msys2.org/packages/mingw-w64-x86_64-gcc-libs) (GCC ランタイム DLL)
    - [mingw-w64-x86_64-gcc-libs-15.2.0-14-any.pkg.tar.zst](https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-gcc-libs-15.2.0-14-any.pkg.tar.zst)
- [mingw-w64-x86_64-libiconv](https://packages.msys2.org/packages/mingw-w64-x86_64-libiconv) (libiconv DLL)
    - [mingw-w64-x86_64-libiconv-1.19-1-any.pkg.tar.zst](https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-libiconv-1.19-1-any.pkg.tar.zst)
- [mingw-w64-x86_64-gettext-runtime](https://packages.msys2.org/packages/mingw-w64-x86_64-gettext-runtime) (gettext ランタイム DLL)
    - [mingw-w64-x86_64-gettext-runtime-1.0-1-any.pkg.tar.zst](https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-gettext-runtime-1.0-1-any.pkg.tar.zst)
- [mingw-w64-x86_64-make](https://packages.msys2.org/packages/mingw-w64-x86_64-make) (make.exe)
    - [mingw-w64-x86_64-make-4.4.1-4-any.pkg.tar.zst](https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-make-4.4.1-4-any.pkg.tar.zst)

### iconv

from [MSYS2 Packages](https://packages.msys2.org/)

iconv.exe を MSYS2 MinGW パッケージから取得します。実行に必要な `libiconv-2.dll` は GNU Make の依存として配置済みです。

- [mingw-w64-x86_64-iconv](https://packages.msys2.org/packages/mingw-w64-x86_64-iconv) (iconv コマンド)
    - [mingw-w64-x86_64-iconv-1.19-1-any.pkg.tar.zst](https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-iconv-1.19-1-any.pkg.tar.zst)

### CMake

from [CMake](https://cmake.org/)

- [Download](https://cmake.org/download/)
    - Latest Release (4.3.1)
        - Binary distributions
            - Windows x64 ZIP
                - [cmake-4.3.1-windows-x86_64.zip](https://github.com/Kitware/CMake/releases/download/v4.3.1/cmake-4.3.1-windows-x86_64.zip)

### NuGet

from [NuGet](https://www.nuget.org/)

- [Available NuGet Distribution Versions](https://www.nuget.org/downloads)
    - [nuget.exe v7.3.1](https://dist.nuget.org/win-x86-commandline/v7.3.1/nuget.exe)

### cloc

from [AlDanial/cloc](https://github.com/AlDanial/cloc)

- [/releases/tag/v2.08](https://github.com/AlDanial/cloc/releases/tag/v2.08)
    - [cloc-2.08.exe](https://github.com/AlDanial/cloc/releases/download/v2.08/cloc-2.08.exe)

### nkf

from [nkf-bin](https://github.com/Hondarer/nkf-bin)

- [/releases/tag/v2.1.5-96c3371](https://github.com/Hondarer/nkf-bin/releases/tag/v2.1.5-96c3371)
    - [nkf-bin-2.1.5-96c3371.zip](https://github.com/Hondarer/nkf-bin/archive/refs/tags/v2.1.5-96c3371.zip)

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

- [/releases/tag/v5.5.1](https://github.com/danielpalme/ReportGenerator/releases/tag/v5.5.1)
    - [ReportGenerator_5.5.1.zip](https://github.com/danielpalme/ReportGenerator/releases/download/v5.5.1/ReportGenerator_5.5.1.zip)

### vswhere

from [microsoft/vswhere](https://github.com/microsoft/vswhere)

- [/releases/tag/3.1.7](https://github.com/microsoft/vswhere/releases/tag/3.1.7)
    - [vswhere.exe](https://github.com/microsoft/vswhere/releases/download/3.1.7/vswhere.exe)

### Visual Studio BUild Tools (VS 2022 C++ toolset 14.44 & Windows SDK v26100)

## TODO

- VS Code などのスタート メニュー用ショートカットの作成
- HTTP_PROXY の設定
