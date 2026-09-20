# Development Tools Installation Guide

このガイドでは、開発ツールのインストール・アンインストール方法について説明します。

## インストール

### かんたんインストール (推奨)

1. このフォルダーをダウンロード フォルダーやデスクトップなどへ配置
2. `Manage-Bin.cmd` をダブルクリックして実行
3. 初回は既定のコンポーネントが選択済みのため、Enter キーで適用内容を確認し、Y キーで実行します

```cmd
Manage-Bin.cmd
```

VS Code、Visual Studio Build Tools、GitHub Copilot CLI、Antigravity CLI は既定値では選択されません。
必要な場合は Space キーで選択してから Enter キーを押してください。
すべて導入する場合は A キーで全選択します。

### インストール内容

- **インストール先**: `C:\ProgramData\<ユーザー名>\devbin-win\bin`
- **PATH環境変数**: パッケージ定義に基づいて自動的にユーザー PATH に追加。低優先度指定の項目は既存 PATH の後段に配置
- **既存ツール保護**: システムに同じツールがある場合は既存を優先

### インストール後の確認

新しいコマンド プロンプトまたは PowerShell を開き、次のコマンドで確認します。

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
agy --version
glab --version
```

PowerShell では `ni` が標準エイリアス (`New-Item`) と衝突します。
PowerShell で `@antfu/ni` の `ni` コマンドを使用する場合は、セッション内で `Remove-Item Alias:ni -Force` を実行してください。
`cmd /c ni` や Git Bash では、この衝突は発生しません。

## 操作ログ

`Manage-Bin.cmd` と `Setup-Bin.ps1` の Manage および Uninstall は、外部で Transcript を取得しなくても操作結果をファイルへ記録します。
保存先は導入先によらず `%ProgramData%\%USERNAME%\log` です。
既定の導入先では、`C:\ProgramData\<ユーザー名>\log\devbin-win-operation-yyyyMMdd-HHmmss.log` に保存されます。

製品フォルダーを完全削除した場合でも、このログ ファイルは保持されます。
古いログは既定では保持します。完全アンインストール時に `-RemoveLogs` を指定すると、現在記録中のログを除いて削除します。
処理の開始時に、保存先パスを画面へ表示します。

## オフライン環境での npm インストール

Node.js/npm パッケージは、ShortName ごとに依存関係ツリーを保存します。
オンライン環境で Node.js/npm が使用できる状態で、次のコマンドを実行してください。

```powershell
.\subscripts\Get-Packages.ps1
```

生成物は `packages\npm-packages\<ShortName>\` の次の構成です。

```text
package-lock.json
npm-cache-manifest.json
archives\*.tgz
```

`npm-cache-manifest.json` は、全アーカイブのバージョン、ファイル サイズ、および SHA-512 ハッシュ値を検証するために使用します。
`Manage-Bin.cmd` は、キャッシュが不足している場合に限り `Get-Packages.ps1` の自動実行を試行します。
この処理ではネットワーク接続が発生するため、完全オフラインでの導入環境では事前にキャッシュを準備し、`packages\OFFLINE` を置いてください。

導入時はレジストリ メタデータに依存せず、lockfile の `resolved` と `integrity` をキャッシュ内のローカル `.tgz` に差し替えた一時プロジェクトに対して `npm install --offline` を実行します。
処理の完了後、一時プロジェクトの `node_modules` とコマンド shim をインストール先へ配置します。

Marp CLI、Mermaid CLI、Puppeteer は Chromium をダウンロードせず、PATH、標準インストール先、および Windows の `App Paths` レジストリから既存の Microsoft Edge を自動検出して使用します。
Microsoft Edge が検出されない場合は、ブラウザーを必要とするコンポーネントの導入に失敗します。

## 完全オフラインモード

`packages` フォルダーに `OFFLINE` という空ファイルを置くと、完全オフラインモードになります。
中身は見ません。ファイルがあることだけを判定します。

このモードでは次のように動作します。

- 導入中の不足資材の自動取得を行わない。`Get-Packages.ps1` を明示実行した場合は取得する
- メニュー項目に対応する資材が `packages` に無い場合は非活性にし、状態列に `Unavailable` と表示する
- 導入済みの項目はアンインストールできる。再インストールはできない
- システムに同じツールがある `External` とは表示を分ける
- 初回導入時は、資材が `packages` にある項目を `DefaultChecked = $false` であってもチェック状態にする

オンライン環境で資材を揃えたあと、オフライン環境へコピーしてから `packages\OFFLINE` を置いてください。

1. オンライン環境で `Get-Packages.ps1` を実行
2. `packages` フォルダーを含むリポジトリ全体をコピー
3. オフライン環境の `packages` フォルダーへ空の `OFFLINE` を置く
4. `Manage-Bin.cmd` を実行
5. 新しいターミナルでコマンドを確認

## パッケージの補足

### cloc について

cloc はソースコードの空行・コメント行・コード行を数えるツールです。

- **用途**: リポジトリやディレクトリ単位のコード行数集計
- **配置場所**: `bin\cloc.exe`
- **バージョン**: 2.10
- **プロジェクト**: [AlDanial/cloc](https://github.com/AlDanial/cloc)

### vswhere について

vswhere は Visual Studio インスタンスを検出するための Microsoft 公式ツールです。

- **用途**: Visual Studio Build Tools (VSBT) の環境スクリプト (`Add-VSBT-Env-*.ps1`) で使用
- **配置場所**: `bin\vswhere.exe`
- **バージョン**: 3.1.7
- **プロジェクト**: [microsoft/vswhere](https://github.com/microsoft/vswhere)

### clang-format について

clang-format はソースコードを自動整形する LLVM ツールです。`git-clang-format` で Git との連携が可能です。

- **用途**: C/C++/Java/JavaScript 等のコード整形、Git コミット前の自動整形 (`git-clang-format`)
- **配置ファイル**: `bin\clang-format.exe`、`bin\git-clang-format`、`bin\git-clang-format.bat`
- **バージョン**: 23.1.1
- **プロジェクト**: [llvm/llvm-project](https://github.com/llvm/llvm-project)

### WinFlexBison について

WinFlexBison は Flex と GNU Bison の Windows 移植版です。
字句解析器 (lexer) および構文解析器 (parser) の生成に使用します。

- **用途**: `flex` / `bison` による字句解析器と構文解析器の生成
- **配置場所**: `bin\winflexbison`
- **コマンド**: `win_flex.exe`、`win_bison.exe`。同じディレクトリへ `flex.exe` と `bison.exe` の別名コピーを配置します
- **バージョン**: 2.5.25 (bison 3.8.2、flex 2.6.4)
- **プロジェクト**: [lexxmark/winflexbison](https://github.com/lexxmark/winflexbison)

### editorconfig-checker について

editorconfig-checker は `.editorconfig` の定義に対してファイルのフォーマットを検証するツールです。

- **用途**: `.editorconfig` ルールへの準拠チェック (インデント、改行コード、末尾空白など)
- **配置ファイル**: `bin\editorconfig-checker.exe`
- **バージョン**: 3.7.0
- **プロジェクト**: [editorconfig-checker/editorconfig-checker](https://github.com/editorconfig-checker/editorconfig-checker)

### gh について

gh は GitHub の Issue・Pull Request・リリース等をコマンドラインから操作する公式 CLI です。

- **用途**: GitHub の Issue/PR/Release 操作、ワークフロー実行
- **配置ファイル**: `bin\gh.exe`
- **バージョン**: 2.101.0
- **プロジェクト**: [cli/cli](https://github.com/cli/cli)

### Copilot CLI について

GitHub Copilot CLI は、ターミナルから GitHub Copilot を利用するための公式 CLI です。

- **用途**: ターミナル上でのコード調査、編集、デバッグ、GitHub 操作
- **配置ファイル**: `bin\copilot.exe`
- **バージョン**: 1.0.86 (初回導入時。導入後は自己更新する)
- **プロジェクト**: [github/copilot-cli](https://github.com/github/copilot-cli)
- **前提条件**: PowerShell 6 以上、GitHub Copilot の有効な契約

Copilot CLI は既定値では選択されていません。
コンポーネント マネージャーで選択して導入し、初回起動時に `copilot login` または CLI 内の `/login` で認証してください。
システムに devbin-win 外の `copilot.exe` が存在する場合、コンポーネント マネージャーでは `External` と表示して導入を無効化し、既存の Copilot CLI を優先します。

導入後は Copilot CLI 自身が `bin\copilot.exe` を新しい版に入れ替えます。
このため、packages フォルダーの版が新しくなっても、コンポーネント マネージャーは `Updateable` と表示しません。
packages フォルダーの版で入れ直したい場合は、メニューで再インストールを選択してください。
自己更新時に作られる `copilot.exe.old-*` は、アンインストール時と再インストール時に削除します。

### agy について

agy は、ターミナルから Google Antigravity のエージェントを利用するための公式 CLI (Antigravity CLI) です。

- **用途**: ターミナル上でのコード調査、編集、コマンド実行
- **配置ファイル**: `bin\agy.exe`
- **バージョン**: 1.2.7 (初回導入時。導入後は自己更新する)
- **プロジェクト**: [google-antigravity/antigravity-cli](https://github.com/google-antigravity/antigravity-cli)
- **前提条件**: Google アカウント、または Gemini API キー

Antigravity CLI は既定値では選択されていません。
コンポーネント マネージャーで選択して導入し、初回起動時にブラウザーで Google アカウントにサインインしてください。
システムに devbin-win 外の `agy.exe` が存在する場合、コンポーネント マネージャーでは `External` と表示して導入を無効化し、既存の Antigravity CLI を優先します。
API キーで利用する場合は、`~/.gemini/antigravity-cli/settings.json` の `modelProvider` を `gemini` にし、環境変数 `GEMINI_API_KEY` を設定します。

公式インストーラーは `agy install` を実行してユーザー PATH とシェル設定を変更しますが、devbin-win では実行しません。
導入後は Antigravity CLI 自身が `bin\agy.exe` を新しい版に入れ替えます。`agy update` で手動更新もできます。
このため、packages フォルダーの版が新しくなっても、コンポーネント マネージャーは `Updateable` と表示しません。
packages フォルダーの版で入れ直したい場合は、メニューで再インストールを選択してください。
自己更新時に作られる `agy.exe.<数値>.old` は、アンインストール時と再インストール時に削除します。

### glab について

glab は GitLab の Issue・Merge Request・CI/CD パイプライン等をコマンドラインから操作する公式 CLI です。

- **用途**: GitLab の Issue/MR/Pipeline 操作
- **配置ファイル**: `bin\glab.exe`
- **バージョン**: 1.118.0
- **プロジェクト**: [gitlab-org/cli](https://gitlab.com/gitlab-org/cli)

## アンインストール

### かんたんアンインストール (完全削除)

インストールの途中失敗やバージョン更新時の移行不良から復帰するための完全削除手順です。
マニフェストやパッケージ定義は参照せず、対象フォルダーと該当フォルダーを参照している設定を機械的に削除します。
`bin` フォルダーが既に存在しない状態であっても実行できます。

1. `Manage-Bin.cmd` をダブルクリックして実行
2. コンポーネント マネージャーで `U` を押す
3. 確認プロンプトで `Y` を押す (Enter は不要。既定はキャンセル)

PowerShell から直接実行する場合は、対象を明示します。

```powershell
.\subscripts\Setup-Bin.ps1 -Uninstall -InstallDir "$env:ProgramData\$env:USERNAME\devbin-win\bin"
```

`-Force` パラメーターを指定すると、確認プロンプトの表示を省略します。

### アンインストール内容

対象ルート `C:\ProgramData\<ユーザー名>\devbin-win` をフォルダーごと削除します。
この削除対象には `bin` が含まれます。VS Code の設定・拡張機能を置く `data\vscode` は製品フォルダーの外にあり、`-RemoveData` を選択した場合のみ削除します。
続けて、設定値がこのフォルダー配下を参照しているユーザー PATH、ユーザー環境変数、HKCU フォント登録、Windows Terminal プロファイル、および vswhere の `installationPath` を機械的に削除します。
MinGW 用 Windows Terminal プロファイルはパスを含まないため、固定 GUID をキーとして削除します。

環境変数はセミコロン (`;`) 区切りのエントリ単位で除去します。
対象ルート配下を参照するエントリのみを取り除き、他のエントリが残る環境変数については該当エントリを除いた値を維持します。
すべてのエントリが対象となった環境変数は、環境変数自体を削除します。

削除できる対象は `C:\ProgramData\<ユーザー名>\devbin-win` に限定されています。
`-InstallDir` に他の場所を指定した場合は、いかなるファイルも削除せずに処理を拒絶します。
この制限は、リポジトリや展開された配布フォルダーの誤削除を防止するために設けています。

`%ProgramData%\%USERNAME%\data` と `log` は既定では保持します。実行前にそれぞれの削除を選択できます。CLI では `-RemoveData` / `-RemoveLogs` で指定します。`-Force` 単独では両方を保持します。data 削除時はその配下を参照するユーザー環境変数・PATH も解除します。data の外にある領域は削除しません。

設定の保存先と例外は [ユーザー設定・データの保存先](user-storage.md) を参照してください。
値がパスではない環境変数 (`DOTNET_CLI_TELEMETRY_OPTOUT` など) や、Microsoft Edge を参照する `BROWSER_PATH` も削除しません。

個別コンポーネントの削除は、同一の `Manage-Bin.cmd` から行います。
個別コンポーネントの削除・再インストールでは、`data\vscode` を保持します。VS Code の個別削除では `VSCODE_PORTABLE` を解除します。

## 既存ツールとの共存

インストール時に既存のツールが検出された場合の動作は次のとおりです。

### Java

- システムに `java.exe` が存在する場合、Microsoft JDK への PATH は追加されません
- 既存の Java インストールが優先されます

### Python

- システムに有効な `python.exe` が存在する場合、Python 3.14 への PATH は追加されません
- Windows Store の Python プロキシ (実際にはインストールされていない) は無視され、Python 3.14 がインストールされます
- 有効な Python インストールが検出された場合は既存のインストールが優先されます

### .NET SDK

- システムに `dotnet.exe` が存在する場合、.NET SDK への PATH は追加されません
- 既存の .NET SDK インストールが優先されます

### PowerShell 7

- PowerShell 7.6.6 x64 ZIP を `bin\pwsh` に展開し、`pwsh` コマンドを提供します
- Windows PowerShell 5.1 は置き換えず、並行して利用できます
- システムに devbin-win 外の `pwsh.exe` が存在する場合、コンポーネント マネージャーでは `External` と表示して導入を無効化し、既存の PowerShell 7 を優先します

### Git

- システムに `git.exe` が存在する場合、Portable Git への PATH は追加されません
- 既存の Git インストールが優先されます
- インストール後に `core.editor`、`http.sslBackend`、`core.autocrlf` のうち未設定の項目を設定します。詳細については、[Update-Git-Config](./Update-Git-Config.md) を参照してください

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
- これにより、Inkscape に同梱された `python.exe` が `python` コマンドとして優先実行される事態を防止しています

### その他のツール

- Node.js、Pandoc、Doxygen、PlantUML、cloc、vswhere などは常に PATH に追加されます

## オフライン環境での pip インストール

完全オフライン環境での pip インストールに対応しています。

### 自動対応の仕組み

`Get-Packages.ps1` の実行により、pip のソース tarball および pip インストールに必要な wheel ファイルが自動的に準備されます。

#### Python がインストール済みの環境

1. `Get-Packages.ps1` を実行すると、pip、setuptools、wheel、packaging、pytest とその依存パッケージの wheel ファイルが `packages\pip-packages` に自動ダウンロードされます
2. その後、オフライン環境に移行しても `Manage-Bin.cmd` で pip と pytest が正常にインストールされます

#### Python が未インストールの環境

1. `Get-Packages.ps1` 実行時は wheel ファイルのダウンロードをスキップします (Python がインストールされていないため)
2. `Manage-Bin.cmd` で Python をインストールします
3. 初回インストール時にオンライン接続があれば、wheel ファイルを自動的に `packages\pip-packages` に保存します
4. 次回以降はオフラインでも pip インストールが可能になります

### オフライン環境への移行手順

インターネット接続のある環境で次の手順を実行してください。

1. `Get-Packages.ps1` を実行して、全パッケージと wheel ファイルをダウンロード
2. リポジトリ全体 (特に `packages` フォルダー) をオフライン環境にコピー
3. `packages\OFFLINE` を置く
4. オフライン環境で `Manage-Bin.cmd` を実行

これにより、完全オフライン環境でも pip とプリインストール対象の pytest を含む全ツールがインストールされます。
Python 導入後は、`python -m pytest` でテストを実行できます。

詳細な設計や内部動作については、[offline-pip-design.md](./offline-pip-design.md) を参照してください。

## コンポーネント マネージャー

個別のコンポーネントを選択してインストール/アンインストール/更新できます。

### 起動方法

```cmd
Manage-Bin.cmd
```

### メニュー操作

起動すると番号付きの一覧が表示されます。
`[X]` がインストール済み、`[ ]` が未インストールです。

Space キーで選択状態を切り替えます。
未インストール項目は `[ ] <-> [X]`、インストール済み項目は `[X] -> [ ] -> [R] -> [X]` の順で切り替わります。
`cmd.exe` および `powershell.exe` の標準コンソールでは、一覧上にマウス カーソルを置いた状態でホイール スクロールも使用できます。

```text
  #  コンポーネント          状態          依存
 --- ---------------------- ------------- ------------------
  1  [X] Node.js            Installed     -
  6  [X] Microsoft JDK      Installed     -
  8  [ ] PlantUML           Not Installed -> jdk
 13  [X] GNU Make           Installed     (auto: gcc-libs, libiconv, gettext)
