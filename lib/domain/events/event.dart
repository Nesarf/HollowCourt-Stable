import 'dart:convert';

import 'hlc.dart';

/// One entry in the append-only log.
///
/// Section 2 decided on an event log rather than a database for a specific
/// reason: the same bytes serve as the storage format, the sync format and the
/// audit trail, so there is no diff layer to write and no migration to plan.
/// This class is that format.
///
/// The [hlc] doubles as the identity. It is unique across devices because the
/// node id is inside it and totally ordered because [Hlc] compares totally, so
/// nothing else has to be minted to name an event -- and two devices that sync
/// with each other dedupe by comparing clocks rather than by trusting a
/// separate id they might disagree about.
final class Event {
  Event({
    required this.hlc,
    required this.type,
    Map<String, Object?> data = const {},
  }) : data = Map.unmodifiable(data);

  /// When and where this happened, and the tie-break for both.
  final Hlc hlc;

  /// What happened. A dotted name such as `stock.bottle.consumed`.
  ///
  /// Deliberately an open string rather than an enum. Two versions of the app
  /// will meet during a sync, and the older one must carry the newer one's
  /// events across without understanding them. A closed set would force the
  /// older build to either invent a mapping or drop the event, and dropping an
  /// event in an op-log means losing a real operation -- a bottle that was
  /// drunk, a price that was paid.
  final String type;

  /// The payload, as JSON-safe values.
  ///
  /// Unmodifiable because a log of operations is only as trustworthy as the
  /// operations in it: handing out a mutable map would let a caller rewrite an
  /// event after it had been appended.
  final Map<String, Object?> data;

  /// Reads a payload field, or throws if it is missing or the wrong type.
  ///
  /// The strictness is the point. A payload that has drifted is a bug worth
  /// surfacing, and a default value here would turn it into a plausible wrong
  /// number in a stock ledger.
  T require<T>(String key) {
    final value = data[key];
    if (value is T) return value;
    throw FormatException(
      'event $type: field "$key" is ${value.runtimeType}, expected $T',
    );
  }

  /// The same, for fields a payload may legitimately leave out.
  T? optional<T>(String key) {
    final value = data[key];
    if (value == null) return null;
    // The cast is explicit because Dart will not promote a value to a type
    // parameter when the return type is itself nullable -- `T` might already
    // include null, which makes the narrowing unsound. The `is` check above it
    // is what keeps the cast safe.
    if (value is T) return value as T;
    throw FormatException(
      'event $type: field "$key" is ${value.runtimeType}, expected $T',
    );
  }

  Map<String, Object?> toJson() => {
    'hlc': hlc.toJson(),
    'type': type,
    'data': data,
  };

  factory Event.fromJson(Map<String, Object?> json) {
    final hlc = json['hlc'];
    final type = json['type'];
    final data = json['data'];
    if (hlc is! Map<String, Object?>) {
      throw FormatException('event without a readable clock: $json');
    }
    if (type is! String || type.isEmpty) {
      throw FormatException('event without a type: $json');
    }
    if (data is! Map<String, Object?>) {
      throw FormatException('event $type without a payload object: $json');
    }
    return Event(hlc: Hlc.fromJson(hlc), type: type, data: data);
  }

  /// The event as one line of the log, without its terminator.
  ///
  /// Compact rather than pretty: an audit log that a human can read is worth
  /// something, but a year of mixing is thousands of lines and each one is read
  /// on every startup.
  String encode() => jsonEncode(toJson());

  /// Parses one line of the log.
  ///
  /// Throws [FormatException] on anything malformed. The store decides what to
  /// do about a bad line -- this layer only refuses to guess.
  static Event decode(String line) {
    final decoded = jsonDecode(line);
    if (decoded is! Map<String, Object?>) {
      throw FormatException('log line is not a JSON object: $line');
    }
    return Event.fromJson(decoded);
  }

  @override
  String toString() => '${hlc.toString()} $type ${jsonEncode(data)}';

  /// Events are equal when everything about them is equal, which for a
  /// correctly behaving device means the clock alone settles it.
  @override
  bool operator ==(Object other) =>
      other is Event && other.hlc == hlc && other.type == type &&
      _dataEquals(other.data, data);

  @override
  int get hashCode => Object.hash(hlc, type, jsonEncode(data));

  static bool _dataEquals(Map<String, Object?> a, Map<String, Object?> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      if (jsonEncode(a[key]) != jsonEncode(b[key])) return false;
    }
    return true;
  }
}
