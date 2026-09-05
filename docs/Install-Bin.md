# Development Tools Installation Guide

このガイドでは、開発ツールのインストール・アンインストール方法について説明します。

## インストール

### かんたんインストール (推奨)

1. このフォルダをダウンロードフォルダやデスクトップなどに配置
2. `Install-Bin.cmd` をダブルクリックして実行

```cmd
Install-Bin.cmd
```

### インストール内容

- **インストール先**: `C:\ProgramData\<ユーザー名>\devbin-win\bin`
- **PATH環境変数**: パッケージ定義に基づいて自動的にユーザー PATH に追加。低優先度指定の項目は既存 PATH の後段に配置
- **既存ツール保護**: システムに同じツールがある場合は既存を優先

### インストール後の確認

新しいコマンドプロンプトまたは PowerShell を開いて以下のコマンドで確認します。

```cmd
node --version
pnpm --version
cmd /c ni --version
marp --version
mmdc --version
widdershins --version
pandoc --version
doxygen --version
java -version
plantuml --version
python --version
python3 --version
dotnet --version
pwsh -NoLogo -Command "$PSVersionTable.PSVersion"
git --version
code --version
cloc --version
vswhere -?
clang-format --version
win_flex --version
win_bison --version
flex --version
bison --version
editorconfig-checker --version
gh --version
copilot --version
glab --version
```

PowerShell では `ni` が標準 alias (`New-Item`) と衝突します。PowerShell で `@antfu/ni` の `ni` コマンドを使う場合は、セッション内で `Remove-Item Alias:ni -Force` を実行してください。`cmd /c ni` や Git Bash ではこの衝突は発生しません。

## オフライン環境での npm インストール

Node.js/npm パッケージは ShortName ごとに依存木を保存します。オンライン環境で Node.js/npm が使用できる状態で、次を実行してください。

```powershell
.\subscripts\Get-Packages.ps1
```

