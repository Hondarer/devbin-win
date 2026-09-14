# devbin-win を公開配布する場合のライセンス課題

最終確認日: 2026-07-23

## 1. 本書の位置づけと結論

現行の `Make-Dist.ps1` は、個人利用または利用条件を管理できる組織内での利用を目的として、開発環境一式をまとめるためのものである。本書はこの現在の用途を否定するものではなく、**将来、不特定多数へ一般公開する場合に追加で解決すべき課題**を整理したものである。

現在の ZIP は `packages` を丸ごと含む構成であり、公開配布物として必要な除外処理、ライセンス表示、対応ソースの提供などは実装していない。そのため、公開版を作成する場合は、次の課題への対応が必要となる。

- Visual Studio Code の製品ライセンスは、ソフトウェアの共有・公開・スタンドアロン提供を禁止している。
- Sysinternals PsTools は、無償配布であっても第三者による再配布を明示的に禁止している。
- Windows 版 .NET SDK の `.NET Library` ライセンスは、開発したプログラムの一部として所定条件を満たす場合の Distributable Code の配布を認めるが、SDK ZIP 自体の公開を認めていない。
- Visual Studio Build Tools、MSVC、Windows SDK の取得済みペイロード全体について、第三者が公開ミラーとして再配布できる許諾を確認できない。再配布可能物として明示されたランタイム等と、開発ツール一式は区別する必要がある。
- GPL/LGPL/EPL のバイナリについて、対応ソース、ビルドスクリプト、ライセンス表示を devbin-win の配布者が継続提供できる状態になっていないものがある。
- `Make-Dist.ps1` はdevbin-win自身のMIT `LICENSE` と `docs` を配布ZIPへ収録する。公開版では、これに加えて第三者ライセンス通知を整備する必要がある。

したがって、現行の個人用・組織内用 ZIP と公開用 ZIP は分けて考える必要がある。公開版を用意する場合の最低条件は、公開再配布が禁止または未確認のパッケージを除外し、コピーレフト対象物の対応ソースを整備し、全成果物のライセンス表示を配布物の最上位から参照できるようにすることである。

> [!IMPORTANT]
> 本書は、公開情報と取得済み成果物に基づく技術的なライセンス調査であり、法律上の助言ではない。組織内での複製・共有も、契約やライセンスによって扱いが異なるため、組織の利用条件に従うこと。「要確認」の成果物を一般公開する場合や、独自ライセンスの解釈に依存する場合は、権利者または資格を持つ専門家へ確認すること。

## 2. 対象と判定基準

### 2.1 対象

- `subscripts/config/packages.psd1` の40パッケージ定義
- `packages/npm-packages` の10件の `NpmInstall` 定義と、各依存ツリーから生成される archive 群
- `packages/pip-packages` の9成果物
- `packages/vsbt` の65ファイル
- `Make-Dist.ps1` が `packages` とともに配布する devbin-win 固有ファイル

実ファイル数は `packages` 直下40件（第三者成果物36件、devbin-win固有スクリプト4件）、npmのトップレベル定義10件（依存 archive 数は各 cache manifest により変動）、pip 9件、VSBT 65件の合計である。devbin-win固有スクリプトと配布スクリプト群はリポジトリのMITライセンス対象であり、現行配布ZIPにはルートの `LICENSE` が収録される。

本調査の判定は、取得済みのベンダーアーカイブを含む ZIP を無償で不特定多数へ公開する場合を対象とする。現行の個人利用・組織内利用に対する適否を一律に判定するものではない。インストール後の展開済み `bin` 一式を別製品として再配布する場合も対象外であり、別途調査が必要である。

### 2.2 判定

| 公開時の判定 | 意味 |
|---|---|
| 再配布可 | 現在の未改変アーカイブを同梱する範囲では、必要なライセンス表示も成果物内に存在する |
| 条件付きで可 | ライセンス上は再配布可能だが、NOTICE、対応ソース、帰属表示などを追加しなければならない |
| 再配布不可 | 不特定多数への公開配布を許諾しない条項が確認できた |
| 要確認 | 公開再配布を許す根拠、またはバイナリに対応する完全なライセンス・ソースを確認できない。公開版には確認完了まで含めない |

判定では、アーカイブ内部の `LICENSE`、`COPYING`、`NOTICE`、パッケージメタデータを確認し、次に公式の製品条項、対象タグ、配布サイトを参照した。単にダウンロード可能、無償、オープンソースであることは再配布許諾とはみなしていない。

