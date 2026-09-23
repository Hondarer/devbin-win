# Extract Strategies 仕様書

## 概要

Extract Strategies (抽出戦略) は、パッケージのアーカイブ ファイルを展開し、bin ディレクトリに配置する際の処理パターンを定義したものです。
各戦略は `subscripts/Devbin/Extract` に実装されており、`packages.psd1` の `ExtractStrategy` プロパティで指定されます。

定義駆動アーキテクチャの中核を担い、新しい戦略を追加することで、複数のパッケージに適用可能な処理パターンを標準化できます。

## 実装の場所

```text
subscripts/Devbin/Extract/
+- ArchiveExtraction.ps1        (共通の展開処理)
+- StandardStrategy.ps1         (Standard)
+- SubdirectoryStrategy.ps1     (Subdirectory, SubdirectoryToTarget)
+- TargetDirectoryStrategy.ps1  (VersionNormalized, TargetDirectory)
+- ExecutableStrategy.ps1       (JarWithWrapper, SingleExecutable)
+- InstallerStrategy.ps1        (SelfExtractingArchive, InnoSetup, VSBuildTools)
+- PackageManagerStrategy.ps1   (PipInstall, NpmInstall)
+- ExtractStrategy.ps1          (戦略の呼び分け)
```

## 戦略一覧

| 戦略名 | 説明 | 主な用途 |
|--------|------|---------|
| Standard | ZIP を展開し、すべてを bin に配置 | Node.js, Pandoc, Doxygen |
| Subdirectory | 特定のサブディレクトリのみ抽出 | nkf, CMake, GNU Make, innoextract, iconv, clang-format |
| SubdirectoryToTarget | サブディレクトリをターゲットディレクトリに抽出 | Graphviz, FFmpeg |
| VersionNormalized | バージョン番号を正規化 | JDK, Python |
| TargetDirectory | 指定ディレクトリに展開 | .NET SDK, VS Code, WinFlexBison |
| JarWithWrapper | JAR + cmd ラッパー生成 | PlantUML |
| SingleExecutable | 単一実行ファイルをコピー | NuGet, cloc, vswhere |
| SelfExtractingArchive | 自己解凍実行ファイルを実行 | Git (ポータブル版) |
| InnoSetup | innoextract で Inno Setup インストーラーを解凍 | OpenCppCoverage |
| VSBuildTools | Visual Studio Build Tools のセットアップ | VSBT |
| PipInstall | python -m pip install でパッケージをインストール | yamllint |
| NpmInstall | 保存した npm キャッシュから bin へ npm install -g --offline | pnpm, @antfu/ni |

## 共通関数

`ArchiveExtraction.ps1` では、複数の戦略で共有される共通関数を提供しています。

### Unblock-ArchiveFile

アーカイブ ファイルのブロックを解除します。
ダウンロードしたファイルに付加される Zone.Identifier 代替データ ストリームを削除します。

```powershell
function Unblock-ArchiveFile {
    param([string]$ArchiveFile)
    # ...
}
```

### Expand-ArchiveToTemp

アーカイブを一時ディレクトリに展開します。
ZIP、7z、zstd 圧縮 tar (.pkg.tar.zst)、および xz 圧縮 tar (.tar.xz) 形式に対応しています。

```powershell
function Expand-ArchiveToTemp {
    param(
        [string]$ArchiveFile,
        [string]$TempDir
    )
    # ...
}
```

### Get-ExtractedSourcePath

展開されたアーカイブの実際のソース パスを取得します。
単一フォルダーの場合はそのフォルダー パスを返し、複数フォルダーまたはファイルのみで構成される場合は TempDir を返します。

```powershell
function Get-ExtractedSourcePath {
    param([string]$TempDir)
    # ...
}
```

## 各戦略の詳細

### Standard 戦略

ZIP を展開し、すべてのファイルを bin ディレクトリに配置します。

#### パラメーター

なし (共通プロパティのみ)

#### 処理フロー

1. アーカイブをブロック解除
2. 一時ディレクトリに展開
3. ソースパスを特定
4. ソースに `node_modules\<パッケージ>` がある場合は、配置先の同名ディレクトリを削除してからコピーする (Node.js 付属 npm の旧ファイルが残らないようにする)
5. すべてのファイルを bin ディレクトリにコピー