生成物は `packages\npm-packages\<ShortName>\` の次の構成です。

```text
package-lock.json
npm-cache-manifest.json
archives\*.tgz
```

`npm-cache-manifest.json` は全 archive の version・サイズ・SHA-512 を検証するために使用します。`Install-Bin.cmd` またはコンポーネントマネージャーは、cache が不足している場合だけ `Get-Packages.ps1` の自動実行を試みます。この場合はネットワークへ接続するため、完全オフライン導入では事前に cache を揃えてください。取得後も不足する場合は導入を開始せずエラーで停止します。

導入時は registry metadata に依存せず、lockfile の `resolved` と `integrity` を cache 内のローカル `.tgz` に差し替えた一時プロジェクトへ `npm install --offline` します。完了後、一時プロジェクトの `node_modules` と command shim をインストール先へ配置します。

Marp CLI、Mermaid CLI、Puppeteer は Chromium をダウンロードせず、PATH、標準インストール先、Windows の `App Paths` レジストリから既存の Microsoft Edge を自動検出して使用します。Edge が見つからない場合はブラウザを必要とするコンポーネントの導入に失敗します。

### オフライン移行手順

1. オンライン環境で `Get-Packages.ps1` を実行
2. `packages` フォルダを含むリポジトリ全体をコピー
3. オフライン環境で `Install-Bin.cmd` を実行
4. 新しいターミナルで npm コマンドと Marp/Mermaid の出力を確認

#### cloc について

cloc はソースコードの空行・コメント行・コード行を数えるツールです。

- **用途**: リポジトリやディレクトリ単位のコード行数集計
- **配置場所**: `bin\cloc.exe`
- **バージョン**: 2.08
- **プロジェクト**: [AlDanial/cloc](https://github.com/AlDanial/cloc)

#### vswhere について

vswhere は Visual Studio インスタンスを検出するための Microsoft 公式ツールです。

- **用途**: Visual Studio Build Tools (VSBT) の環境スクリプト (`Add-VSBT-Env-*.ps1`) で使用
- **配置場所**: `bin\vswhere.exe`
- **バージョン**: 3.1.7
- **プロジェクト**: [microsoft/vswhere](https://github.com/microsoft/vswhere)

#### clang-format について

clang-format はソースコードを自動整形する LLVM ツールです。`git-clang-format` で Git との連携が可能です。

- **用途**: C/C++/Java/JavaScript 等のコード整形、Git コミット前の自動整形 (`git-clang-format`)
- **配置ファイル**: `bin\clang-format.exe`、`bin\git-clang-format`、`bin\git-clang-format.bat`
- **バージョン**: 22.1.4
- **プロジェクト**: [llvm/llvm-project](https://github.com/llvm/llvm-project)

#### WinFlexBison について

WinFlexBison は Flex と GNU Bison の Windows 移植です。lexer / parser 生成に使います。

- **用途**: `flex` / `bison` による字句解析器と構文解析器の生成
- **配置場所**: `bin\winflexbison`
- **コマンド**: `win_flex.exe`、`win_bison.exe`。同じディレクトリに `flex.exe` と `bison.exe` の別名コピーを置く
- **バージョン**: 2.5.25 (bison 3.8.2、flex 2.6.4)
- **プロジェクト**: [lexxmark/winflexbison](https://github.com/lexxmark/winflexbison)

#### editorconfig-checker について

editorconfig-checker は `.editorconfig` の定義に対してファイルのフォーマットを検証するツールです。

- **用途**: `.editorconfig` ルールへの準拠チェック (インデント、改行コード、末尾空白など)
- **配置ファイル**: `bin\editorconfig-checker.exe`
- **バージョン**: 3.6.1
- **プロジェクト**: [editorconfig-checker/editorconfig-checker](https://github.com/editorconfig-checker/editorconfig-checker)

#### gh について

gh は GitHub の Issue・Pull Request・リリース等をコマンドラインから操作する公式 CLI です。

- **用途**: GitHub の Issue/PR/Release 操作、ワークフロー実行
- **配置ファイル**: `bin\gh.exe`
- **バージョン**: 2.95.0
- **プロジェクト**: [cli/cli](https://github.com/cli/cli)

#### Copilot CLI について

GitHub Copilot CLI は、ターミナルから GitHub Copilot を利用するための公式 CLI です。

- **用途**: ターミナル上でのコード調査、編集、デバッグ、GitHub 操作
- **配置ファイル**: `bin\copilot.exe`
- **バージョン**: 1.0.81
- **プロジェクト**: [github/copilot-cli](https://github.com/github/copilot-cli)
- **前提条件**: PowerShell 6 以上、GitHub Copilot の有効な契約

Copilot CLI は一括インストールでは既定で選択されません。コンポーネントマネージャーで選択して導入し、初回起動時に `copilot login` または CLI 内の `/login` で認証してください。

#### glab について

glab は GitLab の Issue・Merge Request・CI/CD パイプライン等をコマンドラインから操作する公式 CLI です。

- **用途**: GitLab の Issue/MR/Pipeline 操作
- **配置ファイル**: `bin\glab.exe`
- **バージョン**: 1.105.0
- **プロジェクト**: [gitlab-org/cli](https://gitlab.com/gitlab-org/cli)

## アンインストール

### かんたんアンインストール (完全削除)

インストールの途中失敗や版更新の移行不良から復帰するための完全削除です。マニフェストやパッケージ定義は見ず、対象フォルダとそこを指す参照を機械的に消します。`bin` フォルダが既に無くても実行できます。

1. `Manage-Bin.cmd` をダブルクリックして実行
2. コンポーネントマネージャーで `U` を押す
3. 確認プロンプトで `y` を入力

PowerShell から直接実行する場合は、対象を明示します。

```powershell
.\subscripts\Setup-Bin.ps1 -Uninstall -InstallDir "$env:ProgramData\$env:USERNAME\devbin-win\bin"
```

`-Force` を付けると確認プロンプトを省略します。

### アンインストール内容

対象ルート `C:\ProgramData\<ユーザー名>\devbin-win` をフォルダごと削除します。`bin` と VS Code の `data` も含みます。続けて、値がこのフォルダ配下を指しているユーザー PATH、ユーザー環境変数、HKCU フォント登録、Windows Terminal プロファイル、vswhere の `installationPath` を機械的に削除します。MinGW 用 Windows Terminal プロファイルはパスを含まないため、固定 GUID でも削除します。

環境変数は `;` 区切りのエントリ単位で除去します。対象ルート配下を指すエントリだけを取り除き、他のエントリが残る変数はその値を残します。すべてのエントリが対象だった変数は変数ごと削除します。

削除できるのは `C:\ProgramData\<ユーザー名>\devbin-win` だけです。`-InstallDir` に他の場所を指定した場合は、何も削除せずに拒否します。リポジトリや展開した配布フォルダを誤って消さないための制限です。

HOME (`C:\ProgramData\home\<ユーザー>` と XDG 系環境変数) は対象ルート外のため削除しません。値がパスでない環境変数 (`DOTNET_CLI_TELEMETRY_OPTOUT` など) や、Edge を指す `BROWSER_PATH` も削除しません。

個別コンポーネントの削除は同じ `Manage-Bin.cmd` で行います。こちらは VS Code の `data` を残す通常操作です。

## 既存ツールとの共存

インストール時に既存のツールが検出された場合の動作は以下の通りです。

### Java

- システムに `java.exe` が存在する場合、Microsoft JDK への PATH は追加されません
- 既存の Java インストールが優先されます

### Python

- システムに有効な `python.exe` が存在する場合、Python 3.13 への PATH は追加されません
- Windows Store の Python プロキシ (実際にはインストールされていない) は無視され、Python 3.13 がインストールされます
- 有効な Python インストールが検出された場合は既存のインストールが優先されます

### .NET SDK

- システムに `dotnet.exe` が存在する場合、.NET SDK への PATH は追加されません
- 既存の .NET SDK インストールが優先されます

### PowerShell 7

- PowerShell 7.6.3 x64 ZIP を `bin\pwsh` に展開し、`pwsh` コマンドを提供します
- Windows PowerShell 5.1 は置き換えず、並行して利用できます
- システムに devbin-win 外の `pwsh.exe` が存在する場合、コンポーネントマネージャーでは `External` と表示して導入を無効化し、既存の PowerShell 7 を優先します

### Git

- システムに `git.exe` が存在する場合、Portable Git への PATH は追加されません
- 既存の Git インストールが優先されます

### VS Code

- システムに `code.cmd` が存在する場合、VS Code への PATH は追加されません
- 既存の VS Code インストールが優先されます

### FFmpeg

- システムに `ffmpeg.exe` が存在する場合、FFmpeg への PATH は追加されません
- 既存の FFmpeg インストールが優先されます

### Inkscape

- システムに `inkscape.exe` が存在する場合、Inkscape への PATH は追加されません
- 既存の Inkscape インストールが優先されます
- devbin-win の Inkscape は低優先度の PATH 項目として扱われ、既存の Python より後ろに配置されます
- これにより Inkscape 同梱 `python.exe` が `python` コマンドを横取りしないようにしています

### その他のツール

- Node.js、Pandoc、Doxygen、PlantUML、cloc、vswhere などは常に PATH に追加されます

## オフライン環境での pip インストール

完全オフライン環境での pip インストールに対応しています。

### 自動対応の仕組み

`Get-Packages.ps1` の実行により、pip source tarball と、pip インストールに必要な wheel ファイルが自動的に準備されます。

#### Python がインストール済みの環境

1. `Get-Packages.ps1` を実行すると、pip、setuptools、wheel の wheel ファイルが `packages\pip-packages` に自動ダウンロードされます
2. その後、オフライン環境に移行しても `Install-Bin.cmd` で pip が正常にインストールされます

#### Python が未インストールの環境

1. `Get-Packages.ps1` 実行時は wheel ファイルのダウンロードをスキップします (Python がないため)
2. `Install-Bin.cmd` で Python をインストールします
3. 初回インストール時にオンライン接続があれば、wheel ファイルを自動的に `packages\pip-packages` に保存します
4. 次回以降はオフラインでも pip インストールが可能になります

### オフライン環境への移行手順

インターネット接続のある環境で以下を実行してください。

1. `Get-Packages.ps1` を実行して、全パッケージと wheel ファイルをダウンロード
2. リポジトリ全体 (特に `packages` フォルダ) をオフライン環境にコピー
3. オフライン環境で `Install-Bin.cmd` を実行

これにより、完全オフライン環境でも pip を含む全ツールがインストールされます。

詳細な設計や内部動作については、[offline-pip-design.md](./offline-pip-design.md) を参照してください。

## コンポーネントマネージャー

個別のコンポーネントを選択してインストール/アンインストール/更新できます。

### 起動方法

```cmd
Manage-Bin.cmd
```

### メニュー操作

起動すると番号付きの一覧が表示されます。`[X]` がインストール済み、`[ ]` が未インストールです。

Space キーで選択状態を切り替えます。未インストール項目は `[ ] <-> [X]`、インストール済み項目は `[X] -> [ ] -> [R] -> [X]` の順で切り替わります。`cmd.exe` / `powershell.exe` の標準コンソールでは、一覧上にマウスカーソルを置いた状態でホイールスクロールも使えます。

```text
  #  コンポーネント          状態          依存
 --- ---------------------- ------------- ------------------
  1  [X] Node.js            Installed     -
  6  [X] Microsoft JDK      Installed     -
  8  [ ] PlantUML           Not Installed -> jdk
 13  [X] GNU Make           Installed     (auto: gcc-libs, libiconv, gettext)
