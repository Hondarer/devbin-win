# Development Tools Installation Guide

このガイドでは、開発ツールのインストール・アンインストール方法について説明します。

## インストール

### かんたんインストール (推奨)

1. このフォルダをダウンロードフォルダやデスクトップなどに配置
2. `install.cmd` をダブルクリックして実行

```cmd
install.cmd
```

### インストール内容

- **インストール先**: `C:\ProgramData\devbin-win\bin`
- **PATH環境変数**: 自動的にユーザー PATH に追加
- **既存ツール保護**: システムに同じツールがある場合は既存を優先

### インストール後の確認

新しいコマンドプロンプトまたは PowerShell を開いて以下のコマンドで確認します。

```cmd
node --version
pandoc --version
java -version
python --version
git --version
```

## アンインストール

### かんたんアンインストール

1. 最初にインストール時に使用したフォルダから実行
2. `uninstall.cmd` をダブルクリックして実行

```cmd
uninstall.cmd
```

### アンインストール内容

- インストールディレクトリ `C:\ProgramData\devbin-win\bin` を完全削除
- ユーザー PATH 環境変数から該当エントリを削除
- 親ディレクトリ `C:\ProgramData\devbin-win` も削除 (空の場合)

## 既存ツールとの共存

インストール時に既存のツールが検出された場合の動作は以下の通りです。

### Java

- システムに `java.exe` が存在する場合、Microsoft JDK への PATH は追加されません
- 既存の Java インストールが優先されます

### Python

- システムに `python.exe` が存在する場合、Python 3.13 への PATH は追加されません
- 既存の Python インストールが優先されます

### Git

- システムに `git.exe` が存在する場合、Portable Git への PATH は追加されません
- 既存の Git インストールが優先されます

### その他のツール

- Node.js、Pandoc、Doxygen、PlantUML は常に PATH に追加されます

## 高度な使用方法

### setup.ps1 直接実行

より詳細な制御が必要な場合は、PowerShell スクリプトを直接実行できます。

```powershell
# ファイル抽出のみ
.\setup.ps1 -Extract

# インストール (抽出 + PATH 追加)
.\setup.ps1 -Install

# アンインストール (削除 + PATH 削除)
.\setup.ps1 -Uninstall

# カスタムインストール先
.\setup.ps1 -Install -InstallDir "C:\MyTools"
```

### 利用可能なオプション

```powershell
# 利用方法を表示
.\setup.ps1
```

## トラブルシューティング

### PowerShell 実行ポリシーエラー

install.cmd と uninstall.cmd は `-ExecutionPolicy Bypass` を使用するため、通常は問題ありません。

### 管理者権限エラー

C:\ProgramData は通常ユーザーでも書き込み可能なため、管理者権限は不要です。

### PATH が反映されない

新しいコマンドプロンプトまたは PowerShell を開いてください。
