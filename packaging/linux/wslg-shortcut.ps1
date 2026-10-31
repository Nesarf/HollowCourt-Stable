# Keep the Windows shortcut that WSLg generates pointing at Hollow Court's own icon.
#
# WHY THIS IS A SEPARATE STEP, AND WHY IT IS WINDOWS. WSLg scans /usr/share/applications on start and
# writes one .lnk per entry into the user's Start Menu. Each .lnk names an icon under
# %TEMP%\WSLDVCPlugin\<distro>\<name>.ico, a file WSLg regenerates on every start -- and regenerates
# from artwork that no longer matches the install. Measured on 2026-10-31: every icon directory in the
# distribution held the current picture, and WSLg still rebuilt a 16 KB file carrying the old mark.
# Neither Windows' FileIO tracing nor inotify inside the distribution could see where it read the old
# one: 9p reads are issued by the Windows side, so they appear in neither place.
#
# The shortcut's own IconLocation wins over that file. So this sets it, and then marks the .lnk
# read-only, because otherwise the next WSL start writes it again.
#
#     pwsh -File packaging/linux/wslg-shortcut.ps1 -Distro Nyarch
#
# Exit codes: 0 done or nothing to do, 1 the shortcut or the icon source was missing.

param(
  [string]$Distro = 'Nyarch',
  [string]$IconSource = '',
  [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
function Say($m) { if (-not $Quiet) { Write-Host $m } }

$startMenu = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\$Distro"
if (-not (Test-Path -LiteralPath $startMenu)) {
  Write-Host "no Start Menu folder for $Distro at $startMenu -- has it been started once under WSLg?" -ErrorAction Continue
  exit 1
}

# The icon to point at. A shortcut may name an .ico directly, and that is what Windows already does
# for its own applications, so one file is enough.
if (-not $IconSource) {
  $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
  $candidate = Join-Path $repo 'windows\runner\resources\app_icon.ico'
  if (Test-Path -LiteralPath $candidate) { $IconSource = $candidate }
}
if (-not $IconSource -or -not (Test-Path -LiteralPath $IconSource)) {
  Write-Host "no .ico to install: pass -IconSource, or build once so windows\runner\resources\app_icon.ico exists" -ErrorAction Continue
  exit 1
}

# A stable copy, because the repository is a build tree and the shortcut outlives it.
$iconDir = Join-Path $env:LOCALAPPDATA 'HollowCourt'
New-Item -ItemType Directory -Force -Path $iconDir | Out-Null
$icon = Join-Path $iconDir 'app_icon.ico'
Copy-Item -LiteralPath $IconSource -Destination $icon -Force
Say "icon: $icon"

$wsh = New-Object -ComObject WScript.Shell
$entries = Get-ChildItem -LiteralPath $startMenu -Filter '*.lnk' | Where-Object {
  try { $wsh.CreateShortcut($_.FullName).Arguments -match 'hollow-court' } catch { $false }
}
if (-not $entries) {
  Write-Host "no shortcut under $startMenu launches hollow-court" -ErrorAction Continue
  exit 1
}

$changed = 0
foreach ($entry in $entries) {
  # Read-only first: writing to a read-only .lnk throws, and the whole point is to write into one.
  if ($entry.IsReadOnly) { Set-ItemProperty -LiteralPath $entry.FullName -Name IsReadOnly -Value $false }
  $sc = $wsh.CreateShortcut($entry.FullName)
  $before = $sc.IconLocation
  $sc.IconLocation = "$icon,0"
  $sc.Save()
  Set-ItemProperty -LiteralPath $entry.FullName -Name IsReadOnly -Value $true
  Say ("{0}`n  {1}`n  -> {2}  (read-only)" -f $entry.Name, $before, $sc.IconLocation)
  $changed++
}

Say "done: $changed shortcut(s)"
exit 0
