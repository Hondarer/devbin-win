# 管理者権限なしでのポータブル版 Visual Studio Code セットアップ

## 概要

この文書では、Windows 環境で管理者権限を使わずに Visual Studio Code (以下 VS Code) をポータブル版として設置する方法と、その際の制限事項を説明します。  
ポータブル版は、システムへの変更を最小限にして、VS Code を任意のフォルダで動かせる配布形式です。  
公式の説明は [Portable Mode](https://code.visualstudio.com/docs/editor/portable) を参照してください。

本書のコマンドは、特に記載がない限り PowerShell での実行を想定しています。

## セットアップ手順

### 事前準備

次を用意します。

- Windows 用 ZIP 版 VS Code
- 必要に応じて拡張機能の .vsix ファイル

### 基本インストール手順

```powershell
# 共有可能な場所への配置
New-Item -ItemType Directory -Force -Path "C:\ProgramData\vscode" | Out-Null
Expand-Archive -Path "$env:USERPROFILE\Downloads\VSCode-win32-x64.zip" -DestinationPath "C:\ProgramData\vscode" -Force
New-Item -ItemType Directory -Force -Path "C:\ProgramData\vscode\data" | Out-Null
```

### 環境設定

#### ユーザー環境変数の設定

コマンドラインから `code` を使えるように、VS Code の bin フォルダを Path (ユーザー環境変数) に追加します。

```powershell
# 既存のユーザー Path に vscode\bin を追加
$bin = "C:\ProgramData\vscode\bin"
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (-not $userPath.Split(';') -contains $bin) {
  [Environment]::SetEnvironmentVariable('Path', ($userPath.TrimEnd(';') + ';' + $bin), 'User')
  Write-Host "Path に追加しました。新しいターミナルを開いて反映してください。"
} else {
  Write-Host "すでに Path に含まれています。"
}
```

参考: コマンドラインオプションは [Command line interface](https://code.visualstudio.com/docs/editor/command-line) を参照してください。

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

事前にダウンロードした .vsix を使ってオフラインで拡張機能をインストールできます。

```powershell
"C:\ProgramData\vscode\Code.exe" --install-extension "$env:USERPROFILE\Downloads\path_to_extension.vsix"
```

マーケットプレースからの通常インストールや .vsix の説明は [Extension Marketplace](https://code.visualstudio.com/docs/editor/extension-marketplace) を参照してください。

## ポータブルモードの特徴

### 動作原理

VS Code の実行ファイルと同じ場所に `data` フォルダを置くとポータブルモードになります。次の情報がすべて `data` 配下に保存されます。

- ユーザー設定
- インストール済み拡張機能
- ワークスペース設定
- ユーザースニペット

詳細は公式の [Portable Mode](https://code.visualstudio.com/docs/editor/portable) を参照してください。

### データ保存場所

```text
vscode/
├─ Code.exe            # 実行ファイル
├─ resources/          # リソース
└─ data/               # このフォルダの存在でポータブルモード有効
   ├─ user-data/       # 設定など
   └─ extensions/      # 拡張機能
```

## 制限事項と注意点

### 自動更新の無効化

ポータブルモードでは自動更新が無効です (公式仕様) [参考: [Portable Mode](https://code.visualstudio.com/docs/editor/portable)]。

- セキュリティ修正が自動適用されない
- 新機能が自動更新されない
- 手動で更新する必要がある

定期的な更新チェックの一例です (GitHub API を使用)。  
ネットワーク制限がある環境では動かない場合があります。

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

- ファイルの関連付けを自動設定しない
- レジストリ登録を行わない
- エクスプローラーの右クリックメニューを自動追加しない

このため、ファイルのダブルクリックで VS Code が開かなかったり、コンテキストメニューに「VS Code で開く」が出ないことがあります。必要に応じて手動で設定してください (管理者権限が必要になる場合があります)。

### 依存関係の制限

一部の拡張機能やデバッガーはシステムレベルのコンポーネントを必要とします。

- 例: .NET デバッガー、C/C++ のデバッグツール、Python の自動検出 など
- 初回セットアップで追加のランタイムや SDK を求められることがあります

## 手動更新手順

### 完全な再インストール方法

```powershell
# 1. データのバックアップ
robocopy "C:\ProgramData\vscode\data" "$env:TEMP\VS Code_backup\data" /MIR

# 2. VS Code 終了
Stop-Process -Name Code -ErrorAction SilentlyContinue

# 3. 新バージョンの展開 (ダウンロードした ZIP のパスを指定)
Expand-Archive -Path "$env:USERPROFILE\Downloads\VSCode-new-version.zip" -DestinationPath "C:\ProgramData\vscode" -Force

# 4. データの復元
robocopy "$env:TEMP\VS Code_backup\data" "C:\ProgramData\vscode\data" /MIR
```

## 利用シーンの適性

### 適している場面

- 企業環境などで管理者権限がない場合
- 複数 PC で同じ設定を持ち運びたい場合
- USB メモリで持ち運んで使いたい場合

### 適していない場面

- 常に最新バージョンを自動で使いたい場合
- システム統合 (関連付けやコンテキストメニュー) を重視する場合
- 複雑なデバッグ環境を必要とする場合

## まとめ

ポータブル版 VS Code は、管理者権限なしで開発環境を整えたいときに有効です。一方で、自動更新が無効であることやシステム統合が弱いことは避けられません。  
利用環境や要件に合わせて採用を判断してください。定期的な手動更新とバックアップを組み合わせれば、現実的に運用できます。
