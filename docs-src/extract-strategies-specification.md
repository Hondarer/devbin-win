# Extract Strategies 仕様書

## 概要

Extract Strategies (抽出戦略) は、パッケージのアーカイブファイルを展開し、bin ディレクトリに配置する際の処理パターンを定義したものです。各戦略は Setup-Strategies.psm1 に実装されており、packages.psd1 の `ExtractStrategy` プロパティで指定されます。

定義駆動アーキテクチャの中核を担い、新しい戦略を追加することで、複数のパッケージに適用可能な処理パターンを標準化できます。

## 実装の場所

```text
subscripts/Setup-Strategies.psm1
```

## 戦略一覧

| 戦略名 | 説明 | 主な用途 |
|--------|------|---------|
| Standard | ZIP を展開し、すべてを bin に配置 | Node.js, Pandoc, Doxygen |
| Subdirectory | 特定のサブディレクトリのみ抽出 | nkf, CMake, GNU Make, innoextract |
| SubdirectoryToTarget | サブディレクトリをターゲットディレクトリに抽出 | Graphviz |
| VersionNormalized | バージョン番号を正規化 | JDK, Python |
| TargetDirectory | 指定ディレクトリに展開 | .NET SDK, VS Code |
| JarWithWrapper | JAR + cmd ラッパー生成 | PlantUML |
| SingleExecutable | 単一実行ファイルをコピー | NuGet |
| SelfExtractingArchive | 自己解凍実行ファイルを実行 | Portable Git |
| InnoSetup | innoextract で Inno Setup インストーラを解凍 | OpenCppCoverage |
| VSBuildTools | Visual Studio Build Tools のセットアップ | VSBT |

## 共通関数

Setup-Strategies.psm1 では、複数の戦略で共有される共通関数を提供しています。

### Unblock-ArchiveFile

アーカイブファイルをブロック解除します。ダウンロードしたファイルに付加される Zone.Identifier を削除します。

```powershell
function Unblock-ArchiveFile {
    param([string]$ArchiveFile)
    # ...
}
```

### Expand-ArchiveToTemp

アーカイブを一時ディレクトリに展開します。ZIP と 7z 形式をサポートします。

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

展開されたアーカイブの実際のソースパスを取得します。単一フォルダの場合はそのフォルダを、複数フォルダまたはファイルのみの場合は TempDir を返します。

```powershell
function Get-ExtractedSourcePath {
    param([string]$TempDir)
    # ...
}
```

## 各戦略の詳細

### Standard 戦略

ZIP を展開し、すべてのファイルを bin ディレクトリに配置します。

#### パラメータ

なし (共通プロパティのみ)

#### 処理フロー

1. アーカイブをブロック解除
2. 一時ディレクトリに展開
3. ソースパスを特定
4. すべてのファイルを bin ディレクトリにコピー

#### 使用例

```powershell
@{
    Name = "Node.js"
    ShortName = "nodejs"
    ArchivePattern = "node-v.*-win-x64\.zip$"
    ExtractStrategy = "Standard"
    DownloadUrl = "https://nodejs.org/dist/v22.18.0/node-v22.18.0-win-x64.zip"
}
```

#### 適用パッケージ

Node.js, Pandoc, pandoc-crossref, Doxygen

### Subdirectory 戦略

ZIP を展開後、指定されたサブディレクトリの内容のみを bin ディレクトリに配置します。

#### パラメータ

| パラメータ | 説明 | 型 | 必須 |
|-----------|------|-----|------|
| ExtractPath | 抽出するサブディレクトリのパス | string | ✅ |
| FilePattern | 抽出するファイル名のパターン (正規表現) | string | ❌ |

#### 処理フロー

1. アーカイブをブロック解除
2. 一時ディレクトリに展開
3. ソースパスを特定
4. ExtractPath で指定されたサブディレクトリを検索
5. FilePattern が指定されている場合、パターンに一致するファイルのみをフィルタリング
6. サブディレクトリの内容を bin ディレクトリにコピー

#### 使用例

```powershell
@{
    Name = "nkf"
    ShortName = "nkf"
    ArchivePattern = "nkf-bin-.*\.zip$"
    ExtractStrategy = "Subdirectory"
    ExtractPath = "bin\mingw64"
    DownloadUrl = "https://github.com/Hondarer/nkf-bin/archive/refs/tags/v2.1.5-96c3371.zip"
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

#### 適用パッケージ

nkf, CMake, GNU Make, doxybook2, innoextract

### SubdirectoryToTarget 戦略

ZIP を展開後、指定されたサブディレクトリの内容を指定のターゲットディレクトリに配置します。Subdirectory 戦略との違いは、抽出先が bin 直下ではなく、bin 内の特定のサブディレクトリになる点です。

#### パラメータ

| パラメータ | 説明 | 型 | 必須 |
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
    DownloadUrl = "https://gitlab.com/api/v4/projects/4207231/packages/generic/graphviz-releases/14.0.2/windows_10_cmake_Release_Graphviz-14.0.2-win64.zip"
}
```

この例では、アーカイブ内の `bin` フォルダが `bin/graphviz` に配置されます。

