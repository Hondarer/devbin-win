# 管理者権限なしでのポータブル版 Visual Studio Code セットアップ

## 概要

本書では、Windows 環境において管理者権限を使用せずに Visual Studio Code (以下 VS Code) をポータブル版として配置・運用する手順と、その制限事項について説明します。
ポータブル版は、OS やレジストリへの変更を最小限に抑え、任意のフォルダー配下で VS Code を実行できる配布形式です。
公式の仕様および詳細については [Portable Mode](https://code.visualstudio.com/docs/editor/portable) を参照してください。

本書に記載のコマンドは、特段の注記がない限り PowerShell での実行を想定しています。

## セットアップ手順

### 事前準備

次の資材を事前に準備します。

- Windows 向け ZIP 版 VS Code
- 必要に応じた拡張機能パッケージ (.vsix ファイル)

### 基本インストール手順

```powershell
# 共有可能な場所への配置
New-Item -ItemType Directory -Force -Path "C:\ProgramData\vscode" | Out-Null
Expand-Archive -Path "$env:USERPROFILE\Downloads\VSCode-win32-x64.zip" -DestinationPath "C:\ProgramData\vscode" -Force
New-Item -ItemType Directory -Force -Path "C:\ProgramData\vscode\data" | Out-Null
```

### 環境設定

#### ユーザー環境変数の設定

コマンドラインから `code` コマンドを実行できるように、VS Code の `bin` ディレクトリをユーザー環境変数 `PATH` に追加します。

```powershell
# 既存のユーザー Path に vscode\bin を追加
$bin = "C:\ProgramData\vscode\bin"
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (-not $userPath.Split(';') -contains $bin) {
  [Environment]::SetEnvironmentVariable('Path', ($userPath.TrimEnd(';') + ';' + $bin), 'User')
  Write-Host "Path に追加しました。新しいターミナルを開いて反映してください。"
} else {
  Write-Host "既に Path に含まれています。"
}
```

参考: 利用可能なコマンドラインオプションの詳細は [Command line interface](https://code.visualstudio.com/docs/editor/command-line) を参照してください。

#### スタートメニューへのショートカット追加

```powershell
$ws = New-Object -ComObject WScript.Shell
$lnk = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Visual Studio Code.lnk"
$sc = $ws.CreateShortcut($lnk)
$sc.TargetPath = "C:\ProgramData\vscode\Code.exe"
$sc.WorkingDirectory = "C:\ProgramData\vscode"
$sc.Save()
Write-Host "スタートメニューにショートカットを作成しました。"
```

### 拡張機能のインストール

事前にダウンロードした `.vsix` ファイルを指定することで、オフライン環境でも拡張機能をインストールできます。

```powershell
"C:\ProgramData\vscode\Code.exe" --install-extension "$env:USERPROFILE\Downloads\path_to_extension.vsix"
```

VS Code Marketplace からの通常のインストール手順や `.vsix` の詳細仕様については、[Extension Marketplace](https://code.visualstudio.com/docs/editor/extension-marketplace) を参照してください。

## ポータブルモードの特徴

### 動作原理

VS Code の実行可能ファイルと同一ディレクトリに `data` フォルダーを配置すると、ポータブルモードとして動作します。
次の各種データがすべて `data` ディレクトリ配下に集約して保存されます。

- ユーザー設定
- インストール済み拡張機能
- ワークスペース固有設定
- ユーザースニペット

詳細な動作仕様については、公式ドキュメントの [Portable Mode](https://code.visualstudio.com/docs/editor/portable) を参照してください。

### データ保存場所

```text
vscode/
+- Code.exe            # 実行ファイル
+- resources/          # リソース
+- data/               # このフォルダーの存在によりポータブルモードが有効化
   +- user-data/       # ユーザー設定など
   +- extensions/      # 拡張機能
```

## 制限事項と注意点

### 自動更新の無効化

ポータブルモードでは、アプリケーションの自動更新機能が無効化されます (公式仕様) [参考: [Portable Mode](https://code.visualstudio.com/docs/editor/portable)]。

- セキュリティ修正プログラムが自動適用されません。
- 新機能を含むバージョンアップが自動実行されません。
- 新しいバージョンへの移行は手動で実施する必要があります。

定期的な更新確認を行うスクリプト例です (GitHub REST API を使用)。
外部ネットワーク接続に制限がある環境では動作しない場合があります。

```powershell
$codeExe = "C:\ProgramData\vscode\Code.exe"
$currentVersion = & $codeExe --version | Select-Object -First 1

$headers = @{ 'User-Agent' = 'vscode-portable-check' }
$latestInfo = Invoke-RestMethod "https://api.github.com/repos/microsoft/vscode/releases/latest" -Headers $headers

if ($currentVersion -ne $latestInfo.tag_name) {
  Write-Host "新しいバージョンがあります: $($latestInfo.tag_name) (現在: $currentVersion) "
} else {
  Write-Host "最新バージョンを使用しています: $currentVersion"
}
```

### システム統合の制限

ポータブルモードでは、インストーラーによる次のシステム統合処理が行われません。

- 拡張子やファイルの関連付けの自動登録
- レジストリへのアプリケーション情報の登録
- エクスプローラーのコンテキスト (右クリック) メニューへの項目追加

そのため、ファイルをダブルクリックしても VS Code が起動しなかったり、コンテキストメニューに「VS Code で開く」が表示されなかったりする制約があります。
必要に応じて手動での設定を行ってください (設定内容によっては管理者権限が必要となる場合があります)。

### 依存関係の制限

一部の拡張機能やデバッガーは、OS レベルの共有コンポーネントや外部ランタイムを必要とします。

- 該当例: .NET デバッガー、C/C++ デバッグツール、Python ランタイムの自動検出など
- 初回セットアップ時や拡張機能の初回実行時に、追加ランタイムや SDK の導入が求められる場合があります。

## 手動更新手順

### 完全な再インストール方法

```powershell
# 1. データのバックアップ
robocopy "C:\ProgramData\vscode\data" "$env:TEMP\VS Code_backup\data" /MIR

# 2. 実行中の VS Code プロセスの終了
Stop-Process -Name Code -ErrorAction SilentlyContinue

# 3. 新バージョンの展開 (ダウンロードした ZIP のパスを指定)
Expand-Archive -Path "$env:USERPROFILE\Downloads\VSCode-new-version.zip" -DestinationPath "C:\ProgramData\vscode" -Force

# 4. データの復元
robocopy "$env:TEMP\VS Code_backup\data" "C:\ProgramData\vscode\data" /MIR
```

## 利用シーンの適性

### 適している場面

- 企業の制約などにより、管理者権限が付与されていない環境
- 複数の PC 間で同一の設定および拡張機能環境を持ち運ぶ場合
- USB メモリー等の外部ストレージに格納してポータブルに運用する場合

### 適していない場面

- 常に最新の安定版へ自動更新される運用を求める場合
- ファイルの関連付けやコンテキストメニュー等の OS 統合機能を重視する場合
- 複雑なシステムレベルの依存関係を持つデバッグ環境を必要とする場合

## まとめ

ポータブル版 VS Code は、管理者権限を保持していない Windows 環境で開発環境を構築する際に有効な選択肢です。
一方で、自動更新機能が無効化される点や、OS とのシステム統合が限定的である点には留意する必要があります。
運用要件やセキュリティポリシーに応じて適切な導入形態を判断してください。
定期的な手動更新とデータのバックアップ運用を組み合わせることで、安定した開発環境を維持できます。