#### 使用例

```powershell
@{
    Name = "Node.js"
    ShortName = "nodejs"
    ArchivePattern = "node-v.*-win-x64\.zip$"
    ExtractStrategy = "Standard"
    DownloadUrl = "https://nodejs.org/dist/v26.9.0/node-v26.9.0-win-x64.zip"
}
```

#### 適用パッケージ

Node.js, Pandoc, pandoc-crossref, Doxygen

### Subdirectory 戦略

アーカイブの展開後、指定されたサブディレクトリの内容のみを bin ディレクトリに配置します。
ZIP に加え、MSYS2 パッケージ形式 (.pkg.tar.zst) や tar.xz 形式にも対応しています。

#### パラメーター

| パラメーター | 説明 | 型 | 必須 |
|-----------|------|-----|------|
| ExtractPath | 抽出するサブディレクトリのパス | string | ✅ |
| FilePattern | 抽出するファイル名のパターン (正規表現) | string | ❌ |
| RenameFiles | コピー時にファイル名を変更するマッピング | hashtable | ❌ |
| PostSetupScript | 抽出後に実行するスクリプトのファイル名 (BinDir を TargetPath として渡す) | string | ❌ |

#### 処理フロー

1. アーカイブをブロック解除
2. 一時ディレクトリに展開
3. ソースパスを特定
4. ExtractPath で指定されたサブディレクトリを検索
5. FilePattern が指定されている場合、パターンに一致するファイルのみをフィルタリング
6. RenameFiles が指定されている場合、ファイル名がキーに一致するファイルを値の名前に変更
7. サブディレクトリの内容を bin ディレクトリにコピー

#### 使用例

```powershell
@{
    Name = "nkf"
    ShortName = "nkf"
    ArchivePattern = "^nkf-bin-v2_1_5-windows\.zip$"
    ExtractStrategy = "Subdirectory"
    ExtractPath = ""
    FilePattern = "^nkf\.exe$"
    DownloadUrl = "https://github.com/Hondarer/nkf-bin/releases/download/v2_1_5/nkf-bin-v2_1_5-windows.zip"
}
```

ファイルパターンを使用した例:

```powershell
@{
    Name = "innoextract"
    ShortName = "innoextract"
    ArchivePattern = "innoextract-.*-windows\.zip$"
    ExtractStrategy = "Subdirectory"
    ExtractPath = "bin"
    FilePattern = "^innoextract\.exe$"
    DownloadUrl = "https://github.com/dscharrer/innoextract/releases/download/v1.9-beta1/innoextract-1.9-beta1-windows.zip"
}
```

MSYS2 パッケージ (.pkg.tar.zst) を使用した例:

`iconv.exe` は `mingw-w64-x86_64-libiconv` パッケージに含まれます。同じアーカイブから DLL のみを抽出する `mingw-w64-x86_64-libiconv` エントリとは別に、`iconv.exe` だけを抽出するエントリを定義します。

```powershell
@{
    Name = "iconv"
    ShortName = "iconv"
    ArchivePattern = "^mingw-w64-x86_64-libiconv-.*\.pkg\.tar\.zst$"
    ExtractStrategy = "Subdirectory"
    ExtractPath = "bin"
    FilePattern = "^iconv\.exe$"
    DownloadUrl = "https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-libiconv-1.19-1-any.pkg.tar.zst"
}
```

RenameFiles を使用してファイル名を変更する例:

```powershell
@{
    Name = "GNU Make"
    ShortName = "make"
    ArchivePattern = "^mingw-w64-x86_64-make-.*\.pkg\.tar\.zst$"
    ExtractStrategy = "Subdirectory"
    ExtractPath = "bin"
    FilePattern = "^mingw32-make\.exe$"
    RenameFiles = @{ "mingw32-make.exe" = "make.exe" }
    DownloadUrl = "https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-make-4.4.1-5-any.pkg.tar.zst"
}
```

この例では、`mingw32-make.exe` のファイル名を `make.exe` に変更して bin ディレクトリに配置します。

