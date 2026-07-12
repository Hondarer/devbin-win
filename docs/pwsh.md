# devbin-win でインストールした VS Code を各アプリケーションで使用する方法

## VS Code

ユーザーの settings.json に以下を編集/追加します。

キーボードショートカット: Windows: Ctrl + Shift + P

上記のショートカットでコマンドパレットを開きます。  
検索窓に settings.json と入力します。  
候補に表示される [基本設定: ユーザー設定を開く (JSON)] (英語の場合は Preferences: Open User Settings (JSON)) を選択します。

以下のように設定ファイルを編集します。

`terminal.integrated.defaultProfile.windows` がすでに定義されている場合は、値を変更してください。

`terminal.integrated.profiles.windows` がすでに定義されている場合は、値を変更してください。  
`terminal.integrated.profiles.windows` に別の項目がある場合は、`pwsh` を追加するように編集してください。

```json
    "terminal.integrated.defaultProfile.windows": "pwsh",
    "terminal.integrated.profiles.windows": {
        "pwsh": {
            "path": "pwsh",
            "icon": "terminal-powershell"
        },
        
        // 他のエントリ

    },
```

## Windows Terminal

- Windows Terminalを開き、上部のタブにある [v] (プルダウンメニュー) をクリックして [設定] を開きます。
- 左側のメニューから [新しいプロファイルを追加します] を選択します。
- [新しい空のプロファイル] を選択します。
- [名前] を `pwsh` とします。任意の名前でも問題ありません。
- [コマンド ライン] を `pwsh` とします。
- 常にこのpwshを標準で開きたい場合は、設定画面の「スタートアップ」にある「規定のプロファイル」から指定した名前のプロファイルを選択することで、ターミナル起動時のデフォルト シェルに設定できます。
