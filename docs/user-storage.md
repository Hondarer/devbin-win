# ユーザー設定・データの保存先

devbin-win が導入するコンポーネントの設定・キャッシュ・状態を、Windows のユーザー プロファイルの外へ集約します。対象は `subscripts/config/packages.psd1` の全コンポーネントです。リポジトリの設定と各ツールの公式仕様に基づく整理であり、各アプリを起動してすべての書き込みを追跡した結果ではありません。

## 配置方針

共通ルートは `%ProgramData%\%USERNAME%` です。

| 区分 | 保存先 | 設定のタイミング |
| --- | --- | --- |
| ユーザー設定・キャッシュ・状態 | `data` | 対象コンポーネントのインストール時 |
| HOME と XDG | `data` とその配下 | Manage の開始時 |
| VS Code のポータブルデータ | `data\vscode` | VS Code のインストール・再インストール時 |
| devbin-win の操作トランスクリプト | `log` | Manage / Uninstall の開始時。カスタム導入先でも共通 |
| バイナリ・導入状態 | `devbin-win\bin` | インストール時 |
| 配布用パッケージ・オフラインキャッシュ | 配布元の `packages` | パッケージ取得時。実行時のユーザーデータとは別 |

`Manage-Bin.cmd` は起動時に `data` と `log` を作成し、HOME と XDG のうち未設定のものを設定します。コンポーネントを導入すると、そのコンポーネントが使う保存先を作成し、未設定の環境変数を設定します。個別アンインストールでは、devbin-win が設定した値と一致する環境変数だけを解除します。利用者が別の値へ変更した項目と、導入済みの他コンポーネントと共有する項目は残します。

既存のユーザー環境変数は上書きしません。設定ファイルの移動・統合も行いません。HOME は未設定の場合だけ `data` 自体に設定し、Windows の USERPROFILE、AppData、Documents は変更しません。

## 設定する環境変数

相対パスの基準は `%ProgramData%\%USERNAME%\data` です。

| 環境変数 | 保存先 | 設定するコンポーネント |
| --- | --- | --- |
| HOME | data 自体 | (共通) |
| CONTINUE_GLOBAL_DIR | `continue` | (共通) |
| XDG_CONFIG_HOME | `.config` | (共通) |
| XDG_CACHE_HOME | `.cache` | (共通) |
| XDG_DATA_HOME | `.local\share` | (共通) |
| XDG_STATE_HOME | `.local\state` | (共通) |
| GH_CONFIG_DIR | `gh` | `gh` |
| GLAB_CONFIG_DIR | `glab` | `glab` |
| COPILOT_HOME | `copilot` | `copilot` |
| COPILOT_CACHE_HOME | `copilot\cache` | `copilot` |
| INKSCAPE_PROFILE_DIR | `inkscape` | `inkscape` |
| DOTNET_CLI_HOME | `dotnet` | `dotnet10sdk` |
| NUGET_PACKAGES | `nuget\packages` | `nuget`、`dotnet10sdk` |
| NUGET_HTTP_CACHE_PATH | `nuget\http-cache` | `nuget`、`dotnet10sdk` |
| NUGET_PLUGINS_CACHE_PATH | `nuget\plugins-cache` | `nuget`、`dotnet10sdk` |
| NPM_CONFIG_CACHE | `npm\cache` | `nodejs` |
| NPM_CONFIG_USERCONFIG | `npm\npmrc` (ファイル) | `nodejs` |
| PUPPETEER_CACHE_DIR | `puppeteer\cache` | `puppeteer`、`marp-cli`、`mermaid-cli` |
| PIP_CACHE_DIR | `pip\cache` | `python` |
| PIP_CONFIG_FILE | `pip\pip.ini` (ファイル) | `python` |
| PYTHONUSERBASE | `python` | `python` |
| VSCODE_PORTABLE | `vscode` | `vscode` |

