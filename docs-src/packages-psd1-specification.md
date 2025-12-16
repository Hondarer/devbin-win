# packages.psd1 仕様書

## 概要

packages.psd1 は、devbin-win で管理されるすべてのパッケージ情報を一元管理する PowerShell データファイルです。パッケージの定義情報を宣言的に記述することで、コードを変更せずに新しいパッケージを追加できます。

このファイルは定義駆動アーキテクチャの中核を担い、Setup-Bin.ps1 および Get-Packages.ps1 によって読み込まれます。

## ファイルの場所

```text
subscripts/config/packages.psd1
```

## 基本構造

packages.psd1 は PowerShell データファイル (.psd1) 形式で記述されます。

```powershell
@{
    Packages = @(
        @{
            Name = "パッケージ名"
            ShortName = "短縮名"
            ArchivePattern = "アーカイブファイル名のパターン (正規表現)"
            ExtractStrategy = "抽出戦略名"
            DownloadUrl = "ダウンロード URL"
            # その他、戦略固有のパラメータ
        },
        @{
            # 次のパッケージ定義...
        }
    )
}
```

## 共通プロパティ

すべてのパッケージ定義で必須となる共通プロパティです。

| プロパティ | 説明 | 型 | 必須 |
|-----------|------|-----|------|
| Name | パッケージの表示名 | string | ✅ |
| ShortName | パッケージの短縮名 (識別子) | string | ✅ |
| ArchivePattern | アーカイブファイルのパターン (正規表現) | string | ✅ |
| ExtractStrategy | 抽出戦略名 | string | ✅ |
| DownloadUrl | パッケージのダウンロード URL | string | ✅ |

### 共通プロパティの詳細

#### Name

パッケージの表示名です。ログやメッセージに使用されます。

例: `"Node.js"`, `"Microsoft JDK"`, `"PlantUML"`

#### ShortName

パッケージの短縮名で、内部的な識別子として使用されます。小文字の英数字とハイフンで構成することを推奨します。

例: `"nodejs"`, `"jdk"`, `"plantuml"`

#### ArchivePattern

packages フォルダ内でアーカイブファイルを検索する際に使用する正規表現パターンです。バージョン番号を含む柔軟なマッチングが可能です。

例:
- `"node-v.*-win-x64\.zip$"` - Node.js の ZIP ファイル
- `"microsoft-jdk-.*-windows-x64\.zip$"` - Microsoft JDK の ZIP ファイル
- `"plantuml-.*\.jar$"` - PlantUML の JAR ファイル

#### ExtractStrategy

使用する抽出戦略の名前です。利用可能な戦略については [extract-strategies-specification.md](./extract-strategies-specification.md) を参照してください。

主な戦略:
- `Standard` - 標準的な ZIP 展開
- `Subdirectory` - 特定のサブディレクトリのみ抽出
- `SubdirectoryToTarget` - サブディレクトリをターゲットディレクトリに抽出
- `VersionNormalized` - バージョン番号を正規化
- `TargetDirectory` - 指定ディレクトリに展開
- `JarWithWrapper` - JAR + cmd ラッパー生成
- `SingleExecutable` - 単一実行ファイルをコピー
- `SelfExtractingArchive` - 自己解凍実行ファイルを実行
- `InnoSetup` - innoextract で Inno Setup インストーラを解凍
- `VSBuildTools` - Visual Studio Build Tools のセットアップ

#### DownloadUrl

パッケージをダウンロードする URL です。Get-Packages.ps1 がこの URL を使用してパッケージをダウンロードします。

SourceForge の URL は自動的に実際のダウンロード URL に変換されます。

## 戦略別の定義例

各抽出戦略で必要となるプロパティは異なります。以下は代表的な戦略の定義例です。

### Standard 戦略

ZIP を展開し、すべてのファイルを bin ディレクトリに配置します。

```powershell
@{
    Name = "Node.js"
    ShortName = "nodejs"
    ArchivePattern = "node-v.*-win-x64\.zip$"
    ExtractStrategy = "Standard"
    DownloadUrl = "https://nodejs.org/dist/v22.18.0/node-v22.18.0-win-x64.zip"
}
```

**追加パラメータ**: なし

### Subdirectory 戦略

ZIP を展開後、指定されたサブディレクトリの内容のみを bin ディレクトリに配置します。

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

**追加パラメータ**:
- `ExtractPath` (必須): 抽出するサブディレクトリのパス
- `FilePattern` (オプション): 抽出するファイル名のパターン (正規表現)

### SubdirectoryToTarget 戦略

ZIP を展開後、指定されたサブディレクトリの内容を指定のターゲットディレクトリに配置します。

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

