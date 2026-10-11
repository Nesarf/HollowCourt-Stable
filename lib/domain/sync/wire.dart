/// What a sync connection says to itself.
///
/// **One frame is one line, and it is the same shape as the log.** The store is already an
/// append-only file of JSON events, one per line, and a reader for it already exists; a wire
/// format that invented a second shape would need a second reader, a second set of malformed
/// cases and a second idea of what a clock looks like. So a frame is a JSON object on one line,
/// and the events inside it are the very same objects the log holds -- `Event.toJson` on the way
/// out, `Event.fromJson` on the way in.
///
/// **The four kinds are the four questions the handshake actually has to ask**, in the order
/// `ClockDigest`'s own documentation lays out:
///
///   1. [HelloFrame]  -- do we hold the same events? A hash and a count, deliberately cheap.
///   2. [ClocksFrame] -- what do you hold, exactly? Sent **only** when the answers differ, which
///                       is the entire reason the digest exists.
///   3. [EventsFrame] -- here is what you are missing. May repeat; see below.
///   4. [ByeFrame]    -- nothing more is coming, and here is why.
///
/// **Batches repeat rather than growing, and `bye` is what ends them.** A single frame carrying
/// every missing event would have to be built in memory in full before any of it could be read,
/// which on a first sync is the whole cellar. Chunking to [maxItemsPerFrame] and letting the
/// receiver merge each chunk as it lands means the memory a sync costs is set by the chunk size
/// and not by the size of the cellar, and it means a long sync makes visible progress instead of
/// one silent pause. [ByeFrame] terminates, so no count needs to be trusted in advance -- and a
/// count the sender got wrong would otherwise be a hang.
///
/// **A frame from the wire is a claim, and parsing says so by returning null.** Same rule as
/// [PairingTicket.parse] and for the same reason: this input arrives from whatever is on the
/// network, which is very often not this program. A parser that threw would turn "something
/// else is on this port" into a crash, and something else on the port is the common case. An
/// unknown `kind` also yields null rather than throwing, so a newer sender's new frame type is
/// refused as unreadable instead of being mistaken for one we understand.
library;
import 'scope.dart';


import 'dart:convert';

import '../archive/archive_manifest.dart';
import '../events/event.dart';
import '../events/hlc.dart';
import 'pairing.dart';

/// The largest number of items one [ClocksFrame] or [EventsFrame] may carry.
///
/// A limit rather than a preference: the receiver allocates per frame, so an unbounded frame is
/// an unbounded allocation decided by the other end of a socket. 256 readings is a few tens of
/// kilobytes at the sizes these objects encode to, which is small enough that a hostile frame
/// costs nothing and large enough that an ordinary sync is a handful of frames.
const int maxItemsPerFrame = 256;

/// The largest number of bytes one line may be before it is refused unread.
///
/// **Enforced while reading, not after**, because the point is not to judge a large frame but to
/// never hold one: a peer that opens a connection and sends bytes forever must cost this process
/// nothing, and a reader that accumulates first and checks afterwards has already paid. The
/// figure is generous against a legitimate frame -- [maxItemsPerFrame] events of the sizes this
/// project writes come to well under a megabyte -- so reaching it means something is wrong.
const int maxFrameBytes = 4 * 1024 * 1024;

/// Which of the four things a frame is.
///
/// The names are on the wire, so they are part of the protocol and not an implementation detail:
/// renaming one breaks a connection between two versions rather than failing a test.
enum WireKind {
  hello('hello'),
  clocks('clocks'),
  events('events'),
  bye('bye'),

  /// **What one device is asking another for.** Carries the [SyncKind]s, and
  /// nothing else: the answer decides whether anything is sent at all.
  request('request'),

  /// **The answer to a [RequestFrame]** -- approval, or a refusal that says
  /// why. See [AnswerFrame] for why the reason is not optional on the wire.
  answer('answer'),

  /// **A list of segments one device is asking another for**, by digest. See [SegmentWantFrame].
  want('want'),

  /// **One segment the other end cannot serve**, with the reason. See [SegmentDeniedFrame].
  denied('denied');

  const WireKind(this.wire);

  /// The string this kind is called on the wire.
  final String wire;

