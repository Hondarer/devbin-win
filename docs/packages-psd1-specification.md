# packages.psd1 仕様書

## 概要

`packages.psd1` は、devbin-win で管理されるすべてのパッケージ情報を一元管理する PowerShell データ ファイルです。
パッケージの定義情報を宣言的に記述することで、コードを変更せずに新しいパッケージを追加できます。

このファイルは定義駆動アーキテクチャの中核を担い、`Setup-Bin.ps1` および `Get-Packages.ps1` によって読み込まれます。

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
            # その他、戦略固有のパラメーター
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
| Version | パッケージのバージョン番号。マニフェストに記録され、`Manage-Bin.cmd` ではこの値とマニフェスト記録値を比較して `Updateable` 判定に使用する (`SelfUpdating = $true` の場合は比較しない)。バージョン管理の対象外の場合は `""` を指定する | string | ✅ |
| DownloadVersion | ダウンロード保存名を固定するためのバージョン。配布ファイル名にバージョンが含まれない場合に、`DownloadFileName` と組み合わせて使用する | string | ❌ |
| VersionSource | インストール時/更新判定時にアーカイブ内容から実バージョンを読み取る定義 | hashtable | ❌ |
| ArchivePattern | アーカイブファイルのパターン (正規表現) | string | ✅ |
| ExtractStrategy | 抽出戦略名 | string | ✅ |
| DownloadUrl | パッケージのダウンロード URL | string | ✅ |
| DownloadFileName | packages フォルダーへ保存するファイル名を明示指定する。未指定時は URL から算出後、必要に応じて Version を付与して正規化する | string | ❌ |
| DownloadHeaders | ダウンロード時に `Invoke-WebRequest` へ渡す HTTP ヘッダー。配布元が `User-Agent` や `Referer` を要求する場合に指定する | hashtable | ❌ |

## コンポーネント管理プロパティ

コンポーネント マネージャー (`Manage-Bin.cmd`) が使用するプロパティです。`PathDirs` / `PathPosition` / `SkipIfCommand` は PATH の再構成に使用されます。

| プロパティ | 説明 | 型 | 省略時の動作 |
|-----------|------|-----|------------|
| DependsOn | 依存パッケージの ShortName 配列 | string[] | `@()` (依存なし) |
| PathDirs | PATH に追加するディレクトリ ($InstallDir からの相対パス) | string[] | `@()` (PATH 変更なし) |
| PathPosition | `PathDirs` を既存 PATH の前後どちらに配置するか。`Prepend` または `Append` | string | `"Prepend"` |
| EnvVars | 設定する環境変数のハッシュテーブル | hashtable | `@{}` (環境変数変更なし) |
| EnvVarIsLiteral | リテラル値として扱う環境変数名の配列 | string[] | `@()` (全てパスとして結合) |
| DetectFiles | インストール状態を検出するファイル ($InstallDir からの相対パス) | string[] | `@()` (ファイル検出なし) |
| PostInstallScripts | インストール完了後に実行する後処理スクリプト定義の配列 | hashtable[] | `@()` (後処理なし) |
| PostUninstallScripts | アンインストール完了後に実行する後処理スクリプト定義の配列 | hashtable[] | `@()` (後処理なし) |
| SkipIfCommand | このコマンドが PATH にある場合は PathDirs の追加をスキップ | string | なし (常に追加) |
| DisableIfCommand | このコマンドが devbin-win 外部の PATH に見つかった場合、メニューでのインストール操作を無効化する。インストール済みであればアンインストールは可能 | string | なし (常に有効) |
| DisableIfFont | このフォント名を持つ登録が HKCU/HKLM にあり、かつ HKCU の value data が devbin-win 配下を指していない場合、メニューでのインストール操作を無効化する。UI 表示は `External` に統一 | string | なし (常に有効) |
| Hidden | `$true` なら CLI メニューに表示しない | bool | `$false` (表示) |
| DefaultChecked | 初回導入時に、メニューで最初からチェック状態にするか | bool | `$false` (チェックしない) |
| SelfUpdating | `$true` なら、導入後にツール自身が実行ファイルを更新するものとして扱い、`Updateable` 判定を行わない | bool | `$false` (更新判定あり) |
| CleanupPatterns | ツールが実行時に生成し、マニフェストに記録されないファイルのパターン ($InstallDir からの相対パス)。アンインストール時と再インストール時に削除する | string[] | `@()` (追加削除なし) |

