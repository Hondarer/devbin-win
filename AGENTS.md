# AGENTS.md

このファイルは、このリポジトリでコードを取り扱う AI エージェント向けの指針を定義します。

## 共通ルール

文字コードと改行コードは、次のとおり統一してください。
Markdown (.md) は UTF-8 (BOM なし) かつ LF、PowerShell (.ps1 / .psm1 / .psd1) は UTF-8 with BOM かつ LF、バッチ (.cmd) は UTF-8 (BOM なし) かつ LF です。
PowerShell ファイルに BOM が付与されていない場合、Windows PowerShell 5.1 が日本語を誤って解釈します。
cmd.exe は UTF-8 BOM を無視せず先頭コマンドの一部として読み込むため、`.cmd` に BOM を付与すると `@echo off` が `'ï»¿@echo'` と解釈されて実行に失敗します。

AI エージェントによる調査・改修ステップおよび確認ステップにおけるパッケージ取得 (`Get-Packages.ps1` の実行、npm や pip 等による外部パッケージのダウンロード) は、ネットワーク権限やローカル権限の制約を回避するため、AI エージェントではなくユーザーへ実行を依頼してください。
エージェントは必要なコマンドと期待される生成物を提示し、ユーザーによる実行後の出力およびファイル状態を確認してください。

## テスト

回帰テストは `tests` フォルダーに配置されています。
Windows PowerShell 5.1 に同梱の Pester 3.4 で動作するため、追加のインストールは不要です。
リポジトリのルートから次のコマンドを実行してください。

```text
powershell.exe -ExecutionPolicy Bypass -File tests\Run-Tests.ps1
```

テストは一時ファイルおよびモックのみを使用し、外部通信、ユーザー環境変数やレジストリの変更、製品ディレクトリの削除は行いません。
この前提を損なうテストは追加しないでください。

## ドキュメント参照

詳細な設計情報やガイドは、[docs](./docs) フォルダーを参照してください。

+ [Setup-Bin.ps1 設計書](./docs/setup-bin-design.md) - 定義駆動アーキテクチャ・コンポーネント マネージャーの説明
+ [packages.psd1 仕様書](./docs/packages-psd1-specification.md) - パッケージ定義ファイルの仕様 (DependsOn, PathDirs 等のコンポーネント管理プロパティを含む)
+ [Extract Strategies 仕様書](./docs/extract-strategies-specification.md) - 抽出戦略の仕様
+ [Setup-VSBT.ps1 仕様書](./docs/Setup-VSBT-Specification.md) - MSVC と Windows SDK のポータブル セットアップ
+ [Development Tools Installation Guide](./docs/Install-Bin.md) - インストール・アンインストール・コンポーネント マネージャーの手順
+ [Update-GitBash-Profile](./docs/Update-GitBash-Profile.md) - Git Bash プロファイル更新
+ [Update-MinGW-Profile](./docs/Update-MinGW-Profile.md) - MinGW プロファイル更新
+ [Update-Git-Config](./docs/Update-Git-Config.md) - Git のグローバル設定の初期値
+ [ユーザー設定・データの保存先](./docs/user-storage.md) - data / log の配置と設定する環境変数
+ [vscode-portable](./docs/vscode-portable.md) - VS Code のポータブル セットアップ
+ [offline-pip-design](./docs/offline-pip-design.md) - 完全オフライン pip インストール設計