  /// The kind a peer named, or null when the name is not one of ours.
  static WireKind? byWire(String raw) {
    for (final kind in WireKind.values) {
      if (kind.wire == raw) return kind;
    }
    return null;
  }
}

/// Reads one announced segment, or null when this build cannot use it.
///
/// **One unreadable entry costs that entry and not the four beside it**, which is the rule this build applies to the
/// `segments` list and not to its other fields. A segment is a *claim about somebody's files*, so a claim this build
/// cannot use is dropped and the rest are kept: a peer that announced five and sent one this build cannot parse is
/// announcing four, which is a true statement about it. Refusing the whole hello would end a sync over a field that
/// does nothing but describe.
///
/// **A negative count is refused here rather than downstream, for the reason `digest.count` already is.** A count is
/// what a receiver sizes itself against -- a loop that reads exactly that many events -- so a negative one completes
/// that loop immediately with nothing, which is a decision about what to accept made by the far end of a socket. The
/// comment on `HelloFrame._fromJson` records the same argument for the same kind of number.
///
/// **A known limitation, stated rather than discovered later**: a segment written in a *newer* package format is
/// dropped here along with a garbage one, so a reader is not told that it exists. The honest fix is a claim that
/// survives an unreadable manifest and says so; it is not built, and this is where that would go.
ArchiveManifest? readSegmentClaim(Object? entry) {
  if (entry is! Map<String, Object?>) return null;
  try {
    final manifest = ArchiveManifest.fromJson(entry);
    if (manifest.count < 0) return null;
    // A segment nothing names cannot be asked for, and keeping it would put a claim on an outcome that a reader
    // could not act on.
    if (manifest.digest.isEmpty) return null;
    return manifest;
  } on Object {
    return null;
  }
}

/// One message on a sync connection.
sealed class WireFrame {
  const WireFrame();

  /// This kind, for the `kind` field.
  WireKind get kind;

  /// The frame as one line, without its terminator.
  String encode() => jsonEncode(_toJson());

  Map<String, Object?> _toJson();

  /// Reads one line, or returns null when it is not a frame this version understands.
  ///
  /// Never throws, on the same argument the class comment gives: the input is the network's, and
  /// every malformed case here has a caller that wants to close the connection and say why
  /// rather than a stack trace.
  static WireFrame? parse(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return null;

    final Object? decoded;
    try {
      decoded = jsonDecode(trimmed);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, Object?>) return null;

    final named = decoded['kind'];
    if (named is! String) return null;
    final kind = WireKind.byWire(named);
    if (kind == null) return null;

    try {
      return switch (kind) {
        WireKind.hello => HelloFrame._fromJson(decoded),
        WireKind.clocks => ClocksFrame._fromJson(decoded),
        WireKind.events => EventsFrame._fromJson(decoded),
        WireKind.bye => ByeFrame._fromJson(decoded),
        WireKind.request => RequestFrame._fromJson(decoded),
        WireKind.answer => AnswerFrame._fromJson(decoded),
        WireKind.want => SegmentWantFrame._fromJson(decoded),
        WireKind.denied => SegmentDeniedFrame._fromJson(decoded),
      };
    } on FormatException {
      // A well-named frame with an unreadable body is still unreadable. Caught here rather than
      // left to the caller so that "null means not understandable" is one rule and not two.
      return null;
    }
  }
}

/// The first frame either side sends: what this cellar calls itself, and what it holds.
///
/// **The digest travels in both directions and the token in only one.** The digest is what makes
/// the common case -- two devices that already agree -- cost one frame each and no clock set at
/// all. The token is what a stranger on the same network does not have; the side that is being
/// connected *to* is the one holding the ticket's value to check against, so only the connecting
/// side presents it. A symmetric field would invite the answer to also carry a secret, which it
/// has no reason to.
final class HelloFrame extends WireFrame {
  HelloFrame({
    required this.name,
    required this.digest,
    this.token = '',
    Iterable<ArchiveManifest> segments = const [],
  }) : segments = List.unmodifiable(segments);

  @override
  WireKind get kind => WireKind.hello;

  /// What the sending cellar calls itself, for a reader telling two devices apart.
  final String name;

  /// A summary of the sender's clock set. A claim, and treated as one.
  final ClockDigest digest;

