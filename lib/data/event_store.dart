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
  Future<int?> _startOfTornTail(int length) async {
    final handle = await file.open();
    try {
      final tail = await handle.read(length < 65536 ? length : 65536);
      if (tail.isEmpty || tail.last == 0x0A) return null; // ends with '\n'
      for (var i = tail.length - 1; i >= 0; i--) {
        if (tail[i] == 0x0A) return length - (tail.length - 1 - i);
      }
      return 0; // no newline anywhere in the tail we looked at
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
    final raw = await file.readAsString();

    // A file that does not end in a newline ends in an unfinished line. Keeping
    // that fact lets the last line be judged as a torn write rather than as
    // corruption -- different causes, different responses.
    final endsCleanly = raw.isEmpty || raw.endsWith('\n');
    final lines = const LineSplitter().convert(raw);
    final lastIndex = lines.length - 1;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim().isEmpty) continue;
      try {
        events.add(Event.decode(line));
      } catch (error) {
        final isTornTail = i == lastIndex && !endsCleanly;
        defects.add(
          LogDefect(
            kind: isTornTail ? LogDefectKind.tornTail : LogDefectKind.unreadable,
            lineNumber: i + 1,
            reason: '$error',
            snippet: line.length > 120 ? '${line.substring(0, 120)}...' : line,
          ),
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