`npmrc` や `pip.ini` のようにファイルを指す項目は、親ディレクトリだけを作成します。ファイルの内容は生成しません。`VSCODE_PORTABLE` だけは他と異なり、VS Code のインストールのたびに値を設定します。設定の反映には新しいターミナルを開いてください。

## コンポーネント別の扱い

「対象なし」は、ユーザー領域への書き込みが絶対にないという保証ではなく、セットアップが管理するユーザー設定を確認できなかったものです。プロジェクト内の設定ファイルは対象外です。

| コンポーネント (ShortName) | 保存先と例外 |
| --- | --- |
| `git` | HOME=`data` に従う。`.gitconfig`、`.ssh` の内容は生成しない。Git Credential Manager と Windows 資格情報は別管理 |
| `vscode` | `VSCODE_PORTABLE=data\vscode`。個別アンインストールでこの変数を解除する。拡張機能が独自に外部へ保存するデータは保証しない |
| `nodejs` | `NPM_CONFIG_USERCONFIG=data\npm\npmrc`、`NPM_CONFIG_CACHE=data\npm\cache`。プロジェクトの `.npmrc` とマシン共通設定は別 |
| `pnpm` | XDG に従う範囲のみ。ストアとグローバル設定は実機の `pnpm store path` / `pnpm config list` で確認が必要 |
| `antfu-ni` | HOME/XDG に従う範囲のみ。個別の保存先指定はなし |
| `marp-cli`, `mermaid-cli`, `puppeteer` | npm キャッシュを集約し、`PUPPETEER_CACHE_DIR=data\puppeteer\cache`。Puppeteer の既定は `os.homedir()` 基準で HOME では移らないため個別に指定する。ブラウザーの一時プロファイルと OS 側の Edge データは別 |
| `widdershins`, `minisearch`, `plantuml-core`, `sharp`, `minimist`, `textlint` | npm キャッシュを集約。ライブラリ利用側とプロジェクト設定は対象外 |
| `python`, `get-pip` | `PIP_CONFIG_FILE=data\pip\pip.ini`、`PIP_CACHE_DIR=data\pip\cache`、`PYTHONUSERBASE=data\python`。pip の他階層の設定の読み込みは残る |
| `yamllint` | XDG/HOME に従う範囲のみ。プロジェクトの `.yamllint` は対象外 |
| `dotnet10sdk` | `DOTNET_CLI_HOME=data\dotnet`、NuGet のパッケージ/HTTP/プラグイン キャッシュを集約。全設定が移るわけではない |
| `nuget` | `NUGET_PACKAGES=data\nuget\packages`、`NUGET_HTTP_CACHE_PATH=data\nuget\http-cache`、`NUGET_PLUGINS_CACHE_PATH=data\nuget\plugins-cache`。一時領域 (`NUGET_SCRATCH`) は TEMP のまま。AppData の `NuGet.Config` と資格情報の設定は対象外 |
| `gh` | `GH_CONFIG_DIR=data\gh`。認証が OS 資格情報ストアにある場合は対象外 |
| `glab` | `GLAB_CONFIG_DIR=data\glab`。リポジトリ内の `.git\glab-cli` は対象外 |
| `copilot` | `COPILOT_HOME=data\copilot`、`COPILOT_CACHE_HOME=data\copilot\cache`。資格情報ストアまで移るとは限らない |
| `agy` | 個別の保存先指定はなし。公式の既定は `~/.gemini/antigravity-cli`。資格情報ストアは対象外 |
| `inkscape` | `INKSCAPE_PROFILE_DIR=data\inkscape` |
| `pwsh` | 指定なし。Documents の PowerShell プロファイルと AppData の PSReadLine 履歴は HOME の変更では移らない |
| `pandoc` | 指定なし。Windows の既定は `%APPDATA%\pandoc`。環境変数での変更手段がなく、`--data-dir` の一律付与も行わない |
| `pandoc-crossref` | 指定なし。設定は引数とプロジェクト設定で与える |
| `jdk`, `plantuml` | 指定なし。Java の Preferences や `user.home` を使うアプリの設定は HOME の変更では一律に移らない |
| `pstools` | EULA 同意を HKCU に登録する。レジストリのため data 集約と data 削除の対象外 |
| `vsbt`, `vswhere` | MSVC/SDK は製品内、vswhere の情報は ProgramData の Microsoft 配下。製品のアンインストール処理で登録を解除する |
| `udev-gothic-hsrf-jpdoc-em` | フォント実体は製品内、登録は HKCU。製品のアンインストール処理で登録を解除する |
| `doxygen`, `doxybook2`, `graphviz`, `ffmpeg` | 対象なし。プロジェクトの入力設定と出力は対象外 |
| `mingw64-gcc-libs`, `mingw64-libiconv`, `mingw64-gettext-runtime` | 対象なし。DLL を配置するだけ |
| `iconv`, `make`, `cmake`, `winflexbison`, `clang-format` | 対象なし。CMake のユーザー パッケージ登録など OS 側の機能は集約しない |
| `cloc`, `nkf`, `innoextract`, `opencppcoverage`, `reportgenerator`, `editorconfig-checker` | 対象なし。引数とプロジェクト設定で動作する |