  /// The pairing token the sender was given, or empty when it was given none.
  final String token;

  /// **The history this device holds that its log does not** -- the manifests of the archives its reader has attached.
  ///
  /// Empty for every build that came before this one, and empty for a reader who has attached nothing, which is the
  /// ordinary case. **Its absence is not a claim that the peer has no archives**, only that it has announced none:
  /// the two are indistinguishable on this frame, and treating them the same is what makes the degradation automatic.
  ///
  /// **The whole manifest rather than a summary of it** -- `{digest, count, first, last}` was the first version and it
  /// was enough to *identify* a package and not enough to *receive* one. A receiver writes the package it is given,
  /// and a manifest needs `createdMillis` and `nodeId` too: **when the package was made, and which device made it.**
  /// Reconstructing those would put "made here, just now" on a file made on somebody else's machine a month ago,
  /// and the manifest is the one thing in this project that is meant to still be true in five years.
  final List<ArchiveManifest> segments;

  @override
  Map<String, Object?> _toJson() => {
    'kind': kind.wire,
    'name': name,
    'count': digest.count,
    'digest': digest.digest,
    if (token.isNotEmpty) 'token': token,
    // **Omitted when there is nothing to say**, the same rule the token follows and for the same reason: a hello that
    // differs from the old one only when it has something new to carry is a hello an old peer never has to notice.
    if (segments.isNotEmpty) 'segments': [for (final segment in segments) segment.toJson()],
  };

  static HelloFrame _fromJson(Map<String, Object?> json) {
    final name = json['name'];
    final count = json['count'];
    final digest = json['digest'];
    final token = json['token'];
    if (name is! String) throw FormatException('hello without a name: $json');
    if (count is! int || digest is! int) {
      throw FormatException('hello without a readable digest: $json');
    }
    // **A negative count is refused here rather than downstream, because downstream is where it does damage.**
    // `runExchange` collects readings until it has `count` of them, so a negative count completes that loop
    // immediately with an empty set -- and then `missingFrom({})` returns **every event this device holds**, which
    // it would send to a peer that claimed to have none. A malformed frame should be refused where it is read,
    // not turned into a decision about what to disclose.
    if (count < 0) {
      throw FormatException('hello with a negative count: $json');
    }
    if (token != null && token is! String) {
      throw FormatException('hello with an unreadable token: $json');
    }
    // **A segments field that is not a list is refused, and entries inside it that are not readable are dropped.**
    // The asymmetry is deliberate: a field of the wrong *type* is a peer contradicting the protocol, while one bad
    // entry among several is a claim this build cannot use and the others still are -- see `SegmentClaim.tryFromJson`.
    final rawSegments = json['segments'];
    if (rawSegments != null && rawSegments is! List) {
      throw FormatException('hello with a segments field that is not a list: $json');
    }
    final segments = <ArchiveManifest>[
      for (final entry in (rawSegments as List?) ?? const []) ?readSegmentClaim(entry),
    ];
    return HelloFrame(
      name: name,
      digest: ClockDigest.fromSummary(count: count, digest: digest),
      token: (token as String?) ?? '',
      segments: segments,
    );
  }
}

/// The full clock set, sent when the digests disagree.
///
/// This is the frame `ClockDigest`'s documentation calls "the question of whether to ask for it":
/// finding what a peer is missing needs the readings themselves, and this is how they arrive.
final class ClocksFrame extends WireFrame {
  ClocksFrame(Iterable<Hlc> clocks) : clocks = List.unmodifiable(clocks);

  @override
  WireKind get kind => WireKind.clocks;

  final List<Hlc> clocks;

  @override
  Map<String, Object?> _toJson() => {
    'kind': kind.wire,
    'clocks': [for (final clock in clocks) clock.toJson()],
  };

  static ClocksFrame _fromJson(Map<String, Object?> json) {
    final raw = json['clocks'];
    if (raw is! List) throw FormatException('clocks frame without a list: $json');
    if (raw.length > maxItemsPerFrame) {
      throw FormatException('clocks frame of ${raw.length} exceeds $maxItemsPerFrame');
    }
    return ClocksFrame([
      for (final item in raw)
        if (item is Map<String, Object?>)
          Hlc.fromJson(item)
        else
          throw FormatException('clocks frame with an unreadable reading: $item'),
    ]);
  }
}