### DependsOn

依存するパッケージの ShortName を配列で指定します。
コンポーネント マネージャーが依存関係を自動解決し、依存先を先にインストールします。

```powershell
DependsOn = @("jdk")                  # JDK が必要
DependsOn = @("innoextract")          # innoextract が必要
DependsOn = @("mingw64-gcc-libs", "mingw64-libiconv", "mingw64-gettext-runtime")
```

### PathDirs

インストール後にユーザー PATH へ追加するディレクトリを `$InstallDir` からの相対パスで指定します。

```powershell
PathDirs = @("jdk-25\bin")            # bin/jdk-25/bin を PATH に追加
PathDirs = @("git", "git\bin", "git\cmd")  # 複数ディレクトリを追加
PathDirs = @()                        # PATH 変更なし (bin/ ルートは共通で追加される)
```

`PathDirs` の並び順は宣言順のまま保持され、パッケージ一覧の順序と組み合わせて PATH 再構成時の優先順位になります。

### PathPosition

`PathDirs` を既存 PATH の前段に配置するか後段に配置するかを指定します。
低優先度で公開したいランタイム同梱ディレクトリに使用します。

```powershell
PathDirs = @("inkscape\bin")
PathPosition = "Append"              # 既存 PATH の後段に配置
```

- `Prepend` (既定値): devbin-win 管理の高優先度 PATH ブロックへ追加
- `Append`: 既存 PATH の後段へ追加 (Inkscape 同梱の `python.exe` が優先実行される事態を回避したい場合などに使用)

### EnvVars と EnvVarIsLiteral

設定する環境変数を `名前 = 値` のハッシュテーブルで指定します。値の意味は次のとおりです。

- 空文字列 `""`: `$InstallDir` そのものを値として使用
- それ以外: `$InstallDir\<値>` に展開
- `EnvVarIsLiteral` に名前を列挙した変数: パス結合せずリテラル値として使用

```powershell
# .NET SDK の例
EnvVars = @{
    "DOTNET_HOME" = "dotnet10sdk"          # $InstallDir\dotnet10sdk
    "DOTNET_CLI_TELEMETRY_OPTOUT" = "1"    # リテラル "1"
}
EnvVarIsLiteral = @("DOTNET_CLI_TELEMETRY_OPTOUT")

# PlantUML の例
EnvVars = @{ "PLANTUML_HOME" = "" }        # $InstallDir そのもの
```

### DetectFiles

インストール済みかどうかをファイルシステムで確認するためのファイルパスを指定します (マニフェストが存在しない場合のフォールバックや、レガシーインストール検出に使用)。

```powershell
DetectFiles = @("jdk-25\bin\java.exe")
DetectFiles = @("plantuml.jar", "plantuml.cmd")
```

### Hidden

`$true` に設定すると CLI メニューに表示されず、他のコンポーネントの依存関係として自動的にインストールおよびアンインストールされます。
GNU Make が依存する MinGW ランタイム DLL パッケージ (`mingw64-gcc-libs` など) に使用します。

```powershell
Hidden = $true   # メニュー非表示・自動管理
```

### DefaultChecked

導入済みのコンポーネントが 1 件も無い初回導入時に、メニューで最初からチェック状態にするかどうかを指定します。
既に何かを導入済みの環境では、この値ではなく各コンポーネントの導入状態に従って選択が決まるため、影響しません。

```powershell
DefaultChecked = $true    # 初回導入時に選択済みで表示する
```

### SelfUpdating と CleanupPatterns

導入後にツール自身が実行ファイルを入れ替えて更新する (自己更新する) パッケージに使用します。
自己更新後は、マニフェストに記録した版と実際の版が一致しなくなります。
このため `SelfUpdating = $true` を指定すると、定義の `Version` がマニフェストの記録値より新しくても `Updateable` と判定しません。
これにより、定義の版を上げたときに、自己更新で新しくなった実行ファイルを古い版で上書きする事態を防ぎます。

この場合の `Version` は、初回導入と明示的な再インストールで packages フォルダーから導入する版を示します。
packages フォルダーの版で入れ直したい場合は、メニューで再インストールを選択してください。

