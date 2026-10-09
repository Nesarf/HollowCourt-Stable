# Compaction: the obstacle, and how it was answered

Written 2026-10-08, before any of it was built.

> **Settled later the same day: compaction is not deletion but a move.** The owner's answer is in `docs/archival.md`
> -- old history leaves the working log and arrives in a package the reader owns, so **the log shrinks while the
> history stays complete**. **The obstacle measured below is what made that the right answer rather than a preference**,
> so it is kept rather than replaced.

## The finding, and the paragraph that already knew

`docs/proposal-recipes-and-packs.md` and `overlay.dart` both record it. The overlay's own words:

> **What would break that, written down because it is a real future temptation.** Compacting the log: dropping an old
> `set` and the `clear` that superseded it together is safe only while nothing older can still arrive, and "nothing
> older can arrive" is a claim about sync rather than about the file. A compacted log would need the tombstone kept,
> and **the day someone adds compaction is the day this paragraph stops being true.**

So the temptation was foreseen. What was not written down is **what the sync protocol would have to become**, and that
is the whole of the work.

## The obstacle is not the tombstone. It is `missingFrom`.

The wire protocol exchanges **events**, and decides which by **clock identity**:

```dart
List<Event> missingFrom(Set<Hlc> theirClocks) =>
    [for (final event in _events) if (!theirClocks.contains(event.hlc)) event];
```

**And `ClockDigest` is a summary of exactly those readings.** So compaction removes two things at once: the events, and
the evidence that they ever existed.

That makes a specific failure reachable. **B is offline when A compacts.** A drops an old `set` and the `clear` that
superseded it. Then B comes back:

* B still holds the `set`, and its clock set still names it.
* **A has never heard of that reading** -- and cannot, because the reading was the thing that was dropped.
* So A never asks for it, and B never sends it. **B's stale write is now invisible to both sides**, and the two logs
  disagree with neither device able to tell.

**A tombstone does not fix this**, which is the part worth being clear about: keeping "this field was cleared at clock
X" while dropping the `clear`'s own reading still leaves B holding a reading A does not have. **The tombstone preserves
the effect; the protocol needs the identity.**

## What a frontier would have to be, and it is more than a retention horizon

The review proposes *device acknowledgement frontier + snapshot + tombstone retention horizon*. The middle term is the
one that changes the protocol: **a peer that has compacted cannot be caught up by exchanging events with a peer that
has not**, so one side has to be able to say *"I collapsed everything up to X"* and the other has to be able to answer
*"then send me a snapshot instead"*.

**That is a snapshot exchange**, which is a new frame type and a new question at every point the protocol currently
assumes events: `missingFrom`, `ClockDigest`, the scope whitelist, and `.courtpack`, which is a copy of the log and
would have to be able to carry a snapshot.

## The three real options, with what each costs

| | What it is | What it costs |
| --- | --- | --- |
| **A. Never compact; make the log smaller instead** | Periodic rewrite of superseded events into one *state snapshot* event per key, keeping every reading that was ever issued as a cheap "seen" marker | The seen-markers are what a million events costs anyway, so this buys less than it looks like |
| **B. A frontier protocol** | Peers acknowledge a clock reading; only a reading every known peer has acknowledged may be dropped, and a returning device is offered a snapshot rather than a diff | A new frame, a new state per peer, and the answer to "what is a known peer" -- see below |
| **C. Segment and archive** | The log is split into segments; the tail is what syncs, and an old segment is kept whole and out of the way | The file stops growing in memory but keeps growing on disk, and a peer that needs an old segment still needs the old segment |

**B is the only one that lets the file actually shrink**, which is presumably the point. **A and C are ways of stopping
the growth.**

## The question that is the owner's rather than the design's

**B needs an answer to "when may a reading be dropped", and every candidate answer is a promise about the reader's
other devices.** The choices are not technical:

1. **Only when every device that has ever synced has acknowledged it.** Safe, and **one device that is thrown away, or
   lost, or never opened again stops compaction for ever.**
2. **After a time horizon** -- a device untouched for N months is assumed gone. Compaction always eventually possible,
   **and the assumption is wrong exactly when somebody finds an old phone.**
3. **When the reader says so**, per device: *"I no longer have this machine."* Honest, needs a screen, and puts the
   consequence where the knowledge is.
4. **Never** -- keep every reading and compact nothing, and treat a cellar as bounded by its own history.

**The project's own values point at (3) and at (4)**, and neither is what a "compaction protocol" usually means. **（1）
is the one the review's shape implies, and it is the one that cannot survive a lost phone.**

## The answer, and it is not one of the four

**All four above assume something is dropped. The owner's answer was that nothing is.** Old events leave the working
log and arrive in a package under `Documents/`, so:

* **The question of "when may a reading be dropped" never has to be answered**, because no reading is dropped.
* **The package is a file the reader owns**, which is where "for ever" belongs -- it does not depend on the protocol
  being right, on a device answering, or on this application existing in five years.
* **And the archive list replaces the guess**: instead of the application deciding that a device is gone, **the reader
  selects which packages to read**, with select-all and invert.

The full shape -- the grain, the container, the marker event and the new sync frame -- is in `docs/archival.md`.

## What is built

**Nothing yet.** `docs/ingredient-gap.md`'s rule applies to this file as much as to that one: **nothing here is a
claim about what the code does, because the code is not there.** What is here is the obstacle, which is real and
measured, and the reasoning that led away from compaction and towards a move.
