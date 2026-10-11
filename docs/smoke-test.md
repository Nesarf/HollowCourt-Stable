# The persistence smoke test

`tool/smoke_persistence.sh`, and what it does and does not cover. Written 2026-10-08, answering a code review's **QA
gap**: *install, open, create a bottle, mutate, restart, read the persisted state.*

## Why the existing tests could not answer it

`event_log_test` and `overlay_persistence_test` already prove that reopening a log brings back what was written --
**inside one process, in a temporary directory.** Neither says anything about a real platform: whether the path the
application picks is writable, whether the file survives the process ending, whether a lock left behind blocks the next
start. **A restart cannot be faked inside a process**, so it is run in two.

## What it is

One test, `test/data/persistence_smoke_test.dart`, driven in two phases by the script:

```
SMOKE_PHASE=write   ->  opens the log, appends one stock.bottle.added, closes
SMOKE_PHASE=read    ->  a second process opens the same file and asserts the event is there
```

**The second process shares nothing with the first but the disk**, which is the whole point. It uses the
application's own `EventLog` -- so the cross-process lock, the serialised write path and the reader are all the real
ones -- and it skips itself unless `SMOKE_DIR` is set, so `flutter test` stays a test suite rather than something that
depends on a directory outside the repository.

## What has been measured, and on what

| Platform | Result |
| --- | --- |
| **Windows** | **passes** -- `1 events survived`, and the lock file and owner appear beside the log |
| **Linux (Nyarch, WSL)** | **passes** -- same, with a 4-byte owner file because a Linux pid is shorter |
| **Android** | **not covered by this test, and here is why** |

`flutter test` needs a Dart VM on the device; the Android half would need either an `integration_test` run through
`flutter drive` or a debug-signed build so `adb shell run-as` can read the application's own files.
**A release APK is not debuggable, and `run-as` refuses it** -- measured: *"package not debuggable"*. So the honest
statement is that **Android's write path is exercised by daily use and is not covered by this check**, which is a gap
rather than a pass.

**And the two platforms that do pass are not a formality**: the first run of the Windows half is what confirmed that
`CellarLock` writes `<log>.lock` and `<log>.lock.owner` on a real filesystem, which is the kind of thing a temporary
directory and a fake clock cannot show.

## How to run it

```bash
# Windows
bash tool/smoke_persistence.sh

# Linux, where the SDK is not the Windows one
export FLUTTER_BIN=/opt/flutter/bin/flutter
export SMOKE_ROOT=/mnt/e/DaShaoHuo/cache/tmp
bash tool/smoke_persistence.sh
```

**`FLUTTER_BIN` exists because the two platforms need different SDKs**, and on WSL the Windows copy under `/mnt/e` does
not work: `shared.sh` reaches for `cache/dart-sdk/bin/dart`, which is a Windows binary and absent on the Linux side --
its symptom was `Unable to 'pub upgrade' flutter tool`, retried nine times. **The Linux SDK is at `/opt/flutter`, and
that is what has to be named.**

## Looking at the Windows window without photographing somebody's desktop

Written 2026-10-11, after an attempt that got it wrong twice.

**`CopyFromScreen` is the wrong tool and it is not a small wrongness.** It copies what is *on the screen* in
the window's rectangle, so it captured a frame of whatever application happened to be on top -- on somebody
else's machine. `SetForegroundWindow` does not fix it: a background process is refused that call by Windows,
silently, and the capture succeeds anyway with the wrong contents in it.

**`PrintWindow` with `PW_RENDERFULLCONTENT` renders the window's own surface** and cannot reach the desktop.
Two details make it faithful rather than approximate:

* **`SetProcessDPIAware()` before measuring anything.** This machine runs at **125%**, and without it
  `GetWindowRect` answered `1280x720` for a window whose client area is **`1582x853` physical**. Rendering the
  larger window into the smaller bitmap produced two frames in which the bottom of the interface was simply
  absent -- including the whole navigation bar, which then looked like a missing bar rather than a bad
  measurement. **A capture that is one and a quarter times too small is indistinguishable from an interface
  with pieces missing.**
* **`GetClientRect`, not `GetWindowRect`**, for the bitmap size, so the frame is the interface rather than the
  interface plus its title bar.

```powershell
# The two lines that matter, in order.
[void][C]::SetProcessDPIAware()
[void][C]::GetClientRect($p.MainWindowHandle, [ref]$r)   # then size the bitmap from $r
```

**Let the window settle before capturing.** A resize followed by a capture a second later returned a frame
from before the resize had been drawn, stretched to the new size -- which reads as a layout defect and is a
race.

And the rule that made the third attempt worth doing: **when the tool cannot be trusted, say the result is
unresolved rather than reading it as a finding.** The first two frames were recorded as *the bar did not
appear, and the instrument cannot tell "missing" from "not rendered"* -- which is what it was -- instead of as
a bug in the bar, and the difference is that one of those sentences sends somebody to fix the wrong file.