`CleanupPatterns` には、ツールが実行時に生成するファイルをパターンで指定します。
これらのファイルはマニフェストのファイル一覧に含まれないため、指定しないとアンインストール後に残ります。
ワイルドカードはファイル名の部分にだけ使用できます。
他のコンポーネントがマニフェストに記録しているファイルは削除しません。
実行中のプロセスが使用しているファイルは削除できないため、警告を表示して処理を続けます。

```powershell
# GitHub Copilot CLI の例: 自己更新時に旧版を copilot.exe.old-<数値>-<数値> へ退避する
SelfUpdating = $true
CleanupPatterns = @("copilot.exe.old-*")
```

### DisableIfFont

フォント系パッケージにおいて、同名フォントが既に登録済みの場合にメニューからの新規インストールを無効化する目的で使用します。

- `HKCU` の value name を照合し、value data が `$InstallDir` 配下なら devbin 自身の登録として扱う
- `HKCU` に一致があっても value data が `$InstallDir` 配下以外なら `External`
- `HKLM` に一致がある場合も `External`
- UI 表示は原因を分けず `External` に統一する

```powershell
DisableIfFont = "UDEV Gothic HSRFJPDOCEM"
```

### 共通プロパティの詳細

#### Name

パッケージの表示名です。ログやメッセージに使用されます。

例: `"Node.js"`, `"Microsoft JDK"`, `"PlantUML"`

#### ShortName

パッケージの短縮名で、内部的な識別子として使用されます。小文字の英数字とハイフンで構成することを推奨します。

例: `"nodejs"`, `"jdk"`, `"plantuml"`

#### ArchivePattern

packages フォルダー内でアーカイブファイルを検索する際に使用する正規表現パターンです。バージョン番号を含む柔軟なマッチングが可能です。

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
- `PipInstall` - python -m pip install でパッケージをインストール
- `NpmInstall` - 検証済み依存木を npm のオフライン一時 prefix へ展開

#### DownloadUrl

パッケージをダウンロードする URL です。Get-Packages.ps1 がこの URL を使用してパッケージをダウンロードします。

SourceForge の URL は自動的に実際のダウンロード URL に変換されます。

`DownloadHeaders` を指定すると、`Get-Packages.ps1` はそのハッシュテーブルを `Invoke-WebRequest -Headers` に渡します。
通常は指定不要ですが、配布元がブラウザー相当の `User-Agent` や元ページの `Referer` を要求する場合に使用します。

```powershell
DownloadHeaders = @{
    "User-Agent" = "Mozilla/5.0"
    "Referer" = "https://example.com/download-page/"
}
```

`DownloadFileName` を省略した場合、`Get-Packages.ps1` は URL から保存ファイル名を決定します。
`Version` が空ではない場合、保存ファイル名に同一バージョンが含まれていなければ、拡張子の直前に `-<Version>` を付与して packages フォルダー内の保存名を正規化します。
バージョン比較では、ピリオド (`.`)、アンダースコア (`_`)、ハイフン (`-`) の区切り文字の差異を同一と判定します (例: `2.1.5` と `2_1_5`)。

`ArchivePattern` は、配布元の元ファイル名ではなく、packages フォルダーへ保存される最終ファイル名に一致するように定義してください。
`Install-Component` には互換フォールバック機能があり、`ArchivePattern` に一致するファイルが存在しない場合に限り、URL 由来の元ファイル名が packages に存在すればそのファイルを使用します。

#### DownloadVersion と VersionSource

配布元の ZIP ファイル名にバージョンが含まれないものの、オフライン インストール用にはバージョン付きファイル名で保存したい場合は、`DownloadVersion` と `DownloadFileName` を組み合わせて指定します。

`VersionSource` を指定すると、インストール時のマニフェスト記録および `Manage-Bin.cmd` の更新判定において、`Version` の固定値ではなく取得済みアーカイブから読み取った値を使用できます。
現在サポートしている `Type` は `ZipEntry` です。

```powershell
@{
    Name = "PsTools"
    ShortName = "pstools"
    Version = ""
    DownloadVersion = "2.43"
    DownloadFileName = "PSTools-2.43.zip"
    ArchivePattern = "^PSTools-.*\.zip$"
    VersionSource = @{
        Type = "ZipEntry"
        Path = "psversion.txt"
        Pattern = "\d+(?:\.\d+)+"
    }
}
```

