# devbin-win

Windows 用開発バイナリの自動展開ツールです。

## ダウンロード

所定の方法で以下のアーカイブをダウンロードし、packages ディレクトリに格納してください。

### Node.js

from [https://nodejs.org/en](https://nodejs.org/en)

+ [https://nodejs.org/en/download/](https://nodejs.org/en/download/)
    + [node-v22.18.0-win-x64.zip](https://nodejs.org/dist/v22.18.0/node-v22.18.0-win-x64.zip)

### pandoc

from [https://github.com/jgm/pandoc](https://github.com/jgm/pandoc)

+ [/releases/tag/3.7.0.2](https://github.com/jgm/pandoc/releases/tag/3.7.0.2)
    + [pandoc-3.7.0.2-windows-x86_64.zip](https://github.com/jgm/pandoc/releases/download/3.7.0.2/pandoc-3.7.0.2-windows-x86_64.zip)

### pandoc-crossref

from [lierdakil/pandoc-crossref](https://github.com/lierdakil/pandoc-crossref)

+ [/releases/tag/v0.3.20](https://github.com/lierdakil/pandoc-crossref/releases/tag/v0.3.20)
    + [pandoc-crossref-Windows-X64.7z](https://github.com/lierdakil/pandoc-crossref/releases/download/v0.3.20/pandoc-crossref-Windows-X64.7z)

### doxygen

from [https://doxygen.nl/](https://doxygen.nl/)

+ [doxygen-1.14.0.windows.x64.bin.zip](https://www.doxygen.nl/files/doxygen-1.14.0.windows.x64.bin.zip)

### doxybook2

from [Antonz0/doxybook2](https://github.com/Antonz0/doxybook2)

+ [/releases/tag/v1.6.1](https://github.com/Antonz0/doxybook2/releases/tag/v1.6.1)
    + [doxybook2-windows-win64-v1.6.1.zip](https://github.com/Antonz0/doxybook2/releases/download/v1.6.1/doxybook2-windows-win64-v1.6.1.zip)

### Microsoft Build of OpenJDK

from [Download the Microsoft Build of OpenJDK](https://learn.microsoft.com/en-us/java/openjdk/download)

+ [OpenJDK 21.0.8 LTS](https://learn.microsoft.com/en-us/java/openjdk/download#openjdk-2108-lts--see-previous-releases)
    + [microsoft-jdk-21.0.8-windows-x64.zip](https://aka.ms/download-jdk/microsoft-jdk-21.0.8-windows-x64.zip)

### PlantUML

from [plantuml](https://github.com/plantuml/plantuml)

+ [/releases/tag/v1.2025.4](https://github.com/plantuml/plantuml/releases/tag/v1.2025.4)
    + [plantuml-1.2025.4.jar](https://github.com/plantuml/plantuml/releases/download/v1.2025.4/plantuml-1.2025.4.jar)

### Python

from [python.org](https://www.python.org/)

+ [Python Releases for Windows](https://www.python.org/downloads/windows/)
    + [Python 3.13.7](https://www.python.org/downloads/release/python-3137/)
        + [Windows embeddable package (64-bit)](https://www.python.org/ftp/python/3.13.7/python-3.13.7-embed-amd64.zip)

+ [get-pip](https://bootstrap.pypa.io/get-pip.py)

## セットアップ

以下のコマンドで実行ファイルを bin フォルダに展開します。  
展開後、bin フォルダと bin\python-3.13 フォルダに PATH を通してください。  
また、PYTHONPATH を以下のように設定してください。

```bat
set PYTHONPATH=C:\path\to\your\bin\python-3.13\Lib\site-packages
```

PlantUML のために java をセットアップしています。  
java を外部から利用する場合は、bin/jdk-21/bin フォルダに PATH を通し、bin/jdk-21 を JAVA_HOME として設定してください。

### PowerShell から実行

```powershell
.\setup.ps1
```

### コマンドプロンプトから実行

```cmd
powershell -ExecutionPolicy Bypass -File setup.ps1
```

### PowerShell 実行ポリシーエラーが発生する場合

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
.\setup.ps1
```
