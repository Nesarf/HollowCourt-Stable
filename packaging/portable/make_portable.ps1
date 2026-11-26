# Builds one portable archive from whatever platform outputs exist for a version.
#
#     pwsh -File packaging/portable/make_portable.ps1
#     pwsh -File packaging/portable/make_portable.ps1 -Version 1.0.0.51541
#
# **Why an archive of three native builds rather than one universal file.** Flutter
# compiles a desktop application to native code: a PE for Windows, an ELF for Linux, a
# Mach-O bundle for macOS. There is no single executable that runs on all three, so
# "portable" can only mean one archive a reader unpacks once and runs from, picking the
# folder that matches their machine. This script collects those folders and writes the
# README that says which is which.
#
# **What each platform contributes, and why that shape.**
#
#   windows/  the whole `build\windows\x64\runner\Release` directory, not the MSI.
#             The MSI is an installer that writes to a fixed path and registers itself;
#             a reader who wants portable wants `hollow_court.exe` beside its `data\`
#             and three DLLs, with nothing installed and nothing to uninstall.
#
#   linux/    the `build/linux/x64/release/bundle` directory. There is no single-file format
#             any more: the AppImage was dropped on 2026-11-27, so the folder is the
#             deliverable. It needs its executable bit restored after unpacking, because not
#             every archive format carries permissions -- the README says so at the step where
#             a reader would otherwise meet a file that will not start.
#
#   macos/    `build/macos/Build/Products/Release/*.app`, when this machine has one.
#             A macOS build requires macOS: Flutter's macos target drives xcodebuild,
#             and no cross-compilation path exists. So on this machine the folder is
#             simply absent, and the archive says so in its README rather than
#             pretending the set is complete.
#
# **Why the version comes from pubspec and not from a parameter by default.** The four
# files of one round have to agree on a name or the archive becomes the one place where
# nobody can tell which build it holds; pubspec is what every artefact is already named
# from, so it is the only input that cannot drift.
[CmdletBinding()]
param(
    [string]$Version,
    [string]$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [string]$Bundle = ''
)

$ErrorActionPreference = 'Stop'

if (-not $Bundle) { $Bundle = Join-Path $Repo 'dist' }

if (-not $Version) {
    $pubspec = Join-Path $Repo 'pubspec.yaml'
    $line = (Select-String -LiteralPath $pubspec -Pattern '^version:' | Select-Object -First 1).Line
    $pair = ($line -replace '^version:\s*', '').Trim()          # 1.0.0+51541
    $Version = $pair -replace '\+', '.'                        # 1.0.0.51541
}

$stage = Join-Path ([System.IO.Path]::GetTempPath()) ("hollow-portable-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $stage | Out-Null

$collected = @()
$missing = @()

# windows/ -- the release directory as the compiler left it.
$winRelease = Join-Path $Repo 'build\windows\x64\runner\Release'
if (Test-Path -LiteralPath (Join-Path $winRelease 'hollow_court.exe')) {
    $dst = Join-Path $stage 'windows'
    New-Item -ItemType Directory -Force -Path $dst | Out-Null
    Copy-Item -Path (Join-Path $winRelease '*') -Destination $dst -Recurse -Force
    $n = (Get-ChildItem -LiteralPath $dst -Recurse -File | Measure-Object).Count
    $collected += "windows  ({0} files)" -f $n
} else {
    $missing += 'windows (no build\windows\x64\runner\Release on this machine)'
}

# linux/ -- the release bundle Flutter's Linux build produced, with the launcher inside it.
$linBundle = Join-Path $Repo 'build\linux\x64\release\bundle'
if (Test-Path -LiteralPath (Join-Path $linBundle 'hollow_court')) {
    $dst = Join-Path $stage 'linux'
    New-Item -ItemType Directory -Force -Path $dst | Out-Null
    Copy-Item -Path (Join-Path $linBundle '*') -Destination $dst -Recurse -Force
    $n = (Get-ChildItem -LiteralPath $dst -Recurse -File | Measure-Object).Count
    $collected += "linux    (bundle directory, {0} files)" -f $n
} else {
    $missing += 'linux (no build\linux\x64\release\bundle on this machine)'
}

# macos/ -- absent unless this machine is a Mac, which is a fact rather than a failure.
$macApp = Get-ChildItem -Path (Join-Path $Repo 'build\macos\Build\Products\Release') -Filter '*.app' -Directory -ErrorAction SilentlyContinue |
    Select-Object -First 1
if ($macApp) {
    $dst = Join-Path $stage 'macos'
    New-Item -ItemType Directory -Force -Path $dst | Out-Null
    Copy-Item -LiteralPath $macApp.FullName -Destination $dst -Recurse -Force
    $collected += "macos    ({0})" -f $macApp.Name
} else {
    $missing += 'macos (a macOS build needs macOS; nothing was built here)'
}

if ($collected.Count -eq 0) {
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    throw "nothing to collect for $Version -- build a platform first"
}

# The README is part of the deliverable: a folder holding three programs and no sentence
# about which one to run is a folder a reader has to guess at.
$readme = @(
    "Hollow Court $Version -- portable"
    ''
    'Each folder is a complete copy of the application for one operating system.'
    'Unpack the whole archive, then open the folder that matches your machine.'
    ''
    '  windows\hollow_court.exe      double-click. Nothing is installed, nothing is'
    '                                written outside this folder except your own'
    '                                cellar data in your documents folder.'
    ''
    '  linux\hollow_court           run it from inside this folder, with lib\ and data\'
    '                                beside it. If your archive tool dropped the executable'
    '                                bit, `chmod +x hollow_court` once and it starts.'
    ''
    '  macos\Hollow Court.app        build it on a Mac first -- see the note below.'
    ''
    'Your bottles, recipes and settings are not part of this archive. They live in your'
    'own documents folder, which is why an update can replace these files without'
    'touching them.'
    ''
    'This archive was assembled from:'
    ($collected | ForEach-Object { "  $_" })
    ''
    'Not included:'
    ($missing | ForEach-Object { "  $_" })
    ''
    'The single-file installers (msi, setup.exe) are published beside this archive for'
    'anyone who would rather install than unpack.'
) -join "`r`n"
Set-Content -LiteralPath (Join-Path $stage 'README.txt') -Value $readme -Encoding utf8

$out = Join-Path $Bundle "hollow-court-$Version-portable.zip"
if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Force }
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $out -CompressionLevel Optimal
Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue

# **The receipt, because a file whose provenance is only in a person's head is a file the
# manifest has to call `unrecorded`.** The source commit is read from the MSI's receipt
# rather than recomputed from HEAD: HEAD moves on every doc commit, while the MSI beside this
# archive was built from one specific tree, and the archive holds that same build. Recomputing
# would make the receipt disagree with the bytes, which is the failure `write_receipt.sh`'s
# own header describes.
$siblingReceipt = Join-Path $Bundle ("hollow-court-{0}-arm64-v8a.apk.commit" -f $Version)
$srcCommit = ''
if (Test-Path -LiteralPath $siblingReceipt) {
    $line = (Select-String -LiteralPath $siblingReceipt -Pattern '^src-commit' | Select-Object -First 1).Line
    if ($line) { $srcCommit = ($line -replace '^src-commit\s*:\s*', '').Trim() }
}

# git-bash, not whatever `bash` resolves to: on Windows `bash` is usually WSL's entry point,
# and WSL cannot read `/d/...` paths from this side of the boundary.
$bashPath = 'C:\Program Files\Git\bin\bash.exe'
if (-not (Test-Path -LiteralPath $bashPath)) {
    $c = Get-Command bash -ErrorAction SilentlyContinue
    if ($c -and $c.Source -notmatch 'system32') { $bashPath = $c.Source }
}
if ((Test-Path -LiteralPath $bashPath) -and $srcCommit) {
    $note = "assembled from windows/ (build\windows\x64\runner\Release) and the Linux bundle; source commit taken from the MSI receipt beside it"
    $env:SRC_COMMIT = $srcCommit
    $env:SRC_SUBJECT = (git -C $Repo log -1 --format=%s $srcCommit 2>$null)
    $env:HEAD_REV   = (git -C $Repo rev-parse HEAD 2>$null)
    $env:TREE_DIRTY = 'no'
    $env:SRC_DIRTY  = 'no'
    $repoPosix = $Repo -replace '\\', '/'
    $outPosix  = $out  -replace '\\', '/'
    & $bashPath "$repoPosix/packaging/write_receipt.sh" $outPosix $note 'lib' 'windows' 'linux' 'pubspec.yaml' 'assets' 2>&1 | Out-Null
    $wrote = Test-Path -LiteralPath "$out.commit"
    Remove-Item Env:SRC_COMMIT, Env:SRC_SUBJECT, Env:HEAD_REV, Env:TREE_DIRTY, Env:SRC_DIRTY -ErrorAction SilentlyContinue
    if ($wrote) { Write-Output "   receipt  $([System.IO.Path]::GetFileName("$out.commit")) (src-commit $($srcCommit.Substring(0,7)))" }
    else        { Write-Output '   receipt  NOT written -- write_receipt.sh did not produce one' }
} else {
    Write-Output '   receipt  skipped: no bash, or no sibling MSI receipt to take the commit from'
}

$size = (Get-Item -LiteralPath $out).Length / 1MB
Write-Output "== portable archive =="
$collected | ForEach-Object { Write-Output "   collected $_" }
$missing   | ForEach-Object { Write-Output "   omitted   $_" }
Write-Output ("== done: {0} ({1:N1} MB) ==" -f $out, $size)
