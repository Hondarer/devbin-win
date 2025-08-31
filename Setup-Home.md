# Setup-Home

HOME 環境変数とホームディレクトリのセットアップを行う PowerShell スクリプトです。

## 概要

このスクリプトは、Windows 環境でのホームディレクトリセットアップを自動化します。HOME 環境変数が設定されていない場合に、適切なディレクトリ構造を作成し、必要な環境変数を設定します。

## 主な機能

- HOME 環境変数の設定状況を確認
- ホームディレクトリの自動作成 (`C:\ProgramData\home\{ユーザー名}`)
- Continue ディレクトリの作成 (`{ホームディレクトリ}\.continue`)
- 環境変数の設定:
  - `HOME`: ユーザーのホームディレクトリパス
  - `CONTINUE_GLOBAL_DIR`: Continue 設定ディレクトリパス

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

3. **環境変数の設定**
   - `HOME` 環境変数をユーザーレベルで設定
   - `CONTINUE_GLOBAL_DIR` 環境変数をユーザーレベルで設定

## セットアップ後の構造

```text
C:\ProgramData\home\
└── {ユーザー名}\
    └── .continue\
```

## 注意事項

- すでに HOME 環境変数が設定されている場合、CONTINUE_GLOBAL_DIR のみをチェックします。
- 環境変数の変更を反映するには新しいターミナルセッションを開始する必要があります。
