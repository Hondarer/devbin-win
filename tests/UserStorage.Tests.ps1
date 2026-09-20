. (Join-Path $PSScriptRoot 'TestHelpers.ps1')
Import-DevbinModules

InModuleScope Devbin {
    Describe 'Storage configuration planning' {
        BeforeEach {
            Mock Get-DevbinUserStorageRoot { Join-Path $TestDrive 'storage' }
            Mock Get-DevbinUserEnvironmentValue { $null }
            Mock Set-DevbinUserEnvironmentValue {}
        }
        It 'places a new HOME and configured paths under data without writing' {
            $plan = Get-DevbinHomePlan
            $plan.HomePath | Should Be (Get-DevbinDataDirectory)
            foreach ($entry in $plan.EnvVars) {
                $entry.Value.StartsWith((Get-DevbinDataDirectory), [StringComparison]::OrdinalIgnoreCase) | Should Be $true
            }
            Assert-MockCalled Set-DevbinUserEnvironmentValue -Scope It -Times 0 -Exactly
        }
        It 'keeps existing HOME and XDG overrides' {
            Mock Get-DevbinUserEnvironmentValue { 'C:\existing-home' } -ParameterFilter { $Name -eq 'HOME' -or $Name -eq 'XDG_CONFIG_HOME' }
            $plan = Get-DevbinHomePlan
            $plan.HomePath | Should Be 'C:\existing-home'
            @($plan.EnvVars | Where-Object { $_.Name -eq 'HOME' -or $_.Name -eq 'XDG_CONFIG_HOME' }).Count | Should Be 0
            ($plan.EnvVars | Where-Object { $_.Name -eq 'XDG_CACHE_HOME' }).Value | Should Be (Join-Path (Get-DevbinDataDirectory) '.cache')
        }
        It 'leaves component destinations to the component installation' {
            $plan = Get-DevbinHomePlan
            @($plan.EnvVars | Where-Object { $_.Name -eq 'GH_CONFIG_DIR' }).Count | Should Be 0
            @($plan.EnvVars | Where-Object { $_.Name -eq 'NPM_CONFIG_USERCONFIG' }).Count | Should Be 0
            @($plan.EnvVars | Where-Object { $_.Name -eq 'CONTINUE_GLOBAL_DIR' }).Count | Should Be 1
        }
        It 'uses external portable data for a fresh VS Code installation' {
            Initialize-DevbinVSCodeData
            Test-Path (Join-Path (Get-DevbinDataDirectory) 'vscode') | Should Be $true
            Assert-MockCalled Set-DevbinUserEnvironmentValue -Scope It -Times 1 -Exactly -ParameterFilter { $Name -eq 'VSCODE_PORTABLE' -and $Value -eq (Join-Path (Get-DevbinDataDirectory) 'vscode') }
        }
        It 'uses the new destination even when legacy settings exist' {
            $legacy = Join-Path $TestDrive 'vscode\data'
            New-Item -ItemType Directory -Path $legacy -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $legacy 'settings') -Value 'existing'
            Initialize-DevbinVSCodeData
            Assert-MockCalled Set-DevbinUserEnvironmentValue -Scope It -Times 1 -Exactly -ParameterFilter { $Name -eq 'VSCODE_PORTABLE' -and $Value -eq (Join-Path (Get-DevbinDataDirectory) 'vscode') }
        }
        It 'resets an old portable override on installation' {
            Mock Get-DevbinUserEnvironmentValue { 'C:\existing-vscode' } -ParameterFilter { $Name -eq 'VSCODE_PORTABLE' }
            Initialize-DevbinVSCodeData
            Assert-MockCalled Set-DevbinUserEnvironmentValue -Scope It -Times 1 -Exactly -ParameterFilter { $Name -eq 'VSCODE_PORTABLE' -and $Value -eq (Join-Path (Get-DevbinDataDirectory) 'vscode') }
        }
    }
}