## 3. トップレベルパッケージの公開時評価

| ShortName / 対象成果物 | ライセンス・条件 | 公開時の判定 | 公開する場合の対応・根拠 |
|---|---|---|---|
| `nodejs` 25.9.0 | MITおよび同梱依存物の個別ライセンス | 再配布可 | ZIP内にトップレベルおよびnpm依存物のライセンスを収録。未改変ZIPを保持する。[Node.js LICENSE](https://github.com/nodejs/node/blob/v25.9.0/LICENSE) |
| `pnpm` 11.3.0 | MIT、バンドル依存物の個別ライセンス | 再配布可 | tgz内に本体およびバンドル依存物のライセンスを収録。未改変tgzを保持する。[pnpm](https://www.npmjs.com/package/pnpm/v/11.3.0) |
| `antfu-ni` 30.1.0 | MIT | 再配布可 | tgz内の `LICENSE` を保持する。[npm](https://www.npmjs.com/package/@antfu/ni/v/30.1.0) |
| `pandoc` 3.9.0.2 | GPL-2.0-or-later、BSD/MIT等 | 条件付きで可 | ZIP内にGPL本文、帰属、対象ソースURLがある。公開場所から対応ソースへ同等にアクセスできる状態を配布者が維持し、URLを配布ページにも明記する。[リリース](https://github.com/jgm/pandoc/releases/tag/3.9.0.2) |
| `pandoc-crossref` 0.3.24a | GPL-2.0-or-later | 条件付きで可 | 現行7zはexeだけで、ライセンス本文を含まない。GPL本文、著作権表示、対応ソースを追加する。[プロジェクト](https://lierdakil.github.io/pandoc-crossref/) / [リリース](https://github.com/lierdakil/pandoc-crossref/releases/tag/v0.3.24a) |
| `doxygen` 1.15.0 | GPL-2.0 | 条件付きで可 | 現行Windows ZIPは実行ファイルのみ。GPL本文と、1.15.0に対応する完全なソースへの同等アクセスを追加する。[公式リポジトリ](https://github.com/doxygen/doxygen) |
| `doxybook2` 1.6.1 | MIT | 条件付きで可 | リリースZIPにLICENSEがない。MITの著作権・許諾表示を配布物へ追加し、静的リンク依存物の通知も確認する。[公式リポジトリ](https://github.com/Antonz0/doxybook2/tree/v1.6.1) |
| `jdk` 25.0.1 | GPL-2.0-with-Classpath-exception | 条件付きで可 | ZIP内の `legal` 一式を保持し、Microsoftの対象ソースを同等に提供する。商標上、Microsoft/Javaからの承認を示唆しない。[Microsoft FAQ](https://learn.microsoft.com/en-us/java/openjdk/faq) / [サポート情報](https://learn.microsoft.com/en-us/java/openjdk/support) |
| `graphviz` 14.0.2 | EPL-2.0および多数の同梱DLL | 要確認 | 取得ZIPは `bin` のみでLICENSE/NOTICEを含まない。EPL本文、ソース取得方法、全同梱DLLのライセンスと通知を確定するまで除外する。[Graphviz License](https://graphviz.org/license/) |
| `ffmpeg` 8.1.2 essentials | GPL-3.0、静的リンクされた多数の外部ライブラリ | 要確認 | ZIPはGPL本文とFFmpegコミットを示すが、全静的リンク依存物を含む完全な対応ソース・ビルドスクリプトの提供を確認できない。完全なソースセットをミラーできるまで除外する。[Gyan builds](https://www.gyan.dev/ffmpeg/builds/) |
| `plantuml` 1.2026.2 | 標準jarはGPL系。jar内にGPL-2.0の本文と個別依存ライセンスあり | 条件付きで可 | 配布しているjarのライセンス種別をリリース資産名と照合し、対応ソースを同等提供する。LGPL版へ切り替える場合も別資産として再監査する。[PlantUML FAQ](https://plantuml.com/faq) |
| `python` 3.13.13 embeddable | PSF-2.0および第三者ライセンス、Microsoft Distributable Code条件 | 再配布可 | `LICENSE.txt` を保持し、Windows上で未改変バイナリを配布する。Microsoft表示を変更せず、承認を示唆しない。[Python 3.13 copyright/license](https://docs.python.org/3.13/copyright.html) |
| `get-pip` 26.1.1 source | MITおよびvendor依存物の個別ライセンス | 再配布可 | source tarballはライセンスとvendorコードを含む。未改変で保持する。[pip](https://pypi.org/project/pip/26.1.1/) |
| `dotnet10sdk` 10.0.202 Windows | Microsoft .NET Library License | **再配布不可** | 同梱 `LICENSE.txt` は、SDKを使って開発したプログラムに重要な主機能を追加した場合のDistributable Code配布を規定する一方、ソフトウェア自体の公開・第三者移転を禁止する。SDK ZIPを除外し、利用者がMicrosoftから取得する方式にする。[.NET license information](https://github.com/dotnet/core/blob/main/license-information.md) |
| `pwsh` 7.6.3 | MITおよびThirdPartyNotices | 再配布可 | ZIP内の `LICENSE.txt` と `ThirdPartyNotices.txt` を保持する。[PowerShell](https://github.com/PowerShell/PowerShell/tree/v7.6.3) |
| `git` 2.55.0.2 PortableGit | GPL-2.0および多数の個別ライセンス | 条件付きで可 | SFX内にライセンス群はあるが、多数のGPL/LGPLコンポーネントを含む。Git for Windowsの同一リリースに対応する完全なソース群とビルド情報を同等提供する。[Git for Windows](https://github.com/git-for-windows/git/releases/tag/v2.55.0.windows.2) |
| `vscode` 1.128.0 Microsoft build | Microsoft Visual Studio Code製品ライセンス | **再配布不可** | 条項5が share/publish およびスタンドアロン提供を禁止する。公式バイナリを除外し、利用者による公式ダウンロードへ変更する。MITなのは公開ソースであり、この製品バイナリではない。[製品ライセンス](https://code.visualstudio.com/license) |
| `pstools` 2.43 | Sysinternals Software License Terms | **再配布不可** | FAQは、無償であっても第三者による配布を明示的に拒否している。ZIPを除外し、利用者がMicrosoftから取得する方式にする。[Sysinternals Licensing FAQ](https://learn.microsoft.com/en-us/sysinternals/license-faq) |
| `inkscape` 1.4.4 | GPLおよび同梱コンポーネントの多数のライセンス | 条件付きで可 | 7z内の `COPYING`、各Pythonパッケージ等のライセンスを保持する。1.4.4 Windows buildの完全な対応ソースを同等提供する。[Inkscape license](https://inkscape.org/about/license/) |
| `mingw64-gcc-libs` 16.1.0-2 | GPL/LGPLおよびGCC Runtime Library Exception | 条件付きで可 | pkg内の `COPYING*` とRuntime Exceptionを保持し、正確なMSYS2 source packageをミラーする。[MSYS2 package](https://packages.msys2.org/packages/mingw-w64-x86_64-gcc-libs) |
| `mingw64-libiconv` 1.19-1 | LGPL-2.1-or-later | 条件付きで可 | pkg内のライセンスを保持し、対応ソースと、LGPLが要求する改変・再リンク可能性を損なわない。[MSYS2 package](https://packages.msys2.org/packages/mingw-w64-x86_64-libiconv) |
| `mingw64-gettext-runtime` 1.0-1 | GPL-3.0-or-later / LGPL-2.1-or-later | 条件付きで可 | pkg内のライセンスを保持し、該当DLLごとのライセンスと正確なsource packageを提供する。[MSYS2 package](https://packages.msys2.org/packages/mingw-w64-x86_64-gettext-runtime) |
| `iconv` 1.19-1 | GPL-3.0-or-later | 条件付きで可 | `iconv.exe` の対応ソースを同等提供し、GPL本文を配布ページからも参照可能にする。[MSYS2 package](https://packages.msys2.org/packages/mingw-w64-x86_64-iconv) |
| `make` 4.4.1-4 | GPL-3.0-or-later | 条件付きで可 | 対象版のMSYS2 source-only tarballをミラーする。最新版のsource packageで代用しない。[MSYS2 package](https://packages.msys2.org/packages/mingw-w64-x86_64-make) |
| `cmake` 4.3.1 | BSD-3-Clauseおよび同梱第三者ライセンス | 再配布可 | ZIP内の `LICENSE.rst` と各 `COPYING`/`NOTICE` を保持する。[CMake](https://github.com/Kitware/CMake/tree/v4.3.1) |
| `winflexbison` 2.5.25 | Flex は BSD、Bison とビルドスクリプトは GPL-3.0+、文書は FDL 1.3+ | 条件付きで可 | ZIP内の `COPYING`、`COPYING.flex`、`COPYING.bison`、`COPYING.DOC` を保持する。公開場所から [v2.5.25](https://github.com/lexxmark/winflexbison/tree/v2.5.25) の対応ソースへ同等にアクセスできる状態を配布者が維持する。[公式リポジトリ](https://github.com/lexxmark/winflexbison) / [リリース](https://github.com/lexxmark/winflexbison/releases/tag/v2.5.25) |
| `clang-format` 22.1.4 | Apache-2.0 WITH LLVM-exceptionほか | 条件付きで可 | tar.xz内にLLVMライセンスがあるが深いパスにある。配布ルートのNOTICEから明示し、著作権・第三者表示を保持する。[LLVM licensing](https://llvm.org/docs/DeveloperPolicy.html#copyright-license-and-patents) |
| `nuget` 7.3.1 | Apache-2.0 | 条件付きで可 | 単体exeにはライセンス文書がない。Apache-2.0本文、著作権、該当NOTICEを追加する。[NuGet.Client](https://github.com/NuGet/NuGet.Client/tree/7.3.1) |
| `cloc` 2.08 | GPL-2.0 | 条件付きで可 | 単体exeにはライセンス・対応ソースを伴わない。GPL本文とv2.08の対応ソースを同等提供する。[cloc v2.08](https://github.com/AlDanial/cloc/tree/v2.08) |
| `vswhere` 3.1.7 | MIT | 条件付きで可 | 単体exeにはMIT表示がない。著作権・許諾表示を配布物へ追加する。[vswhere](https://github.com/microsoft/vswhere/tree/3.1.7) |
| `nkf` 2.1.5 | zlib系の独自許諾 | 再配布可 | ZIP内の `LICENSE` を保持し、由来を偽らず、改変する場合は明示する。[nkf-bin](https://github.com/Hondarer/nkf-bin/tree/v2_1_5) |
| `innoextract` 1.9 | zlib | 条件付きで可 | ZIPのREADMEはLICENSEを参照するが、そのLICENSEがZIPにない。zlibライセンス全文を追加する。[innoextract](https://github.com/dscharrer/innoextract/tree/1.9) |
| `opencppcoverage` 0.9.9.0 | GPL-3.0 | 条件付きで可 | インストーラーに対応するGPL本文と完全なソース・ビルド情報を同等提供する。[OpenCppCoverage](https://github.com/OpenCppCoverage/OpenCppCoverage/tree/release-0.9.9.0) |
| `reportgenerator` 5.5.1 | Apache-2.0 | 条件付きで可 | ZIP内にApache-2.0本文はある。収録DLLの第三者通知を正確なソース/依存関係から生成し、必要なNOTICEがないことを確認する。[ReportGenerator](https://github.com/danielpalme/ReportGenerator/tree/v5.5.1) |
| `vsbt` 14.44 / SDK 26100 | Visual Studio 2022 Diagnostic Build Tools、Windows SDK等のMicrosoft条項 | **要確認（公開版には含めない）** | 製品全体の公開ミラー許諾は確認できず、再配布可能コードとして列挙された一部ランタイムと開発ツール本体を混同できない。65ファイル全体を除外し、各利用者がライセンスを受諾してMicrosoftから取得する方式にする。[Visual Studio License Directory](https://visualstudio.microsoft.com/license-terms/) |
| `udev-gothic-hsrf-jpdoc-em` 2.2.0.1 | SIL Open Font License 1.1 | 再配布可 | ZIP内に著作権表示とOFL全文がある。フォント単体を販売せず、改変版にReserved Font Nameを使わず、OFLを保持する。[OFL](https://openfontlicense.org/) |
| `editorconfig-checker` 3.6.1 | MIT | 条件付きで可 | ZIP内に本体LICENSEはある。Goバイナリへ静的リンクされた依存物のライセンス通知を対象タグから生成・追加する。[公式リポジトリ](https://github.com/editorconfig-checker/editorconfig-checker/tree/v3.6.1) |
| `gh` 2.95.0 | MITおよびGo依存物の個別ライセンス | 条件付きで可 | ZIP内は本体LICENSEのみ。対象タグの依存物から第三者通知を生成し、必要なMIT/BSD/Apache表示を追加する。[GitHub CLI](https://github.com/cli/cli/tree/v2.95.0) |
| `glab` 1.105.0 | MITおよびGo依存物の個別ライセンス | 条件付きで可 | ZIP内は本体LICENSEのみ。対象タグの依存物から第三者通知を生成する。[GitLab CLI](https://gitlab.com/gitlab-org/cli/-/tree/v1.105.0) |
| `yamllint` 1.38.0 | GPL-3.0-or-later | 再配布可 | wheelはpure Pythonのソース形式で、ライセンス本文も収録する。未改変wheelを保持する。[PyPI](https://pypi.org/project/yamllint/1.38.0/) |

## 4. npm/pip依存成果物の公開時評価

### 4.1 npm

現行の内部用途では、10件の `NpmInstall` 定義ごとに `package-lock.json`、`npm-cache-manifest.json`、依存ツリー全体の archive を生成する。以下の表は本調査時点の旧 flat cache snapshot に対する記録であり、現在の依存 archive 全体の公開可否を保証する inventory ではない。不特定多数への公開配布を行う場合は、各 cache manifest の全 archive を再監査すること。

| ファイル | パッケージ | ライセンス | 公開時の判定 |
|---|---|---|---|
| `antfu-ni-30.1.0.tgz` | `@antfu/ni` 30.1.0 | MIT | 再配布可 |
| `fdir-6.5.0.tgz` | `fdir` 6.5.0 | MIT | 再配布可 |
| `fzf-0.5.2.tgz` | `fzf` 0.5.2 | BSD-3-Clause | 再配布可 |
| `package-manager-detector-1.6.0.tgz` | `package-manager-detector` 1.6.0 | MIT | 再配布可 |
| `picomatch-4.0.3.tgz` | `picomatch` 4.0.3 | MIT | 再配布可 |
| `pnpm-11.3.0.tgz` | `pnpm` 11.3.0 | MIT + bundled dependencies | 再配布可 |
| `tinyexec-1.0.4.tgz` | `tinyexec` 1.0.4 | MIT | 再配布可 |
| `tinyglobby-0.2.15.tgz` | `tinyglobby` 0.2.15 | MIT | 再配布可 |

### 4.2 pip

wheel内の `METADATA` と `*.dist-info/licenses` を確認した。現在は定義が要求する版以外の `pip` と `setuptools` も残っている。法的には未改変wheelを配布できるが、不要な旧版・新版を含めないよう配布前にロックファイルと一致させるべきである。

| ファイル | ライセンス | 公開時の判定・注意 |
|---|---|---|
| `packaging-26.2-py3-none-any.whl` | Apache-2.0 OR BSD-2-Clause | 再配布可。両ライセンスを収録 |
| `pathspec-1.1.1-py3-none-any.whl` | MPL-2.0 | 再配布可。未改変wheelとLICENSEを保持 |
| `pip-26.1.1-py3-none-any.whl` | MIT + vendor licenses | 再配布可 |
| `pip-26.1.2-py3-none-any.whl` | MIT + vendor licenses | 再配布可だが定義外の重複版。除外候補 |
| `pyyaml-6.0.3-cp313-cp313-win_amd64.whl` | MIT | 再配布可 |
| `setuptools-82.0.1-py3-none-any.whl` | MIT + vendor licenses | 再配布可だが重複版。使用版を固定する |
| `setuptools-83.0.0-py3-none-any.whl` | MIT + vendor licenses | 再配布可だが重複版。使用版を固定する |
| `wheel-0.47.0-py3-none-any.whl` | MIT | 再配布可 |
| `yamllint-1.38.0-py3-none-any.whl` | GPL-3.0-or-later | 再配布可。pure PythonソースとLICENSEをwheel内に収録 |

## 5. Visual Studio Build Tools内部物の公開時評価

`packages/vsbt` の65ファイルは次の3グループに漏れなく分類できる。

| グループ | 件数 | 対象 | 公開時の扱い |
|---|---:|---|---|
| Visual Studio manifests | 2 | `channel_release.json`, `manifest_release.json` | 公開版には含めない |
| MSVC 14.44 VSIX | 12 | ASAN、CRT、PGO、C++ tools、DIA SDK | 製品・SDK本体。公開再配布許諾未確認のため公開版には含めない |
| Windows SDK 26100 payload | 51 | 39 CAB、12 MSI | SDK本体。公開再配布許諾未確認のため公開版には含めない |

Visual C++ Runtime等について別途再配布可能とされるファイルが存在しても、それはMicrosoftのDistributable Code Listに列挙されたファイルを、許諾された方法でアプリケーションと配布する権利である。上記のVSIX/CAB/MSIキャッシュ全体を公開する根拠にはならない。

## 6. 公開する場合の課題と対応案

### P0: 公開版を作成する前に対応

1. 現行の個人用・組織内用 ZIP とは別に公開用の生成方式を設け、次の要件を満たさない構成では公開版を生成しない。
2. `dotnet-sdk-10.0.202-win-x64.zip`、`VSCode-win32-x64-1.128.0.zip`、`PSTools-2.43.zip`、`packages/vsbt` を公開版から除外する。
3. FFmpegとGraphvizは、完全なソース/第三者ライセンスを確定できるまで公開版から除外する。
4. 公開版から除外した製品は、利用者が各公式サイトから取得する方式にする。自動取得を行う場合も、利用者の環境で公式URLから取得し、必要なEULA受諾を省略しない。
5. 公開版でも、現行ZIPと同様にリポジトリルートの `LICENSE` を必ず収録する。

### P1: 公開版に含めるコピーレフト成果物への対応

1. `sources/<ShortName>/<Version>/` または継続管理できる公開サーバーに、配布バイナリと正確に対応するソース、パッチ、ビルドスクリプトを配置する。
2. 公開ダウンロードページで、バイナリと対応ソースを同じ粒度・同等のアクセス条件で案内する。単に上流のトップページへリンクするだけにしない。
3. GPL/LGPL/EPL対象ごとに、提供期間、担当者、上流削除時のミラー継続方法を決定する。
4. FFmpeg、PortableGit、Inkscapeのような集合物は、本体リポジトリだけでなく、静的リンクまたは同梱された対象依存物まで対応ソースの範囲を確認する。

GPLのバイナリ配布時のソース提供については、[GNU GPL FAQ: UnchangedJustBinary](https://www.gnu.org/licenses/gpl-faq.html#UnchangedJustBinary) およびGPL本文を基準とする。EPL-2.0は、オブジェクトコードの受領者へソースの取得方法を合理的に通知する必要がある。

### P2: 公開版の生成工程を分離・自動検査

1. `packages.psd1` に `Redistribution`、`LicenseId`、`LicenseFiles`、`SourceUrl`、`ThirdPartyNotice` を追加し、公開用モードでは未調査または `Redistribution = "Prohibited"` の成果物を `Make-Dist.ps1` が拒否するようにする。
2. `THIRD_PARTY_NOTICES.md` とライセンス原文を公開版ZIPの最上位へ生成する。アーカイブ内部にしかない表示も索引から参照可能にする。
3. 公開版へ収録するファイルと承認済みinventoryを照合し、未定義ファイル、重複版、古いキャッシュが1件でもあれば公開用ビルドを失敗させる。
4. Go/.NET/静的リンクバイナリは対象タグの依存ロックからSBOMと第三者通知を生成し、リリースアーカイブの内容と照合する。
5. `Make-Dist.ps1` は追跡中の `docs` と本調査書を収録する。公開用モードを追加する際は、生成した第三者ライセンス通知も公開版ZIPへ必ず収録する。

## 7. 公開版を更新する際の確認手順

公開版を更新する場合は、パッケージ更新ごとに次を確認する。

1. `packages.psd1` のバージョン、実ファイル名、上流のリリースタグが一致する。
2. アーカイブ内のLICENSE/NOTICEを再抽出し、前版との差分を確認する。
3. 公式の製品条項と再配布FAQを確認し、確認日と恒久URLを更新する。
4. GPL/LGPL/EPLの場合、正確な対応ソースとビルド情報を先に確保する。
5. npm/pip/Go/.NET等の推移依存物を再列挙し、全成果物が公開時評価表または承認済みグループに属することを検査する。
6. 公開再配布が禁止または要確認の成果物が1件でも含まれる場合、公開用ZIPの生成を失敗させる。

## 8. 調査上の制約

- `packages` はGit管理対象外であり、同じコミットでも各作業環境の実ファイルが異なり得る。本書は2026-07-23時点の当該作業ディレクトリを調査したスナップショットである。
- 上流サイトの「現在のライセンス」だけでは旧版の条件を証明できないため、可能な限り対象タグと成果物内文書を優先した。
- 公式配布者がライセンス表示を欠落させていても、devbin-winの再配布者の義務が自動的に免除されるとは扱っていない。
- 輸出管理、暗号規制、特許、商標、個人向け/法人向け利用資格は、著作権ライセンスとは別の確認事項である。
