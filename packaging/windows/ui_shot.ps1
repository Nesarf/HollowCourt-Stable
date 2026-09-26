# Photograph a page of the running application, by driving its window.
#
#     powershell -NoProfile -File packaging/windows/ui_shot.ps1 `
#         -Title "Hollow Court" -Clicks "1152,680" -Scroll 18 -Out E:\...\about.png
#
# **Why input synthesis rather than a test that renders the widget.** The About section's version and
# commit come from compile-time defines, so a widget test can only show the test's own default -- it
# proves the wiring and cannot prove the value. The value is a fact about the *built artifact*, and the
# only place it is visible is the installed program's own screen. `test/render_themes_test.dart` renders
# the shell offscreen for the same reason in reverse: it can draw anything and cannot show a release.
#
# **The window is photographed with PrintWindow, not by capturing the desktop**, because a process
# started from a background shell cannot raise its window and a desktop grab catches whatever is on top.
# That mistake is recorded in packaging/README.md and cost this project a round.
param(
  [string]$Title = 'Hollow Court',
  [string]$Clicks = '',
  [int]$Scroll = 0,
  [Parameter(Mandatory = $true)][string]$Out
)
Add-Type -AssemblyName System.Drawing

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Ui {
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint x, uint y, int data, IntPtr extra);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  public const uint LEFTDOWN = 0x0002, LEFTUP = 0x0004, WHEEL = 0x0800;
  public const uint WM_LBUTTONDOWN = 0x0201, WM_LBUTTONUP = 0x0202, WM_MOUSEWHEEL = 0x020A;
  public static IntPtr Point(int x, int y) { return (IntPtr)((y << 16) | (x & 0xFFFF)); }
}
"@

$proc = Get-Process | Where-Object { $_.MainWindowTitle -eq $Title } | Select-Object -First 1
if (-not $proc) { Write-Output "no window titled '$Title' is open"; exit 1 }

$rect = New-Object Ui+RECT
[void][Ui]::GetWindowRect($proc.MainWindowHandle, [ref]$rect)
$w = $rect.R - $rect.L
$h = $rect.B - $rect.T
Write-Output "window '$Title' $w x $h at $($rect.L),$($rect.T)"

# **A BACKGROUND SHELL CANNOT RAISE A WINDOW, SO IT POSTS INSTEAD.** `SetForegroundWindow` from a process
# started by a background shell is refused by Windows, and the first version of this script proved it the
# hard way: the synthesized clicks went nowhere, the photograph came out byte-identical to the one before
# it, and the only reason that was visible is that the two files hashed the same. Posted messages do not
# need focus -- they go into the window's queue directly -- which is why this uses PostMessage with client
# coordinates rather than the cursor.
[void][Ui]::SetForegroundWindow($proc.MainWindowHandle)
Start-Sleep -Milliseconds 400

foreach ($click in ($Clicks -split ';' | Where-Object { $_ -ne '' })) {
  $parts = $click -split ','
  $point = [Ui]::Point([int]$parts[0], [int]$parts[1])
  [void][Ui]::PostMessage($proc.MainWindowHandle, [Ui]::WM_LBUTTONDOWN, [IntPtr]1, $point)
  Start-Sleep -Milliseconds 120
  [void][Ui]::PostMessage($proc.MainWindowHandle, [Ui]::WM_LBUTTONUP, [IntPtr]0, $point)
  Start-Sleep -Milliseconds 700
}

# Wheel notches of -120 scroll down, posted at the centre of the client area so the list under the cursor
# is the one that scrolls. One notch per step, because a list with a long extent swallows a burst.
$client = New-Object Ui+RECT
[void][Ui]::GetClientRect($proc.MainWindowHandle, [ref]$client)
$centre = [Ui]::Point([int]($client.R / 2), [int]($client.B / 2))
for ($i = 0; $i -lt $Scroll; $i++) {
  [void][Ui]::PostMessage($proc.MainWindowHandle, [Ui]::WM_MOUSEWHEEL, [IntPtr](-120 -shl 16), $centre)
  Start-Sleep -Milliseconds 90
}
Start-Sleep -Milliseconds 500

[void][Ui]::GetWindowRect($proc.MainWindowHandle, [ref]$rect)
$w = $rect.R - $rect.L
$h = $rect.B - $rect.T
$bitmap = New-Object System.Drawing.Bitmap $w, $h
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$dc = $graphics.GetHdc()
# PW_RENDERFULLCONTENT: without the flag a composited window photographs as an empty rectangle.
[void][Ui]::PrintWindow($proc.MainWindowHandle, $dc, 2)
$graphics.ReleaseHdc($dc)
$bitmap.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
Write-Output "wrote $Out ($w x $h)"