InModuleScope Devbin {
    Describe 'User storage cleanup' {
        BeforeEach {
            Mock Get-DevbinUserStorageRoot { Join-Path $TestDrive 'storage' }
            $script:DevbinOperationLogState.Started = $false
            $script:DevbinOperationLogState.Path = $null
            New-Item -ItemType Directory -Path (Get-DevbinDataDirectory) -Force | Out-Null
            New-Item -ItemType Directory -Path (Get-DevbinLogDirectory) -Force | Out-Null
            Set-Content -LiteralPath (Join-Path (Get-DevbinDataDirectory) 'settings') -Value 'keep'
            Set-Content -LiteralPath (Join-Path (Get-DevbinLogDirectory) 'old.log') -Value 'old'
        }
        AfterEach {
            $script:DevbinOperationLogState.Started = $false
            $script:DevbinOperationLogState.Path = $null
        }
        It 'preserves both directories by default' {
            Remove-DevbinUserStorage
            Test-Path (Join-Path (Get-DevbinDataDirectory) 'settings') | Should Be $true
            Test-Path (Join-Path (Get-DevbinLogDirectory) 'old.log') | Should Be $true
        }
        It 'removes only data when selected' {
            Remove-DevbinUserStorage -RemoveData
            Test-Path (Get-DevbinDataDirectory) | Should Be $false
            Test-Path (Join-Path (Get-DevbinLogDirectory) 'old.log') | Should Be $true
        }
        It 'keeps the active transcript while deleting previous logs' {
            $script:DevbinOperationLogState.Path = Join-Path (Get-DevbinLogDirectory) 'current.log'
            $script:DevbinOperationLogState.Started = $true
            Set-Content -LiteralPath $script:DevbinOperationLogState.Path -Value 'current'
            Remove-DevbinUserStorage -RemoveLogs
            Test-Path $script:DevbinOperationLogState.Path | Should Be $true
            Test-Path (Join-Path (Get-DevbinLogDirectory) 'old.log') | Should Be $false
            Test-Path (Get-DevbinDataDirectory) | Should Be $true
        }
        It 'removes both selected areas while retaining the log directory' {
            Remove-DevbinUserStorage -RemoveData -RemoveLogs
            Test-Path (Get-DevbinDataDirectory) | Should Be $false
            Test-Path (Get-DevbinLogDirectory) | Should Be $true
            @(Get-ChildItem -LiteralPath (Get-DevbinLogDirectory) -Force).Count | Should Be 0
        }
        It 'refuses an arbitrary path' {
            { Assert-DevbinStorageTreeSafe -Path $TestDrive } | Should Throw
        }
        It 'reports deletion errors instead of silently succeeding' {
            Mock Remove-Item { throw 'locked' }
            { Remove-DevbinUserStorage -RemoveData } | Should Throw 'locked'
        }
        It 'refuses a reparse point before removal' {
            Mock Get-Item { [PSCustomObject]@{ Attributes = [IO.FileAttributes]::ReparsePoint } }
            Mock Remove-Item { throw 'must not remove' }
            { Remove-DevbinUserStorage -RemoveData -RemoveLogs } | Should Throw
            Assert-MockCalled Remove-Item -Scope It -Times 0 -Exactly
        }
        It 'refuses a nested reparse point before deleting either area' {
            Mock Get-Item { [PSCustomObject]@{ Attributes = [IO.FileAttributes]::Directory } }
            Mock Get-ChildItem { [PSCustomObject]@{ Attributes = [IO.FileAttributes]::ReparsePoint; FullName = 'nested-link' } }
            Mock Remove-Item { throw 'must not remove' }
            { Remove-DevbinUserStorage -RemoveData -RemoveLogs } | Should Throw
            Assert-MockCalled Remove-Item -Scope It -Times 0 -Exactly
        }

    }
}

