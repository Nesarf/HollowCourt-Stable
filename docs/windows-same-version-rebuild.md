# Installing a same-version rebuild on Windows: what was measured

Written 2026-10-08, after a round where **the installer reported success twice and the executable on disk was still
the one from two days earlier.** The owner's report was that a fix did not appear; the fix had been built, installed
and registered, and **the machine was running the old binary the whole time.**

## The three numbers, and only one of them was moving

| | |
| --- | --- |
| pubspec `version: 1.0.0+48000` | the display version, and what a reader sees |
| `.wxs` `Version="1.0.48000"` | the **product version**, which Windows Installer compares |
| `ProductCode` | the product's **identity**, which decides whether an install replaces or is refused |

**The locale work of 2026-10-08 changed the code and none of the three.** The `.wxs` says bump `Version` and
`ProductCode` together *"even for a rebuild of the same round"*, and that rule is right; what it does not say is what
happens when you follow it and the version number still does not move.

## What was measured, in order

1. **`EXITCODE=1638`** -- *another version of this product is already installed* -- when reinstalling the same
   `Version` **and** the same `ProductCode`. Correct behaviour: same pair means repair.
2. **`EXITCODE=0`, and the registered `ProductCode` still the old one** -- because the `.msi` had not actually been
   rebuilt. **The build had failed and the failure was swallowed**: its output was piped through
   `Select-Object -First 5`, which closes the pipeline and took the build process with it, leaving `exit=1` and an old
   artifact. **The real error was under that**: `WIX0104`, an XML comment containing `--`, which WiX refuses.
3. **`EXITCODE=0` with the new `ProductCode` registered, and the `.exe` still two days old.** This is the one worth
   keeping: **the install succeeded, the product is registered under the new code, and the file was not replaced.**

## Why (3) happens, and it is the rule the `.wxs` already states

Windows Installer **only replaces a file whose version is higher**. This application's executable carries the
assembly version derived from the build, and a same-round rebuild does not raise it -- so the installer treats the file
as already correct and leaves it. **`ProductCode` decides whether you get a fresh install or a repair; it does not
decide whether the files are newer enough to overwrite.**

**So a same-version rebuild must be removed first**, by the old product's code, and then installed:

```
msiexec.exe /x {old-product-code} /qn /norestart
msiexec.exe /i "hollow-court-1.0.48000.msi" /qn /norestart
```

That is what the two codes are for: the old one removes, the new one installs. **Two entries in
"Apps & features" would otherwise accumulate for one product**, since Windows sees different codes as different
products.

## The check that would have caught all of it

**Compare the installed file against the build output, and compare *content*, not the timestamp.**

**`LastWriteTime` is not evidence here, and believing it cost a round.** After the round was installed,
`E:\Hollow Court Win\hollow_court.exe` still reported `10/06 21:40:10` -- and so did
`build\windows\x64\runner\Release\hollow_court.exe`, which the build had just spent 199 seconds producing and reported
as `Built`. **So the mtime is carried over from somewhere in the toolchain**, and it says nothing about whether the
file was rewritten. Reading it as "the old binary is still installed" was wrong.

**What actually settles it is behaviour the old build could not have.** `CellarLock` landed on 2026-10-08, so
launching the installed application and finding `<documents>\cellar.ndjson.lock` created *at that moment* proves the
running code includes it:

```powershell
Start-Process 'E:\Hollow Court Win\hollow_court.exe'
Get-ChildItem ([Environment]::GetFolderPath('MyDocuments')) -Filter 'cellar*'
#   cellar.ndjson.lock        0 bytes   10/08 22:22:05
#   cellar.ndjson.lock.owner  5 bytes   10/08 22:22:05
```

**A release check should compare hashes** -- the built exe against the installed one -- because that is the fact, and
both the mtime and "the installer said success" are claims about it rather than it.

## And the pipeline lesson, which cost a round by itself

**`... | Select-Object -First N` terminates the command it is reading.** Used on a build's output it silently kills
the build, and the truncation looks like normal operation. Redirect to a file and filter the file, or do not filter.
