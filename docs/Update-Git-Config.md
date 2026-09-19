# Update-Git-Config

Git のグローバル設定 (ユーザーのホームにある `.gitconfig`) に、devbin-win の推奨値を書き込む PowerShell スクリプトです。

## 概要

Portable Git のインストール後に自動的に実行され、次の 3 項目を設定します。
いずれも、まだ値が設定されていない項目だけを対象とします。利用者が自分で設定した値は変更しません。

| 項目 | 値 | 目的 |
|------|-----|------|
| `core.editor` | `code --wait` | コミットメッセージの編集に VS Code を使う |
| `http.sslBackend` | `openssl` | 証明書の検証に OpenSSL を使う |
| `core.autocrlf` | `false` | チェックアウト時に改行コードを変換しない |

`core.editor` は、VS Code が利用できる場合にのみ設定します。
Git と VS Code を同時に導入する場合、Git の後処理の時点では VS Code がまだ配置されていないことがあります。
このため、VS Code 側の後処理からも同じスクリプトを実行し、どちらの順序でも設定できるようにしています。

アンインストール時に設定を戻す処理はありません。不要になった項目は、`git config --global --unset <項目名>` で削除してください。

## 使用方法

通常はコンポーネント マネージャーが自動的に実行するため、手動で実行する必要はありません。
設定を入れ直したい場合は、次のように実行します。

```powershell
# 推奨値のうち、未設定の項目を設定
.\Update-Git-Config.ps1 -Install

# devbin-win の bin ディレクトリを指定して実行
.\Update-Git-Config.ps1 -Install -InstallDir "C:\ProgramData\<ユーザー名>\devbin-win\bin"
```

## パラメーター

- `-Install`: 未設定の推奨値を設定
- `-InstallDir`: devbin-win の bin ディレクトリ。`git.exe` と `code.cmd` を探す場所として使います

`-InstallDir` を指定した場合は、その配下の `git\cmd\git.exe` と `vscode\bin\code.cmd` を優先して使います。
見つからない場合は、PATH 上の `git` と `code` を使います。`git` が見つからない場合は、何もせずに終了します。
