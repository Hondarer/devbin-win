# Update-GitBash-Profile

Windows Terminal に Git Bash プロファイルをインストール・アンインストールする PowerShell スクリプトです。

## 概要

Windows Terminal の設定ファイル (`settings.json`) を自動的に編集し、Git Bash プロファイルの追加・削除を行います。

## 使用方法

```cmd
# Git Bash プロファイルをインストール
.\Update-GitBash-Profile.cmd -Install

# 既存プロファイルを強制的に上書き
.\Update-GitBash-Profile.cmd -Install -Force

# Git Bash プロファイルをアンインストール
.\Update-GitBash-Profile.cmd -Uninstall
```

```powershell
# Git Bash プロファイルをインストール
.\Update-GitBash-Profile.ps1 -Install

# 既存プロファイルを強制的に上書き
.\Update-GitBash-Profile.ps1 -Install -Force

# Git Bash プロファイルをアンインストール
.\Update-GitBash-Profile.ps1 -Uninstall
```

## パラメータ

- `-Install`: Git Bash プロファイルを Windows Terminal に追加
- `-Uninstall`: Git Bash プロファイルを Windows Terminal から削除
- `-Force`: 既存のプロファイルを強制的に上書き (Install と併用)

## Git Bash プロファイル設定

追加されるプロファイルの設定内容:

- **GUID**: `{b2e42366-5d93-4fb7-be22-177d0a5850d1}`
- **名前**: Git Bash
- **実行ファイル**: `C:\ProgramData\devbin-win\bin\git\bin\bash.exe -i -l`
- **開始ディレクトリ**: `%USERPROFILE%`
- **アイコン**: `C:\ProgramData\devbin-win\bin\git\mingw64\share\git\git-for-windows.ico`

## 主な機能

### 設定ファイルの検索

以下の場所から Windows Terminal の設定ファイルを自動検索します。

- `%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json`
- `%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json`
- `%APPDATA%\Microsoft\Windows Terminal\settings.json`

### バックアップ機能

- 操作前に自動的に設定ファイルのバックアップを作成します。
- バックアップファイル名: `settings.json.yyMMddHHmmss`

### 重複チェック

- GUID または名前が重複するプロファイルの存在を確認します。
- `-Force` オプションなしでは既存プロファイルが存在した場合は処理を中断します。

### ファイル存在確認

- Git Bash 実行ファイルとアイコンファイルの存在を確認します。
- 存在しない場合は警告を表示 (処理は継続) します。

## 注意事項

- Windows Terminal を再起動して変更を反映してください。