MSYS2 パッケージは展開すると `mingw64/` をルートとするディレクトリ構造になります。
`Get-ExtractedSourcePath` が `mingw64` を単一フォルダーとして認識するため、`ExtractPath` には `mingw64` を含めず、その配下のパス (例: `"bin"`) を指定します。

tar.xz アーカイブと PostSetupScript を使用した例:

```powershell
@{
    Name = "clang-format"
    ShortName = "clang-format"
    ArchivePattern = "^clang\+llvm-.*-x86_64-pc-windows-msvc\.tar\.xz$"
    ExtractStrategy = "Subdirectory"
    ExtractPath = "bin"
    FilePattern = "^(clang-format\.exe|git-clang-format|git-clang-format\.cmd)$"
    PostSetupScript = "clang-format-setup.ps1"
    DownloadUrl = "https://github.com/llvm/llvm-project/releases/download/llvmorg-23.1.1/clang+llvm-23.1.1-x86_64-pc-windows-msvc.tar.xz"
}
```

この例では、大規模な LLVM アーカイブから 3 ファイルのみを抽出し、`clang-format-setup.ps1` で `git-clang-format.bat` 内の `py` コマンドを `python3` に置換します。

#### 適用パッケージ

nkf, CMake, GNU Make, doxybook2, innoextract, iconv, mingw-w64-x86_64-gcc-libs, mingw-w64-x86_64-libiconv, mingw-w64-x86_64-gettext-runtime, clang-format, GitHub CLI, GitLab CLI, GitHub Copilot CLI, Antigravity CLI

### SubdirectoryToTarget 戦略

ZIP を展開後、指定されたサブディレクトリの内容を指定のターゲット ディレクトリに配置します。
Subdirectory 戦略との違いは、抽出先が bin 直下ではなく、bin 内の特定のサブディレクトリになる点です。

#### パラメーター

| パラメーター | 説明 | 型 | 必須 |
|-----------|------|-----|------|
| ExtractPath | 抽出するサブディレクトリのパス | string | ✅ |
| TargetDirectory | 配置先のディレクトリ名 (bin からの相対パス) | string | ✅ |

#### 処理フロー

1. アーカイブをブロック解除
2. 一時ディレクトリに展開
3. ソースパスを特定
4. ExtractPath で指定されたサブディレクトリを検索
5. bin 内に TargetDirectory を作成
6. サブディレクトリの内容を TargetDirectory にコピー

#### 使用例

```powershell
@{
    Name = "Graphviz"
    ShortName = "graphviz"
    ArchivePattern = "windows_10_cmake_Release_Graphviz-.*-win64\.zip$"
    ExtractStrategy = "SubdirectoryToTarget"
    ExtractPath = "bin"
    TargetDirectory = "graphviz"
    DownloadUrl = "https://gitlab.com/api/v4/projects/4207231/packages/generic/graphviz-releases/16.1.0/windows_10_cmake_Release_Graphviz-16.1.0-win64.zip"
}
```

この例では、アーカイブ内の `bin` フォルダーが `bin/graphviz` に配置されます。
FFmpeg も同一の戦略により、アーカイブ内の `bin` フォルダーを `bin/ffmpeg` に配置します。

#### 適用パッケージ

Graphviz, FFmpeg

### VersionNormalized 戦略

ZIP を展開後、バージョン番号を含むディレクトリ名を正規化します。
パッケージのバージョンが更新された場合でも、一貫したディレクトリ名を維持できます。

#### パラメーター

| パラメーター | 説明 | 型 | 必須 |
|-----------|------|-----|------|
| VersionPattern | バージョン番号を抽出する正規表現 | string | ✅ |
| TargetDirectory | ターゲットディレクトリ名 (プレースホルダー `{0}` にバージョンが埋め込まれる) | string | ✅ |

#### 処理フロー

1. アーカイブをブロック解除
2. 一時ディレクトリに展開
3. ソースパスを特定
4. VersionPattern でバージョン番号を抽出
5. TargetDirectory のプレースホルダー `{0}` をバージョンで置換
6. 正規化されたディレクトリ名で bin に配置

#### 使用例