#### 適用パッケージ

Graphviz

### VersionNormalized 戦略

ZIP を展開後、バージョン番号を含むディレクトリ名を正規化します。パッケージのバージョンが変わっても、一貫したディレクトリ名を維持できます。

#### パラメータ

| パラメータ | 説明 | 型 | 必須 |
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
    DownloadUrl = "https://aka.ms/download-jdk/microsoft-jdk-21.0.8-windows-x64.zip"
}
```

この例では、`jdk-21.0.8+9` が `jdk-21` に正規化されます。

#### 適用パッケージ

Microsoft JDK

### TargetDirectory 戦略

ZIP を展開後、指定されたディレクトリ名で配置します。

#### パラメータ

| パラメータ | 説明 | 型 | 必須 |
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

PostExtract では以下の後処理がサポートされています。

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

#### 使用例

基本的な使用例:

```powershell
@{
    Name = ".NET SDK"
    ShortName = "dotnet10sdk"
    ArchivePattern = "dotnet-sdk-.*-win-x64\.zip$"
    ExtractStrategy = "TargetDirectory"
    TargetDirectory = "dotnet10sdk"
    DownloadUrl = "https://builds.dotnet.microsoft.com/dotnet/Sdk/10.0.103/dotnet-sdk-10.0.103-win-x64.zip"
}
```

PostSetupScript を使用した例:

```powershell
@{
    Name = "Python"
    ShortName = "python"
    ArchivePattern = "python-(\d+\.\d+)\.\d+-embed-amd64\.zip$"
    ExtractStrategy = "TargetDirectory"
    TargetDirectory = "python-3.13"
    PostSetupScript = "python-setup.ps1"
    DownloadUrl = "https://www.python.org/ftp/python/3.13.7/python-3.13.7-embed-amd64.zip"
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

.NET SDK, Python, VS Code, ReportGenerator

### JarWithWrapper 戦略

JAR ファイルをコピーし、実行用の cmd ラッパースクリプトを生成します。Java アプリケーションの実行を簡素化します。

#### パラメータ

| パラメータ | 説明 | 型 | 必須 |
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
set "JAVA_HOME=%SCRIPT_DIR%jdk-21"
"%JAVA_HOME%\bin\java.exe" -jar "%SCRIPT_DIR%plantuml.jar" %*

endlocal
"@
    DownloadUrl = "https://github.com/plantuml/plantuml/releases/download/v1.2025.4/plantuml-1.2025.4.jar"
}
```

#### 適用パッケージ

PlantUML

### SingleExecutable 戦略

実行ファイルを直接 bin ディレクトリにコピーします。アーカイブではなく、単一の実行ファイルをダウンロードする場合に使用します。

#### パラメータ

| パラメータ | 説明 | 型 | 必須 |
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
    DownloadUrl = "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe"
}
```

#### 適用パッケージ

NuGet

### SelfExtractingArchive 戦略

自己解凍実行ファイルを実行して展開します。7z.exe や Setup.exe などの自己解凍アーカイブに対応します。

#### パラメータ

| パラメータ | 説明 | 型 | 必須 |
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
    Name = "Portable Git"
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
}
```

#### 適用パッケージ

Portable Git

### InnoSetup 戦略

innoextract を使用して Inno Setup インストーラを解凍します。Inno Setup で作成されたインストーラからファイルを抽出します。

#### パラメータ

| パラメータ | 説明 | 型 | 必須 |
|-----------|------|-----|------|
| ExtractPath | 解凍後に抽出するサブディレクトリのパス | string | ✅ |
| TargetDirectory | 配置先のディレクトリ名 (bin からの相対パス) | string | ✅ |

#### 処理フロー

1. bin ディレクトリ内の innoextract.exe を使用してインストーラを一時ディレクトリに解凍
2. ExtractPath で指定されたサブディレクトリを特定
3. TargetDirectory で指定された名前のディレクトリとして bin に配置

#### 依存関係

innoextract パッケージが先にインストールされている必要があります。packages.psd1 での定義順序により、この依存関係は自動的に満たされます。

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

この例では、Inno Setup インストーラから `app` フォルダが抽出され、`bin/OpenCppCoverage` に配置されます。

#### 適用パッケージ

OpenCppCoverage

### VSBuildTools 戦略

Setup-VSBT.ps1 を呼び出して Visual Studio Build Tools をセットアップします。MSVC と Windows SDK をポータブル形式でダウンロード・展開します。

#### パラメータ

| パラメータ | 説明 | 型 | 必須 |
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

## 新しい戦略の追加

新しい抽出パターンが必要な場合、以下の手順で新しい戦略を追加できます。

### 1. Setup-Strategies.psm1 に戦略関数を追加

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
    # 新しい戦略のパラメータ
    CustomParam = "value"
    DownloadUrl = "https://example.com/newtool.zip"
}
```

## 関連ドキュメント

- [packages-psd1-specification.md](./packages-psd1-specification.md) - packages.psd1 の仕様
- [setup-bin-design.md](./setup-bin-design.md) - Setup-Bin.ps1 の設計書
- [Install-Bin.md](./Install-Bin.md) - インストール・アンインストール手順
