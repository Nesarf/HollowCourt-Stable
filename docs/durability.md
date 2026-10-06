# Durability: when an event is actually saved

Written 2026-10-01, answering HC-003 from a code review. **The finding is not that the code lies -- it is that the
project never said what "saved" means**, and a log that is simultaneously storage, a sync format and an audit record
needs to say.

## The four things that "flushed" can mean, and which one this is

The review put the ladder plainly:

```
Dart stream flush  !=  OS flush  !=  filesystem durable  !=  SSD power-loss persistence
```

**The write path is the first rung.** `EventStore.append` opens the file with `FileMode.append`, writes each line
through an `IOSink`, and calls `sink.flush()` before closing. That flush pushes the bytes out of Dart's buffers and
into the operating system's write cache. **It does not ask the operating system to write them to the platter**, and
Dart does not offer a portable way to ask -- there is no `fsync` in `dart:io`.

**So the honest statement is this**: after a successful append, an event has been handed to the operating system
and **will survive the application crashing**. It will **not** necessarily survive the *machine* losing power, where
the last few appended lines can be in the OS cache and nowhere else.

## Why that is acceptable here rather than a defect to close

**Because the design already assumes it, and the handling is already written.** `EventStore._startOfTornTail` exists
for exactly this: a line that was being written when the power went is a *torn tail*, and the next append truncates
back to the start of that line so the fragment cannot fuse with the next event and turn a lost event into a
corrupt one.

**A crash can therefore cost the last event or two. It cannot cost the file.** That is a bound the rest of the design
is built on -- "the ledger tolerates a repeated reading", the fold taking whatever events exist -- and it is why the
torn-tail reader was written carefully rather than treated as an edge case.

**What would change the answer**: a sync that must be certain both devices kept what was sent. `EventLog.merge`
writes a peer's events and then reports the merge; if the machine lost power immediately afterwards, the peer would
believe this device holds events it does not, and would not send them again -- because the digest would have moved.
**That is the one place where losing the tail is not merely tolerable but silently wrong**, and it is recorded here
rather than fixed, because fixing it means a durability primitive Dart does not expose portably.

## What was deliberately not built

**A `durableCommit()` that pretends.** The review suggested splitting `commit()` from `durableCommit()`; there is
nothing to put in the second one, because the only implementation available is "call flush and hope", which is what
the first one already does. **A method named `durableCommit` that is not durable is worse than no method**, and this
project has already been caught twice this session by exactly that shape -- a field nothing read, and a test that
could not fail.

**Writing a platform channel to reach `FlushFileBuffers` and `fsync`** is possible and was not done. It would be a
real capability, and it belongs with the work it protects rather than before it: the case that needs it is the merge
acknowledgement above, which is a protocol change and not a file-system one.

## The contract, stated in one place

| After this | The event has | Survives |
| --- | --- | --- |
| `sink.writeln` | left Dart | nothing, yet |
| `sink.flush()` returns | reached the OS | the **application** dying |
| (nothing available) | reached the disk | the **machine** losing power |

**What a reader of `EventLog.record` may rely on**: once `record` returns, the event is in the log this process will
read back, and in the file a restart will read -- **unless the machine lost power in between, in which case at most
the last few events are gone and the file is still valid.**

**What a caller may not rely on**: that a peer which has been told about an event will find it after a power cut.
The merge path above is where that matters, and it is the open item.

---

## Appendix: the status-bar inset, and a method that worked

Unrelated to durability, recorded here because the *method* is the same and the failure is one this project has now
made twice: **guessing at a framework's behaviour instead of reading it.**

Three bottom sheets had their title overlapping the status bar. Two attempts changed nothing -- a manual
`MediaQuery.paddingOf(context).top` added to the padding, and wrapping the content in `SafeArea`. Both were reading a
value that had deliberately been emptied, and neither attempt explained why the other had failed, so the second felt
like trying something else rather than learning anything.

**The answer came from the SDK source**, `packages/flutter/lib/src/material/bottom_sheet.dart`:

    Widget bottomSheet = useSafeArea
        ? SafeArea(...)
        : MediaQuery.removePadding(context: context, removeTop: true, child: content);

**`useSafeArea` defaults to false and the default branch removes the top padding**, so the zero a probe measured inside
the sheet was by design. One line per sheet on `showModalBottomSheet` fixed all three, and a screenshot from the handset
confirmed it.

**The lesson is the cheap one**: two failed attempts were cheap, and the third was cheap once it began with reading
rather than with trying. **A probe that prints the value being relied on is not slower than a guess; it is the thing
that stops the guesses.** The same argument this project makes about measuring a claim instead of asserting it applies
to the framework's claims as much as to its own.