InModuleScope Devbin {
    Describe 'Complete uninstall storage choices' {
        BeforeEach {
            Mock Test-DevbinProductRootAllowed { $true }
            Mock Get-DevbinExpectedProductRoot { Join-Path $TestDrive 'product' }
            Mock Get-DevbinUserStorageRoot { Join-Path $TestDrive 'storage' }
            Mock Get-DevbinProductRoot { Join-Path $TestDrive 'product' }
            Mock Read-ConfirmationKey { $false }
            Mock Remove-UserEnvVarsPointingToRoot { @() }
            Mock Remove-UserPathEntriesPointingToRoot {}
            Mock Remove-FontRegistrationsPointingToRoot {}
            Mock Remove-WindowsTerminalProfilesForRoot {}
            Mock Unregister-VswhereInstanceIfPointingToRoot {}
            Mock Sync-EnvironmentVariables {}
            Mock Remove-DirectoryTree { [PSCustomObject]@{ Success = $true } }
            Mock Remove-DevbinUserStorage {}
            Mock Write-Host {}
        }
        It 'force alone retains data and logs' {
            (Invoke-ProductUninstall -InstallDir 'ignored' -Force).Status | Should Be 'Success'
            Assert-MockCalled Remove-DevbinUserStorage -Scope It -Times 1 -Exactly -ParameterFilter { -not $RemoveData -and -not $RemoveLogs }
            Assert-MockCalled Read-ConfirmationKey -Scope It -Times 0 -Exactly
        }
        It 'passes both explicit cleanup switches' {
            (Invoke-ProductUninstall -InstallDir 'ignored' -Force -RemoveData -RemoveLogs).Status | Should Be 'Success'
            Assert-MockCalled Remove-DevbinUserStorage -Scope It -Times 1 -Exactly -ParameterFilter { $RemoveData -and $RemoveLogs }
        }
        It 'collects both choices before the final confirmation' {
            Mock Read-ConfirmationKey { $true } -ParameterFilter { $Prompt -like 'data *' -or $Prompt -like '続行しますか*' }
            (Invoke-ProductUninstall -InstallDir 'ignored').Status | Should Be 'Success'
            Assert-MockCalled Read-ConfirmationKey -Scope It -Times 3 -Exactly
            Assert-MockCalled Remove-DevbinUserStorage -Scope It -Times 1 -Exactly -ParameterFilter { $RemoveData -and -not $RemoveLogs }
        }
        It 'does nothing after cancellation' {
            Mock Read-ConfirmationKey { $false } -ParameterFilter { $Prompt -like '続行しますか*' }
            (Invoke-ProductUninstall -InstallDir 'ignored' -RemoveData -RemoveLogs).Status | Should Be 'Cancelled'
            Assert-MockCalled Remove-DevbinUserStorage -Scope It -Times 0 -Exactly
            Assert-MockCalled Remove-UserEnvVarsPointingToRoot -Scope It -Times 0 -Exactly
        }
        It 'refuses cleanup for an unexpected product location' {
            Mock Test-DevbinProductRootAllowed { $false }
            (Invoke-ProductUninstall -InstallDir 'ignored' -Force -RemoveData -RemoveLogs).Status | Should Be 'Refused'
            Assert-MockCalled Remove-DevbinUserStorage -Scope It -Times 0 -Exactly
        }
        It 'propagates cleanup failure' {
            Mock Remove-DevbinUserStorage { throw 'locked' }
            (Invoke-ProductUninstall -InstallDir 'ignored' -Force -RemoveLogs).Status | Should Be 'Failed'
        }
        It 'clears references to removed data even if log cleanup fails' {
            Mock Remove-DevbinUserStorage { throw 'log locked after data removal' }
            (Invoke-ProductUninstall -InstallDir 'ignored' -Force -RemoveData -RemoveLogs).Status | Should Be 'Failed'
            Assert-MockCalled Remove-UserEnvVarsPointingToRoot -Scope It -Times 1 -Exactly -ParameterFilter { $Root -eq (Get-DevbinDataDirectory) }
        }
    }
}

