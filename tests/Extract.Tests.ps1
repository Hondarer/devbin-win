# Extract.Tests.ps1
# Extract モジュールの抽出戦略処理のテスト
# 一時ディレクトリ内に生成した ZIP アーカイブのみを対象とし、製品ディレクトリへのアクセスは行いません。

. (Join-Path $PSScriptRoot "TestHelpers.ps1")
Import-DevbinModules

# テスト用の ZIP アーカイブを生成します (指定の相対パスに空ファイルを作成して圧縮)。
function New-TestArchive {
    param(
        [string]$Path,
        [string[]]$Entries
    )

    $stagingDir = New-TestDirectory
    try {
        foreach ($entry in $Entries) {
            $full = Join-Path $stagingDir $entry
            $parent = Split-Path $full -Parent
            if ($parent -and -not (Test-Path $parent)) {
                New-Item -ItemType Directory -Path $parent -Force | Out-Null
            }
            Set-Content -Path $full -Value $entry -Encoding ASCII
        }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::CreateFromDirectory($stagingDir, $Path)
    } finally {
        Remove-TestDirectory -Path $stagingDir
    }
}

Describe "Get-ExtractedSourcePath" {

    It "フォルダが 1 つだけならそのフォルダを返す" {
        $tempDir = New-TestDirectory
        try {
            New-Item -ItemType Directory -Path (Join-Path $tempDir "tool-1.0.0") -Force | Out-Null

            (Get-ExtractedSourcePath $tempDir) | Should Be (Join-Path $tempDir "tool-1.0.0")
        } finally {
            Remove-TestDirectory -Path $tempDir
        }
    }

    It "ファイルだけなら展開先そのものを返す" {
        $tempDir = New-TestDirectory
        try {
            Set-Content -Path (Join-Path $tempDir "tool.exe") -Value "x" -Encoding ASCII

            (Get-ExtractedSourcePath $tempDir) | Should Be $tempDir
        } finally {
            Remove-TestDirectory -Path $tempDir
        }
    }

    It "フォルダが複数あれば展開先そのものを返す" {
        $tempDir = New-TestDirectory
        try {
            New-Item -ItemType Directory -Path (Join-Path $tempDir "a") -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $tempDir "b") -Force | Out-Null

            (Get-ExtractedSourcePath $tempDir) | Should Be $tempDir
        } finally {
            Remove-TestDirectory -Path $tempDir
        }
    }

    It "空の展開先では何も返さない" {
        $tempDir = New-TestDirectory
        try {
            (Get-ExtractedSourcePath $tempDir) | Should BeNullOrEmpty
        } finally {
            Remove-TestDirectory -Path $tempDir
        }
    }
}

Describe "Resolve-PostExtractSourcePath" {

    It "絶対パスはそのまま返す" {
        (Resolve-PostExtractSourcePath -SourcePath "C:\dist\extra.txt" -ScriptDir "C:\repo\subscripts") | Should Be "C:\dist\extra.txt"
    }

    It "空のパスはそのまま返す" {
        (Resolve-PostExtractSourcePath -SourcePath "" -ScriptDir "C:\repo\subscripts") | Should BeNullOrEmpty
    }

    It "相対パスはリポジトリルート基準で解決する" {
        $repoRoot = New-TestDirectory
        try {
            $subscriptsDir = Join-Path $repoRoot "subscripts"
            New-Item -ItemType Directory -Path $subscriptsDir -Force | Out-Null
            Set-Content -Path (Join-Path $repoRoot "extra.txt") -Value "x" -Encoding ASCII

            (Resolve-PostExtractSourcePath -SourcePath "extra.txt" -ScriptDir $subscriptsDir) |
                Should Be (Join-Path $repoRoot "extra.txt")
        } finally {
            Remove-TestDirectory -Path $repoRoot
        }
    }

    It "見つからなければ最初の候補を返す" {
        $result = Resolve-PostExtractSourcePath -SourcePath "missing.txt" -ScriptDir "C:\repo\subscripts"

        $result | Should Be (Join-Path "C:\repo" "missing.txt")
    }
}