/// Events the peer does not hold. May arrive more than once; [ByeFrame] ends the stream.
final class EventsFrame extends WireFrame {
  EventsFrame(Iterable<Event> events) : events = List.unmodifiable(events);

  @override
  WireKind get kind => WireKind.events;

  final List<Event> events;

  @override
  Map<String, Object?> _toJson() => {
    'kind': kind.wire,
    'events': [for (final event in events) event.toJson()],
  };

  static EventsFrame _fromJson(Map<String, Object?> json) {
    final raw = json['events'];
    if (raw is! List) throw FormatException('events frame without a list: $json');
    if (raw.length > maxItemsPerFrame) {
      throw FormatException('events frame of ${raw.length} exceeds $maxItemsPerFrame');
    }
    return EventsFrame([
      for (final item in raw)
        if (item is Map<String, Object?>)
          Event.fromJson(item)
        else
          throw FormatException('events frame with an unreadable event: $item'),
    ]);
  }
}

/// The last frame, and the only one that says the connection is finished.
///
/// **A reason travels with it, and the reasons are for a person.** "in sync", "bad token",
/// "done" -- a sync that stops for a reason nobody can read is a sync the reader has to guess
/// about, and the reader here is holding a phone and looking at a screen that has to say
/// something. The reason is display copy and no decision is made from it, so it is a free-form
/// string rather than an enum: the set of reasons will grow, and a peer on an older version
/// should not refuse to close because it does not recognise the word.
final class ByeFrame extends WireFrame {
  const ByeFrame({this.reason = ''});

  @override
  WireKind get kind => WireKind.bye;

  final String reason;

  @override
  Map<String, Object?> _toJson() => {
    'kind': kind.wire,
    if (reason.isNotEmpty) 'reason': reason,
  };

  static ByeFrame _fromJson(Map<String, Object?> json) {
    final reason = json['reason'];
    if (reason != null && reason is! String) {
      throw FormatException('bye with an unreadable reason: $json');
    }
    return ByeFrame(reason: (reason as String?) ?? '');
  }
}

/// **One device asking another for specific kinds of content.**
///
/// The kinds are the whole body: the answer decides whether anything is sent, and what is sent is what the kinds allow.
/// Sending them makes the question explicit on the wire rather than leaving it to whatever the host happened to be willing
/// to hand over.
final class RequestFrame extends WireFrame {
  const RequestFrame({required this.kinds});

  @override
  WireKind get kind => WireKind.request;

  /// What is being asked for. Never empty: a request for nothing is a frame that should not have been sent.
  final Set<SyncKind> kinds;

  @override
  Map<String, Object?> _toJson() => {
    'kind': kind.wire,
    // **Sorted, so the same question produces the same bytes.** A set has no order, and two devices asking the same thing
    // should not differ on the wire for a reason nobody can see.
    'kinds': (kinds.map((each) => each.name).toList()..sort()),
  };

  static RequestFrame _fromJson(Map<String, Object?> json) {
    final raw = json['kinds'];
    if (raw is! List || raw.isEmpty) {
      throw FormatException('request without kinds: $json');
    }
    final kinds = <SyncKind>{};
    for (final each in raw) {
      if (each is! String) throw FormatException('request with an unreadable kind: $json');
      final match = SyncKind.values.where((candidate) => candidate.name == each);
      if (match.isEmpty) throw FormatException('request for an unknown kind "$each"');
      kinds.add(match.first);
    }
    return RequestFrame(kinds: kinds);
  }
}

/// **The answer to a [RequestFrame]**: yes, or no with a reason.
///
/// **A refusal without a reason does not parse**, and that is the design row rather than a preference: it asked for "an
/// explicit request/approve exchange with refusal reasons". A bare no leaves the person on the other device with a screen
/// that failed and nothing to act on, and the wire is the last place that can insist on it.
final class AnswerFrame extends WireFrame {
  const AnswerFrame.approved()
      : approved = true,
        reason = '';

  const AnswerFrame.refused(this.reason) : approved = false;

  @override
  WireKind get kind => WireKind.answer;

  /// Whether the request was granted.
  final bool approved;