```

キー操作:

| キー | 動作 |
|---|---|
| ↑↓ / Wheel | 項目の移動 |
| Space | 選択状態の切り替え |
| A | 全選択 |
| N | 全解除 |
| Enter | 差分を確認して適用 |
| U | 完全アンインストール (対象フォルダーと該当フォルダーを参照している設定を削除して終了) |
| Q / Esc | 終了 |

### 依存関係の自動処理

依存コンポーネントが未インストールの場合は、確認後に自動インストールされます。
依存元コンポーネントが存在する状態でアンインストールを試行した場合は、警告が表示されます。

個別インストール時に必要なアーカイブが `packages` フォルダーに存在しない場合は、選択したコンポーネントおよび不足している依存コンポーネントのみを自動ダウンロードします。

### 既存インストールからの移行

マニフェストが存在しない既存インストール環境で `Manage-Bin.cmd` を起動した場合、現在のインストール状態を自動検出してマニフェストを生成します。
マニフェスト生成後は、コンポーネント単位の個別管理が可能になります。

## 高度な使用方法

### Setup-Bin.ps1 直接実行

より詳細な制御が必要な場合は、PowerShell スクリプトを直接実行できます。

```powershell
# 対話型コンポーネント マネージャー
.\subscripts\Setup-Bin.ps1 -Manage

