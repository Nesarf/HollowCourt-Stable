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
