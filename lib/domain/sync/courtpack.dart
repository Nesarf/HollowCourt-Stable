import 'dart:convert';

// `dart.dart` rather than the main entry point: it is the pure-Dart implementation, and it is the
// one that exposes a synchronous hash (see [CourtPack.hashBody]).
import 'package:cryptography/dart.dart';

import '../events/event.dart';

/// The offline exchange format: a cellar in one file, transferable over any channel.
///
/// **Section 10.2's third path, and the section calls it a necessity rather than a nicety**: a great
/// many routers and guest networks enable client isolation by default, and on those neither mDNS nor a
/// QR code can reach anything. A file can always be carried -- by a cable, a chat application, a USB
/// stick, or two people standing next to each other -- and the merge is the same merge the network path
/// uses, so the two differ only in transport.
///
/// THE FORMAT IS THE LOG, WITH ONE LINE IN FRONT.
///
/// A pack is newline-delimited JSON whose **first line is a header** and whose remaining lines are the
/// same event lines the log holds, byte for byte. That is the same argument section 2 makes for the log
/// itself: the same bytes serve as storage, as payload and as an audit trail, and a format that needs a
/// tool to inspect gives up the third of those. A `.zip` or an envelope object would have been the
/// obvious alternative and would have bought nothing -- the events are already JSON, and a person can
/// `grep` a pack.
///
/// WHAT THE HEADER IS FOR, AND WHAT IT IS NOT.
///
/// It carries a count and a **SHA-256 of the body**, because the two failures that actually happen in
/// transit are a file cut short (a cancelled download, a chat client's size limit) and a file edited in
/// passing. A count catches the first and the hash catches both. Note what is deliberately *not* used:
/// the wire's own `ClockDigest`, whose hash is over the *clock readings* -- an edit to a volume or a sku
/// leaves every reading identical, so it would report a tampered pack as intact. A file is the unit
/// here, so the file's bytes are what gets hashed.
///
/// **It is not a signature, and the format does not pretend otherwise.** The hash says "these bytes are
/// the bytes that were written"; it says nothing about *who* wrote them. A pack is a document a person
/// hands over, and the trust is the trust they already have in each other -- which is the same position
/// the pairing code takes, and the reason section 10.3 puts authentication at the moment of connection
/// rather than in the payload.
final class CourtPack {
  const CourtPack._();

  /// **A version on every pack, and a newer one is refused rather than half-read.**
  ///
  /// A reader that skipped the fields it did not recognise would import a partial cellar and report
  /// success, which is the failure mode that costs a person their data rather than their time.
  static const int version = 1;

  static const String _marker = 'courtpack';

  /// The header line, as it is written to the file.
  static String encodeHeader({
    required String source,
    required Iterable<Event> events,
    required String body,
    int version = CourtPack.version,
    String fingerprint = '',
    String shelfId = '',
    int exportedAtMillis = 0,
  }) {
    final list = events.toList();
    return jsonEncode({
      _marker: version,
      'source': source,
      if (fingerprint.isNotEmpty) 'fingerprint': fingerprint,
      if (shelfId.isNotEmpty) 'shelfId': shelfId,
      'events': list.length,
      'sha256': hashBody(body),
      'exportedAt': exportedAtMillis,
    });
  }

