# devbin-win でインストールした PowerShell 7 (pwsh) を各アプリケーションで使用する方法

## VS Code

ユーザーの settings.json を次のとおり編集または追加します。

キーボード ショートカット: Windows: Ctrl + Shift + P

上記のショートカットでコマンドパレットを開きます。  
検索窓に settings.json と入力します。  
候補に表示される [基本設定: ユーザー設定を開く (JSON)] (英語の場合は Preferences: Open User Settings (JSON)) を選択します。

次のとおり設定ファイルを編集します。

`terminal.integrated.defaultProfile.windows` が既に定義されている場合は、値を変更してください。

`terminal.integrated.profiles.windows` が既に定義されている場合は、値を変更してください。  
`terminal.integrated.profiles.windows` に別の項目がある場合は、`pwsh` を追加するように編集してください。

```json
    "terminal.integrated.defaultProfile.windows": "pwsh",
    "terminal.integrated.profiles.windows": {
        "pwsh": {
            "path": "${env:PROGRAMDATA}\\${env:USERNAME}\\devbin-win\\bin\\pwsh\\pwsh.exe",
            "icon": "terminal-powershell"
        },
        
        // 他のエントリ

    },
```

## Windows Terminal

- Windows Terminal を開き、上部のタブにある [v] (プルダウンメニュー) をクリックして [設定] を開きます。
- 左側のメニューから [新しいプロファイルを追加します] を選択します。
- [新しい空のプロファイル] を選択します。
- [名前] を `pwsh` とします。任意の名前でも問題ありません。
- [コマンド ライン] を `%ProgramData%\%USERNAME%\devbin-win\bin\pwsh\pwsh.exe` とします。
- [アイコン] を [ファイル] とし、`%ProgramData%\%USERNAME%\devbin-win\bin\pwsh\pwsh.ico` を指定すると、タブに PowerShell 7 のアイコンが表示されます。
- 常に常にこの pwsh を標準で開きたい場合は、設定画面の「スタートアップ」にある「既定のプロファイル」から指定した名前のプロファイルを選択することで、ターミナル起動時の既定のシェルに設定できます。
