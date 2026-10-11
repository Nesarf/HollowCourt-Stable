# Archival: compaction as moving house

**Settled with the owner on 2026-10-08.** This replaces the earlier framing in this file, which asked whether to
compact at all. **The answer is that nothing is deleted** -- old history is moved into a package the reader owns, and
the working log is what shrinks.

## The idea, in the owner's words

> 我很想做「永远」，但考虑到一些东西可以作为「用户数据文件」得到永久存放，所以其实有一个两全的方案…

**So compaction is not a retention policy.** It is a move: a range of events leaves the working log and arrives in a
file under `Documents/`, and **the working log gets smaller while the history stays complete.**

**And that removes the obstacle this document was written about.** The fatal problem of true compaction was that
`missingFrom` decides what to send by clock identity:

```dart
List<Event> missingFrom(Set<Hlc> theirClocks) =>
    [for (final event in _events) if (!theirClocks.contains(event.hlc)) event];
```

**Dropping a reading means a peer that still holds it can never be told apart from a peer that does not** -- so a stale
write becomes invisible to both sides. **Archival never drops a reading; it moves one.** The frontier is still
needed, but for *distribution* rather than for safety.

## The decisions, and they are the owner's

| Question | Settled |
| --- | --- |
| Does the application read archives by itself? | **No -- the reader chooses.** A step that lists the packages and lets them be selected, **with select-all and invert** |
| Do archives travel by sync? | **Yes -- a new frame that can request a segment.** Not by file-copying alone |
| When does a range become an archive? | **Five years.** Anything older than five years is a candidate |
| Is a marker left in the working log? | **Yes, and it is an ordinary event -- it syncs** |
| What is a package? | **A custom container with a manifest**, carrying the events of one archival |
| Who is written when an archival happens? | **Both** -- the working log's marker *and* the package |

### Why five years is the right shape, and not arbitrary

`price_period.dart` reads **120 monthly candles -- ten years**. **A five-year grain never cuts a window in half**: the
widest view spans two archives and **both of them exist.** A grain shorter than the widest window would mean a reader
attaching archives and still seeing a truncated chart, which is the silent-failure shape this project keeps meeting.

### Why the reader chooses, and what that buys

**No archive is read unless the reader says so.** The consequences are worth stating:

* **A package the reader deletes is simply not in the list.** Nothing has to notice, and no history changes behind
  their back.
* **History depth is a visible choice rather than a hidden constant.** The alternative -- a retention horizon -- is a
  guess about devices that have gone away, and it is wrong exactly when somebody finds an old phone.
* **The cost is real**: a reader who wants a ten-year price chart has to select two packages. That is the price of not
  guessing, and it is paid once per package.

## The package

A container with a manifest, **and the owner asked for it to be a custom format rather than a bare `.ndjson`.** The
manifest is what makes it self-describing: without one, a file of events cannot say which clock range it holds, which
device made it, or whether it is complete.

```
cellar-archive-<first>-<last>.courtarchive      the container
  manifest.json      what it is: range, count, creator, digest, format version
  events.ndjson      the events themselves, in the format the log already uses
```

**Internal format unchanged and that is deliberate.** The container is new; **what is inside it is the same
line-delimited JSON the log is written in**, so the promise that a reader can verify the file without trusting the
application still holds -- they can open it, and the lines are the same lines.

**`.courtarchive` rather than `.courtpack`**, because the two mean different things and `Documents/` already holds
both kinds: a `.courtpack` is *imported*, merging its events into the log; an archive is *read beside* it. **A reader
who confuses them would delete their history believing they were restoring it.**

## A screen that reads the log while its neighbour reads the history

**Found 2026-10-11, while the reorder section was being built, and it was the section's own doing.** Attaching a
package already changed the folds -- `Cellar.of` merges before folding, and `ShelfLayout`, `Overlay` and the rest all
come out of the whole history. **What did not change were five projections that reached for `cellar.log.events`
directly**, so a reader who attached a package got a screen where the shelf knew about ten years and the chart beside
it knew about three.

    cellarValueOf      the cellar's value, priced from its own receipts
    ConsumptionCurve   the consumption chart
    CellarStats        the statistics joined to it
    priceSeriesOf      the price history
    Cashflow           the four money windows