  /// The whole file: header line, then one event per line.
  ///
  /// [events] are written in the order given and the caller is expected to hand them over in clock order,
  /// exactly as the store does -- the log's own order is a convenience for people, and the ordering the
  /// application relies on is the clock in each event.
  static String encode({
    required String source,
    required List<Event> events,
    String fingerprint = '',
    String shelfId = '',
    int exportedAtMillis = 0,
  }) {
    final body = encodeBody(events);
    return '${encodeHeader(
      source: source,
      events: events,
      body: body,
      fingerprint: fingerprint,
      shelfId: shelfId,
      exportedAtMillis: exportedAtMillis,
    )}\n$body';
  }

  /// The event lines only, each terminated by a newline.
  ///
  /// Terminated rather than joined, so that appending is a concatenation and a file cut mid-line is
  /// visible as one unreadable trailing line instead of as a silently shortened last event.
  static String encodeBody(Iterable<Event> events) {
    final buffer = StringBuffer();
    for (final event in events) {
      buffer.writeln(jsonEncode(event.toJson()));
    }
    return buffer.toString();
  }

  static String hashBody(String body) {
    // `DartSha256` rather than `Sha256`: the latter's `hash` returns a `Future`, and this is a codec whose
    // two functions are pure and synchronous. The package's Dart-only implementation has the synchronous
    // form, and a pure-Dart hash is the right one here anyway -- the domain layer runs on the plain VM.
    final hash = const DartSha256().hashSync(utf8.encode(body));
    return hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Reads a pack, checking what can be checked before a single event is handed over.
  ///
  /// **Nothing is returned for a bad pack except the reason**, and that is the point: an import that
  /// merged the first half of an incomplete file and then complained would have already changed the
  /// cellar, and the reader's next action -- retry the transfer -- would no longer be a no-op.
  static CourtPackRead read(String text) {
    final lines = text.split('\n');
    if (lines.isEmpty || lines.first.trim().isEmpty) {
      return const CourtPackRead._failed(CourtPackProblem.notAPack);
    }

    final Map<String, Object?> header;
    try {
      final decoded = jsonDecode(lines.first.trim());
      if (decoded is! Map<String, Object?>) {
        return const CourtPackRead._failed(CourtPackProblem.notAPack);
      }
      header = decoded;
    } on FormatException {
      return const CourtPackRead._failed(CourtPackProblem.notAPack);
    }

    final declared = header[_marker];
    if (declared is! int) {
      // The file is JSON and is not a pack. Named separately from "not JSON at all", because a reader
      // who grabbed the wrong file wants to hear that rather than that their file is broken.
      return const CourtPackRead._failed(CourtPackProblem.notAPack);
    }
    if (declared > version) {
      return CourtPackRead._failed(CourtPackProblem.tooNew, version: declared);
    }

    final events = <Event>[];
    final bodyLines = <String>[];
    for (final line in lines.skip(1)) {
      if (line.trim().isEmpty) continue;
      bodyLines.add(line);
      try {
        final decoded = jsonDecode(line);
        if (decoded is! Map<String, Object?>) {
          return const CourtPackRead._failed(CourtPackProblem.damaged);
        }
        events.add(Event.fromJson(decoded));
      } on Object {
        // A line that is there and unreadable is damage, not truncation: truncation removes lines from
        // the end, and a damaged line is in the middle of what arrived.
        return const CourtPackRead._failed(CourtPackProblem.damaged);
      }
    }

    final expected = header['events'];
    if (expected is! int || events.length != expected) {
      // **The failure that happens most**: a file that transferred incompletely. Its header promises more
      // than the body holds, and the count is what sees it.
      return CourtPackRead._failed(
        CourtPackProblem.truncated,
        version: declared,
        found: events.length,
        expected: expected is int ? expected : -1,
      );
    }

    final declaredHash = header['sha256'];
    final actualHash = hashBody('${bodyLines.join('\n')}\n');
    if (declaredHash is! String || declaredHash != actualHash) {
      return CourtPackRead._failed(
        CourtPackProblem.altered,
        version: declared,
        found: events.length,
        expected: expected,
      );
    }

    return CourtPackRead._opened(
      CourtPackHeader(
        version: declared,
        source: header['source'] is String ? header['source']! as String : '',
        fingerprint:
            header['fingerprint'] is String ? header['fingerprint']! as String : '',
        shelfId: header['shelfId'] is String ? header['shelfId']! as String : '',
        events: expected,
        exportedAtMillis: header['exportedAt'] is int ? header['exportedAt']! as int : 0,
      ),
      events,
    );
  }
}

/// What a pack's header says about itself, for a screen that wants to describe a file before importing it.
final class CourtPackHeader {
  const CourtPackHeader({
    required this.version,
    required this.source,
    required this.fingerprint,
    required this.shelfId,
    required this.events,
    required this.exportedAtMillis,
  });

  final int version;

  /// The name of the device that wrote it, so a reader can tell whose cellar this is.
  final String source;

  /// The writer's long-term key fingerprint, when it has one. Untrusted by construction: see the class
  /// comment on [CourtPack] -- a pack says what it says, and nothing proves it.
  final String fingerprint;

  /// Empty for the whole cellar, or the shelf a scoped export was limited to.
  final String shelfId;

  final int events;
  final int exportedAtMillis;
}

/// Why a pack could not be read.
enum CourtPackProblem {
  /// Not JSON, or JSON that is not a pack.
  notAPack,

  /// A pack from a newer build. Refused rather than partly read.
  tooNew,

  /// Fewer events arrived than the header promised.
  truncated,

  /// A line is unreadable, or the body does not match the header's hash.
  damaged,

  /// The count and the lines agree but the bytes do not match the hash that was written over them.
  altered,
}

/// A pack that has been read, or the reason it was not.
final class CourtPackRead {
  const CourtPackRead._opened(this.header, this.events)
    : problem = null,
      found = -1,
      expected = -1,
      _declaredVersion = 0;

  const CourtPackRead._failed(
    CourtPackProblem this.problem, {
    int version = 0,
    this.found = -1,
    this.expected = -1,
  }) : header = null,
       events = const [],
       _declaredVersion = version;

  final CourtPackHeader? header;

  /// Empty unless the pack was read whole. There is no partial result on purpose.
  final List<Event> events;

  final CourtPackProblem? problem;

  /// What arrived, and what the header promised: both -1 when the question does not apply.
  final int found;
  final int expected;

  final int _declaredVersion;

  bool get ok => problem == null;

  /// The version the header declared, when it declared one: a `tooNew` refusal can say how new.
  int get declaredVersion => header?.version ?? _declaredVersion;
}
