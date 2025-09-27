# 管理者権限なしでのポータブル版 Visual Studio Code セットアップレポート

## 概要

このレポートでは、Windows 環境で管理者権限を使わずに Visual Studio Code（以下 VS Code）をポータブル版として設置する方法と、その際の制限事項を説明します。ポータブル版は、システムへの変更を最小限にして、VS Code を任意のフォルダで動かせる配布形式です。公式の説明は [Portable Mode](https://code.visualstudio.com/docs/editor/portable) を参照してください。

本書のコマンドは、特に記載がない限り PowerShell での実行を想定しています。

## セットアップ手順

### 1. 事前準備

インターネット接続できる環境で次を用意します。

- Windows 用 ZIP 版 VS Code（ポータブル向け）[ダウンロード](https://code.visualstudio.com/Download)
- 必要に応じて拡張機能の .vsix ファイル［参考: [Install from a VSIX](https://code.visualstudio.com/docs/editor/extension-marketplace#_install-from-a-vsix)］

### 2. 基本インストール手順

#### ユーザーディレクトリへの配置（推奨）

次の例では、ユーザープロファイル配下に VS Code を展開します。

```powershell
# ユーザーディレクトリ内にフォルダ作成
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\Applications\VS Code" | Out-Null

# ZIP ファイルの展開（ダウンロードした ZIP のパスを指定）
Expand-Archive -Path "$env:USERPROFILE\Downloads\VSCode-win32-x64.zip" -DestinationPath "$env:USERPROFILE\Applications\VS Code" -Force

# ポータブルモード有効化用の data フォルダ作成
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\Applications\VS Code\data" | Out-Null
```

#### 共有ディレクトリへの配置（代替案）

共有場所に配置したい場合の例です。環境によっては書き込みに管理者権限が必要になります。

```powershell
# 共有可能な場所への配置（権限がある場合）
New-Item -ItemType Directory -Force -Path "C:\ProgramData\VS Code" | Out-Null
Expand-Archive -Path "$env:USERPROFILE\Downloads\VSCode-win32-x64.zip" -DestinationPath "C:\ProgramData\VS Code" -Force
New-Item -ItemType Directory -Force -Path "C:\ProgramData\VS Code\data" | Out-Null
```

### 3. 環境設定

#### ユーザー環境変数の設定

コマンドラインから `code` を使えるように、VS Code の bin フォルダを Path（ユーザー環境変数）に追加します。

```powershell
# 既存のユーザー Path に VS Code\bin を追加
$bin = "$env:USERPROFILE\Applications\VS Code\bin"
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (-not $userPath.Split(';') -contains $bin) {
  [Environment]::SetEnvironmentVariable('Path', ($userPath.TrimEnd(';') + ';' + $bin), 'User')
  Write-Host "Path に追加しました。新しいターミナルを開いて反映してください。"
} else {
  Write-Host "すでに Path に含まれています。"
}
```

参考: コマンドラインオプションは [Command line interface](https://code.visualstudio.com/docs/editor/command-line) を参照してください。

#### スタートメニューへのショートカット追加（ユーザー領域）

```powershell
$ws = New-Object -ComObject WScript.Shell
$lnk = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Visual Studio Code.lnk"
$sc = $ws.CreateShortcut($lnk)
$sc.TargetPath = "$env:USERPROFILE\Applications\VS Code\Code.exe"
$sc.WorkingDirectory = "$env:USERPROFILE\Applications\VS Code"
$sc.Save()
Write-Host "スタートメニューにショートカットを作成しました。"
```

### 4. 拡張機能のインストール

事前にダウンロードした .vsix を使ってオフラインで拡張機能を入れられます。

```powershell
"$env:USERPROFILE\Applications\VS Code\Code.exe" --install-extension "C:\path\to\extension.vsix"
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
VS Code/
├─ Code.exe            # 実行ファイル
├─ resources/          # リソース
└─ data/               # このフォルダの存在でポータブルモード有効
   ├─ user-data/       # 設定など
   └─ extensions/      # 拡張機能
```

## 制限事項と注意点

### 1. 自動更新の無効化

ポータブルモードでは自動更新が無効です（公式仕様）［参考: [Portable Mode](https://code.visualstudio.com/docs/editor/portable)］。

- セキュリティ修正が自動適用されない
- 新機能が自動更新されない
- 手動で更新する必要がある

定期的な更新チェックの一例です（GitHub API を使用）。ネットワーク制限がある環境では動かない場合があります。

```powershell
$codeExe = "$env:USERPROFILE\Applications\VS Code\Code.exe"
$currentVersion = & $codeExe --version | Select-Object -First 1

$headers = @{ 'User-Agent' = 'vscode-portable-check' }
$latestInfo = Invoke-RestMethod "https://api.github.com/repos/microsoft/vscode/releases/latest" -Headers $headers

if ($currentVersion -ne $latestInfo.tag_name) {
  Write-Host "新しいバージョンがあります: $($latestInfo.tag_name)（現在: $currentVersion）"
} else {
  Write-Host "最新バージョンを使用しています: $currentVersion"
}
```

### 2. システム統合の制限

- ファイルの関連付けを自動設定しない
- レジストリ登録を行わない
- エクスプローラーの右クリックメニューを自動追加しない

このため、ファイルのダブルクリックで VS Code が開かなかったり、コンテキストメニューに「VS Code で開く」が出ないことがあります。必要に応じて手動で設定してください（管理者権限が必要になる場合があります）。

### 3. アクセス権限による制限

`C:\ProgramData` など共有ディレクトリは、環境によって書き込み権限が制限されます。基本はユーザーディレクトリ（`%USERPROFILE%`）配下への配置を推奨します。

### 4. 依存関係の制限

一部の拡張機能やデバッガーはシステムレベルのコンポーネントを必要とします。

- 例: .NET デバッガー、C/C++ のデバッグツール、Python の自動検出 など
- 初回セットアップで追加のランタイムや SDK を求められることがあります

## 手動更新手順

### 完全な再インストール方法

```powershell
# 1. データのバックアップ
robocopy "$env:USERPROFILE\Applications\VS Code\data" "$env:USERPROFILE\Applications\VS Code_backup\data" /MIR

# 2. VS Code 終了
Stop-Process -Name Code -ErrorAction SilentlyContinue

# 3. 新バージョンの展開（ダウンロードした ZIP のパスを指定）
Expand-Archive -Path "$env:USERPROFILE\Downloads\VSCode-new-version.zip" -DestinationPath "$env:USERPROFILE\Applications\VS Code" -Force

# 4. データの復元
robocopy "$env:USERPROFILE\Applications\VS Code_backup\data" "$env:USERPROFILE\Applications\VS Code\data" /MIR
```

更新の都度、公式の ZIP を入手してください［ダウンロード: https://code.visualstudio.com/Download］。

## 利用シーンの適性

### 適している場面

- 企業環境などで管理者権限がない場合
- 複数 PC で同じ設定を持ち運びたい場合
- USB メモリで持ち運んで使いたい場合

### 適していない場面

- 常に最新バージョンを自動で使いたい場合
- システム統合（関連付けやコンテキストメニュー）を重視する場合
- 複雑なデバッグ環境を必要とする場合

## まとめ

ポータブル版 VS Code は、管理者権限なしで開発環境を整えたいときに有効です。一方で、自動更新が無効であることやシステム統合が弱いことは避けられません。利用環境や要件に合わせて採用を判断してください。定期的な手動更新とバックアップを組み合わせれば、現実的に運用できます。
