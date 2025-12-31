# Setup-VSBT.ps1 仕様書

## プロジェクト概要

このリポジトリは、MSVC (Microsoft Visual C++) と Windows SDK をポータブル形式でダウンロードして展開する PowerShell スクリプト (Setup-VSBT) です。Visual Studio Build Tools のコンポーネントを、公式マニフェストから必要なパッケージを取得し、インストーラーを使わずに直接ファイルを展開します。

## アーキテクチャ

### メインスクリプト: subscripts/Setup-VSBT.ps1

単一の PowerShell スクリプトとして実装されており、以下の処理フローで動作します。

1. **vswhere 登録の解除** (再インストール時のクリーンアップ)
2. 一時ダウンロードフォルダ (`temp_extract`) と既存の出力フォルダ (`OutputPath`) をクリーンアップ (常に実行)
3. Visual Studio のマニフェストをダウンロード (`https://aka.ms/vs/17/release/channel` または preview、`packages\vsbt` にキャッシュ)
4. 利用可能な MSVC と Windows SDK のバージョンを解析
5. 指定されたバージョン (またはデフォルトで最新) のパッケージ一覧を構築
6. 各パッケージを SHA256 検証付きでダウンロード
   - キャッシュ (`packages\vsbt`) を確認し、存在すれば再利用
   - 存在しなければ `temp_extract` にダウンロードし、検証後に `packages\vsbt` に移動
7. ZIP および MSI 形式のパッケージを `packages\vsbt` から読み込み、最終出力先 (`bin\vsbt`) に展開
8. 不要なファイルを削除してサイズを最適化
9. DIA SDK のフォルダ名を正規化 (`DIA%20SDK` → `DIA SDK`)
10. 環境設定用のスクリプト (`Add-VSBT-Env-x64.cmd` と `Add-VSBT-Env-x64.ps1` など) を bin ディレクトリに生成
11. **vswhere への登録** (`%ProgramData%\Microsoft\VisualStudio\Packages\_Instances\devbin-win\state.json` を作成)
12. `temp_extract` フォルダを削除 (キャッシュは `packages\vsbt` に保持)

### ディレクトリ構造

- `packages/vsbt/`: パッケージとマニフェストの永続的キャッシュ (手動削除が必要)
  - `channel_release.json`: チャンネルマニフェストのキャッシュ
  - `manifest_release.json`: VS マニフェストのキャッシュ
  - `{target}/MSVC/{version}/`: キャッシュされた MSVC パッケージ (ZIP)
  - `{target}/SDK/{version}/`: キャッシュされた SDK パッケージ (MSI, CAB)
- `temp_extract/`: ダウンロード中の一時ファイル置き場 (処理完了後に自動削除)
- `bin/`: 環境設定用スクリプトと最終出力先
  - `Add-VSBT-Env-x64.cmd`, `Add-VSBT-Env-x64.ps1` など (CMD と PowerShell 両対応)
  - `vsbt/`: MSVC と Windows SDK の展開先 (デフォルト、変更可能)

複数のターゲット (例: x64, arm64) を指定した場合、パッケージが各ターゲットフォルダに重複してキャッシュされます。
`temp_extract` フォルダは処理の成功・失敗に関わらず、スクリプト終了時に自動的に削除されます。
`packages/vsbt` のキャッシュにより、2 回目以降の実行ではダウンロードがスキップされます。

## コマンド

### スクリプトの実行

```{.powershell caption="利用可能なバージョンを表示"}
.\subscripts\Setup-VSBT.ps1 -ShowVersions
```

```{.powershell caption="デフォルト設定でダウンロード (最新版の MSVC と SDK、x64 ターゲット)"}
.\subscripts\Setup-VSBT.ps1 -AcceptLicense
```

```{.powershell caption="バージョンとターゲットを指定"}
.\subscripts\Setup-VSBT.ps1 -MSVCVersion "14.44" -SDKVersion "26100" -Target "x64" -AcceptLicense
.\subscripts\Setup-VSBT.ps1 -MSVCVersion "14.44" -SDKVersion "26100" -Target "x64,arm64" -AcceptLicense
```

```{.powershell caption="プレビュー版を使用"}
.\subscripts\Setup-VSBT.ps1 -Preview -AcceptLicense
```

```{.powershell caption="出力先とダウンロードキャッシュを指定"}
.\subscripts\Setup-VSBT.ps1 -OutputPath "C:\buildtools" -DownloadsPath "C:\cache" -AcceptLicense
```

```{.powershell caption="ダウンロードのみ実行 (展開はスキップ)"}
.\subscripts\Setup-VSBT.ps1 -DownloadOnly -AcceptLicense
```

```{.powershell caption="バージョンとターゲットを指定してダウンロードのみ実行"}
.\subscripts\Setup-VSBT.ps1 -MSVCVersion "14.44" -SDKVersion "26100" -Target "x64" -DownloadOnly -AcceptLicense
```

### バージョン表記について

14.44.35207 の「14.44」は MSVC major.minor で、実際のコンパイラ内部バージョンは 19.44.35207 です。

v144 は Visual Studio Installer や Build Tools で「MSVC v144 - VS 2022 C++ toolset (14.44)」として表示されます。

このツールセットは Windows SDK v26100 (Windows 11 24H2 対応) と組み合わせるのが一般的です。

### パラメーター一覧