`ZipEntry` は、`ArchivePattern` に一致する ZIP アーカイブの中から `Path` のエントリを読み取り、`Pattern` に最初に一致した文字列をバージョンとして使用します。
該当する ZIP が `packages` に存在しない場合は、空文字列または `Version` の値にフォールバックするため、自動的な `Updateable` 判定は行われません。

## 戦略別の定義例

各抽出戦略で必要となるプロパティは異なります。
代表的な戦略の定義例は、次のとおりです。

### Standard 戦略

ZIP を展開し、すべてのファイルを bin ディレクトリに配置します。

```powershell
@{
    Name = "Node.js"
    ShortName = "nodejs"
    ArchivePattern = "node-v.*-win-x64\.zip$"
    ExtractStrategy = "Standard"
    DownloadUrl = "https://nodejs.org/dist/v25.9.0/node-v25.9.0-win-x64.zip"
}
```

**追加パラメーター**: なし

### Subdirectory 戦略

アーカイブを展開後、指定されたサブディレクトリの内容のみを bin ディレクトリに配置します。ZIP に加え、MSYS2 パッケージ形式 (.pkg.tar.zst) や tar.xz 形式にも対応しています。

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

MSYS2 MinGW パッケージの例 (RenameFiles 使用):

```powershell
@{
    Name = "GNU Make"
    ShortName = "make"
    ArchivePattern = "^mingw-w64-x86_64-make-.*\.pkg\.tar\.zst$"
    ExtractStrategy = "Subdirectory"
    ExtractPath = "bin"
    FilePattern = "^mingw32-make\.exe$"
    RenameFiles = @{ "mingw32-make.exe" = "make.exe" }
    DownloadUrl = "https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-make-4.4.1-4-any.pkg.tar.zst"
}
```

MSYS2 パッケージは展開するとルート フォルダーが 1 つだけ含まれる構造になります。
mingw パッケージは `mingw64/`、msys パッケージは `usr/` がルートです。
`Get-ExtractedSourcePath` がこれらを自動認識するため、`ExtractPath` にはルート フォルダーを含めず配下のパスを指定してください。

**追加パラメーター**:
- `ExtractPath` (必須): 抽出するサブディレクトリのパス
- `FilePattern` (オプション): 抽出するファイル名のパターン (正規表現)
- `RenameFiles` (オプション): コピー時にファイル名を変更するハッシュテーブル (キー: 元のファイル名、値: 変更後のファイル名)

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

**追加パラメーター**:
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
    DownloadUrl = "https://aka.ms/download-jdk/microsoft-jdk-25.0.1-windows-x64.zip"
}
```

**追加パラメーター**:
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
    DownloadUrl = "https://www.python.org/ftp/python/3.13.13/python-3.13.13-embed-amd64.zip"
}
```

**追加パラメーター**:
- `TargetDirectory` (必須): ターゲットディレクトリ名
- `UseLongPathSupport` (オプション): 長いパス対応を有効化 (ブール値)
- `PostSetupScript` (オプション): 後処理スクリプトのファイル名 (subscripts/config/templates 内)
- `PostExtract` (オプション): 後処理の定義

### PostInstallScripts / PostUninstallScripts

コンポーネント マネージャーの install / uninstall 完了後に追加で実行するスクリプトを定義します。

```powershell
@{
    Name = "Portable Git"
    ShortName = "git"
    PostInstallScripts = @(
        @{
            Path = "Update-GitBash-Profile.ps1"
            Arguments = @("-Install", "-Force", "-InstallDir", "<InstallDir>")
        }
    )
    PostUninstallScripts = @(
        @{
            Path = "Update-GitBash-Profile.ps1"
            Arguments = @("-Uninstall")
        }
    )
}
```

- `Path` (必須): `subscripts/` からの相対パス
- `Arguments` (オプション): 引数配列。`<InstallDir>` は実際のインストール先に置換される
- スクリプトの実行に失敗した場合は警告を出力し、本体のインストールまたはアンインストール処理は継続

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
set "JAVA_HOME=%SCRIPT_DIR%jdk-25"
"%JAVA_HOME%\bin\java.exe" -jar "%SCRIPT_DIR%plantuml.jar" %*