Describe "Expand-ArchiveToTemp" {

    It "ZIP を展開先に取り出す" {
        $workDir = New-TestDirectory
        try {
            $archive = Join-Path $workDir "tool.zip"
            New-TestArchive -Path $archive -Entries @("tool-1.0.0\bin\tool.exe")
            $tempDir = Join-Path $workDir "extract"

            Expand-ArchiveToTemp -ArchiveFile $archive -TempDir $tempDir

            (Test-Path (Join-Path $tempDir "tool-1.0.0\bin\tool.exe")) | Should Be $true
        } finally {
            Remove-TestDirectory -Path $workDir
        }
    }

    It "扱えない拡張子は失敗として返す" {
        $workDir = New-TestDirectory
        try {
            $archive = Join-Path $workDir "tool.rar"
            Set-Content -Path $archive -Value "dummy" -Encoding ASCII

            { Expand-ArchiveToTemp -ArchiveFile $archive -TempDir (Join-Path $workDir "extract") } | Should Throw
        } finally {
            Remove-TestDirectory -Path $workDir
        }
    }
}

Describe "Invoke-ExtractStrategy" {

    It "Standard 戦略は展開した中身を配置先へ移す" {
        $workDir = New-TestDirectory
        try {
            $archive = Join-Path $workDir "tool.zip"
            New-TestArchive -Path $archive -Entries @("tool-1.0.0\tool.exe", "tool-1.0.0\lib\tool.dll")
            $binDir = Join-Path $workDir "bin"
            New-Item -ItemType Directory -Path $binDir -Force | Out-Null
            $pkg = New-TestPackage -ShortName "tool"

            $result = Invoke-ExtractStrategy `
                -PackageConfig $pkg `
                -ArchiveFile $archive `
                -BinDir $binDir `
                -ScriptDir "C:\nonexistent"

            $result | Should Be $true
            (Test-Path (Join-Path $binDir "tool.exe")) | Should Be $true
            (Test-Path (Join-Path $binDir "lib\tool.dll")) | Should Be $true
        } finally {
            Remove-TestDirectory -Path $workDir
        }
    }

    It "知らない戦略名は失敗として返す" {
        $pkg = New-TestPackage -ShortName "tool" -Extra @{ ExtractStrategy = "NoSuchStrategy" }

        $result = Invoke-ExtractStrategy -PackageConfig $pkg -BinDir "C:\nonexistent" -ScriptDir "C:\nonexistent"

        $result | Should Be $false
    }

    It "PostSetupScript の .ps1 は別プロセスで実行する" {
        $source = Get-Content (Join-Path (Get-DevbinSubscriptsDir) "Devbin\Extract\ExtractStrategy.ps1") -Raw

        $source | Should Match 'powershell\.exe -ExecutionPolicy Bypass -File \$scriptPath'
        $source | Should Match 'if \(\$extension -ieq "\.ps1"\)'
    }

    It "PostSetupScript の Import-Module -Force で実行中の未公開関数を失わない" {
        $workDir = New-TestDirectory
        try {
            $scriptDir = Join-Path $workDir "subscripts"
            $templatesDir = Join-Path $scriptDir "config\templates"
            New-Item -ItemType Directory -Path $templatesDir -Force | Out-Null

            $devbinPath = Join-Path (Get-DevbinSubscriptsDir) "Devbin"
            $reloadScript = Join-Path $templatesDir "reload-devbin.ps1"
            $reloadBody = @"
param([string]`$TargetPath)
Import-Module '$devbinPath' -Force -ErrorAction Stop
Set-Content -Path (Join-Path `$TargetPath 'post-setup.txt') -Value 'ok'
"@
            $utf8Bom = New-Object System.Text.UTF8Encoding $true
            [System.IO.File]::WriteAllText($reloadScript, $reloadBody, $utf8Bom)

            $archive = Join-Path $workDir "tool.zip"
            New-TestArchive -Path $archive -Entries @("tool-1.0.0\tool.exe")
            $binDir = Join-Path $workDir "bin"
            New-Item -ItemType Directory -Path $binDir -Force | Out-Null
            $pkg = New-TestPackage -ShortName "tool" -Extra @{ PostSetupScript = "reload-devbin.ps1" }
            $global:DevbinReloadExtractParams = @{
                PackageConfig = $pkg
                ArchiveFile   = $archive
                BinDir        = $binDir
                ScriptDir     = $scriptDir
            }

            InModuleScope Devbin {
                $threw = $false
                $extractResult = $false
                $changeStatus = ""
                try {
                    $extractResult = Invoke-ExtractStrategy @global:DevbinReloadExtractParams
                    $changeStatus = (New-ComponentChangeResult -Status "Installed" -ShortName "tool").Status
                } catch {
                    $threw = $true
                }

                $threw | Should Be $false
                $extractResult | Should Be $true
                $changeStatus | Should Be "Installed"
            }

            (Test-Path (Join-Path $binDir "post-setup.txt")) | Should Be $true
        } finally {
            Remove-Variable -Name DevbinReloadExtractParams -Scope Global -ErrorAction SilentlyContinue
            Remove-TestDirectory -Path $workDir
        }
    }

    It "戦略の失敗を握りつぶさずに false を返す" {
        $workDir = New-TestDirectory
        try {
            $archive = Join-Path $workDir "tool.rar"
            Set-Content -Path $archive -Value "dummy" -Encoding ASCII
            $pkg = New-TestPackage -ShortName "tool"

            $result = Invoke-ExtractStrategy `
                -PackageConfig $pkg `
                -ArchiveFile $archive `
                -BinDir $workDir `
                -ScriptDir "C:\nonexistent"

            $result | Should Be $false
        } finally {
            Remove-TestDirectory -Path $workDir
        }
    }
}

