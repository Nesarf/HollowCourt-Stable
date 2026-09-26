# Drive the running application's window: click at a logical position, scroll, and photograph it.
#
#     powershell -NoProfile -File packaging/windows/drive.ps1 -Tab recipes
#     powershell -NoProfile -File packaging/windows/drive.ps1 -Click "506,505" -Wheel -6 -Out E:\...\x.png
#
# **Why this exists.** Verifying a release on Windows means looking at the installed program, and a
# screenshot alone cannot open a tab. The photographs this project keeps are of pages somebody had already
# navigated to by hand, which is a step that cannot be repeated by a script or written into a receipt.
#
# **Two coordinate mistakes were made before this worked, and both looked like "input does not work".**
#
#   1. **Window coordinates where client coordinates were needed.** The title bar is 32 physical pixels, so
#      a click computed from `GetWindowRect` lands 32 px low -- and it was sent with `SetCursorPos` +
#      `mouse_event`, which go to whatever is under the cursor, so it silently hit the desktop.
#   2. **Physical where logical was needed.** Flutter lays out in logical pixels and the window here is at
#      125 % (`dpi 120`), so a client 682 physical pixels tall is 546 logical. Passing a logical 640
#      straight to `ClientToScreen` pointed below the window entirely. Logical coordinates are multiplied by
#      `dpi/96` here, and **the printed client size is physical while the coordinates taken are logical** --
#      which is the sort of mismatch worth saying out loud in the output rather than in a comment.
#
# Both failures produced a byte-identical screenshot, which is exactly why the hash is printed: "nothing
# changed" is a measurement, and an impression of a grey window is not.
# **ONE INSTANCE, AND THAT IS NOT A PREFERENCE.** `Get-Process ... | Select -First 1` picks whichever
# process Windows lists first, so with two windows of this application open a script clicks one and
# photographs the other. That is what a whole round of "the clicks do nothing" actually was: the
# screenshots were byte-identical because they were of a window nobody was clicking, and the window
# size changing mid-run was the other instance. Kill every instance before driving one, or pass the
# process id explicitly.
param(
  [string]$Title = 'Hollow Court',
  [int]$ProcessId = 0,
  [string]$Click = '',
  [int]$Wheel = 0,
  [string]$Out = '',
  # **The window's client size and position in LOGICAL pixels**, e.g. `-Size 1000x1400 -Pos 0,-800`.
  #
  # Why this exists, after the wheel turned out not to be enough: the sync section is at the bottom of a long
  # page, and a click can only land where the *screen* is. Making the window taller than the screen and pushing
  # its top above it puts the section on the screen without scrolling anything -- and `PrintWindow` still
  # photographs the whole window, so the same run produces a picture of everything below the fold.
  [string]$Size = '',
  [string]$Pos = '',
  [switch]$Quiet
)
Add-Type -AssemblyName System.Drawing

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Drv {
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int index);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr pid);
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, int d, IntPtr e);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  public const uint LEFTDOWN = 0x0002, LEFTUP = 0x0004, WHEEL = 0x0800, MOVEABS = 0x8001;
}
"@

function Get-Handle {
  $proc = if ($ProcessId -ne 0) {
    Get-Process -Id $ProcessId
  } else {
    Get-Process | Where-Object { $_.MainWindowTitle -eq $Title } | Select-Object -First 1
  }
  if (-not $proc) { Write-Output "no window titled '$Title' is open"; exit 1 }
  return $proc.MainWindowHandle
}

function Get-Scale([IntPtr]$handle) { return ([Drv]::GetDpiForWindow($handle)) / 96.0 }

# Logical client point -> screen point, which is the only conversion that has to be right.
function To-Screen([IntPtr]$handle, [int]$x, [int]$y) {
  $scale = Get-Scale $handle
  $p = New-Object Drv+POINT
  $p.X = [int]($x * $scale); $p.Y = [int]($y * $scale)
  [void][Drv]::ClientToScreen($handle, [ref]$p)
  return $p
}

function Show-Hash([string]$path) {
  if (-not (Test-Path $path)) { return '(none)' }
  $sha = [System.Security.Cryptography.SHA256]::Create()
  $bytes = $sha.ComputeHash([System.IO.File]::ReadAllBytes($path))
  return ([System.BitConverter]::ToString($bytes) -replace '-', '').Substring(0, 16)
}

