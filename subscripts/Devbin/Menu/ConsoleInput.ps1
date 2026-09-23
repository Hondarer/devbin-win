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
# Win32 では公開されていない IME 開状態コマンドを使用し、対象端末側の IME を操作します。
$script:WM_IME_CONTROL_MESSAGE = 0x0283
$script:IMC_GETOPENSTATUS_COMMAND = 0x0005
$script:IMC_SETOPENSTATUS_COMMAND = 0x0006
$script:SMTO_ABORTIFHUNG_FLAG = 0x0002
$script:GA_ROOTOWNER_FLAG = 3
# TSF で IME を処理する端末 (Windows Terminal, VS Code) は IMM の開状態コマンドに追従しないため、
# 日本語キーボードの IME OFF キーを合成入力し、IME 自身に半角英数モードへ切り替えさせます。
$script:VK_IME_ON_KEY = 0x16
$script:VK_IME_OFF_KEY = 0x1A
$script:LANG_JAPANESE_PRIMARY = 0x11

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
        [StructLayout(LayoutKind.Sequential)]
        public struct RECT
        {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct GUITHREADINFO
        {
            public uint cbSize;
            public uint flags;
            public IntPtr hwndActive;
            public IntPtr hwndFocus;
            public IntPtr hwndCapture;
            public IntPtr hwndMenuOwner;
            public IntPtr hwndMoveSize;
            public IntPtr hwndCaret;
            public RECT rcCaret;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct MOUSEINPUT
        {
            public int dx;
            public int dy;
            public uint mouseData;
            public uint dwFlags;
            public uint time;
            public IntPtr dwExtraInfo;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct KEYBDINPUT
        {
            public ushort wVk;
            public ushort wScan;
            public uint dwFlags;
            public uint time;
            public IntPtr dwExtraInfo;
        }

        // INPUT のサイズを OS の定義 (MOUSEINPUT を含む共用体) と一致させます。
        [StructLayout(LayoutKind.Explicit)]
        public struct INPUTUNION
        {
            [FieldOffset(0)]
            public MOUSEINPUT mi;

            [FieldOffset(0)]
            public KEYBDINPUT ki;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct INPUT
        {
            public uint type;
            public INPUTUNION u;
        }

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern IntPtr GetStdHandle(int nStdHandle);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern IntPtr GetConsoleWindow();

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

        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        public static extern IntPtr GetAncestor(IntPtr hWnd, uint flags);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool GetGUIThreadInfo(uint threadId, ref GUITHREADINFO info);

        [DllImport("user32.dll")]
        public static extern IntPtr GetKeyboardLayout(uint threadId);

        [DllImport("kernel32.dll", EntryPoint = "GetConsoleKeyboardLayoutNameW", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool GetConsoleKeyboardLayoutName(System.Text.StringBuilder layoutName);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern uint SendInput(uint inputCount, INPUT[] inputs, int inputSize);

        // 仮想キーの押下と解放を 1 回の SendInput で送信し、送信できたイベント数を返します。
        public static uint SendKeyPress(ushort virtualKey)
        {
            INPUT[] inputs = new INPUT[2];
            inputs[0].type = 1;
            inputs[0].u.ki.wVk = virtualKey;
            inputs[1].type = 1;
            inputs[1].u.ki.wVk = virtualKey;
            inputs[1].u.ki.dwFlags = 0x0002;
            return SendInput(2, inputs, Marshal.SizeOf(typeof(INPUT)));
        }

        [DllImport("imm32.dll", SetLastError = true)]
        public static extern IntPtr ImmGetDefaultIMEWnd(IntPtr hWnd);

        [DllImport("user32.dll", EntryPoint = "SendMessageTimeoutW", SetLastError = true)]
        public static extern IntPtr SendMessageTimeout(
            IntPtr hWnd,
            uint message,
            IntPtr wParam,
            IntPtr lParam,
            uint flags,
            uint timeout,
            out IntPtr result);
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

# 前景端末が Manage-Bin を表示しているか確認し、IME の入力先を取得します。
function Get-MenuImeTarget {
    Initialize-ConsoleInputType

    $foregroundWindow = [Devbin.ConsoleInputNative]::GetForegroundWindow()
    if ($foregroundWindow -eq [IntPtr]::Zero) {
        return @{ IsTarget = $false; Reason = "前景ウィンドウを取得できません" }
    }

    $consoleWindow = [Devbin.ConsoleInputNative]::GetConsoleWindow()
    $foregroundProcessId = [uint32]0
    $foregroundThreadId = [Devbin.ConsoleInputNative]::GetWindowThreadProcessId($foregroundWindow, [ref]$foregroundProcessId)
    if ($foregroundThreadId -eq 0) {
        return @{ IsTarget = $false; Reason = "前景端末を確認できません" }
    }

    $isCurrentConsole = ($foregroundWindow -eq $consoleWindow)
    # Windows Terminal は擬似コンソールの隠しウィンドウの所有者を自身のウィンドウに設定します。
    # 既定のターミナル経由の起動では WT_SESSION が設定されないため、環境変数より先に所有関係で判定します。
    if (-not $isCurrentConsole -and $consoleWindow -ne [IntPtr]::Zero) {
        $consoleRootOwner = [Devbin.ConsoleInputNative]::GetAncestor($consoleWindow, [uint32]$script:GA_ROOTOWNER_FLAG)
        $isCurrentConsole = ($consoleRootOwner -eq $foregroundWindow)
    }
    $isHostTerminal = $false
    if (-not $isCurrentConsole) {
        try {
            $foregroundProcess = Get-Process -Id ([int]$foregroundProcessId) -ErrorAction Stop
            $isHostTerminal = Test-MenuImeHostTerminal -ProcessName $foregroundProcess.ProcessName
        } catch {
            $isHostTerminal = $false
        }
    }
    if (-not ($isCurrentConsole -or $isHostTerminal)) {
        return @{ IsTarget = $false; Reason = "Manage-Bin の端末にフォーカスがありません" }
    }

    $threadInfo = New-Object Devbin.ConsoleInputNative+GUITHREADINFO
    $threadInfo.cbSize = [uint32][Runtime.InteropServices.Marshal]::SizeOf($threadInfo)
    $hasThreadInfo = [Devbin.ConsoleInputNative]::GetGUIThreadInfo($foregroundThreadId, [ref]$threadInfo)
    if (-not $hasThreadInfo) {
        # conhost はコンソール ウィンドウの所有スレッドを接続中のクライアントのスレッドとして報告するため、
        # ウィンドウを実際に処理する前景スレッドの情報 (スレッド ID 0) を取得します。
        $threadInfo = New-Object Devbin.ConsoleInputNative+GUITHREADINFO
        $threadInfo.cbSize = [uint32][Runtime.InteropServices.Marshal]::SizeOf($threadInfo)
        $hasThreadInfo = ([Devbin.ConsoleInputNative]::GetGUIThreadInfo([uint32]0, [ref]$threadInfo) -and
            $threadInfo.hwndActive -eq $foregroundWindow)
        $foregroundThreadId = [uint32]0
    }
    if (-not $hasThreadInfo -or $threadInfo.hwndFocus -eq [IntPtr]::Zero) {
        return @{ IsTarget = $false; Reason = "端末の入力先を取得できません" }
    }

    return @{ IsTarget = $true; FocusWindow = $threadInfo.hwndFocus; ThreadId = $foregroundThreadId; Reason = "" }
}

# 前景プロセスが Manage-Bin を表示している疑似コンソール端末かを、端末が設定する環境変数と照合します。
function Test-MenuImeHostTerminal {
    param([string]$ProcessName)

    if (-not [string]::IsNullOrWhiteSpace($env:WT_SESSION) -and $ProcessName -like "WindowsTerminal*") {
        return $true
    }
    if ($env:TERM_PROGRAM -eq "vscode" -and $ProcessName -in @("Code", "Code - Insiders")) {
        return $true
    }
    return $false
}

# 入力先スレッドのキーボード レイアウトが日本語かを判定します。
# 入力先スレッドを特定できない conhost では、コンソールのキーボード レイアウトで判定します。
function Test-MenuImeJapaneseLayout {
    param([uint32]$ThreadId)

    $layout = [int64]0
    if ($ThreadId -ne 0) {
        $layout = [Devbin.ConsoleInputNative]::GetKeyboardLayout($ThreadId).ToInt64()
    }
    if ($layout -eq 0) {
        $layoutName = New-Object System.Text.StringBuilder 9
        if ([Devbin.ConsoleInputNative]::GetConsoleKeyboardLayoutName($layoutName)) {
            $layout = [Convert]::ToInt64($layoutName.ToString(), 16)
        }
    }
    return (($layout -band 0x3FF) -eq $script:LANG_JAPANESE_PRIMARY)
}

# IME OFF キーの押下と解放を前景ウィンドウへ合成入力します。
function Send-MenuImeOffKey {
    Initialize-ConsoleInputType

    $sentCount = [Devbin.ConsoleInputNative]::SendKeyPress([uint16]$script:VK_IME_OFF_KEY)
    if ($sentCount -ne 2) {
        return @{ Success = $false; Reason = "IME OFF キーを送信できません" }
    }
    return @{ Success = $true; Reason = "" }
}

# IMM の IME 開状態を設定し、閉じたことを確認します。
function Set-MenuImeOpenStatus {
    param([IntPtr]$FocusWindow)

    $imeWindow = [Devbin.ConsoleInputNative]::ImmGetDefaultIMEWnd($FocusWindow)
    if ($imeWindow -eq [IntPtr]::Zero) {
        return @{ Success = $false; Reason = "IME ウィンドウを取得できません" }
    }

    $messageResult = [IntPtr]::Zero
    $sent = [Devbin.ConsoleInputNative]::SendMessageTimeout(
        $imeWindow, $script:WM_IME_CONTROL_MESSAGE, [IntPtr]$script:IMC_SETOPENSTATUS_COMMAND,
        [IntPtr]::Zero, $script:SMTO_ABORTIFHUNG_FLAG, 500, [ref]$messageResult)
    if ($sent -eq [IntPtr]::Zero) {
        return @{ Success = $false; Reason = "IME の OFF 操作がタイムアウトしました" }
    }

    $queryResult = [IntPtr]::Zero
    $queried = [Devbin.ConsoleInputNative]::SendMessageTimeout(
        $imeWindow, $script:WM_IME_CONTROL_MESSAGE, [IntPtr]$script:IMC_GETOPENSTATUS_COMMAND,
        [IntPtr]::Zero, $script:SMTO_ABORTIFHUNG_FLAG, 500, [ref]$queryResult)
    if ($queried -eq [IntPtr]::Zero -or $queryResult.ToInt64() -ne 0) {
        return @{ Success = $false; Reason = "IME の開状態が OFF になりませんでした" }
    }

    return @{ Success = $true; Reason = "" }
}

# Manage-Bin を表示している端末の IME 開状態を閉じます。
function Set-MenuImeClosed {
    $target = Get-MenuImeTarget
    if (-not $target.IsTarget) {
        return @{ Success = $false; Reason = $target.Reason }
    }

    # conhost のように IMM で IME を処理する端末は開状態コマンドで閉じます。
    # TSF の端末では開状態コマンドが無視されるか、確認結果が実際の状態と一致しない場合があるため、
    # 結果によらず日本語レイアウトでは IME OFF キーも送信します。IME OFF キーは何度送っても同じ状態になります。
    $immResult = Set-MenuImeOpenStatus -FocusWindow $target.FocusWindow
    if (-not (Test-MenuImeJapaneseLayout -ThreadId $target.ThreadId)) {
        return $immResult
    }

    $keyResult = Send-MenuImeOffKey
    if ($keyResult.Success -or $immResult.Success) {
        return @{ Success = $true; Reason = "" }
    }
    return $keyResult
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
                # IME が処理しなかった IME ON/OFF キーは、端末からメニューへ転送されても操作として扱いません。
                $virtualKeyCode = [int]$record.KeyEvent.wVirtualKeyCode
                if ($virtualKeyCode -eq $script:VK_IME_ON_KEY -or $virtualKeyCode -eq $script:VK_IME_OFF_KEY) {
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