InModuleScope Devbin {
    Describe 'Component storage configuration' {
        BeforeEach {
            Mock Get-DevbinUserStorageRoot { Join-Path $TestDrive 'storage' }
            Mock Get-DevbinUserEnvironmentValue { $null }
            Mock Set-DevbinUserEnvironmentValue {}
        }
        It 'creates data even for a component without its own storage' {
            Initialize-DevbinComponentStorage -ShortName 'cloc' | Should BeNullOrEmpty
            Test-Path (Get-DevbinDataDirectory) | Should Be $true
            Assert-MockCalled Set-DevbinUserEnvironmentValue -Scope It -Times 0 -Exactly
        }
        It 'creates the directory and sets the variable for the installed component' {
            $applied = @(Initialize-DevbinComponentStorage -ShortName 'gh')
            $applied | Should Be 'GH_CONFIG_DIR'
            Test-Path (Join-Path (Get-DevbinDataDirectory) 'gh') | Should Be $true
            Assert-MockCalled Set-DevbinUserEnvironmentValue -Scope It -Times 1 -Exactly -ParameterFilter { $Name -eq 'GH_CONFIG_DIR' -and $Value -eq (Join-Path (Get-DevbinDataDirectory) 'gh') }
        }
        It 'creates the parent directory for a variable that points at a file' {
            @(Initialize-DevbinComponentStorage -ShortName 'nodejs') -contains 'NPM_CONFIG_USERCONFIG' | Should Be $true
            Test-Path (Join-Path (Get-DevbinDataDirectory) 'npm') | Should Be $true
            Test-Path (Join-Path (Get-DevbinDataDirectory) 'npm\npmrc') | Should Be $false
        }
        It 'keeps a value the user already configured' {
            Mock Get-DevbinUserEnvironmentValue { 'C:\my-gh' } -ParameterFilter { $Name -eq 'GH_CONFIG_DIR' }
            Initialize-DevbinComponentStorage -ShortName 'gh' | Should BeNullOrEmpty
            Assert-MockCalled Set-DevbinUserEnvironmentValue -Scope It -Times 0 -Exactly
        }
        It 'clears its own value on uninstall' {
            Mock Get-DevbinUserEnvironmentValue { Join-Path (Get-DevbinDataDirectory) 'gh' } -ParameterFilter { $Name -eq 'GH_CONFIG_DIR' }
            @(Remove-DevbinComponentStorage -ShortName 'gh') | Should Be 'GH_CONFIG_DIR'
            Assert-MockCalled Set-DevbinUserEnvironmentValue -Scope It -Times 1 -Exactly -ParameterFilter { $Name -eq 'GH_CONFIG_DIR' -and [string]::IsNullOrEmpty($Value) }
        }
        It 'keeps a value the user redirected elsewhere' {
            Mock Get-DevbinUserEnvironmentValue { 'C:\my-gh' } -ParameterFilter { $Name -eq 'GH_CONFIG_DIR' }
            Remove-DevbinComponentStorage -ShortName 'gh' | Should BeNullOrEmpty
            Assert-MockCalled Set-DevbinUserEnvironmentValue -Scope It -Times 0 -Exactly
        }
        It 'keeps a shared destination while another component still uses it' {
            Mock Get-DevbinUserEnvironmentValue { Join-Path (Get-DevbinDataDirectory) 'nuget\packages' } -ParameterFilter { $Name -eq 'NUGET_PACKAGES' }
            @(Remove-DevbinComponentStorage -ShortName 'nuget' -InstalledShortNames @('dotnet10sdk')) -contains 'NUGET_PACKAGES' | Should Be $false
            @(Remove-DevbinComponentStorage -ShortName 'nuget' -InstalledShortNames @()) -contains 'NUGET_PACKAGES' | Should Be $true
        }
        It 'clears VSCODE_PORTABLE only when it still points at data' {
            Mock Get-DevbinUserEnvironmentValue { Join-Path (Get-DevbinDataDirectory) 'vscode' } -ParameterFilter { $Name -eq 'VSCODE_PORTABLE' }
            Remove-DevbinVSCodeData | Should Be $true
            Assert-MockCalled Set-DevbinUserEnvironmentValue -Scope It -Times 1 -Exactly -ParameterFilter { $Name -eq 'VSCODE_PORTABLE' -and [string]::IsNullOrEmpty($Value) }
        }
        It 'keeps a portable location the user chose' {
            Mock Get-DevbinUserEnvironmentValue { 'C:\my-vscode' } -ParameterFilter { $Name -eq 'VSCODE_PORTABLE' }
            Remove-DevbinVSCodeData | Should Be $false
            Assert-MockCalled Set-DevbinUserEnvironmentValue -Scope It -Times 0 -Exactly
        }
    }
}

Describe 'Manage applies the storage configuration' {
    It 'sets and clears the destinations from the component operations' {
        $subscriptsDir = Get-DevbinSubscriptsDir
        $installSource = Get-Content (Join-Path $subscriptsDir 'Devbin\Install\ComponentInstall.ps1') -Raw
        $uninstallSource = Get-Content (Join-Path $subscriptsDir 'Devbin\Install\ComponentUninstall.ps1') -Raw
        $setupSource = Get-Content (Join-Path $subscriptsDir 'Setup-Bin.ps1') -Raw

        $installSource | Should Match 'Initialize-DevbinComponentStorage -ShortName'
        $uninstallSource | Should Match 'Remove-DevbinComponentStorage -ShortName'
        $uninstallSource | Should Match 'Remove-DevbinVSCodeData'
        $setupSource | Should Match 'Initialize-DevbinUserStorage'
        $setupSource | Should Match 'Invoke-DevbinHomePlan -Plan \$homePlan'
    }

    It 'no longer ships a separate home setup script' {
        Test-Path (Join-Path (Get-DevbinSubscriptsDir) 'Setup-Home.ps1') | Should Be $false
    }
}