```

コマンド:

| コマンド | 動作 | 例 |
|---|---|---|
| `i <番号>` | インストール | `i 8` |
| `u <番号>` | アンインストール | `u 6` |
| `r <番号>` | 再インストール/更新 | `r 1 6` |
| `ia` | すべてのコンポーネントをインストール | `ia` |
| `ua` | すべてのコンポーネントをアンインストール | `ua` |
| `q` | 終了 | `q` |
| `U` | 完全アンインストール (対象フォルダとそこを指す参照を削除して終了) | `U` |

### 依存関係の自動処理

依存コンポーネントが未インストールの場合は確認後に自動インストールされます。逆に、依存元コンポーネントが存在する状態でアンインストールしようとすると警告が表示されます。

個別インストール時に必要なアーカイブが `packages` フォルダにない場合は、選択したコンポーネントと不足している依存コンポーネントだけを自動ダウンロードします。

### 既存インストールからの移行

`Install-Bin.cmd` で一括インストールした後に `Manage-Bin.cmd` を起動すると、既存のインストール状態を自動検出してマニフェストを生成します。以降は個別管理が可能になります。

## 高度な使用方法

### Setup-Bin.ps1 直接実行

より詳細な制御が必要な場合は、PowerShell スクリプトを直接実行できます。

```powershell
# ファイル抽出のみ
.\subscripts\Setup-Bin.ps1 -Extract

