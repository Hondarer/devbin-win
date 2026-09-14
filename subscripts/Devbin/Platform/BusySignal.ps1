# BusySignal.ps1
# 長い処理の間、スリープとスクリーンセーバーを抑止する

# スリープ/スクリーンセーバーを抑止する Busy シグナルを開始する
function Start-BusySignal {
    if (-not ("Devbin.PowerNative" -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

namespace Devbin
{
    public static class PowerNative
    {
        [DllImport("kernel32.dll")]
        public static extern uint SetThreadExecutionState(uint esFlags);
    }
}
"@
    }

    # ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED
    $busySignalFlags = [Convert]::ToUInt32("80000003", 16)

    [Devbin.PowerNative]::SetThreadExecutionState($busySignalFlags) | Out-Null

    $script:BusySignalTimer = New-Object System.Timers.Timer
    $script:BusySignalTimer.Interval = 10000
    $script:BusySignalTimer.AutoReset = $true

    # Register-ObjectEvent の -Action はモジュールの $script: スコープを参照できないため、
    # -MessageData 経由でフラグ値を渡す
    $script:BusySignalEventJob = Register-ObjectEvent `
        -InputObject $script:BusySignalTimer `
        -EventName Elapsed `
        -MessageData $busySignalFlags `
        -Action { [Devbin.PowerNative]::SetThreadExecutionState($Event.MessageData) | Out-Null }

    $script:BusySignalTimer.Start()
}

# Busy シグナルを停止し、スリープ抑止状態を解除する
function Stop-BusySignal {
    if ($null -ne $script:BusySignalTimer) {
        $script:BusySignalTimer.Stop()
        $script:BusySignalTimer.Dispose()
        $script:BusySignalTimer = $null
    }

    if ($null -ne $script:BusySignalEventJob) {
        Unregister-Event -SourceIdentifier $script:BusySignalEventJob.Name -ErrorAction SilentlyContinue
        $script:BusySignalEventJob = $null
    }

    if ("Devbin.PowerNative" -as [type]) {
        [Devbin.PowerNative]::SetThreadExecutionState([Convert]::ToUInt32("80000000", 16)) | Out-Null
    }
}
