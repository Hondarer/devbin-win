# Setup-Home

HOME 環境変数とホームディレクトリのセットアップを行う PowerShell スクリプトです。

## 概要

このスクリプトは、Windows 環境でのホームディレクトリセットアップを自動化します。HOME 環境変数が設定されていない場合に、適切なディレクトリ構造を作成し、必要な環境変数を設定します。

## 主な機能

- HOME 環境変数の設定状況を確認
- ホームディレクトリの自動作成 (`C:\ProgramData\home\{ユーザー名}`)
- Continue ディレクトリの作成
- XDG Base Directory Specification ディレクトリの作成
- 環境変数の設定:
  - `HOME`: ユーザーのホームディレクトリパス
  - `CONTINUE_GLOBAL_DIR`: Continue 設定ディレクトリパス (`.continue`)
  - `XDG_CONFIG_HOME`: XDG 設定ディレクトリパス (`.config`)
  - `XDG_CACHE_HOME`: XDG キャッシュディレクトリパス (`.cache`)
  - `XDG_DATA_HOME`: XDG データディレクトリパス (`.local\share`)
  - `XDG_STATE_HOME`: XDG 状態ディレクトリパス (`.local\state`)

## 実行方法

```cmd
.\Setup-Home.cmd
```

```powershell
.\Setup-Home.ps1
```

## 処理フロー

1. **現在の状態確認**
   - 現在のユーザー名を取得
   - HOME 環境変数の設定状況をチェック

2. **必要なディレクトリの作成**
   - ベースディレクトリ (`C:\ProgramData\home`) の作成
   - ユーザーホームディレクトリの作成
   - Continue ディレクトリ (`.continue`) の作成
   - XDG Base Directory Specification 準拠のディレクトリ作成:
     - `.config` (設定ファイル用)
     - `.cache` (キャッシュファイル用)
     - `.local\share` (データファイル用)
     - `.local\state` (状態ファイル用)

3. **環境変数の設定**
   - `HOME` 環境変数をユーザーレベルで設定
   - `CONTINUE_GLOBAL_DIR` 環境変数をユーザーレベルで設定
   - XDG Base Directory 環境変数をユーザーレベルで設定
     - `XDG_CONFIG_HOME`
     - `XDG_CACHE_HOME`
     - `XDG_DATA_HOME`
     - `XDG_STATE_HOME`

## セットアップ後の構造

```text
C:\ProgramData\home\
└── {ユーザー名}\
    ├── .continue\
    ├── .config\
    ├── .cache\
    └── .local\
        ├── share\
        └── state\
```

## 注意事項

- すでに HOME 環境変数が設定されている場合、不足している環境変数とディレクトリのみをチェック・作成します。
- 複数回実行しても安全で、既存の設定を破壊しません (冪等性を保証)。
- 環境変数の変更を反映するには新しいターミナルセッションを開始する必要があります。
- XDG Base Directory Specification は、設定・キャッシュ・データファイルの適切な配置を支援する仕様です。

## XDG Base Directory Specification について

XDG Base Directory Specification は、アプリケーションが設定ファイルやデータファイルを配置する標準的な場所を定義する仕様です。

- **XDG_CONFIG_HOME** (`.config`): アプリケーション設定ファイル
- **XDG_CACHE_HOME** (`.cache`): 一時的なキャッシュファイル
- **XDG_DATA_HOME** (`.local\share`): アプリケーションデータファイル
- **XDG_STATE_HOME** (`.local\state`): ログやヒストリーなどの状態ファイル

この仕様に対応したアプリケーションは、適切なディレクトリにファイルを配置するため、ホームディレクトリが整理されます。