```powershell
@{
    Name = "Microsoft JDK"
    ShortName = "jdk"
    ArchivePattern = "microsoft-jdk-.*-windows-x64\.zip$"
    ExtractStrategy = "VersionNormalized"
    VersionPattern = "^jdk-(\d+)"
    TargetDirectory = "jdk-{0}"
    DownloadUrl = "https://aka.ms/download-jdk/microsoft-jdk-25.0.4.1-windows-x64.zip"
}
```

この例では、`jdk-25.0.4+11` が `jdk-25` に正規化されます。

#### 適用パッケージ

Microsoft JDK

### TargetDirectory 戦略

ZIP を展開後、指定されたディレクトリ名で配置します。

#### パラメーター

| パラメーター | 説明 | 型 | 必須 |
|-----------|------|-----|------|
| TargetDirectory | ターゲットディレクトリ名 | string | ✅ |
| UseLongPathSupport | 長いパス対応を有効化 | bool | ❌ |
| PostSetupScript | 後処理スクリプトのファイル名 | string | ❌ |
| PostExtract | 後処理の定義 | hashtable | ❌ |

#### 処理フロー

1. アーカイブをブロック解除
2. 一時ディレクトリに展開
3. ソースパスを特定
4. TargetDirectory で指定された名前のディレクトリを bin に作成
5. すべてのファイルをそのディレクトリにコピー
6. PostSetupScript を実行 (指定されている場合)
7. PostExtract 処理を実行 (指定されている場合)

#### PostExtract サポート

PostExtract では次の後処理をサポートしています。

- `CreateDirectories`: ディレクトリ作成
  ```powershell
  CreateDirectories = @("dir1", "dir2")
  ```

- `CopyFiles`: 追加ファイルのコピー
  ```powershell
  CopyFiles = @(
      @{
          Source = "source.txt"
          Destination = "dest.txt"
      }
  )
  ```

`CopyFiles.Source` の相対パスは、まずリポジトリ ルートを基準に解決されます。
ファイルが検出されない場合は、既存定義との互換性を保つため、現在の作業ディレクトリを基準に解決します。
Portable Git の MinGW PATH スクリプトなど、リポジトリで管理する追加ファイルは `subscripts` を正本として指定します。

#### 使用例

基本的な使用例:

```powershell
@{
    Name = ".NET SDK"
    ShortName = "dotnet10sdk"
    ArchivePattern = "dotnet-sdk-.*-win-x64\.zip$"
    ExtractStrategy = "TargetDirectory"
    TargetDirectory = "dotnet10sdk"
    DownloadUrl = "https://builds.dotnet.microsoft.com/dotnet/Sdk/10.0.401/dotnet-sdk-10.0.401-win-x64.zip"
}
```

PostSetupScript を使用した例:

```powershell
@{
    Name = "Python"
    ShortName = "python"
    ArchivePattern = "python-(\d+\.\d+)\.\d+-embed-amd64\.zip$"
    ExtractStrategy = "TargetDirectory"
    TargetDirectory = "python3"
    PostSetupScript = "python-setup.ps1"
    DownloadUrl = "https://www.python.org/ftp/python/3.14.7/python-3.14.7-embed-amd64.zip"
}
```

長いパス対応を有効にした例:

```powershell
@{
    Name = "VS Code"
    ShortName = "vscode"
    ArchivePattern = "VSCode-win32-x64-.*\.zip$"
    ExtractStrategy = "TargetDirectory"
    TargetDirectory = "vscode"
    UseLongPathSupport = $true
    DownloadUrl = "https://update.code.visualstudio.com/latest/win32-x64-archive/stable"
}
```

#### 適用パッケージ

.NET SDK, Python, VS Code, ReportGenerator, WinFlexBison

### JarWithWrapper 戦略

JAR ファイルをコピーし、実行用の cmd ラッパースクリプトを生成します。Java アプリケーションの実行を簡素化します。

#### パラメーター

| パラメーター | 説明 | 型 | 必須 |
|-----------|------|-----|------|
| JarName | JAR ファイル名 | string | ✅ |
| WrapperName | ラッパースクリプト名 | string | ✅ |
| WrapperContent | ラッパースクリプトの内容 | string | ✅ |

#### 処理フロー

