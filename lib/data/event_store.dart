import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/events/event.dart';
import '../domain/events/hlc.dart';

/// Why a line could not be read back.
enum LogDefectKind {
  /// The file ends mid-line.
  ///
  /// This is what a crash during an append looks like, and it is expected
  /// rather than alarming: the write that was in flight simply never finished,
  /// so the event it was writing does not exist. Every line before it is
  /// intact. The store discards it on the next append.
  tornTail,

  /// A complete line that is not a readable event.
  ///
  /// This is corruption or a bug, and unlike [tornTail] it is not something a
  /// rewrite will fix. Reported so it can be seen.
  unreadable,
}

/// One line the reader could not turn into an [Event].
final class LogDefect {
  const LogDefect({
    required this.kind,
    required this.lineNumber,
    required this.reason,
    required this.snippet,
  });

  final LogDefectKind kind;

  /// 1-based, so it matches what an editor shows.
  final int lineNumber;

  final String reason;

  /// The first part of the offending line, for a human to look at.
  final String snippet;

  @override
  String toString() => 'line $lineNumber (${kind.name}): $reason -- $snippet';
}

/// Everything read from the log, including what could not be read.
///
/// A read returns defects alongside events rather than only events, because the
/// alternative is a caller who cannot tell "nothing has happened yet" from
/// "half the log was unreadable".
final class LogReadResult {
  const LogReadResult({required this.events, required this.defects});

  final List<Event> events;
  final List<LogDefect> defects;

  /// Defects that mean real damage, i.e. everything except a crash-truncated
  /// tail.
  Iterable<LogDefect> get corruptions =>
      defects.where((defect) => defect.kind == LogDefectKind.unreadable);

  bool get hasCorruption => corruptions.isNotEmpty;
}

/// The append-only event log on disk.
///
/// Plain newline-delimited JSON: one event per line, so the file can be read by
/// eye, by `grep`, and by anything that understands lines. Section 2 chose this
/// over a database because the same bytes serve as storage, sync payload and
/// audit trail -- a format that needs a tool to inspect would give up the third
/// of those.
///
/// Nothing here rewrites an existing line. The only write is an append, which
/// is what makes the file safe to hand to another device mid-edit: whatever the
/// other device reads is a prefix of what this one has.
final class EventStore {
  const EventStore(this.file);

  final File file;