Windows Terminal の `settings.json` は AppData/LocalAppData のままです。Git Bash/MinGW の Terminal プロファイルにある `%USERPROFILE%` は開始ディレクトリの指定であり、設定の保存先ではありません。

## 完全アンインストール

`Manage-Bin.cmd` の U と `Setup-Bin.ps1 -Uninstall` は、実行前に `data` と過去のログを個別に削除するか質問し、最終確認を表示します。既定はいずれも保持です。data の削除はこの共通領域全体を対象とするため、そこへ置いた設定・キャッシュ・認証ファイルを含みます。

```powershell
.\subscripts\Setup-Bin.ps1 -Uninstall `
    -InstallDir "$env:ProgramData\$env:USERNAME\devbin-win\bin" `
    -RemoveData -RemoveLogs
```

`-Force` を併用すると質問を省略します。`-Force` 単独では data と log を保持します。PowerShell から `-RemoveData:$false -RemoveLogs:$false` と明示すれば、その項目の質問を省略して保持できます。削除対象は実行前に表示します。

data の削除に成功した後、その配下を参照するユーザー環境変数と PATH を解除します。data の外は削除しません。data / log とその祖先・内部に再解析ポイントがある場合は削除を拒否します。削除の失敗はアンインストールの失敗として報告します。

log の削除では、記録中のトランスクリプトと `log` フォルダー自体を残します。メニューから完全アンインストールを実行した場合は、その操作を記録しているログが残ります。`log` が利用できない場合は一時フォルダーへ出力します。アプリが自身で生成するログをここへ集約する機能ではありません。

## 仕様の参照先

- [VS Code ポータブルモード](https://code.visualstudio.com/docs/setup/portable) と [VSCODE_PORTABLE の解決実装](https://github.com/microsoft/vscode/blob/main/src/bootstrap-node.ts)
- [npm 設定](https://docs.npmjs.com/using-npm/config/)、[pip 設定](https://pip.pypa.io/en/stable/topics/configuration/)
- [.NET 環境変数](https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet-environment-variables)、[NuGet キャッシュ](https://learn.microsoft.com/en-us/nuget/consume-packages/managing-the-global-packages-and-cache-folders)
- [GitHub CLI 環境変数](https://cli.github.com/manual/gh_help_environment)、[GitLab CLI 設定](https://docs.gitlab.com/cli/configuration/)
- [Copilot CLI 設定ディレクトリ](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-config-dir-reference)、[Inkscape 環境変数](https://wiki.inkscape.org/wiki/Environment_variables)
- [Puppeteer 設定](https://pptr.dev/guides/configuration)、[Pandoc マニュアル](https://pandoc.org/MANUAL.html)
- [Antigravity CLI](https://www.antigravity.google/docs/cli/features) と [設定 (CLI)](https://antigravity.google/docs/settings?tab=cli)