1. JAR ファイルをブロック解除
2. JAR ファイルを bin ディレクトリに JarName でコピー
3. WrapperContent の内容で WrapperName のラッパースクリプトを生成

#### 使用例

```powershell
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
set "JAVA_HOME=%SCRIPT_DIR%jdk-25"
"%JAVA_HOME%\bin\java.exe" -jar "%SCRIPT_DIR%plantuml.jar" %*

endlocal
"@
    DownloadUrl = "https://github.com/plantuml/plantuml/releases/download/v1.2026.8/plantuml-1.2026.8.jar"
}
```

#### 適用パッケージ

PlantUML

### SingleExecutable 戦略

実行ファイルを直接 bin ディレクトリにコピーします。アーカイブではなく、単一の実行ファイルをダウンロードする場合に使用します。

#### パラメーター

| パラメーター | 説明 | 型 | 必須 |
|-----------|------|-----|------|
| TargetName | コピー先のファイル名 | string | ❌ |

#### 処理フロー

1. 実行ファイルをブロック解除
2. TargetName が指定されている場合はその名前で、指定されていない場合は元のファイル名で bin ディレクトリにコピー

#### 使用例

```powershell
@{
    Name = "NuGet"
    ShortName = "nuget"
    ArchivePattern = "nuget\.exe$"
    ExtractStrategy = "SingleExecutable"
    TargetName = "nuget.exe"
    DownloadUrl = "https://dist.nuget.org/win-x86-commandline/v7.9.0/nuget.exe"
}
```

#### 適用パッケージ

NuGet, cloc, vswhere

### SelfExtractingArchive 戦略

自己解凍実行ファイルを実行して展開します。7z.exe や Setup.exe などの自己解凍アーカイブに対応します。

#### パラメーター

| パラメーター | 説明 | 型 | 必須 |
|-----------|------|-----|------|
| TargetDirectory | 展開先ディレクトリ名 | string | ✅ |
| ExtractArgs | 実行時の引数 | string | ✅ |
| PostExtract | 後処理の定義 | hashtable | ❌ |

#### 処理フロー

1. アーカイブをブロック解除
2. TargetDirectory で指定された名前のディレクトリを bin に作成
3. 自己解凍実行ファイルを ExtractArgs の引数で実行
4. PostExtract 処理を実行 (指定されている場合)

#### 使用例

```powershell
@{
    Name = "Git"
    ShortName = "git"
    ArchivePattern = "PortableGit-.*-64-bit\.7z\.exe$"
    ExtractStrategy = "SelfExtractingArchive"
    TargetDirectory = "git"
    ExtractArgs = "-y"
    PostExtract = @{
        CreateDirectories = @("etc")
        CopyFiles = @(
            @{
                Source = "post-install.bat"
                Destination = "post-install.bat"
            }
        )
    }
    DownloadUrl = "https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.1/PortableGit-2.47.1-64-bit.7z.exe"
    SkipIfCommand = "git"
    DisableIfCommand = "git"
}
```

#### 適用パッケージ

Git (ポータブル版)

### InnoSetup 戦略

`innoextract` を使用して Inno Setup インストーラーを展開します。
Inno Setup で作成されたインストーラーからファイルを抽出します。

#### パラメーター

| パラメーター | 説明 | 型 | 必須 |
|-----------|------|-----|------|
| ExtractPath | 展開後に抽出するサブディレクトリのパス | string | ✅ |
| TargetDirectory | 配置先のディレクトリ名 (bin からの相対パス) | string | ✅ |

#### 処理フロー

1. bin ディレクトリ内の innoextract.exe を使用してインストーラーを一時ディレクトリに展開
2. ExtractPath で指定されたサブディレクトリを特定
3. TargetDirectory で指定された名前のディレクトリとして bin に配置

#### 依存関係

`innoextract` パッケージが事前にインストールされている必要があります。
`packages.psd1` における定義順序により、この依存関係は自動的に満たされます。

#### 使用例

```powershell
@{
    Name = "OpenCppCoverage"
    ShortName = "opencppcoverage"
    ArchivePattern = "OpenCppCoverageSetup-x64-.*\.exe$"
    ExtractStrategy = "InnoSetup"
    ExtractPath = "app"
    TargetDirectory = "OpenCppCoverage"
    DownloadUrl = "https://github.com/OpenCppCoverage/OpenCppCoverage/releases/download/release-0.9.9.0/OpenCppCoverageSetup-x64-0.9.9.0.exe"
}
```

