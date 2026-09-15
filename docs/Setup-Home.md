# Setup-Home

HOME 環境変数とホーム ディレクトリのセットアップを行う PowerShell スクリプトです。

## 概要

このスクリプトは、Windows 環境におけるホーム ディレクトリのセットアップを自動化します。
HOME 環境変数が未設定の場合に、適切なディレクトリ構造を作成し、必要な環境変数を設定します。

## 主な機能

- HOME 環境変数の設定状況を確認
- ホーム ディレクトリの自動作成 (`C:\ProgramData\home\{ユーザー名}`)
- Continue ディレクトリの作成
- XDG Base Directory Specification ディレクトリの作成
- 環境変数の設定:
  - `HOME`: ユーザーのホーム ディレクトリパス
  - `CONTINUE_GLOBAL_DIR`: Continue 設定ディレクトリパス (`.continue`)
  - `XDG_CONFIG_HOME`: XDG 設定ディレクトリパス (`.config`)
  - `XDG_CACHE_HOME`: XDG キャッシュディレクトリパス (`.cache`)
  - `XDG_DATA_HOME`: XDG データディレクトリパス (`.local\share`)
  - `XDG_STATE_HOME`: XDG 状態ディレクトリパス (`.local\state`)

## 実行方法

リポジトリのルートから次のコマンドを実行します。

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\subscripts\Setup-Home.ps1
```

## 処理フロー

1. **現在の状態確認**
   - 現在のユーザー名を取得
   - HOME 環境変数の設定状況をチェック

2. **必要なディレクトリの作成**
   - ベースディレクトリ (`C:\ProgramData\home`) の作成
   - ユーザーホーム ディレクトリの作成
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
\-- {ユーザー名}\
    +-- .continue\
    +-- .config\
    +-- .cache\
    \-- .local\
        +-- share\
        \-- state\
```

## 注意事項

- 既に HOME 環境変数が設定されている場合は、未設定の環境変数および未作成のディレクトリのみを検証・作成します。
- 複数回実行しても既存の設定を損なわず、安全に処理を完了します (冪等性を担保)。
- 環境変数の変更を反映するには、新しいターミナル セッションを開始する必要があります。
- XDG Base Directory Specification は、設定・キャッシュ・データ ファイルの適切な配置を支援する仕様です。
- `Manage-Bin.cmd` の `U` (または `Setup-Bin.ps1 -Uninstall`) による完全アンインストールは `C:\ProgramData\{ユーザー名}\devbin-win` を対象とするため、HOME (`C:\ProgramData\home\{ユーザー名}`) および XDG 関連の環境変数は削除されません。

## XDG Base Directory Specification について

XDG Base Directory Specification は、アプリケーションが設定ファイルやデータファイルを配置する標準的な場所を定義する仕様です。

- **XDG_CONFIG_HOME** (`.config`): アプリケーション設定ファイル
- **XDG_CACHE_HOME** (`.cache`): 一時的なキャッシュファイル
- **XDG_DATA_HOME** (`.local\share`): アプリケーションデータファイル
- **XDG_STATE_HOME** (`.local\state`): ログやヒストリーなどの状態ファイル

この仕様に対応したアプリケーションは、適切なディレクトリにファイルを配置するため、ホーム ディレクトリが整理されます。
