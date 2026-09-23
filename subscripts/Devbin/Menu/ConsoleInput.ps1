# ConsoleInput.ps1
# コンソール入力 (キー入力およびマウスホイールイベント) の読み取り

$script:INPUT_RECORD_KEY_EVENT = 0x0001
$script:INPUT_RECORD_MOUSE_EVENT = 0x0002
$script:INPUT_RECORD_WINDOW_BUFFER_SIZE_EVENT = 0x0004
$script:MOUSE_WHEELED_EVENT = 0x0004
$script:MOUSE_DOUBLE_CLICK_EVENT = 0x0002
$script:FROM_LEFT_1ST_BUTTON_PRESSED = 0x0001
$script:SHIFT_PRESSED = 0x0010
$script:LEFT_ALT_PRESSED = 0x0002
$script:RIGHT_ALT_PRESSED = 0x0001
$script:LEFT_CTRL_PRESSED = 0x0008
$script:RIGHT_CTRL_PRESSED = 0x0004
$script:STD_INPUT_HANDLE = -10
$script:ENABLE_MOUSE_INPUT = 0x0010
$script:ENABLE_QUICK_EDIT_MODE = 0x0040
$script:ENABLE_EXTENDED_FLAGS = 0x0080

# ネイティブ型定義はメニュー表示時のみ動的にロードします。
# ヒアストリングの構文規則に従い、終端記号を行頭に配置するためインデントを適用しません。
function Initialize-ConsoleInputType {
if (-not ("Devbin.ConsoleInputNative" -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

namespace Devbin
{
    [StructLayout(LayoutKind.Sequential)]
    public struct COORD
    {
        public short X;
        public short Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct KEY_EVENT_RECORD
    {
        public int bKeyDown;
        public ushort wRepeatCount;
        public ushort wVirtualKeyCode;
        public ushort wVirtualScanCode;
        public ushort UnicodeChar;
        public uint dwControlKeyState;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct MOUSE_EVENT_RECORD
    {
        public COORD dwMousePosition;
        public uint dwButtonState;
        public uint dwControlKeyState;
        public uint dwEventFlags;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct WINDOW_BUFFER_SIZE_RECORD
    {
        public COORD dwSize;
    }

    [StructLayout(LayoutKind.Explicit)]
    public struct INPUT_RECORD
    {
        [FieldOffset(0)]
        public short EventType;

        [FieldOffset(4)]
        public KEY_EVENT_RECORD KeyEvent;

        [FieldOffset(4)]
        public MOUSE_EVENT_RECORD MouseEvent;

        [FieldOffset(4)]
        public WINDOW_BUFFER_SIZE_RECORD WindowBufferSizeEvent;
    }

    public static class ConsoleInputNative
    {
        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern IntPtr GetStdHandle(int nStdHandle);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool ReadConsoleInput(
            IntPtr hConsoleInput,
            [Out] INPUT_RECORD[] lpBuffer,
            uint nLength,
            out uint lpNumberOfEventsRead);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool FlushConsoleInputBuffer(IntPtr hConsoleInput);
    }
}
"@
}
}

function ConvertTo-ConsoleKeyInfo {
    param($KeyEvent)

    $controlState = $KeyEvent.dwControlKeyState
    $virtualKeyCode = [int]$KeyEvent.wVirtualKeyCode
    $unicodeChar = [char][uint16]$KeyEvent.UnicodeChar
    $consoleKey = if ([System.Enum]::IsDefined([System.ConsoleKey], $virtualKeyCode)) {
        [System.ConsoleKey]$virtualKeyCode
    } else {
        [System.ConsoleKey]::NoName
    }

    return [System.ConsoleKeyInfo]::new(
        $unicodeChar,
        $consoleKey,
        (($controlState -band $script:SHIFT_PRESSED) -ne 0),
        ((($controlState -band $script:LEFT_ALT_PRESSED) -ne 0) -or (($controlState -band $script:RIGHT_ALT_PRESSED) -ne 0)),
        ((($controlState -band $script:LEFT_CTRL_PRESSED) -ne 0) -or (($controlState -band $script:RIGHT_CTRL_PRESSED) -ne 0))
    )
}

function Enable-ConsoleMouseInput {
    Initialize-ConsoleInputType

    $inputHandle = [Devbin.ConsoleInputNative]::GetStdHandle($script:STD_INPUT_HANDLE)
    if ($inputHandle -eq [IntPtr]::Zero -or $inputHandle -eq [IntPtr]::new(-1)) {
        return @{ Enabled = $false }
    }

    $originalMode = 0
    if (-not [Devbin.ConsoleInputNative]::GetConsoleMode($inputHandle, [ref]$originalMode)) {
        return @{ Enabled = $false }
    }

    $mouseMode = ($originalMode -bor $script:ENABLE_MOUSE_INPUT -bor $script:ENABLE_EXTENDED_FLAGS) -band (-bnot $script:ENABLE_QUICK_EDIT_MODE)
    if (-not [Devbin.ConsoleInputNative]::SetConsoleMode($inputHandle, [uint32]$mouseMode)) {
        return @{ Enabled = $false; Handle = $inputHandle; OriginalMode = $originalMode }
    }

    [Devbin.ConsoleInputNative]::FlushConsoleInputBuffer($inputHandle) | Out-Null
    return @{ Enabled = $true; Handle = $inputHandle; OriginalMode = $originalMode; LeftButtonDown = $false }
}

function Restore-ConsoleInputMode {
    param([hashtable]$InputModeState)

    if ($InputModeState -and $InputModeState.ContainsKey("Handle") -and $InputModeState.ContainsKey("OriginalMode")) {
        [Devbin.ConsoleInputNative]::SetConsoleMode($InputModeState.Handle, [uint32]$InputModeState.OriginalMode) | Out-Null
    }
}

function Read-MenuInput {
    param([hashtable]$InputModeState)

    if (-not $InputModeState.Enabled) {
        return @{ Kind = "Key"; KeyInfo = [Console]::ReadKey($true) }
    }

    $records = New-Object 'Devbin.INPUT_RECORD[]' 1
    $readCount = 0
    while ($true) {
        $ok = [Devbin.ConsoleInputNative]::ReadConsoleInput($InputModeState.Handle, $records, 1, [ref]$readCount)
        if (-not $ok -or $readCount -le 0) {
            return @{ Kind = "Key"; KeyInfo = [Console]::ReadKey($true) }
        }

        $record = $records[0]
        switch ($record.EventType) {
            $script:INPUT_RECORD_KEY_EVENT {
                if ($record.KeyEvent.bKeyDown -eq 0) {
                    continue
                }
                return @{ Kind = "Key"; KeyInfo = (ConvertTo-ConsoleKeyInfo -KeyEvent $record.KeyEvent) }
            }

            $script:INPUT_RECORD_MOUSE_EVENT {
                if ($record.MouseEvent.dwEventFlags -eq $script:MOUSE_WHEELED_EVENT) {
                    return @{ Kind = "Mouse"; MouseEvent = $record.MouseEvent }
                }
                if (Test-MenuLeftClickPress -InputModeState $InputModeState -MouseEvent $record.MouseEvent) {
                    return @{ Kind = "Mouse"; MouseEvent = $record.MouseEvent }
                }
                continue
            }

            $script:INPUT_RECORD_WINDOW_BUFFER_SIZE_EVENT {
                return @{ Kind = "Resize" }
            }
        }
    }
}

# 左ボタンの新しい押下のみをクリックとして扱い、押し続けた移動をクリックにしません。
function Test-MenuLeftClickPress {
    param(
        [hashtable]$InputModeState,
        $MouseEvent
    )

    $leftButtonDown = (($MouseEvent.dwButtonState -band $script:FROM_LEFT_1ST_BUTTON_PRESSED) -ne 0)
    $wasLeftButtonDown = [bool]$InputModeState.LeftButtonDown
    $InputModeState.LeftButtonDown = $leftButtonDown

    if ($MouseEvent.dwEventFlags -eq $script:MOUSE_DOUBLE_CLICK_EVENT) {
        return $leftButtonDown
    }
    if ($MouseEvent.dwEventFlags -ne 0) {
        return $false
    }

    return $leftButtonDown -and -not $wasLeftButtonDown
}

function Handle-MouseInput {
    param(
        [hashtable]$State,
        $MouseEvent
    )

    if ($MouseEvent.dwEventFlags -eq $script:MOUSE_WHEELED_EVENT) {
        $menuTop = $script:HEADER_ROWS
        $menuBottom = $script:HEADER_ROWS + $State.ViewportSize - 1
        $mouseRow = [int]$MouseEvent.dwMousePosition.Y
        if ($mouseRow -lt $menuTop -or $mouseRow -gt $menuBottom) {
            return "continue"
        }

        $wheelDeltaBits = [int](($MouseEvent.dwButtonState -shr 16) -band 0xFFFF)
        $wheelDelta = if ($wheelDeltaBits -ge 0x8000) { $wheelDeltaBits - 0x10000 } else { $wheelDeltaBits }
        if ($wheelDelta -eq 0) {
            return "continue"
        }

        if ($wheelDelta -gt 0) {
            return Move-MenuCursor -State $State -Delta -1
        }
        return Move-MenuCursor -State $State -Delta 1
    }

    if ($MouseEvent.dwEventFlags -ne 0 -and $MouseEvent.dwEventFlags -ne $script:MOUSE_DOUBLE_CLICK_EVENT) {
        return "continue"
    }
    if (($MouseEvent.dwButtonState -band $script:FROM_LEFT_1ST_BUTTON_PRESSED) -eq 0) {
        return "continue"
    }

    $menuTop = $script:HEADER_ROWS
    $menuBottom = $script:HEADER_ROWS + $State.ViewportSize - 1
    $mouseRow = [int]$MouseEvent.dwMousePosition.Y
    if ($mouseRow -lt $menuTop -or $mouseRow -gt $menuBottom) {
        return "continue"
    }

    $targetIndex = $State.ViewportTop + $mouseRow - $menuTop
    $items = @(Get-MenuItemList -State $State)
    if ($targetIndex -lt 0 -or $targetIndex -ge $items.Count) {
        return "continue"
    }
    if ($null -eq $items[$targetIndex] -or [string]::IsNullOrWhiteSpace([string]$items[$targetIndex].ShortName)) {
        return "continue"
    }

    if ($targetIndex -eq $State.CursorIndex) {
        return Invoke-MenuCursorToggle -State $State
    }
    return Move-MenuCursor -State $State -Delta ($targetIndex - $State.CursorIndex)
}