**All five now read `Cellar.events`**, which is log plus attached packages, merged and ordered. The inconsistency was
always there; what made it visible is that the running-low section added in ⑤'s round reads the merged history --
**a screen that agrees with itself while being wrong is one thing, and a screen whose two halves disagree is a defect
somebody can see.**

## And the readings now say so

Those five are folded from the whole history, and the cellar page had no way of telling a reader that. `Cellar` carried
`archivedEvents` and `readsArchives` for exactly this and **nothing called them** -- so a reader who attached a package
saw a chart *longer* than their log, with nothing on the screen to explain it. **This file already names that shape from
the other side** -- *"a reader attaching archives and still seeing a truncated chart"* -- and a chart longer than
expected is the same failure arriving from the opposite direction.

`lib/ui/archive_note.dart` is the line. It sits **under the cellar page's title**, because the note qualifies five
readings and a note beside any one of them would read as being about that one; and **it renders nothing when no package
is attached**, which is what lets it sit at the top of a page without costing anything.

**Its two numbers come from two places on purpose**: the package count is what the reader ticked, and the event count is
how many the fold **actually used**. A ticked package that contributed nothing counts towards the first and not the
second, and saying both is more honest than picking one.

**And two places still read the log alone, on purpose**:

* **`SyncScope` and the exchange read the working log**, because that is the invariant the whole archive design rests
  on: `digest` and `missingFrom` decide by clock identity what to send, and **archives travel by their own frame rather
  than by the event difference**. A peer asked for what is missing from the *working log*, not from a history the
  reader assembled out of files only they have.
* **The developer section prints `log.events.length`**, and its label says so. It is a count of the file.

## What this still costs, stated rather than discovered later

* **A new frame in the sync protocol.** A peer has to be able to ask for a segment and be answered with the package.
  **An older peer that has never heard of archives must degrade to "I do not have that" rather than to an error.**
  **Built, and the sentence above is half wrong** -- see the next section.

## The announcement, and the requirement a new frame kind could not meet

**The first half of that bullet is built; the second half is why it could not be built the way the bullet says.**

`exchange.dart` reads every line through `WireFrame.parse`, which returns null for a kind this build does not know --
and the reader of that null calls `_end('the other end sent something unreadable')`. **So an old peer does not have a
path that says "I do not have that". The only thing it can do with a frame it cannot read is hang up**, and no amount
of care on the sending side changes that: the requirement *"must degrade to 'I do not have that' rather than to an
error"* is **unsatisfiable by adding a frame kind**.

**So the announcement rides an optional field on `hello`, which every build already parses.**

    hello { name, count, digest, token?, segments? }
    segments: [ <an ArchiveManifest, whole> ]

An older peer ignores a key it does not know, answers the handshake exactly as it always did, and **the session
proceeds with the segments simply not announced** -- which is the required degradation, obtained without asking
anything of the old build. The frame is byte-identical to the one the previous release sent whenever there is nothing
to announce, which is the ordinary case.

**The digest is the identity**, not the file name: `ArchiveManifest.digest` is a stable hash over the package's own
encoded lines, while a file name is a *range* that two devices can independently produce for two different sets of
events -- so comparing names would report a difference that is not there, or miss one that is.

### The announcement carries the whole manifest, and that is a correction

**The first version carried `{digest, count, first, last}` and it was not enough -- found by asking what a receiver
would have to do with it.** A receiver writes the package it is given, and a manifest has **seven** fields: those four
plus `createdMillis` and `nodeId`, which are *when the package was made* and *which device made it*. A receiver that
reconstructed those would be writing **"made on this machine, just now"** about a file made on somebody else's machine
a month ago -- and the manifest is the one thing in this project that is meant to still be true in five years.

So the field carries an `ArchiveManifest`, and `ArchiveManifest`/`ArchiveUnreadable` moved from `lib/data/` to
`lib/domain/archive/` so that the wire can speak about one: `lib/domain/sync/wire.dart` may not import `lib/data/`, and
a summary type would have been a second statement of what a manifest is. `archive_package.dart` re-exports both, so no
call site changed.

**Two more small holes closed on the way**, both of the kind that only show up when a value starts travelling:

* **A negative `count` is refused when the announcement is read**, the rule `hello`'s own `count` already follows: a
  receiver sizes a loop against it, and a negative one completes that loop immediately with nothing -- a decision about
  what to accept, made by the far end of a socket.
