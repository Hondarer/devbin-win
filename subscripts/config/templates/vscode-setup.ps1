param([Parameter(Mandatory=$true)][string]$TargetPath)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\..\Devbin') -Force -ErrorAction Stop
Initialize-DevbinVSCodeData
