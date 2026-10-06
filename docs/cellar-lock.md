# HC-004, the cross-process cellar lock: what was measured, and why it is not in yet

Written 2026-10-01, after an attempt that was reverted. **The code is not here; the findings are**, because the
expensive part of this task is not the lock, it is discovering how Dart's lock actually behaves and where the
failure surfaces. The next attempt should start from this page.

## What the review said, and it is right

`EventLog` serialises its own writes through `_writeTail`, which is correct **within one instance** and says nothing
about the file. A desktop reader can start the application twice -- two icons, a launcher and a shortcut, a
double-click that felt like it did nothing -- and two processes then hold one cellar with no knowledge of each
other.

**What follows is not a lost update but a corrupt file.** Every append is a line, and the reader *rewrites* the log
when it discards a torn tail: two writers mean one process appending while the other truncates and rewrites, and the
surviving file is neither version's. **An append-only log is worth having because it can be trusted line by line**,
so this is the one failure the design cannot absorb.

## What was measured

| Question | Answer, probed on this machine |
| --- | --- |
| Does `dart:io` offer a file lock? | **Yes** -- `RandomAccessFile.lock(FileLock.exclusive)`. No dependency needed. |
| Does it work on Windows here? | **Yes**, for both `exclusive` and `shared`. |
| **Is it per process or per handle?** | **Per handle.** A second handle in the *same* process is refused with `PathAccessException ... errno = 33`. |
| Where does an unreleased lock show up? | **In `tearDown`.** `Directory.deleteSync` fails with **`errno = 32`** naming a *directory*, not a lock. |

**The third row is the one that shaped the design.** Because the lock is per handle, refusing on contention refuses
the application's own `reload` and every test that opens a cellar twice -- **64 tests failed on the first attempt**,
and the same-process case is already handled correctly by `_writeTail`. So a real implementation must tell the two
apart, and the process id is how: write the pid beside the lock *before* attempting it, and a failed acquire reads it
back -- **our own pid means this process already holds the cellar** (legitimate), **anybody else's means another
process has it** (the case the lock exists for).

**The fourth row is where the debugging went.** Every message names a directory or a temporary path, and none of
them mention a lock, so the first three attempts looked for the fault in the wrong place. **A test that opens a
cellar must give its claim up, and `EventLog` has no `close()`** -- production holds the lock until the process
ends, which is the behaviour that survives a crash, but a test that then removes its temporary directory cannot,
because the lock file is still open.

## What a real attempt needs, in order

1. **`CellarLock`** -- acquire on a sibling `<log>.lock` (not the log itself: the store reopens and rewrites the
   log during recovery, so a lock on it would be dropped whenever that happens).
2. **Reentrancy by pid**, as above, or the application cannot reload its own cellar.
3. **`EventLog.close()`** that releases the claim, **and every test opening a log must call it**. Prefer a helper
   that opens and registers, so a test cannot forget -- `List.add` returns `void`, so it cannot be written inline.
4. **Take the lock before anything is read.** The reader rewrites the log when it discards a torn tail, so a second
   instance must be refused *before* it decides the file is damaged; a lock taken after the read would let both
   processes agree the tail is torn and both truncate.
5. **One exclusive lock, not shared-plus-write.** Reader and writer are the same object here: opening a log folds
   it, and a fold is followed by writes as soon as the reader touches anything. A shared mode would be a promise
   this layer cannot keep, and a lock meaning "read-only" while the process goes on to write is worse than none.
6. **`CellarInUse` as its own exception type**, because "the file cannot be read" and "somebody else is writing it
   right now" are different answers and a caller that must tell them apart can only do so if they arrive as
   different types.

## What was thrown away

A complete implementation of all six, because it left **64 tests failing** and the fix for those was still being
found. **Reverted rather than committed red**: a suite that fails is worse than a feature that is absent, and the
value of the attempt is this page rather than the diff.

**`docs/ingredient-gap.md`'s rule applies to this file too** -- nothing here is a claim about what the code does,
because the code is not there.