endlocal
"@
    DownloadUrl = "https://github.com/plantuml/plantuml/releases/download/v1.2026.2/plantuml-1.2026.2.jar"
}
```

**追加パラメーター**:
- `JarName` (必須): JAR ファイル名
- `WrapperName` (必須): ラッパースクリプト名
- `WrapperContent` (必須): ラッパースクリプトの内容

### SingleExecutable 戦略

実行ファイルを直接 bin ディレクトリにコピーします。

```powershell
@{
    Name = "NuGet"
    ShortName = "nuget"
    ArchivePattern = "nuget-.*\.exe$"
    ExtractStrategy = "SingleExecutable"
    TargetName = "nuget.exe"
    DownloadUrl = "https://dist.nuget.org/win-x86-commandline/v7.3.1/nuget.exe"
}
```

**追加パラメーター**:
- `TargetName` (オプション): コピー先のファイル名

NuGet、cloc、vswhere のように、配布物が単体の `.exe` で完結するツールに適しています。

`DownloadFileName` は、保存ファイル名を明示的に固定したい場合に指定します。
たとえば VS Code の公式固定版 URL は末尾が `stable` となるため、`DownloadFileName = "VSCode-win32-x64-1.128.0.zip"` のように指定します。
未指定の場合であっても `Version` が定義されていれば、保存ファイル名は自動的にバージョン付きのファイル名へ正規化されます (区切り文字の差異は同一バージョンとして判定)。

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
    SkipIfCommand = "git"
    DisableIfCommand = "git"
}
```

**追加パラメーター**:
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

**追加パラメーター**:
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

**追加パラメーター**:
- `DisplayName` (必須): 表示名
- `ExtractedName` (必須): 展開先ディレクトリ名
- `VSBTConfig` (必須): VSBT の設定
  - `MSVCVersion`: MSVC バージョン (空文字列の場合は最新)
  - `SDKVersion`: Windows SDK バージョン (空文字列の場合は最新)
  - `Target`: ターゲットアーキテクチャ (カンマ区切りで複数指定可)
  - `HostArch`: ホストアーキテクチャ

### PipInstall 戦略