  /// Appends [events], one line each, and does not return until they are on
  /// disk.
  ///
  /// Each event is written with a single terminating newline. That is the whole
  /// of the crash story: a process that dies mid-append leaves a partial line,
  /// which [read] recognises and which the next successful append overwrites by
  /// trimming back to the last complete line.
  ///
  /// Events are written in the order given, and the caller is expected to hand
  /// them over in clock order. The log's own order is a convenience for humans;
  /// the ordering the app relies on is the clock in each event, which survives
  /// being merged with another device's log.
  Future<void> append(Iterable<Event> events) async {
    final lines = [for (final event in events) event.encode()];
    if (lines.isEmpty) return;

    await file.parent.create(recursive: true);

    // If the file ends mid-line, move the end of the file back to the start of
    // that line before appending. Without this the torn fragment would fuse
    // with the first new event, turning a lost event into a corrupt one.
    if (await file.exists() && await file.length() > 0) {
      final length = await file.length();
      final tornAt = await _startOfTornTail(length);
      if (tornAt != null) {
        final handle = await file.open(mode: FileMode.append);
        try {
          await handle.truncate(tornAt);
        } finally {
          await handle.close();
        }
      }
    }

    final sink = file.openWrite(mode: FileMode.append);
    try {
      for (final line in lines) {
        sink.writeln(line);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  /// The byte offset where an incomplete final line begins, or null when the
  /// file ends cleanly.
  ///
  /// **[A defect found by review on 2026-10-01, and the shape of it is worth keeping.]** This read
  /// `handle.read(...)` with no `seek`, and `RandomAccessFile` starts at offset **0** -- so what the
  /// comment called the tail was the file's **first** sixty-four kilobytes. The arithmetic below then
  /// subtracted a position found near the *start* from a length measured at the *end*, so on any log
  /// larger than 64 KiB with a torn final line it returned an absolute offset far below the real end,
  /// and `append` called `truncate` on it. **That deletes every event between that offset and the
  /// end**, silently, which is the worst thing this file can do to a reader.
  ///
  /// **Why nothing caught it.** A clean file returns at the first check, because it ends with `\n` --
  /// so the fault needs a torn tail *and* a log over 64 KiB, and the existing tests had neither. A
  /// cellar that has been in use for months has both as soon as one write is interrupted.
  ///
  /// The read now seeks to `length - 65536` where it belongs, and the offset it returns is absolute.
  Future<int?> _startOfTornTail(int length) async {
    final handle = await file.open();
    try {
      final tailStart = length < 65536 ? 0 : length - 65536;
      await handle.setPosition(tailStart);
      final tail = await handle.read(length - tailStart);
      if (tail.isEmpty || tail.last == 0x0A) return null; // ends with '\n'
      for (var i = tail.length - 1; i >= 0; i--) {
        if (tail[i] == 0x0A) {
          // Absolute, not relative: `tailStart` is where this window began in the file.
          return tailStart + i + 1;
        }
      }
      // No newline in the window at all. The torn line therefore begins at or before `tailStart` --
      // and **the honest answer is `tailStart`, not 0**, because truncating to 0 would throw away the
      // sixty-four kilobytes we just looked at that contain no newline but are not necessarily one
      // broken line. A read this large with no newline in it is a corrupt file rather than a torn
      // write, and keeping the bytes is the choice that leaves somebody able to look.
      return tailStart;
    } finally {
      await handle.close();
    }
  }

  /// Reads every event in the log, in file order.
  ///
  /// File order, deliberately, not clock order. Sorting is a decision about
  /// what to *do* with the events, and it belongs to whatever is folding them;
  /// a store that quietly reordered its own contents would make the log a worse
  /// witness than it is.
  Future<LogReadResult> read() async {
    if (!await file.exists()) {
      return const LogReadResult(events: [], defects: []);
    }

    final events = <Event>[];
    final defects = <LogDefect>[];

    // **Streamed rather than read whole, and the distinction is not only about memory.** This used to be
    // `readAsString` followed by `LineSplitter`, which loads the entire log as one string and then as a list of
    // one string per event -- for a log the protocol explicitly permits to reach `maxClockEntries` (2^20), that is
    // a copy of the whole cellar in memory to iterate over it once. Every consumer folds the result straight into
    // a state and keeps the events, so the *events* have to be in memory; the string and the line list do not.
    //
    // **Split on the newline byte rather than decoding lines**, because "does the file end with a newline" is a
    // question about bytes and answering it from a decoded string means the answer depends on the encoding. A log
    // with a torn final write is exactly the case that question exists for.
    var endedWithNewline = false;
    var carry = <int>[];
    var lineNumber = 0;
    var pending = false;

    void emit(List<int> bytes) {
      lineNumber++;
      final line = utf8.decode(bytes, allowMalformed: true);
      if (line.trim().isEmpty) return;
      try {
        events.add(Event.decode(line));
        pending = false;
      } catch (error) {
        // **The defect is held rather than recorded**, because whether the last line is a torn write or
        // corruption is only knowable once the stream has ended: a file that stops mid-line is a kill during a
        // write, and everything else is a line somebody has to look at. Deferring by one is what lets the same
        // judgement be made without holding the file.
        pending = true;
        defects.add(
          LogDefect(
            kind: LogDefectKind.unreadable,
            lineNumber: lineNumber,
            reason: '$error',
            snippet: line.length > 120 ? '${line.substring(0, 120)}...' : line,
          ),
        );
      }
    }

    await for (final chunk in file.openRead()) {
      var start = 0;
      for (var i = 0; i < chunk.length; i++) {
        if (chunk[i] != 0x0A) continue;
        endedWithNewline = true;
        final part = chunk.sublist(start, i);
        if (carry.isEmpty) {
          emit(part);
        } else {
          carry.addAll(part);
          emit(carry);
          carry = <int>[];
        }
        start = i + 1;
        endedWithNewline = false;
      }
      carry.addAll(chunk.sublist(start));
      if (carry.isNotEmpty) endedWithNewline = false;
    }

    // Whatever is left in the carry is the last line, and the file did not end with a newline -- which is the
    // torn write. **An empty carry means the file ended cleanly**, and then no line is torn whatever is above it.
    if (carry.isNotEmpty) {
      emit(carry);
      if (pending && defects.isNotEmpty) {
        final last = defects.last;
        defects[defects.length - 1] = LogDefect(
          kind: endedWithNewline ? LogDefectKind.unreadable : LogDefectKind.tornTail,
          lineNumber: last.lineNumber,
          reason: last.reason,
          snippet: last.snippet,
        );
      }
    }

    return LogReadResult(events: events, defects: defects);
  }

  /// The events whose clock is after [clock], for handing to a peer.
  ///
  /// Section 10.4 reduces syncing to "exchange the events the other side is
  /// missing", and this is the cheapest form of that question: a device says
  /// where its log ends, and gets everything past that point. It does not
  /// replace a real set difference -- two devices that have both been offline
  /// need to compare what they have, not just how far they got -- but it is the
  /// common case and it costs one pass.
  Future<List<Event>> since(Hlc clock) async {
    final result = await read();
    return [
      for (final event in result.events)
        if (event.hlc.compareTo(clock) > 0) event,
    ];
  }
}
