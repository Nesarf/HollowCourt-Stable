# Builds one portable archive from whatever platform outputs exist for a version.
#
#     pwsh -File packaging/portable/make_portable.ps1
#     pwsh -File packaging/portable/make_portable.ps1 -Version 1.0.0.51541
#     pwsh -File packaging/portable/make_portable.ps1 -MacArtifact D:\path\hollow-court-macos.zip
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
#             deliverable. Its executable bit now survives the archive, because the writer
#             states the Unix mode on every entry instead of letting it default to nothing.
#
#   macos/    a `*.app` bundle, from this machine's own `build/macos/Build/Products/Release`
#             when there is one, otherwise from whatever `-MacArtifact` points at -- the ZIP
#             the macOS CI job uploads. A macOS build requires macOS (Flutter's macos target
#             drives xcodebuild) and no cross-compilation path exists, so on this machine the
#             bundle only ever arrives as that artifact.
#
# **Why nothing is copied into a staging directory any more.** It used to be: `Copy-Item
# -Recurse` into a temp folder, then `Compress-Archive`. Two failures came out of that pair.
# `Compress-Archive` writes `ExternalAttributes = 0` on every entry, so the Linux executable
# lost its bit and no entry could ever say "symlink"; and `Copy-Item` follows symbolic links,
# so a `.app` would have had its nine links flattened into nine text files before the archiver
# saw them -- a bundle whose tree reads correctly and which macOS refuses to load. The archive
# is now written by `make_portable_zip.py`, which is handed source paths and reads them itself.
#
# **Why the version comes from pubspec and not from a parameter by default.** The four
# files of one round have to agree on a name or the archive becomes the one place where
# nobody can tell which build it holds; pubspec is what every artefact is already named
# from, so it is the only input that cannot drift.
[CmdletBinding()]
param(
    [string]$Version,
    [string]$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [string]$Bundle = '',
    # A macOS bundle built elsewhere, as the ZIP the CI job uploads. Only consulted when this
    # machine has no macOS build of its own.
    [string]$MacArtifact = ''
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
$trees = @()      # PREFIX=DIRECTORY, for the entries the archive writer reads link by link
$zips  = @()      # PREFIX=ARCHIVE,   for entries copied out of another archive

# windows/ -- the release directory as the compiler left it.
$winRelease = Join-Path $Repo 'build\windows\x64\runner\Release'
if (Test-Path -LiteralPath (Join-Path $winRelease 'hollow_court.exe')) {
    $n = (Get-ChildItem -LiteralPath $winRelease -Recurse -File | Measure-Object).Count
    $collected += "windows  ({0} files)" -f $n
    $trees += "windows=$winRelease"
} else {
    $missing += 'windows (no build\windows\x64\runner\Release on this machine)'
}

# linux/ -- the release bundle Flutter's Linux build produced, with the launcher inside it.
$linBundle = Join-Path $Repo 'build\linux\x64\release\bundle'
if (Test-Path -LiteralPath (Join-Path $linBundle 'hollow_court')) {
    $n = (Get-ChildItem -LiteralPath $linBundle -Recurse -File | Measure-Object).Count
    $collected += "linux    (bundle directory, {0} files)" -f $n
    $trees += "linux=$linBundle"
} else {
    $missing += 'linux (no build\linux\x64\release\bundle on this machine)'
}

# macos/ -- a native bundle here, or the CI artifact, or nothing. The third case is a fact
# about the machine rather than a failure, and the README states it in those words.
$macBundle = ''
$macTree = ''
$macZip = ''
$macApp = Get-ChildItem -Path (Join-Path $Repo 'build\macos\Build\Products\Release') -Filter '*.app' -Directory -ErrorAction SilentlyContinue |
    Select-Object -First 1
if ($macApp) {
    $macBundle = $macApp.Name
    $macTree = $macApp.FullName
    $n = (Get-ChildItem -LiteralPath $macTree -Recurse -Force | Measure-Object).Count
    $collected += "macos    ({0}, built here, {1} entries)" -f $macBundle, $n
    $trees += "macos=$macTree"
} elseif ($MacArtifact) {
    if (-not (Test-Path -LiteralPath $MacArtifact)) {
        throw "-MacArtifact: '$MacArtifact' does not exist"
    }
    $macZip = (Resolve-Path -LiteralPath $MacArtifact).Path
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $z = [System.IO.Compression.ZipFile]::OpenRead($macZip)
    try {
        $firstApp = $z.Entries | Where-Object { $_.FullName -match '^[^/]+\.app(/|$)' } | Select-Object -First 1
        if (-not $firstApp) { throw "-MacArtifact: '$macZip' holds no *.app at its top level" }
        $macBundle = $firstApp.FullName.Split('/')[0]
        $n = $z.Entries.Count
        $link = @($z.Entries | Where-Object { ((($_.ExternalAttributes -shr 16) -band 0xF000) -eq 0xA000) }).Count
    } finally {
        $z.Dispose()
    }
    $collected += "macos    ({0}, from {1}, {2} entries, {3} symlink(s))" -f $macBundle, (Split-Path $macZip -Leaf), $n, $link
    $zips += "macos=$macZip"
} else {
    $missing += 'macos (a macOS build needs macOS; nothing was built here and no -MacArtifact was given)'
}

if ($collected.Count -eq 0) {
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    throw "nothing to collect for $Version -- build a platform first"
}

# The README is part of the deliverable: a folder holding three programs and no sentence
# about which one to run is a folder a reader has to guess at.
$macLines = if ($macTree -or $macZip) {
    @(
        ("  macos\{0}" -f $macBundle).PadRight(31) + 'double-click. This build is signed ad-hoc and not'
        '                                notarised, so the first launch is refused: right-click'
        '                                the app and choose Open, or run'
        '                                `xattr -dr com.apple.quarantine "<the app>"` once.'
    )
} else {
    @(
        ('  macos\').PadRight(31) + 'not in this archive. A macOS build needs macOS; build it'
        '                                there and it appears in this folder.'
    )
}

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
    '  linux\hollow_court           run it from inside this folder, with lib/ and data/'
    '                                beside it. The executable bit is recorded in this'
    '                                archive, so an unpacker that keeps Unix modes needs'
    '                                no chmod; one that drops them needs `chmod +x` once.'
    ''
    $macLines
    ''
    'Your bottles, recipes and settings are not part of this archive. They live in your'
    'own documents folder, which is why an update can replace these files without'
    'touching them.'
    ''
    'This archive was assembled from:'
    ($collected | ForEach-Object { "  $_" })
    ''
    # An empty list under a heading reads as an omission rather than as good news. When
    # nothing is missing -- which is now the normal case, because macOS arrives as an
    # artifact instead of waiting for a Mac -- the heading says so in words.
    'Not included:'
    $(if ($missing.Count) { $missing | ForEach-Object { "  $_" } }
      else { '  nothing -- all three platforms are in this archive' })
    ''
    'The single-file installers (msi, setup.exe) are published beside this archive for'
    'anyone who would rather install than unpack.'
) -join "`r`n"
Set-Content -LiteralPath (Join-Path $stage 'README.txt') -Value $readme -Encoding utf8

# The archive is written by a script rather than by Compress-Archive; see the header of
# make_portable_zip.py for the measurement that made that necessary.
$python = Get-Command python -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $python) { throw 'python is not on PATH -- packaging/portable/make_portable_zip.py needs it' }

