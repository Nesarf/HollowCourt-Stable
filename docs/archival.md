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

## What this still costs, stated rather than discovered later

* **A new frame in the sync protocol.** A peer has to be able to ask for a segment and be answered with the package.
  **An older peer that has never heard of archives must degrade to "I do not have that" rather than to an error.**
* **A package must be immutable once written.** That is the whole of its value: it is the thing a reader can trust in
  five years. A rewritten archive is not an archive.
* **The marker event has to be written before the package is considered real**, in that order, so a crash between the
  two leaves a log that names an archive rather than an archive nothing knows about.
* **Serialisation of the two writes.** The marker goes through `EventLog.record` and therefore through `_writeTail`;
  the package is a separate file and needs its own discipline -- written to a temporary name and renamed, the same
  shape `identity_store.dart` uses for the device key.