この例では、Inno Setup インストーラーから `app` フォルダーが抽出され、`bin/OpenCppCoverage` に配置されます。

#### 適用パッケージ

OpenCppCoverage

### VSBuildTools 戦略

`Setup-VSBT.ps1` を呼び出して Visual Studio Build Tools をセットアップします。
MSVC と Windows SDK をポータブル形式でダウンロードおよび展開します。

#### パラメーター

| パラメーター | 説明 | 型 | 必須 |
|-----------|------|-----|------|
| DisplayName | 表示名 | string | ✅ |
| ExtractedName | 展開先ディレクトリ名 | string | ✅ |
| VSBTConfig | VSBT の設定 | hashtable | ✅ |

VSBTConfig の詳細:

| プロパティ | 説明 | 型 | 必須 |
|-----------|------|-----|------|
| MSVCVersion | MSVC バージョン (空文字列の場合は最新) | string | ✅ |
| SDKVersion | Windows SDK バージョン (空文字列の場合は最新) | string | ✅ |
| Target | ターゲットアーキテクチャ (カンマ区切りで複数指定可) | string | ✅ |
| HostArch | ホストアーキテクチャ | string | ✅ |

#### 処理フロー

1. Setup-VSBT.ps1 を実行
2. VSBTConfig で指定されたバージョンの MSVC と SDK をダウンロード
3. bin/vsbt に展開
4. 環境変数設定スクリプトを生成

#### 使用例

```powershell
@{
    Name = "Visual Studio Build Tools"
    ShortName = "vsbt"
    ArchivePattern = "^$"
    ExtractStrategy = "VSBuildTools"
    DisplayName = "Visual Studio Build Tools"
    ExtractedName = "vsbt"
    VSBTConfig = @{
        MSVCVersion = ""
        SDKVersion = ""
        Target = "x64"
        HostArch = "x64"
    }
    DownloadUrl = ""
}
```

#### 適用パッケージ

Visual Studio Build Tools

### PipInstall 戦略

`python -m pip install` を実行して Python パッケージをインストールします。
アーカイブ ファイルを使用せず、`packages/pip-packages/` の wheel を正本として読み込みます。

#### パラメーター

| パラメーター | 説明 | 型 | 必須 |
|-----------|------|-----|------|
| PipPackage | pip パッケージ名 | string | ✅ |
| PipDependencies | オフライン用に一緒に取得・確認する pip 依存パッケージ名 | string[] | ❌ |
| Version | インストールするバージョン (指定時は `==Version` として渡す) | string | ❌ |

#### 処理フロー