* **`ArchiveManifest` had no equality.** It is seven fields describing a file and two manifests read out of the same
  bytes compared as different objects. Nothing depended on it until a peer began announcing one, and a test asserting
  *the peer announced the package I hold* could not be written without it. Its `toString` also gained `createdMillis`,
  because the first version omitted it and a failed equality printed two lines that looked identical.

**What this gives a reader today**: sync two devices and the outcome says how many segments the other one holds that
this one has not, and the screen says so. **What it does not do yet is move one across**, and that is now the only
thing this line owes.

## The ask: the shape, and the two traps found before writing it

**Wanted, so the next attempt is short rather than clever.** Nothing below is built.

### One frame, one round, one direction at a time

    SegmentWantFrame { digests: [ ... ] }        // possibly empty

    initiator  ->  want                        (what it lacks of the responder's)
    responder  ->  events for each, in order   (`count` per digest is already known from the hello)
    responder  ->  want                        (what it lacks of the initiator's)
    initiator  ->  events for each, in order

**One frame per round rather than one per segment**, because a round with a variable number of request/answer pairs
needs an end marker and a sentinel is where protocol bugs live. **A list plus a known count per entry has no ambiguity
in it**: the receiver reads exactly the announced number of events for each digest and then knows it is done.

**Both directions, in a fixed order, and never both at once.** At every moment exactly one side is sending, so the
deadlock the exchange's own comment records cannot form. The order is determined by role, so neither has to negotiate.

### Trap one: `bye` stops meaning what it says

The exchange sends its bye **before awaiting anything**, and the comment on it is explicit: *"`bye` means 'I have
nothing more to send', which became true the moment the last event frame left."* **With segments that sentence is
false** -- a segment *is* something more to send, so the round has to be finished before the bye goes out. Get it wrong
in the other direction and two peers each wait for the other's bye on a connection where both still had something to
say. **This is the one part of the change that must not be rushed**, and it is the part with a test that already
catches it.

### Trap two: the round after the events phase is skipped exactly when it is wanted

`runExchange` returns early when `mine.likelyInSyncWith(greeting.digest)` -- two devices that agree about the log send
one frame each and a bye. **A segment round placed after the events phase therefore never runs for them**, and that is
not an edge case: **it is every retry**, and every reader who attaches a package *after* the sync that moved their
log. The first sync takes the long path and could carry the segment; the second one, the one where the reader is
wondering why the chart is short, does not.

**So the round belongs directly after the consent gate**, before the in-sync return, and gated on *either side having
announced anything* -- which is what keeps the one-frame case a one-frame case for every reader who has no archives.

### What serving needs, and the one decision left open

The responder has to read a package off disk to answer, and `runExchange` is in `lib/domain/` where file I/O does not
belong. So the responder needs a lookup passed in -- `Future<List<Event>> Function(ArchiveManifest)` -- exactly the way
`SyncSource` is passed in, and for the same reason: **the exchange knows about frames and cannot know which files a
reader has ticked.**

**The open decision is what happens when the responder cannot serve one.** The file may have been deleted, or moved,
between the hello and the ask. Three candidates, and none is obviously right:

1. **A denial frame**, so the asker is told rather than left to time out. One more frame kind, and the honest one.
2. **An empty events frame**, reusing what exists -- and ambiguous with a segment whose manifest says `count: 0`, which
   is legal.
3. **Nothing**, letting the asker's deadline report it -- the worst of the three, because a missing file on one side
   becomes a failed sync on both.

**A denial frame is the right answer and it is not built**, and the reason to write the choice down rather than pick it
in a hurry is that it decides what a reader sees: *"the other device no longer has that segment"* is a sentence, where a
timeout is an error.

* **A package must be immutable once written.** That is the whole of its value: it is the thing a reader can trust in
  five years. A rewritten archive is not an archive.
* **The marker event has to be written before the package is considered real**, in that order, so a crash between the
  two leaves a log that names an archive rather than an archive nothing knows about.
* **Serialisation of the two writes.** The marker goes through `EventLog.record` and therefore through `_writeTail`;
  the package is a separate file and needs its own discipline -- written to a temporary name and renamed, the same
  shape `identity_store.dart` uses for the device key.