# カスタムインストール先
.\subscripts\Setup-Bin.ps1 -Manage -InstallDir "C:\MyTools"

# 完全アンインストール (フォルダーと該当フォルダーを参照している設定を削除)
.\subscripts\Setup-Bin.ps1 -Uninstall -InstallDir "$env:ProgramData\$env:USERNAME\devbin-win\bin"
```

一括導入専用のモード (`-Extract` / `-Install`) は廃止されました。
全コンポーネントを導入する場合は、コンポーネント マネージャーで全選択を実行してください。

### 利用可能なオプション

```powershell
# 利用方法を表示
.\subscripts\Setup-Bin.ps1
```

## トラブルシューティング

### PowerShell 実行ポリシーエラー

`Manage-Bin.cmd` は `-ExecutionPolicy Bypass` を使用して起動するため、通常は問題ありません。

### 管理者権限エラー

`C:\ProgramData` は一般ユーザーに対しても書き込み権限が付与されているため、管理者権限は不要です。

### PATH が反映されない

新しいコマンド プロンプトまたは PowerShell を開いてください。

## Git Bash プロファイル管理

`git` パッケージをコンポーネント マネージャーからインストールまたはアンインストールすると、Windows Terminal の Git Bash および MinGW プロファイルが自動的に同期されます。
Windows Terminal が未導入の場合は、警告のみを表示して処理を継続します。

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

Git に同梱されている MinGW ツール (awk, diff など) は、他のコマンドとの衝突を防止するため、既定値では PATH に追加されません。
必要に応じて、次のスクリプトを使用して有効化または無効化を行ってください。
Windows Terminal の `Windows PowerShell (w/MinGW)` プロファイルも、`git` パッケージのインストールおよびアンインストールに連動して自動更新されます。

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

- これらのスクリプトによる設定は、実行したセッション内でのみ有効です。新しいターミナルを開く際は、再度実行してください。
- システムに既存の同名ツールが存在する場合、PATH の優先順位によって動作が変化します。