1. Python の `TargetDirectory` (現行は `python3`) 配下の `python.exe` を特定
2. `packages\pip-packages\` に `PipPackage` と `PipDependencies` の wheel が揃っていることを確認
3. `--no-index --find-links` でオフラインインストール
4. wheel が不足している場合は PyPI へ直接フォールバックせずエラー終了

#### オフライン対応

`Get-Packages.ps1` 実行時に Python が利用可能であれば、`PipPackage` と `PipDependencies` の wheel が `packages/pip-packages/` に保存されます。
インストール時に不足している場合は `Get-Packages.ps1` による取得を試行し、取得後も不足する場合はエラーで停止します。
`PipInstall` は PyPI への直接フォールバックを行いません。

#### 使用例

```powershell
@{
    Name = "yamllint"
    ShortName = "yamllint"
    Version = "1.38.0"
    ArchivePattern = "^$"
    ExtractStrategy = "PipInstall"
    PipPackage = "yamllint"
    PipDependencies = @("pathspec", "pyyaml")
    DependsOn = @("python")
    DetectFiles = @("python3\Scripts\yamllint.exe")
}
```

#### 適用パッケージ

yamllint

### NpmInstall 戦略

devbin-win のインストール先 (`$BinDir`) を npm のグローバル prefix として、`npm install -g --offline` を実行します。
パッケージは ShortName ごとに保存した npm 自身のキャッシュから、常にオフラインで導入します。
配置、コマンド shim、依存関係の解決はすべて npm が行うため、利用者が同じ prefix で `npm -g` を実行した結果と違いはありません。

#### パラメーター

| パラメーター | 説明 | 型 | 必須 |
|-----------|------|-----|------|
| NpmPackage | npm パッケージ名 | string | ✅ |
| Version | インストールするバージョン (指定時は `@Version` として渡す) | string | ❌ |
| NpmDependencies | 本体と一緒に `npm install -g` で明示的に導入する npm package spec | string[] | ❌ |
| NpmIgnoreScripts | npm lifecycle scripts を無効化するか。未指定時は `$true` (`--ignore-scripts`)。`$false` の場合は、本体と `NpmDependencies` のスクリプトだけを `--allow-scripts` で許可する | bool | ❌ |
| Browser | `Edge` の場合、既存 Microsoft Edge を検出してブラウザ関連環境変数を設定 | string | ❌ |

#### 処理フロー

1. `$BinDir\npm.cmd` を特定
2. `packages\npm-packages\<ShortName>` のマニフェストが定義 (本体、版、`NpmDependencies`) と一致し、npm のキャッシュがそろっていることを確認
3. npm のキャッシュを一時ディレクトリへ複製 (npm はオフラインでもキャッシュへ書き込むため)
4. `npm install -g --prefix $BinDir --offline --cache <複製> <package spec>` を実行
5. `$BinDir\node_modules\<NpmPackage>` の版が定義と一致することを確認
6. 要求したパッケージのディレクトリ (`node_modules\<パッケージ>`) を所有パスとしてマニフェストへ記録

アンインストールは `npm uninstall -g --prefix $BinDir` で、本体と `NpmDependencies` のパッケージを削除します。
npm を実行できない場合は、パッケージのディレクトリと、そのパッケージを指すコマンド shim を直接削除します。
再インストールは npm が既存のパッケージを置き換えるため、先にファイルを削除しません。

npm のグローバル ツリーでは、最上位のパッケージがそれぞれ独立しています。
依存関係は peer 依存も含めて各パッケージの配下に入れ子で置かれ、パッケージ間では共有されません。
グローバル ツリーにはロックファイルもないため、状態は `$BinDir\node_modules` の実物だけで決まります。

#### npm -g との相互運用

利用者が devbin-win の npm で `npm install -g`、`npm uninstall -g`、`npm update -g` を実行した結果は、Manage-Bin のメニューの表示へ反映されます。
対象は、`packages.psd1` に `NpmInstall` として定義したパッケージだけです。

マニフェストは、devbin が最後に操作した結果です。
`NpmInstall` コンポーネントの状態は、マニフェストではなく `$BinDir\node_modules` の実物からそのつど求めます (`Get-ComponentStatus`)。
導入、アンインストール、依存元の確認で導入済みかを判定する場合も、同じく実物で判定します (`Test-ComponentInstalled`、`Get-Dependents`)。

| グローバル ツリーの状態 | Manage-Bin の表示 |
|---|---|
| 導入されていない | 未導入 (マニフェストに記録があっても) |
| 定義より古い版が導入されている | 更新可能 |
| 定義と同じか新しい版が導入されている | 導入済み |

利用者の `npm -g` の結果によって、マニフェスト、環境変数、PATH、ユーザー データの保存先を変更することはありません。
`npm -g` も環境変数を変更しないため、この表示は `npm -g` の結果と同じ状態を指します。
`bin` に PATH が通っていれば、`npm -g` で導入したコマンドはそのまま使用できます。
Manage-Bin で導入時に設定する環境変数 (Puppeteer の `PUPPETEER_SKIP_DOWNLOAD` など) が必要な場合は、Manage-Bin から再インストールしてください。
`npm -g` で導入したパッケージも Manage-Bin からアンインストールでき、`npm -g` で削除したパッケージは、マニフェストに記録が残っていても Manage-Bin から導入できます。
`packages` のキャッシュは、`Get-Packages.ps1` と、Manage-Bin の導入時における自動取得でのみ更新します。`npm -g` で導入した版はキャッシュへ取り込みません。

#### オフライン対応

`Get-Packages.ps1` は、一時 prefix に対して、ShortName ごとのキャッシュ ディレクトリを指定して `npm install -g` を実行します。
続けて、同じキャッシュだけを使って別の一時 prefix へ `npm install -g --offline` を実行し、オフラインで導入を再現できることを確認します。
検証済みのキャッシュ (パッケージのメタデータと tarball) と `npm-cache-manifest.json` を `packages\npm-packages\<ShortName>\` に保存します。
tarball の整合性は、npm がキャッシュから読み出すときに SHA-512 で検証します。
キャッシュ不足時は `Get-Packages.ps1 -PackageShortNames <ShortName>` の自動実行を試行し、取得後も不足する場合はエラーで停止します。

#### 使用例

```powershell
@{
    Name = "@antfu/ni"
    ShortName = "antfu-ni"
    Version = "30.5.0"
    ArchivePattern = "^antfu-ni-\d+\.\d+\.\d+\.tgz$"
    ExtractStrategy = "NpmInstall"
    NpmPackage = "@antfu/ni"
    NpmDependencies = @("fzf@^0.5.2", "package-manager-detector@^1.6.0", "tinyexec@^1.0.4", "tinyglobby@^0.2.15", "fdir@^6.5.0", "picomatch@^4.0.3")
    DependsOn = @("pnpm")
    DetectFiles = @("ni.cmd", "nr.cmd")
}
```

`Get-Packages.ps1` は一時 prefix に対して、専用のキャッシュ ディレクトリを指定した `npm install -g` を実行し、同じキャッシュからのオフライン導入を確認してからマニフェストを書き込みます。
作業中のキャッシュは `packages\npm-packages\.staging` に作成し、確認が済んでから既存のキャッシュと置き換えるため、未完了のキャッシュは有効と判定されません。
定義と一致する既存キャッシュは `-Force` 指定時のみ再生成します。

#### 適用パッケージ

pnpm, @antfu/ni, Marp CLI, Mermaid CLI, Widdershins, Puppeteer, MiniSearch, @plantuml/core, sharp, minimist

#### 注意事項

PowerShell の `ni` は、標準エイリアス `New-Item` と衝突します。
devbin-win はプロファイルを自動変更しないため、PowerShell で `ni` コマンドを優先したい場合は、セッション内で `Remove-Item Alias:ni -Force` を実行してください。

## 新しい戦略の追加

新しい抽出パターンが必要な場合、次の手順で新しい戦略を追加できます。

### 1. Devbin/Extract に戦略関数を追加

```powershell
# NewStrategy 戦略: 新しい抽出パターン
function Invoke-NewStrategyExtract {
    param(
        [string]$ArchiveFile,
        [string]$BinDir,
        [string]$TempDir,
        [hashtable]$Config
    )

    # 処理を実装
    # ...

    return $true
}
```

### 2. Invoke-ExtractStrategy の switch 文に case を追加

```powershell
function Invoke-ExtractStrategy {
    param(
        [hashtable]$PackageConfig,
        [string]$ArchiveFile,
        [string]$BinDir,
        [string]$ScriptDir
    )

    switch ($PackageConfig.ExtractStrategy) {
        # 既存の戦略...

        "NewStrategy" {
            return Invoke-NewStrategyExtract `
                -ArchiveFile $ArchiveFile `
                -BinDir $BinDir `
                -TempDir $tempDir `
                -Config $PackageConfig
        }

        default {
            throw "Unknown extract strategy: $($PackageConfig.ExtractStrategy)"
        }
    }
}
```

### 3. packages.psd1 に定義を追加

```powershell
@{
    Name = "New Tool"
    ShortName = "newtool"
    ArchivePattern = "newtool-.*\.zip$"
    ExtractStrategy = "NewStrategy"
    # 新しい戦略のパラメーター
    CustomParam = "value"
    DownloadUrl = "https://example.com/newtool.zip"
}
```

## 関連ドキュメント

- [packages-psd1-specification.md](./packages-psd1-specification.md) - packages.psd1 の仕様
- [setup-bin-design.md](./setup-bin-design.md) - Setup-Bin.ps1 の設計書
- [Install-Bin.md](./Install-Bin.md) - インストール・アンインストール手順
