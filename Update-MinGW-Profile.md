# Update-MinGW-Profile

Windows Terminal に MinGW 対応 PowerShell プロファイルをインストール・アンインストールする PowerShell スクリプトです。

## 概要

Windows Terminal の設定ファイル (`settings.json`) を自動的に編集し、MinGW ツールが利用可能な PowerShell プロファイルの追加・削除を行います。

## 使用方法

```cmd
# MinGW PowerShell プロファイルをインストール
.\Install-MinGW-Profile.cmd

# MinGW PowerShell プロファイルをアンインストール
.\Uninstall-MinGW-Profile.cmd
```

```powershell
# MinGW PowerShell プロファイルをインストール
.\Update-MinGW-Profile.ps1 -Install

# 既存プロファイルを強制的に上書き
.\Update-MinGW-Profile.ps1 -Install -Force

# MinGW PowerShell プロファイルをアンインストール
.\Update-MinGW-Profile.ps1 -Uninstall
```

## パラメータ

- `-Install`: MinGW PowerShell プロファイルを Windows Terminal に追加
- `-Uninstall`: MinGW PowerShell プロファイルを Windows Terminal から削除
- `-Force`: 既存のプロファイルを強制的に上書き (Install と併用)

## MinGW PowerShell プロファイル設定

追加されるプロファイルの設定内容:

- **GUID**: `{d48c104b-44a7-4180-be8d-b542db93a384}`
- **名前**: Windows PowerShell (w/MinGW)
- **実行コマンド**: `powershell.exe -NoExit -Command "& 'Add-MinGW-Path.ps1'"`
- **開始ディレクトリ**: `%USERPROFILE%`
- **アイコン**: PowerShell 標準アイコン

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

### Add-MinGW-Path.ps1 存在確認

- PATH 内で `Add-MinGW-Path.ps1` スクリプトの存在を確認します。
- 存在しない場合は警告を表示 (処理は継続) します。

## 動作について

このプロファイルで PowerShell を起動すると、自動的に以下が実行されます。

1. `Add-MinGW-Path.ps1` スクリプトが実行される
2. Git に含まれる MinGW ツール (`awk`, `diff`, `grep` など) が PATH に追加される
3. 通常の PowerShell コマンドに加えて MinGW ツールが利用可能になる

## 前提条件

- Windows Terminal がインストールされている
- `Add-MinGW-Path.ps1` が PATH に含まれるディレクトリに配置されている
- PowerShell の実行ポリシーが適切に設定されている

## 注意事項

- Windows Terminal を再起動して変更を反映してください。
- `Add-MinGW-Path.ps1` が PATH で見つからない場合でもプロファイルは作成されますが、MinGW ツールは利用できません。
