# AGENTS.md

このファイルは、このリポジトリでコードを扱う際の AI エージェント向けの指針を提供します。

## 共通ルール

全般的な応答のルールとスタイルガイドは、グローバルの CLAUDE.md を参照してください。

## ドキュメント参照

詳細な設計情報やガイドは、[docs-src](./docs-src) フォルダを参照してください。

+ [Setup-Bin.ps1 設計書](./docs-src/setup-bin-design.md) - 定義駆動アーキテクチャ・コンポーネントマネージャーの説明
+ [packages.psd1 仕様書](./docs-src/packages-psd1-specification.md) - パッケージ定義ファイルの仕様 (DependsOn, PathDirs 等のコンポーネント管理プロパティを含む)
+ [Extract Strategies 仕様書](./docs-src/extract-strategies-specification.md) - 抽出戦略の仕様
+ [Setup-VSBT.ps1 仕様書](./docs-src/Setup-VSBT-Specification.md) - MSVC と Windows SDK のポータブルセットアップ
+ [Development Tools Installation Guide](./docs-src/Install-Bin.md) - インストール・アンインストール・コンポーネントマネージャーの手順
+ [Setup-Home](./docs-src/Setup-Home.md) - HOME 環境変数とホームディレクトリのセットアップ
+ [Update-GitBash-Profile](./docs-src/Update-GitBash-Profile.md) - Git Bash プロファイル更新
+ [Update-MinGW-Profile](./docs-src/Update-MinGW-Profile.md) - MinGW プロファイル更新
+ [vscode_portable_setup_report](./docs-src/vscode_portable_setup_report.md) - VSCode ポータブルセットアップレポート
+ [offline-pip-design](./docs-src/offline-pip-design.md) - 完全オフライン pip インストール設計