`python -m pip install` を実行して Python パッケージをインストールします。
アーカイブ ファイルは不要であり、`DownloadUrl` も省略します。
インストール処理は `packages/pip-packages/` の wheel を使用し、PyPI へ直接フォールバックしません。

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
    PathDirs = @()
    EnvVars = @{}
    DetectFiles = @("python-3.13\Scripts\yamllint.exe")
    DefaultChecked = $true
}
```

**追加パラメーター**:
- `PipPackage` (必須): pip パッケージ名
- `PipDependencies` (任意): オフライン用に一緒に取得・確認する pip 依存パッケージ名
- `Version` (共通プロパティ): 指定時は `pip install <PipPackage>==<Version>` として渡す

`ArchivePattern = "^$"` は、アーカイブ検索をスキップするための規約です。
`DownloadUrl` は省略します。
`Get-Packages.ps1` は `PipPackage` と `PipDependencies` の wheel を `packages/pip-packages/` に保存します。
インストール時に不足している場合は `Get-Packages.ps1` による取得を試行し、取得後も不足する場合はエラーで停止します。

### NpmInstall 戦略

検証済みの依存関係ツリーを一時プロジェクトへ `npm install --offline` でインストールし、生成された `node_modules` とコマンド shim を devbin-win のインストール先へマージします。
オンライン環境では `Get-Packages.ps1` が依存関係ツリーを解決し、導入時は保存済みアーカイブと一時 npm キャッシュのみを使用します。

```powershell
@{
    Name = "pnpm"
    ShortName = "pnpm"
    Version = "11.3.0"
    ArchivePattern = "^pnpm-\d+\.\d+\.\d+\.tgz$"
    ExtractStrategy = "NpmInstall"
    NpmPackage = "pnpm"
    DependsOn = @("nodejs")
    PathDirs = @()
    EnvVars = @{}
    DetectFiles = @("pnpm.cmd", "pnpx.cmd")
    DefaultChecked = $true
}
```

**追加パラメーター**:
- `NpmPackage` (必須): npm パッケージ名
- `Version` (共通プロパティ): 指定時は `npm install <NpmPackage>@<Version>` として渡す
- `NpmDependencies` (任意): 本体の依存木とは別に、一緒に取得・導入する npm package spec
- `NpmIgnoreScripts` (任意): `$false` の場合のみ npm lifecycle scripts を許可する。未指定時は `$true`
- `Browser` (任意): `Edge` を指定すると、導入時に既存 Microsoft Edge を検出してブラウザ関連環境変数を設定する

`Get-Packages.ps1` は各 `NpmInstall` の依存木を次の形式で保存します。

```text
packages/npm-packages/<ShortName>/
  package-lock.json
  npm-cache-manifest.json
  archives/*.tgz
```

`npm-cache-manifest.json` には、全パッケージのバージョン、アーカイブ パス、ファイル サイズ、および SHA-512 ハッシュ値が記録されます。
導入時はマニフェスト、lockfile、および全アーカイブを検証し、lockfile の `resolved` と `integrity` をローカル アーカイブに差し替えてから、一時プロジェクトへ `npm install --offline` を実行します。
不足または改変が検出された場合は、npm install を開始しません。
キャッシュ不足時は `Get-Packages.ps1` の自動実行を試行し、取得後も不足する場合はエラーで停止します。
PowerShell の `ni` は標準エイリアス `New-Item` と衝突するため、必要な場合はセッション内で `Remove-Item Alias:ni -Force` を実行してください。

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
            # コンポーネント管理プロパティ
            DependsOn = @()
            PathDirs = @()
            EnvVars = @{}
            DetectFiles = @("newtool.exe")
        }
    )
}
```

コードの変更は不要です。

### ケース2: 新しい戦略が必要な場合

1. Devbin/Extract に新しい戦略関数を追加
2. Invoke-ExtractStrategy の switch 文に case を追加
3. packages.psd1 に定義を追加

詳細は [extract-strategies-specification.md](./extract-strategies-specification.md) を参照してください。

## パッケージ定義の順序

`packages.psd1` 内におけるパッケージ定義の順序は、コンポーネント マネージャーの表示順と PATH の並び順を決定します。

導入順は `DependsOn` から自動解決されるため、定義の順序には依存しません。
ただし可読性のため、依存先パッケージを先に記述することを推奨します。

例: OpenCppCoverage は innoextract に依存するため、innoextract を先に定義します。

```powershell
@{
    Packages = @(
        # 先に定義
        @{
            Name = "innoextract"
            ShortName = "innoextract"
            DependsOn = @()
            # ...
        },

        # 後に定義 (innoextract に依存)
        @{
            Name = "OpenCppCoverage"
            ShortName = "opencppcoverage"
            ExtractStrategy = "InnoSetup"
            DependsOn = @("innoextract")
            # ...
        }
    )
}
```

例: GNU Make は MinGW ランタイム DLL に依存するため、gcc-libs、libiconv、gettext-runtime を先に定義します。iconv は libiconv と同じアーカイブから `iconv.exe` のみを抽出するため、libiconv の後に定義します。

```powershell
@{
    Packages = @(
        @{ Name = "mingw-w64-x86_64-gcc-libs"; ShortName = "mingw64-gcc-libs"; DependsOn = @(); Hidden = $true; ... },
        @{ Name = "mingw-w64-x86_64-libiconv"; ShortName = "mingw64-libiconv"; DependsOn = @(); Hidden = $true; ... },
        @{ Name = "mingw-w64-x86_64-gettext-runtime"; ShortName = "mingw64-gettext-runtime"; DependsOn = @(); Hidden = $true; ... },
        @{ Name = "iconv"; ShortName = "iconv"; DependsOn = @("mingw64-libiconv"); ... },
        @{ Name = "GNU Make"; ShortName = "make"; DependsOn = @("mingw64-gcc-libs", "mingw64-libiconv", "mingw64-gettext-runtime"); ... }
    )
}
```

## 関連ドキュメント

- [extract-strategies-specification.md](./extract-strategies-specification.md) - 抽出戦略の仕様
- [setup-bin-design.md](./setup-bin-design.md) - Setup-Bin.ps1 の設計書
- [Install-Bin.md](./Install-Bin.md) - インストール・アンインストール手順