function Save-Shot([IntPtr]$handle, [string]$path) {
  $rect = New-Object Drv+RECT
  [void][Drv]::GetWindowRect($handle, [ref]$rect)
  $w = $rect.R - $rect.L; $h = $rect.B - $rect.T
  $bitmap = New-Object System.Drawing.Bitmap $w, $h
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  $dc = $graphics.GetHdc()
  # PW_RENDERFULLCONTENT: without the flag a composited window photographs as an empty rectangle.
  [void][Drv]::PrintWindow($handle, $dc, 2)
  $graphics.ReleaseHdc($dc)
  $bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $graphics.Dispose(); $bitmap.Dispose()
  return $w, $h
}

$handle = Get-Handle
$client = New-Object Drv+RECT
[void][Drv]::GetClientRect($handle, [ref]$client)
$scale = Get-Scale $handle

# **RESIZED FIRST, SO THE CLIENT RECT BELOW IS THE ONE THE CLICKS ARE COMPUTED FROM.** A resize after the
# coordinates were worked out would land every click at the old window's idea of a position, which is the
# same class of mistake the header already records twice. The frame is measured rather than assumed: Windows
# gives the outer rectangle and the client rectangle, and the difference is the border and title bar at this
# window's DPI.
if ($Size -ne '') {
  $outer = New-Object Drv+RECT
  [void][Drv]::GetWindowRect($handle, [ref]$outer)
  $frameW = ($outer.R - $outer.L) - $client.R
  $frameH = ($outer.B - $outer.T) - $client.B
  $parts = $Size -split 'x'
  $wantW = [int]([int]$parts[0] * $scale) + $frameW
  $wantH = [int]([int]$parts[1] * $scale) + $frameH
  $x = $outer.L
  $y = $outer.T
  if ($Pos -ne '') {
    $at = $Pos -split ','
    $x = [int]$at[0]
    $y = [int]$at[1]
  }
  # SWP_NOZORDER (4) is deliberately absent: the caller may want the window topmost for the clicks.
  [void][Drv]::SetWindowPos($handle, [IntPtr]0, $x, $y, $wantW, $wantH, 0x14)
  Start-Sleep -Milliseconds 600
  [void][Drv]::GetClientRect($handle, [ref]$client)
  if (-not $Quiet) {
    Write-Output ("resized to client {0} x {1} physical at ({2},{3})" -f $client.R, $client.B, $x, $y)
  }
}
if (-not $Quiet) {
  Write-Output ("client {0} x {1} physical = {2} x {3} logical (dpi {4})" -f `
      $client.R, $client.B, [int]($client.R / $scale), [int]($client.B / $scale), [int]($scale * 96))
}

# **TAKING THE FOREGROUND RATHER THAN ASKING FOR IT.** `SetForegroundWindow` from a process started by a
# background shell is refused by Windows, and the refusal is silent: three clicks at a button produced
# byte-identical screenshots, which is the only reason it was noticed. The way through is the documented
# one -- attach this thread's input to the thread that owns the foreground window, take the foreground,
# then detach -- because a thread that shares input with the current foreground window is allowed to.
#
# This is why the script no longer needs somebody to click the window first, which is what it needed
# between the two halves of test ①.
$foreground = [Drv]::GetForegroundWindow()
$thisThread = [Drv]::GetCurrentThreadId()
$target = [Drv]::GetWindowThreadProcessId($handle, [IntPtr]::Zero)
$foregroundThread = [Drv]::GetWindowThreadProcessId($foreground, [IntPtr]::Zero)
$attached = $false
if ($foregroundThread -ne $thisThread) {
  $attached = [Drv]::AttachThreadInput($thisThread, $foregroundThread, $true)
}
[void][Drv]::ShowWindow($handle, 9)        # SW_RESTORE, in case it is minimised
[void][Drv]::BringWindowToTop($handle)
[void][Drv]::SetForegroundWindow($handle)
if ($attached) { [void][Drv]::AttachThreadInput($thisThread, $foregroundThread, $false) }
Start-Sleep -Milliseconds 400
if (-not $Quiet) {
  Write-Output ("foreground now: {0}" -f $(if ([Drv]::GetForegroundWindow() -eq $handle) { 'the application' } else { 'still something else' }))
}

# **AND IT HAS TO BE ON TOP, NOT MERELY ACTIVE.** Taking the foreground was not enough: the clicks
# still changed nothing while the wheel kept working, and the wheel goes to the window under the
# cursor while a click goes to whatever is *there* -- this session's terminal was over the button.
# HWND_TOPMOST for the duration of the clicks is the difference between "the application is active"
# and "the application is what the cursor is pointing at".
$topmost = [IntPtr](-1)
$notTopmost = [IntPtr](-2)
[void][Drv]::SetWindowPos($handle, $topmost, 0, 0, 0, 0, 3)
Start-Sleep -Milliseconds 200

if ($Click -ne '') {
  foreach ($one in ($Click -split ';' | Where-Object { $_ -ne '' })) {
    $parts = $one -split ','
    $p = To-Screen $handle ([int]$parts[0]) ([int]$parts[1])
    # **Absolute through the input queue, not the cursor.** `SetCursorPos` + relative button messages
    # reached the window for the wheel and never for a click. This asks the input system to move the
    # pointer to a normalized screen position and then press, which is the same path a hand takes.
    # **It did not help either**: the capture was byte-identical again, so the difference between a wheel
    # that arrives and a click that does not is not the coordinate system. Recorded so the next attempt
    # starts from the state of the evidence rather than from the idea.
    $screenW = [Drv]::GetSystemMetrics(0)
    $screenH = [Drv]::GetSystemMetrics(1)
    $nx = [int](($p.X * 65535) / ($screenW - 1))
    $ny = [int](($p.Y * 65535) / ($screenH - 1))
    [Drv]::mouse_event([Drv]::MOVEABS, $nx, $ny, 0, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 150
    [Drv]::mouse_event([Drv]::LEFTDOWN, 0, 0, 0, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 120
    [Drv]::mouse_event([Drv]::LEFTUP, 0, 0, 0, [IntPtr]::Zero)
    if (-not $Quiet) { Write-Output ("clicked logical ({0},{1}) -> screen ({2},{3})" -f $parts[0], $parts[1], $p.X, $p.Y) }
    Start-Sleep -Milliseconds 700
  }
}

# The wheel goes to the window under the cursor, so the cursor is parked in the middle of the client area
# first. One notch per step: a list with a long extent swallows a burst.
if ($Wheel -ne 0) {
  $null = $null
  $centre = To-Screen $handle ([int]($client.R / $scale / 2)) ([int]($client.B / $scale / 2))
  [void][Drv]::SetCursorPos($centre.X, $centre.Y)
  Start-Sleep -Milliseconds 200
  $notches = [math]::Abs($Wheel)
  $delta = if ($Wheel -lt 0) { -120 } else { 120 }
  # **The wheel is sent WITH the absolute move, in one call.** A bare `WHEEL` event goes wherever Windows
  # thinks the wheel belongs, and on this host that is nowhere: fifteen notches produced a byte-identical
  # screenshot twice. Clicks work here only in the `MOVEABS` form, so the wheel is given the same treatment --
  # `MOVEABS -bor WHEEL` names the position and the scroll together.
  $screenW = [Drv]::GetSystemMetrics(0)
  $screenH = [Drv]::GetSystemMetrics(1)
  $nx = [int](($centre.X * 65535) / ($screenW - 1))
  $ny = [int](($centre.Y * 65535) / ($screenH - 1))
  for ($i = 0; $i -lt $notches; $i++) {
    [Drv]::mouse_event(([Drv]::MOVEABS -bor [Drv]::WHEEL), $nx, $ny, $delta, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 110
  }
  Start-Sleep -Milliseconds 400
}

[void][Drv]::SetWindowPos($handle, $notTopmost, 0, 0, 0, 0, 3)

if ($Out -ne '') {
  $size = Save-Shot $handle $Out
  Write-Output ("wrote {0} ({1} x {2}) sha {3}" -f $Out, $size[0], $size[1], (Show-Hash $Out))
}
