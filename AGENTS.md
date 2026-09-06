# AGENTS.md

このファイルは、このリポジトリでコードを扱う際の AI エージェント向けの指針を提供します。

## 共通ルール

Powershell (.ps1) は、UTF-8 with BOM で作成するようにしてください。BOM なしの場合、動作が不正になります。

AI エージェントによる調査改修ステップ、確認ステップにおけるパッケージ取得 (`Get-Packages.ps1` の実行、npm/pip 等による外部パッケージのダウンロード) は、ネットワーク権限やローカル権限の制約を避けるため、AI エージェントではなくユーザーに実行を依頼してください。エージェントは必要なコマンドと期待される生成物を提示し、ユーザー実行後の出力・ファイル状態を確認してください。

## テスト

回帰テストは `tests` フォルダにあります。Windows PowerShell 5.1 に同梱の Pester 3.4 で動くため、追加のインストールは不要です。リポジトリのルートから次を実行してください。

```text
powershell.exe -ExecutionPolicy Bypass -File tests\Run-Tests.ps1
```

テストは一時ファイルとモックのみを使い、通信、ユーザー環境変数・レジストリの変更、製品ディレクトリの削除を行いません。この前提を崩すテストは追加しないでください。

## ドキュメント参照

詳細な設計情報やガイドは、[docs](./docs) フォルダを参照してください。

+ [Setup-Bin.ps1 設計書](./docs/setup-bin-design.md) - 定義駆動アーキテクチャ・コンポーネントマネージャーの説明
+ [packages.psd1 仕様書](./docs/packages-psd1-specification.md) - パッケージ定義ファイルの仕様 (DependsOn, PathDirs 等のコンポーネント管理プロパティを含む)
+ [Extract Strategies 仕様書](./docs/extract-strategies-specification.md) - 抽出戦略の仕様
+ [Setup-VSBT.ps1 仕様書](./docs/Setup-VSBT-Specification.md) - MSVC と Windows SDK のポータブルセットアップ
+ [Development Tools Installation Guide](./docs/Install-Bin.md) - インストール・アンインストール・コンポーネントマネージャーの手順
+ [Setup-Home](./docs/Setup-Home.md) - HOME 環境変数とホームディレクトリのセットアップ
+ [Update-GitBash-Profile](./docs/Update-GitBash-Profile.md) - Git Bash プロファイル更新
+ [Update-MinGW-Profile](./docs/Update-MinGW-Profile.md) - MinGW プロファイル更新
+ [vscode_portable_setup_report](./docs/vscode_portable_setup_report.md) - VSCode ポータブルセットアップレポート
+ [offline-pip-design](./docs/offline-pip-design.md) - 完全オフライン pip インストール設計