# インストール (抽出 + PATH 追加)
.\subscripts\Setup-Bin.ps1 -Install

# 完全アンインストール (フォルダとそこを指す参照を削除)
.\subscripts\Setup-Bin.ps1 -Uninstall -InstallDir "$env:ProgramData\$env:USERNAME\devbin-win\bin"

# 対話型コンポーネントマネージャー
.\subscripts\Setup-Bin.ps1 -Manage

# カスタムインストール先
.\subscripts\Setup-Bin.ps1 -Install -InstallDir "C:\MyTools"
```

### 利用可能なオプション

```powershell
# 利用方法を表示
.\subscripts\Setup-Bin.ps1
```

## トラブルシューティング

### PowerShell 実行ポリシーエラー

Install-Bin.cmd と Manage-Bin.cmd は `-ExecutionPolicy Bypass` を使用するため、通常は問題ありません。

### 管理者権限エラー

C:\ProgramData は通常ユーザーでも書き込み可能なため、管理者権限は不要です。

### PATH が反映されない

新しいコマンドプロンプトまたは PowerShell を開いてください。

## Git Bash プロファイル管理

`git` パッケージをコンポーネントマネージャーからインストール / アンインストールすると、Windows Terminal の Git Bash / MinGW プロファイルは自動的に同期されます。
Windows Terminal が未導入の場合は警告のみ表示して処理を継続します。

### Git Bash プロファイルをインストール

```cmd
Install-GitBash-Profile.cmd
```

### Git Bash プロファイルをアンインストール

```cmd
Uninstall-GitBash-Profile.cmd
```

詳細については、`Update-GitBash-Profile.md` を参照してください。

## MinGW ツール

Git に含まれる MinGW ツール (awk, diff など) は、他のコマンドとの衝突を避けるため、デフォルトでは PATH に追加されません。必要に応じて以下のスクリプトを使用して有効化 / 無効化してください。
Windows Terminal の `Windows PowerShell (w/MinGW)` プロファイルも、`git` パッケージの install / uninstall に連動して自動更新されます。

### MinGW PATH の追加

現在のセッションで MinGW ツールを有効化します。

**コマンドプロンプト:**

```cmd
Add-MinGW-Path.cmd
```

**PowerShell:**

```powershell
.\Add-MinGW-Path.ps1
```

### MinGW PATH の削除

現在のセッションで MinGW ツールを無効化します。

**コマンドプロンプト:**

```cmd
Remove-MinGW-Path.cmd
```

**PowerShell:**

```powershell
.\Remove-MinGW-Path.ps1
```

### 注意事項

- これらのスクリプトは有効化したセッション内でのみ有効です。
  新しいターミナルを開く際は再度実行が必要です。
- システムに既存の同名ツールがある場合、PATH の優先順位によって動作が変わります。
