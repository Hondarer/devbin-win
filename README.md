# devbin-win

Windows 用開発バイナリの自動配置ツールです。

開発環境のバイナリ配置・更新には `Manage-Bin.cmd`、環境変数の確認・編集には `Manage-Env.cmd` を利用できます。
詳しくは [Development Tools Installation Guide](docs/Install-Bin.md) および [環境変数マネージャー](docs/Manage-Env.md) を参照してください。

## インストールされるパッケージ

### Node.js

from [https://nodejs.org/en](https://nodejs.org/en)

- [https://nodejs.org/en/download/](https://nodejs.org/en/download/)
    - [node-v26.9.0-win-x64.zip](https://nodejs.org/dist/v26.9.0/node-v26.9.0-win-x64.zip)

### Marp CLI

from [marp-team/marp-cli](https://github.com/marp-team/marp-cli)

- [v4.5.1](https://www.npmjs.com/package/@marp-team/marp-cli/v/4.5.1)
    - `@marp-team/marp-cli@4.5.1` を検証済みの依存関係ツリーから `npm install --offline` で配置します。
      依存関係ツリーは `packages/npm-packages/marp-cli/` に lock/manifest 付きで保存し、既存の Microsoft Edge を使用します。

### Mermaid CLI

from [mermaid-js/mermaid-cli](https://github.com/mermaid-js/mermaid-cli)

- [v11.17.0](https://www.npmjs.com/package/@mermaid-js/mermaid-cli/v/11.17.0)
    - `@mermaid-js/mermaid-cli@11.17.0` (`mmdc`) を配置します。
      依存関係ツリーは `packages/npm-packages/mermaid-cli/` に保存し、既存の Microsoft Edge を使用します。

### Widdershins

from [Mermade/widdershins](https://github.com/Mermade/widdershins)

- [v4.0.1](https://www.npmjs.com/package/widdershins/v/4.0.1)

### Puppeteer

from [puppeteer/puppeteer](https://github.com/puppeteer/puppeteer)

- [v25.11.0](https://www.npmjs.com/package/puppeteer/v/25.11.0)
    - Google Chrome はダウンロードしません。Windows では Microsoft Edge を使用します。

### MiniSearch / @plantuml/core / sharp / minimist
 
npm グローバル配置パッケージです。
バージョンは `subscripts/config/packages.psd1` を参照してください。

### textlint

from [textlint/textlint](https://github.com/textlint/textlint)

- [v15.8.0](https://www.npmjs.com/package/textlint/v/15.8.0)
    - `textlint-rule-preset-ja-technical-writing`、`textlint-rule-preset-ja-spacing` を依存パッケージとして同梱します。

## npm パッケージのオフライン準備

オンライン環境で Node.js/npm を使用して、依存ツリーを準備します。

```powershell
.\subscripts\Get-Packages.ps1
```

`packages/npm-packages/<ShortName>/` に `package-lock.json`、`npm-cache-manifest.json`、依存パッケージの `.tgz` が生成されます。
生成後は `packages` フォルダーを含めてリポジトリ全体をオフライン環境へコピーし、`Manage-Bin.cmd` を実行してください。
導入時の npm install は検証済みのローカル キャッシュに対して `--offline` で実行されます。

### pandoc

from [https://github.com/jgm/pandoc](https://github.com/jgm/pandoc)

- [/releases/tag/3.11](https://github.com/jgm/pandoc/releases/tag/3.11)
    - [pandoc-3.11-windows-x86_64.zip](https://github.com/jgm/pandoc/releases/download/3.11/pandoc-3.11-windows-x86_64.zip)

### pandoc-crossref

from [lierdakil/pandoc-crossref](https://github.com/lierdakil/pandoc-crossref)

- [/releases/tag/v0.3.25a](https://github.com/lierdakil/pandoc-crossref/releases/tag/v0.3.25a)
    - [pandoc-crossref-Windows-X64.7z](https://github.com/lierdakil/pandoc-crossref/releases/download/v0.3.25a/pandoc-crossref-Windows-X64.7z)

### doxygen

from [https://doxygen.nl/](https://doxygen.nl/)

- [doxygen-1.18.0.windows.x64.bin.zip](https://www.doxygen.nl/files/doxygen-1.18.0.windows.x64.bin.zip)

### doxybook2

from [Antonz0/doxybook2](https://github.com/Antonz0/doxybook2)

- [/releases/tag/v1.6.1](https://github.com/Antonz0/doxybook2/releases/tag/v1.6.1)
    - [doxybook2-windows-win64-v1.6.1.zip](https://github.com/Antonz0/doxybook2/releases/download/v1.6.1/doxybook2-windows-win64-v1.6.1.zip)

### Microsoft Build of OpenJDK

from [Download the Microsoft Build of OpenJDK](https://learn.microsoft.com/en-us/java/openjdk/download)

- [OpenJDK 25.0.4.1 LTS](https://learn.microsoft.com/en-us/java/openjdk/download#openjdk-25)
    - [microsoft-jdk-25.0.4.1-windows-x64.zip](https://aka.ms/download-jdk/microsoft-jdk-25.0.4.1-windows-x64.zip)

### Graphviz

from [Graphviz](https://graphviz.org/)

- [Download](https://graphviz.org/download/)
    - [graphviz-16.1.0 (64-bit) ZIP archive](https://gitlab.com/api/v4/projects/4207231/packages/generic/graphviz-releases/16.1.0/windows_10_cmake_Release_Graphviz-16.1.0-win64.zip)

16.0.0 以降、`diffimg` ユーティリティは含まれません。

### PlantUML

from [plantuml](https://github.com/plantuml/plantuml)

- [/releases/tag/v1.2026.8](https://github.com/plantuml/plantuml/releases/tag/v1.2026.8)
    - [plantuml-1.2026.8.jar](https://github.com/plantuml/plantuml/releases/download/v1.2026.8/plantuml-1.2026.8.jar)

### Python

from [python.org](https://www.python.org/)

- [Python Releases for Windows](https://www.python.org/downloads/windows/)
    - [Python 3.14.7](https://www.python.org/downloads/release/python-3147/)
        - [Windows embeddable package (64-bit)](https://www.python.org/ftp/python/3.14.7/python-3.14.7-embed-amd64.zip)

- [pip 26.2.1](https://pypi.org/project/pip/26.2.1/)
    - [pip-26.2.1.tar.gz](https://files.pythonhosted.org/packages/ae/15/4500e320e6b101ec3b719ae85b697d9940b6cda672bc555bd6016fc60c6f/pip-26.2.1.tar.gz)

完全オフライン環境での pip インストールに対応しています。
pip のソース tarball は Get-Packages.ps1 の実行により `packages` フォルダーへ保存され、pip wheel ファイルは `packages/pip-packages` に自動ダウンロードされます。
詳細は [offline-pip-design.md](./docs/offline-pip-design.md) を参照してください。

### .NET SDK

from [.NET のダウンロード](https://dotnet.microsoft.com/ja-jp/download/dotnet)

- [.NET 10.0 のダウンロード](https://dotnet.microsoft.com/ja-jp/download/dotnet/10.0)
    - [dotnet-sdk-10.0.401-win-x64.zip](https://builds.dotnet.microsoft.com/dotnet/Sdk/10.0.401/dotnet-sdk-10.0.401-win-x64.zip)

### PowerShell 7

from [PowerShell 7 installation on Windows](https://learn.microsoft.com/ja-jp/powershell/scripting/install/install-powershell-on-windows)

- [PowerShell 7.6.6 x64 ZIP](https://github.com/PowerShell/PowerShell/releases/download/v7.6.6/PowerShell-7.6.6-win-x64.zip)

ZIP アーカイブを `bin\pwsh` に展開して `pwsh` コマンドを提供します。
Windows PowerShell 5.1 を置き換えずに共存します。
外部の `pwsh` が PATH に存在する場合は、そちらのインストール環境を優先します。

### Git

from [Git](https://git-scm.com/)

- [Install for Windows](https://git-scm.com/install/windows)
    - [Portable 2.55.0.5](https://sourceforge.net/projects/git-for-windows.mirror/files/v2.55.0.windows.5/PortableGit-2.55.0.5-64-bit.7z.exe/download)

### Visual Studio Code

from [Visual Studio Code](https://code.visualstudio.com/)

- [Download Visual Studio Code](https://code.visualstudio.com/Download)
    - [x64 archive 1.138.0](https://update.code.visualstudio.com/1.138.0/win32-x64-archive/stable)

### PsTools

from [Microsoft Sysinternals](https://learn.microsoft.com/sysinternals/)

- [PsTools](https://learn.microsoft.com/ja-jp/sysinternals/downloads/pstools)
    - [PSTools.zip](https://download.sysinternals.com/files/PSTools.zip)

`packages` フォルダーには `PSTools-2.52.zip` のように、バージョンを付与して保存します。
インストール時の実バージョンは ZIP 内の `psversion.txt` から読み取り、インストール後に Sysinternals EULA を `-accepteula` で自動受諾します。

### Inkscape

from [Inkscape](https://inkscape.org/)

- [Inkscape 1.4.4 for Windows 64-bit compressed 7z](https://inkscape.org/release/inkscape-1.4.4/windows/64-bit/compressed-7z/dl/)
    - [inkscape-1.4.4_2026-05-05_dcaf3e7-x64_mHK170m.7z](https://inkscape.org/gallery/item/59503/inkscape-1.4.4_2026-05-05_dcaf3e7-x64_mHK170m.7z)

### GNU Make

from [MSYS2 Packages](https://packages.msys2.org/)

make.exe と実行に必要な DLL を MSYS2 MinGW パッケージから取得します。
mingw32-make.exe のファイル名を make.exe に変更して配置します。

- [mingw-w64-x86_64-gcc-libs](https://packages.msys2.org/packages/mingw-w64-x86_64-gcc-libs) (GCC ランタイム DLL)
    - [mingw-w64-x86_64-gcc-libs-16.2.0-3-any.pkg.tar.zst](https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-gcc-libs-16.2.0-3-any.pkg.tar.zst)
- [mingw-w64-x86_64-libiconv](https://packages.msys2.org/packages/mingw-w64-x86_64-libiconv) (libiconv DLL)
    - [mingw-w64-x86_64-libiconv-1.19-1-any.pkg.tar.zst](https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-libiconv-1.19-1-any.pkg.tar.zst)
- [mingw-w64-x86_64-gettext-runtime](https://packages.msys2.org/packages/mingw-w64-x86_64-gettext-runtime) (gettext ランタイム DLL)
    - [mingw-w64-x86_64-gettext-runtime-1.0-1-any.pkg.tar.zst](https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-gettext-runtime-1.0-1-any.pkg.tar.zst)
- [mingw-w64-x86_64-make](https://packages.msys2.org/packages/mingw-w64-x86_64-make) (make.exe)
    - [mingw-w64-x86_64-make-4.4.1-5-any.pkg.tar.zst](https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-make-4.4.1-5-any.pkg.tar.zst)

### iconv

from [MSYS2 Packages](https://packages.msys2.org/)

iconv.exe を MSYS2 MinGW パッケージから取得します。
実行に必要な `libiconv-2.dll` は GNU Make の依存関係として配置済みです。

- [mingw-w64-x86_64-iconv](https://packages.msys2.org/packages/mingw-w64-x86_64-iconv) (iconv コマンド)
    - [mingw-w64-x86_64-iconv-1.19-1-any.pkg.tar.zst](https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-iconv-1.19-1-any.pkg.tar.zst)

### CMake

from [CMake](https://cmake.org/)

- [Download](https://cmake.org/download/)
    - Latest Release (4.3.5)
        - Binary distributions
            - Windows x64 ZIP
                - [cmake-4.3.5-windows-x86_64.zip](https://github.com/Kitware/CMake/releases/download/v4.3.5/cmake-4.3.5-windows-x86_64.zip)

### WinFlexBison

from [lexxmark/winflexbison](https://github.com/lexxmark/winflexbison)

- [/releases/tag/v2.5.25](https://github.com/lexxmark/winflexbison/releases/tag/v2.5.25)
    - [win_flex_bison-2.5.25.zip](https://github.com/lexxmark/winflexbison/releases/download/v2.5.25/win_flex_bison-2.5.25.zip)

ZIP アーカイブを `bin\winflexbison` に展開し、同一ディレクトリへ `flex.exe` と `bison.exe` の別名コピーを配置します。
bison が参照する `data/` は実行ファイルと同じ場所に保持します。

### clang-format

from [LLVM Project](https://github.com/llvm/llvm-project)

- [/releases/tag/llvmorg-23.1.1](https://github.com/llvm/llvm-project/releases/tag/llvmorg-23.1.1)
    - [clang+llvm-23.1.1-x86_64-pc-windows-msvc.tar.xz](https://github.com/llvm/llvm-project/releases/download/llvmorg-23.1.1/clang+llvm-23.1.1-x86_64-pc-windows-msvc.tar.xz)

### NuGet

from [NuGet](https://www.nuget.org/)

- [Available NuGet Distribution Versions](https://www.nuget.org/downloads)
    - [nuget.exe v7.9.0](https://dist.nuget.org/win-x86-commandline/v7.9.0/nuget.exe)

### cloc

from [AlDanial/cloc](https://github.com/AlDanial/cloc)

- [/releases/tag/v2.10](https://github.com/AlDanial/cloc/releases/tag/v2.10)
    - [cloc-2.10.exe](https://github.com/AlDanial/cloc/releases/download/v2.10/cloc-2.10.exe)

### nkf

from [nkf-bin](https://github.com/Hondarer/nkf-bin)

- [/releases/tag/v2_1_5](https://github.com/Hondarer/nkf-bin/releases/tag/v2_1_5)
    - [nkf-bin-v2_1_5-windows.zip](https://github.com/Hondarer/nkf-bin/releases/download/v2_1_5/nkf-bin-v2_1_5-windows.zip)

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

- [/releases/tag/v5.5.11](https://github.com/danielpalme/ReportGenerator/releases/tag/v5.5.11)
    - [ReportGenerator_5.5.11.zip](https://github.com/danielpalme/ReportGenerator/releases/download/v5.5.11/ReportGenerator_5.5.11.zip)

### vswhere

from [microsoft/vswhere](https://github.com/microsoft/vswhere)

- [/releases/tag/3.1.7](https://github.com/microsoft/vswhere/releases/tag/3.1.7)
    - [vswhere.exe](https://github.com/microsoft/vswhere/releases/download/3.1.7/vswhere.exe)

### UDEV Gothic HSRF JPDOC EM

from [Hondarer/udev-gothic-rf](https://github.com/Hondarer/udev-gothic-rf)

- [/releases/tag/v2.2.0.1](https://github.com/Hondarer/udev-gothic-rf/releases/tag/v2.2.0.1)
    - [UDEVGothic_HSRF_EM_v2.2.0.1.zip](https://github.com/Hondarer/udev-gothic-rf/releases/download/v2.2.0.1/UDEVGothic_HSRF_EM_v2.2.0.1.zip)

インストール対象フォントは `UDEVGothicHSRFJPDOCEM-{weight}.ttf` です。

### editorconfig-checker

from [editorconfig-checker/editorconfig-checker](https://github.com/editorconfig-checker/editorconfig-checker)

- [/releases/tag/v3.7.0](https://github.com/editorconfig-checker/editorconfig-checker/releases/tag/v3.7.0)
    - [ec-windows-amd64.zip](https://github.com/editorconfig-checker/editorconfig-checker/releases/download/v3.7.0/ec-windows-amd64.zip)

### GitHub CLI

from [cli/cli](https://github.com/cli/cli)

- [/releases/tag/v2.101.0](https://github.com/cli/cli/releases/tag/v2.101.0)
    - [gh_2.101.0_windows_amd64.zip](https://github.com/cli/cli/releases/download/v2.101.0/gh_2.101.0_windows_amd64.zip)

### GitHub Copilot CLI

from [github/copilot-cli](https://github.com/github/copilot-cli)

- [/releases/tag/v1.0.86](https://github.com/github/copilot-cli/releases/tag/v1.0.86)
    - [copilot-win32-x64.zip](https://github.com/github/copilot-cli/releases/download/v1.0.86/copilot-win32-x64.zip)

Windows 版は PowerShell 6 以降が必要です。
devbin-win では PowerShell 7 を依存コンポーネントとして導入します。
Copilot CLI は既定値では選択されていないため、コンポーネント マネージャーで選択して導入してください。
利用には GitHub Copilot の契約と初回認証 (`copilot login`) が必要です。
導入後は Copilot CLI 自身が `bin\copilot.exe` を更新するため、上記の版は初回導入と明示的な再インストールで使用する版です。

### Antigravity CLI

from [google-antigravity/antigravity-cli](https://github.com/google-antigravity/antigravity-cli)

- [/releases/tag/1.2.7](https://github.com/google-antigravity/antigravity-cli/releases/tag/1.2.7)
    - [agy_cli_windows_x64.zip](https://github.com/google-antigravity/antigravity-cli/releases/download/1.2.7/agy_cli_windows_x64.zip)

devbin-win は公式インストーラーを使わずに `bin\agy.exe` へ直接配置するため、`agy install` によるユーザー PATH とシェル設定の変更は行いません。
Antigravity CLI は既定値では選択されていないため、コンポーネント マネージャーで選択して導入してください。
利用には Google アカウントでのサインイン、または環境変数 `GEMINI_API_KEY` が必要です。
導入後は Antigravity CLI 自身が更新するため、上記の版は初回導入と明示的な再インストールで使用する版です。

### GitLab CLI

from [gitlab-org/cli](https://gitlab.com/gitlab-org/cli)

- [/releases/v1.118.0](https://gitlab.com/gitlab-org/cli/-/releases/v1.118.0)
    - [glab_1.118.0_windows_amd64.zip](https://gitlab.com/gitlab-org/cli/-/releases/v1.118.0/downloads/glab_1.118.0_windows_amd64.zip)

### Visual Studio Build Tools (VS 2022 C++ toolset 14.44 & Windows SDK v26100)

MSVC は Visual Studio 2022 の toolset 14.44 を維持します。Windows SDK は系列 26100 のまま、Get-Packages 時のマニフェスト再取得で最新のサービス ビルドを取り込みます。

Visual Studio Build Tools は既定値では選択されていないため、コンポーネント マネージャーで選択して導入してください。

## TODO

- VS Code などのスタート メニュー用ショートカットの作成
- HTTP_PROXY の設定

ユーザー設定・キャッシュ・操作ログの保存先と完全削除オプションは、[ユーザー設定・データの保存先](docs/user-storage.md) を参照してください。
環境変数の確認・編集手順は、[環境変数マネージャー](docs/Manage-Env.md) を参照してください。