- `-OutputPath`: 展開先のパス (デフォルト: `.\bin\vsbt`)
- `-DownloadsPath`: ダウンロードキャッシュのパス (デフォルト: `.\packages\vsbt`)
- `-MSVCVersion`: MSVC のバージョン (省略時は最新)
- `-SDKVersion`: Windows SDK のバージョン (省略時は最新)
- `-HostArch`: ホストアーキテクチャ (x64, x86, arm64、デフォルト: x64)
- `-Target`: ターゲットアーキテクチャ (カンマ区切り: x64, x86, arm, arm64、デフォルト: x64)
- `-ShowVersions`: 利用可能なバージョンを表示して終了
- `-AcceptLicense`: ライセンスを自動承認
- `-Preview`: プレビュー版を使用
- `-OfflineMode`: オフラインモードで実行 (キャッシュされたマニフェストを使用)
- `-DownloadOnly`: ダウンロードのみ実行 (展開処理をスキップ)

### テスト

このプロジェクトには自動テストフレームワークはありません。動作確認は以下のコマンドで行います。

```{.powershell caption="構文チェック"}
powershell -ExecutionPolicy Bypass -File .\subscripts\Setup-VSBT.ps1 -ShowVersions
```

## オフライン動作

### キャッシュ機能

スクリプトは以下のデータを `packages\vsbt` に永続的にキャッシュします。

- **マニフェスト JSON**: `channel_release.json` および `manifest_release.json` (プレビュー版の場合は `_preview`)
- **パッケージファイル**: SHA256 ハッシュ検証済みの ZIP および MSI ファイル

2 回目以降の実行では、キャッシュされたパッケージを再利用するため、ダウンロード時間が大幅に短縮されます。

### キャッシュの自動クリーンアップ

スクリプトは実行時に、現在のパッケージ構成で参照されなくなったファイルをキャッシュから自動的に削除します。

- バージョンやターゲットアーキテクチャを変更した場合、古いバージョンのファイルが自動的に削除されます
- パッケージ構成が更新された場合、不要になったファイルが削除されます
- クリーンアップ処理は `-DownloadOnly` モードでも実行されます

削除されたファイルの数とサイズが実行時に表示されます。

### オフラインモード

一度オンラインで実行してキャッシュを作成すれば、`-OfflineMode` パラメーターで完全にオフラインで動作します。

```{.powershell caption="最初にオンラインで実行してキャッシュを作成"}
.\subscripts\Setup-VSBT.ps1 -MSVCVersion "14.44" -SDKVersion "26100" -Target "x64" -AcceptLicense
```

```{.powershell caption="2 回目以降はオフラインモードで実行可能"}
.\subscripts\Setup-VSBT.ps1 -MSVCVersion "14.44" -SDKVersion "26100" -Target "x64" -AcceptLicense -OfflineMode
```

オフラインモードでは、インターネット接続なしで以下が可能です。

- キャッシュされたマニフェストからバージョン情報を取得
- キャッシュされたパッケージファイルを使用して展開

インターネット接続が利用できない場合、スクリプトは自動的にキャッシュの利用を試みます。
同じバージョン、同じターゲットであれば、2 回目以降の実行は完全にオフラインで実行可能です。

## vswhere 統合

### 自動登録とアンインストール

Setup-VSBT.ps1 は、インストール完了時に自動的に vswhere に登録されます。アンインストール時には、Setup-Bin.ps1 を通じて自動的に削除されます。

- **登録先**: `%ProgramData%\Microsoft\VisualStudio\Packages\_Instances\8f3e5d42\state.json`
- **インスタンス ID**: `8f3e5d42` (固定値、8文字ハッシュ形式)
- **製品情報**: `Microsoft.VisualStudio.Product.BuildTools`
- **コンポーネント**: `Microsoft.VisualStudio.Component.VC.Tools.x86.x64` など

vswhere インスタンスの登録と削除は、Setup-Common.psm1 の `Register-VswhereInstance` および `Unregister-VswhereInstance` 関数で管理されます。Setup-Bin.ps1 の `-Uninstall` オプション実行時、または `Invoke-CompleteUninstall` 関数呼び出し時に自動的に削除されます。

### 環境スクリプトの vswhere 対応

生成される `Add-VSBT-Env-*.ps1` スクリプトは vswhere を使用してインスタンスを自動検出します。

1. **vswhere.exe の検索順序**:
   - `%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe`
   - スクリプトと同じディレクトリの `vswhere.exe`
   - PATH 上の `vswhere.exe`

2. **柔軟なバージョン検出**:
   - MSVC バージョンを動的に検出 (`VC\Tools\MSVC` フォルダから)
   - Windows SDK バージョンを動的に検出 (`Windows Kits\10\bin` フォルダから)
   - DIA SDK を自動検出

3. **フォールバック**:
   - vswhere が見つからない場合、スクリプトと同じディレクトリの `vsbt` フォルダを使用

## 注意事項

1. **出力フォルダのクリーンアップ**: スクリプト実行時に既存の出力フォルダ (`OutputPath`) と一時ダウンロードフォルダ (`temp_extract`) は常に削除されます。前回の実行結果を保持したい場合は、別のフォルダにコピーしてください
2. **一時ダウンロードフォルダ**: パッケージは `temp_extract` にダウンロードされ、最終出力先 (`bin\vsbt`) に直接展開されます。`temp_extract` はスクリプト終了時に必ず削除されます
3. **キャッシュの自動クリーンアップ**: 現在のパッケージ構成で参照されなくなったファイルは、実行時に `packages\vsbt` から自動的に削除されます。バージョンやターゲットを変更した場合、古いファイルが削除されます
4. パッケージ ID やパスの処理では、大文字小文字を区別しない比較 (`.ToLower()`) を使用しています
5. マニフェストは `packages\vsbt\` にキャッシュされ、オフライン動作が可能です
6. マニフェストキャッシュファイル (`channel_*.json`, `manifest_*.json`) は自動削除されないため、完全にクリーンアップしたい場合は `packages\vsbt` フォルダごと手動で削除してください
7. **vswhere 登録**: vswhere への登録は標準ユーザー権限で実行されます。失敗した場合は警告が表示されますが、処理は続行されます