Describe "パッケージ管理戦略の既定キャッシュ" {
    It "npm と pip はリポジトリ直下の packages を使う" {
        InModuleScope Devbin {
            Mock Test-Path { return $true }
            Mock Invoke-NpmInstallFromCache {
                return ($PackagesDir -eq (Join-Path $script:DevbinRepositoryRoot "packages"))
            }
            (Invoke-NpmInstallStrategy -BinDir "C:\test" -Config @{}) | Should Be $true
            Mock Test-PipWheelPackages { return @("missing") }
            (Invoke-PipInstallStrategy -BinDir "C:\test" -Config @{ Name = "app"; PipPackage = "app" }) | Should Be $false
            Assert-MockCalled Test-PipWheelPackages -Times 1 -Exactly -ParameterFilter {
                $DirectoryPath -eq (Join-Path $script:DevbinRepositoryRoot "packages\pip-packages")
            }
        }
    }
}

Describe "抽出戦略の分割" {

    $subscriptsDir = Get-DevbinSubscriptsDir

    It "Setup-Strategies.psm1 が残っていない" {
        (Test-Path (Join-Path $subscriptsDir "Setup-Strategies.psm1")) | Should Be $false
    }

    It "Extract が戦略の系統ごとに分かれている" {
        $extractDir = Join-Path $subscriptsDir "Devbin\Extract"
        $files = @(Get-ChildItem $extractDir -Filter "*.ps1" | ForEach-Object { $_.Name } | Sort-Object)

        ($files -join ",") | Should Be "ArchiveExtraction.ps1,ExecutableStrategy.ps1,ExtractStrategy.ps1,InstallerStrategy.ps1,PackageManagerStrategy.ps1,StandardStrategy.ps1,SubdirectoryStrategy.ps1,TargetDirectoryStrategy.ps1"
    }

    It "戦略の呼び分けは 1 箇所にまとまっている" {
        $extractDir = Join-Path $subscriptsDir "Devbin\Extract"
        $hits = @()
        foreach ($file in (Get-ChildItem $extractDir -Filter "*.ps1")) {
            if ($file.Name -eq "ExtractStrategy.ps1") { continue }
            if (Select-String -Path $file.FullName -Pattern 'PackageConfig\.ExtractStrategy' -Quiet) {
                $hits += $file.Name
            }
        }
        ($hits -join ", ") | Should Be ""
    }

    It "packages.psd1 の戦略名がすべて呼び分けに現れる" {
        $catalog = Import-PackageCatalog -Path (Join-Path $subscriptsDir "config\packages.psd1")
        $catalog.Success | Should Be $true

        $dispatcher = Get-Content (Join-Path $subscriptsDir "Devbin\Extract\ExtractStrategy.ps1") -Raw
        $missing = @()
        foreach ($strategy in (@($catalog.Packages | ForEach-Object { $_.ExtractStrategy }) | Where-Object { $_ } | Sort-Object -Unique)) {
            if ($strategy -eq "CopyToPackages") { continue }
            if ($dispatcher -notmatch ('"' + [regex]::Escape($strategy) + '"')) {
                $missing += $strategy
            }
        }
        ($missing -join ", ") | Should Be ""
    }
}
