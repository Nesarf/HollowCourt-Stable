# Injected-touch input for a Flutter window on Windows.
#
# **Kept in the repository because it was written in a previous session, left in a temporary directory, and
# would have been deleted with it.** That is the same fault this project records about claims and about
# renders: a thing that has to be rediscovered is a thing that will be.
#
# Why touch and not the mouse, in the words of the session that found it out: *"the wheel and the keyboard do
# not reach the application's scroll view, and a mouse drag is not a drag to Flutter -- `ScrollBehavior.dragDevices`
# does not include the mouse on desktop, so dragging selects text instead of scrolling. A touch pointer IS a
# drag, and Windows lets a process inject one."*
#
# The 2026-09-24 round adds the second half of that lesson: `mouse_event` reaches the navigation bar of the
# installed build but **not** the *Add a bottle* button, at six positions covering its drawn area -- and the button is
# fine, because this repository's own test taps it. So synthetic mouse input is not a substitute for a real
# pointer everywhere, and injected touch is the better-behaved path. `adb shell input tap/text` is the same idea
# on Android.
#
# Usage:
#
#     powershell -NoProfile -File packaging/windows/touch.ps1 -X 1056 -Y1 96 -Tap     # tap a point
#     powershell -NoProfile -File packaging/windows/touch.ps1 -X 600 -Y1 500 -Y2 150  # drag-scroll
#
# **A caveat from that round:** on a machine somebody is using, the window in front is theirs, and an injected
# touch goes wherever the pointer is rather than to the application. Three rounds of "the button does not
# respond" happened with a browser in the foreground. Check what is in front before concluding anything.

# Drag-scroll a Flutter window with an injected TOUCH pointer.
#
# Why this exists: on this host the wheel and the keyboard do not reach the application's scroll view, and a
# mouse drag is not a drag to Flutter -- `ScrollBehavior.dragDevices` does not include the mouse on desktop, so
# dragging selects text instead of scrolling. A touch pointer IS a drag, and Windows lets a process inject one.
param([int]$X = 600, [int]$Y1 = 500, [int]$Y2 = 150, [int]$Steps = 14, [switch]$Tap)
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace QT {
  public class Touch {
    [StructLayout(LayoutKind.Sequential)] public struct POINTER_INFO {
      public uint pointerType; public uint pointerId; public uint frameId; public uint pointerFlags;
      public IntPtr sourceDevice; public IntPtr hwndTarget;
      public int ptPixelLocationX; public int ptPixelLocationY;
      public int ptHimetricLocationX; public int ptHimetricLocationY;
      public int ptPixelLocationRawX; public int ptPixelLocationRawY;
      public int ptHimetricLocationRawX; public int ptHimetricLocationRawY;
      public uint dwTime; public uint historyCount; public int inputData; public uint dwKeyStates;
      public ulong PerformanceCount; public int ButtonChangeType;
    }
    [StructLayout(LayoutKind.Sequential)] public struct POINTER_TOUCH_INFO {
      public POINTER_INFO pointerInfo; public uint touchFlags; public uint touchMask;
      public int rcContactLeft; public int rcContactTop; public int rcContactRight; public int rcContactBottom;
      public int rcContactRawLeft; public int rcContactRawTop; public int rcContactRawRight; public int rcContactRawBottom;
      public uint orientation; public uint pressure;
    }
    [DllImport("user32.dll")] public static extern bool InitializeTouchInjection(uint maxCount, uint dwMode);
    [DllImport("user32.dll")] public static extern bool InjectTouchInput(uint count, [In] POINTER_TOUCH_INFO[] contacts);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    public const uint DOWN = 0x0001, UPDATE = 0x0002, UP = 0x0004, INRANGE = 0x0008, INRANGE_PRIMARY = 0x0010, PRIMARY = 0x0002;
    public static POINTER_TOUCH_INFO Make(int x, int y, uint flags) {
      POINTER_TOUCH_INFO info = new POINTER_TOUCH_INFO();
      info.pointerInfo.pointerType = 2;
      info.pointerInfo.pointerId = 1;
      info.pointerInfo.pointerFlags = flags;
      info.pointerInfo.ptPixelLocationX = x;
      info.pointerInfo.ptPixelLocationY = y;
      info.touchFlags = 0; info.touchMask = 0x0007; info.pressure = 320;
      info.rcContactLeft = x - 2; info.rcContactTop = y - 2;
      info.rcContactRight = x + 2; info.rcContactBottom = y + 2;
      return info;
    }
    public static bool Down(int x, int y) {
      return InjectTouchInput(1, new POINTER_TOUCH_INFO[] { Make(x, y, INRANGE | INRANGE_PRIMARY | DOWN | PRIMARY) });
    }
    public static bool Move(int x, int y) {
      return InjectTouchInput(1, new POINTER_TOUCH_INFO[] { Make(x, y, INRANGE | INRANGE_PRIMARY | UPDATE | PRIMARY) });
    }
    public static bool Up(int x, int y) {
      return InjectTouchInput(1, new POINTER_TOUCH_INFO[] { Make(x, y, UP) });
    }
  }
}
'@
[QT.Touch].GetMethods() | ForEach-Object { 'method: ' + $_.Name }
$p = Get-Process hollow_court | Select-Object -First 1
[void][QT.Touch]::SetForegroundWindow($p.MainWindowHandle)
Start-Sleep -Milliseconds 400
if (-not [QT.Touch]::InitializeTouchInjection(1, 1)) { Write-Output 'touch injection refused'; exit 1 }
[void][QT.Touch]::Down($X, $Y1)
Start-Sleep -Milliseconds 60
if ($Tap) { [void][QT.Touch]::Up($X, $Y1); Write-Output 'tapped'; exit 0 }
for ($i = 1; $i -le $Steps; $i++) {
  $y = [int]($Y1 + ($Y2 - $Y1) * $i / $Steps)
  [void][QT.Touch]::Move($X, $y)
  Start-Sleep -Milliseconds 25
}
[void][QT.Touch]::Up($X, $Y2)
Write-Output 'dragged'