**追加パラメータ**:
- `ExtractPath` (必須): 抽出するサブディレクトリのパス
- `TargetDirectory` (必須): 配置先のディレクトリ名 (bin からの相対パス)

### VersionNormalized 戦略

ZIP を展開後、バージョン番号を含むディレクトリ名を正規化します。

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

**追加パラメータ**:
- `VersionPattern` (必須): バージョン番号を抽出する正規表現
- `TargetDirectory` (必須): ターゲットディレクトリ名 (プレースホルダー `{0}` にバージョンが埋め込まれる)

### TargetDirectory 戦略

ZIP を展開後、指定されたディレクトリ名で配置します。

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

**追加パラメータ**:
- `TargetDirectory` (必須): ターゲットディレクトリ名
- `UseLongPathSupport` (オプション): 長いパス対応を有効化 (ブール値)
- `PostSetupScript` (オプション): 後処理スクリプトのファイル名 (subscripts/config/templates 内)
- `PostExtract` (オプション): 後処理の定義

### JarWithWrapper 戦略

JAR ファイルをコピーし、実行用の cmd ラッパースクリプトを生成します。

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

**追加パラメータ**:
- `JarName` (必須): JAR ファイル名
- `WrapperName` (必須): ラッパースクリプト名
- `WrapperContent` (必須): ラッパースクリプトの内容

### SingleExecutable 戦略

実行ファイルを直接 bin ディレクトリにコピーします。

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

**追加パラメータ**:
- `TargetName` (オプション): コピー先のファイル名

### SelfExtractingArchive 戦略

自己解凍実行ファイルを実行して展開します。

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

**追加パラメータ**:
- `TargetDirectory` (必須): 展開先ディレクトリ名
- `ExtractArgs` (必須): 実行時の引数
- `PostExtract` (オプション): 後処理の定義

### InnoSetup 戦略

innoextract を使用して Inno Setup インストーラを解凍します。

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

**追加パラメータ**:
- `ExtractPath` (必須): 解凍後に抽出するサブディレクトリのパス
- `TargetDirectory` (必須): 配置先のディレクトリ名 (bin からの相対パス)

**依存関係**: innoextract パッケージが先にインストールされている必要があります。

### VSBuildTools 戦略

Setup-VSBT.ps1 を呼び出して Visual Studio Build Tools をセットアップします。

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

**追加パラメータ**:
- `DisplayName` (必須): 表示名
- `ExtractedName` (必須): 展開先ディレクトリ名
- `VSBTConfig` (必須): VSBT の設定
  - `MSVCVersion`: MSVC バージョン (空文字列の場合は最新)
  - `SDKVersion`: Windows SDK バージョン (空文字列の場合は最新)
  - `Target`: ターゲットアーキテクチャ (カンマ区切りで複数指定可)
  - `HostArch`: ホストアーキテクチャ

## 新規パッケージの追加手順

### ケース1: 既存の戦略で対応できる場合

packages.psd1 の `Packages` 配列に新しいパッケージ定義を追加するだけで完了します。

```powershell
@{
    Packages = @(
        # 既存のパッケージ定義...

        # 新規パッケージを追加
        @{
            Name = "New Tool"
            ShortName = "newtool"
            ArchivePattern = "newtool-.*-win-x64\.zip$"
            ExtractStrategy = "Standard"
            DownloadUrl = "https://example.com/newtool.zip"
        }
    )
}
```

コードの変更は不要です。

### ケース2: 新しい戦略が必要な場合

1. Setup-Strategies.psm1 に新しい戦略関数を追加
2. Invoke-ExtractStrategy の switch 文に case を追加
3. packages.psd1 に定義を追加

詳細は [extract-strategies-specification.md](./extract-strategies-specification.md) を参照してください。

## パッケージ定義の順序

packages.psd1 内のパッケージ定義の順序は重要です。依存関係がある場合は、依存先のパッケージを先に定義する必要があります。

例: OpenCppCoverage は innoextract に依存するため、innoextract を先に定義します。

```powershell
@{
    Packages = @(
        # 先に定義
        @{
            Name = "innoextract"
            # ...
        },

        # 後に定義 (innoextract に依存)
        @{
            Name = "OpenCppCoverage"
            ExtractStrategy = "InnoSetup"
            # ...
        }
    )
}
```

## 関連ドキュメント

- [extract-strategies-specification.md](./extract-strategies-specification.md) - 抽出戦略の仕様
- [setup-bin-design.md](./setup-bin-design.md) - Setup-Bin.ps1 の設計書
- [Install-Bin.md](./Install-Bin.md) - インストール・アンインストール手順