$out = Join-Path $Bundle "hollow-court-$Version-portable.zip"
$zipArgs = @(
    (Join-Path $PSScriptRoot 'make_portable_zip.py'),
    '--out', $out,
    '--file', "README.txt=$(Join-Path $stage 'README.txt')",
    '--exec', 'linux/hollow_court'
)
foreach ($t in $trees) { $zipArgs += @('--tree', $t) }
foreach ($z in $zips)  { $zipArgs += @('--zip',  $z) }
& $python.Source @zipArgs
if ($LASTEXITCODE -ne 0) { throw "make_portable_zip.py failed with exit code $LASTEXITCODE" }
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
    $note = 'assembled from windows/ (build\x64\runner\Release), the Linux bundle'
    if ($macZip) { $note += ', and the macOS bundle from ' + (Split-Path $macZip -Leaf) }
    elseif ($macTree) { $note += ', and the macOS bundle built here' }
    $note += '; source commit taken from the MSI receipt beside it'
    $env:SRC_COMMIT = $srcCommit
    $env:SRC_SUBJECT = (git -C $Repo log -1 --format=%s $srcCommit 2>$null)
    $env:HEAD_REV   = (git -C $Repo rev-parse HEAD 2>$null)
    $env:TREE_DIRTY = 'no'
    $env:SRC_DIRTY  = 'no'
    $repoPosix = $Repo -replace '\\', '/'
    $outPosix  = $out  -replace '\\', '/'
    & $bashPath "$repoPosix/packaging/write_receipt.sh" $outPosix $note 'lib' 'windows' 'linux' 'macos' 'pubspec.yaml' 'assets' 2>&1 | Out-Null
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