  /// Why it was not. **Empty exactly when [approved] is true**, and never empty otherwise.
  final String reason;

  @override
  Map<String, Object?> _toJson() => {
    'kind': kind.wire,
    'approved': approved,
    if (reason.isNotEmpty) 'reason': reason,
  };

  static AnswerFrame _fromJson(Map<String, Object?> json) {
    final approved = json['approved'];
    final reason = json['reason'];
    if (approved is! bool) throw FormatException('answer without a verdict: $json');
    if (reason != null && reason is! String) {
      throw FormatException('answer with an unreadable reason: $json');
    }
    if (!approved && (reason is! String || reason.isEmpty)) {
      // **The row's requirement, enforced where it cannot be forgotten.**
      throw FormatException('answer refuses without a reason: $json');
    }
    return approved ? const AnswerFrame.approved() : AnswerFrame.refused(reason as String);
  }
}

/// **What one device is asking another for: the segments it holds and this one has not.**
///
/// `docs/archival.md`. The digests are the ones the *answerer* announced in its hello, so both ends already know
/// `count`, `first` and `last` for every one of them -- **which is why this frame carries nothing but the list**: the
/// receiver of an ask reads exactly as many events per digest as it was already told, and no length prefix, sentinel
/// or end marker is needed anywhere.
///
/// **A list rather than one frame per segment.** A variable number of request/answer pairs needs a way to say the
/// sequence has ended, and a sentinel is where protocol bugs live; a list has no ambiguity in it at all.
///
/// **An empty list is legal and means "I want nothing of yours".** It is how the turn is handed over: the asking side
/// sends its list whether or not it has one, and the answering side replies with its own. That is what makes the two
/// directions a fixed sequence rather than a negotiation -- **at every moment exactly one side is sending**, so the
/// deadlock `exchange.dart` records cannot form.
final class SegmentWantFrame extends WireFrame {
  SegmentWantFrame(Iterable<String> digests) : digests = List.unmodifiable(digests);

  @override
  WireKind get kind => WireKind.want;

  /// The digests being asked for, in the order the answers will arrive.
  ///
  /// **Ordered rather than a set**, because the answering side serves them in this order and the asking side reads a
  /// known count for each: a set would leave the *sequence* of a multi-segment transfer undefined, and two devices
  /// would then have to agree on an order that neither stated.
  final List<String> digests;

  @override
  Map<String, Object?> _toJson() => {'kind': kind.wire, 'digests': digests};

  static SegmentWantFrame _fromJson(Map<String, Object?> json) {
    final raw = json['digests'];
    if (raw is! List) throw FormatException('want without a digest list: $json');
    return SegmentWantFrame([
      for (final entry in raw)
        if (entry is String && entry.isNotEmpty) entry,
    ]);
  }
}

/// **One segment the other end cannot serve**, and why.
///
/// **This frame exists because silence is the worst of the three answers.** A package can be moved or deleted between
/// the hello that announced it and the ask that wants it, and a responder with nothing to send would otherwise leave
/// the asker waiting for events that are never coming -- **turning a missing file on one side into a failed sync on
/// both.** `docs/archival.md` records the alternatives and why they were not taken: an empty events frame is
/// ambiguous with a segment whose manifest legally says `count: 0`.
///
/// **The reason travels**, the rule `AnswerFrame` already keeps: *"the other device no longer has that segment"* is a
/// sentence a reader can act on, and a bare denial is one they cannot.
final class SegmentDeniedFrame extends WireFrame {
  const SegmentDeniedFrame({required this.digest, required this.reason});

  @override
  WireKind get kind => WireKind.denied;

  /// Which one, so that a denial in the middle of a batch is attributable.
  final String digest;

  final String reason;

  @override
  Map<String, Object?> _toJson() => {
    'kind': kind.wire,
    'digest': digest,
    'reason': reason,
  };

  static SegmentDeniedFrame _fromJson(Map<String, Object?> json) {
    final digest = json['digest'];
    final reason = json['reason'];
    if (digest is! String || digest.isEmpty) {
      throw FormatException('denied without a digest: $json');
    }
    if (reason is! String) throw FormatException('denied without a reason: $json');
    return SegmentDeniedFrame(digest: digest, reason: reason);
  }
}
