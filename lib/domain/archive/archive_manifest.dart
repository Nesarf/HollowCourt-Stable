import 'dart:convert';

import 'package:cryptography/dart.dart';

import '../events/event.dart';

/// **What a package says about itself**, and the error a file that is not one raises.
///
/// **These live in the domain rather than beside the file I/O**, and moving them is what lets the sync protocol speak
/// about an archive at all: `lib/domain/sync/wire.dart` may not import `lib/data/`, and a segment announced over the
/// wire has to carry **the whole manifest** rather than a summary of it.
///
/// **Why the whole manifest and not a summary, which is a defect that was built and then found.** The first version of
/// the announcement carried `{digest, count, first, last}` -- enough to *identify* a package and not enough to
/// *receive* one. A receiver writes the package it is given, and a manifest needs `createdMillis` and `nodeId` as
/// well: **when the package was made, and which device made it.** A receiver that reconstructed those would be
/// writing "made on this machine, just now" about a file made on somebody else's a month ago -- and the manifest is
/// the one thing in this project that is supposed to still be true in five years.
///
/// `archive_package.dart` re-exports both, so every existing import still resolves.

/// What a package says about itself.
///
/// **Every field is here to answer a question a reader would otherwise have to guess**, and `version` is the one that
/// lets a future build refuse a package it does not understand rather than half-read it -- the rule
/// `CourtPack.version` already follows.
final class ArchiveManifest {
  const ArchiveManifest({
    required this.format,
    required this.createdMillis,
    required this.firstClock,
    required this.lastClock,
    required this.count,
    required this.nodeId,
    required this.digest,
  });

  /// The format this package was written in. **A newer one is refused rather than half-read.**
  static const int formatVersion = 1;

  /// The version this package claims, read out of its manifest.
  ///
  /// **A field as well as the constant above**, because a *reader* holds a number that came from a file and may not be
  /// the one this build writes -- and the first thing it does with it is compare. A single constant could not express
  /// that, and the comparison is the whole reason the number is stored.
  final int format;

  final int createdMillis;
  final String firstClock;
  final String lastClock;
  final int count;
  final String nodeId;

  /// A digest over the events, so damage or an edit is detectable.
  final String digest;

  Map<String, Object?> toJson() => {
    'version': formatVersion,
    'createdMillis': createdMillis,
    'firstClock': firstClock,
    'lastClock': lastClock,
    'count': count,
    'nodeId': nodeId,
    'digest': digest,
  };

  /// **[A gap closed 2026-10-11.]** This is a value -- seven fields that describe a file -- and it had no equality,
  /// so two manifests read out of the same bytes compared as different objects. Nothing depended on it until the sync
  /// protocol began announcing manifests, and a test that asserted *the peer announced the package I hold* could not
  /// be written without it. **A value type without equality is a type that tells you where you got it rather than
  /// what it says.**
  @override
  bool operator ==(Object other) =>
      other is ArchiveManifest &&
      other.format == format &&
      other.createdMillis == createdMillis &&
      other.firstClock == firstClock &&
      other.lastClock == lastClock &&
      other.count == count &&
      other.nodeId == nodeId &&
      other.digest == digest;

  @override
  int get hashCode =>
      Object.hash(format, createdMillis, firstClock, lastClock, count, nodeId, digest);

  /// **Every field, because a `toString` that omits one makes a failed equality unreadable.** The first version of
  /// this left `createdMillis` out and a test comparing two manifests printed
  /// `Expected: ArchiveManifest(abc, 2 events, a..b, by them)` against
  /// `Actual:   ArchiveManifest(abc, 2 events, a..b, by them)` -- identical on screen, different in fact, and the
  /// difference was the one field not shown.
  @override
  String toString() =>
      'ArchiveManifest($digest, $count events, $firstClock..$lastClock, by $nodeId, made $createdMillis)';

  static ArchiveManifest fromJson(Map<String, Object?> json) {
    final version = (json['version'] as num?)?.toInt();
    if (version != ArchiveManifest.formatVersion) {
      throw ArchiveUnreadable(
        '',
        'this package is format version $version and this build writes '
        '${ArchiveManifest.formatVersion}',
      );
    }
    return ArchiveManifest(
      format: version!,
      createdMillis: (json['createdMillis'] as num?)?.toInt() ?? 0,
      firstClock: json['firstClock'] as String? ?? '',
      lastClock: json['lastClock'] as String? ?? '',
      count: (json['count'] as num?)?.toInt() ?? 0,
      nodeId: json['nodeId'] as String? ?? '',
      digest: json['digest'] as String? ?? '',
    );
  }

  /// A stable digest over the events, so two runs over the same events agree.
  ///
  /// **Over the encoded lines rather than the objects**, because the digest has to survive a round trip through the
  /// file: what is hashed is exactly what is stored, so a reader can recompute it from the bytes they have.
  ///
  /// **`DartSha256` rather than `Sha256`**, the same choice `device_identity.dart` makes for the fingerprint and for
  /// the same reason: it hashes synchronously, and this runs while a fold is being built.
  static String digestOf(Iterable<Event> events) {
    final buffer = StringBuffer();
    for (final event in events) {
      buffer.writeln(jsonEncode(event.toJson()));
    }
    return const DartSha256().hashSync(utf8.encode(buffer.toString())).toString();
  }
}

/// Raised when a file is not a readable archive.
///
/// **A separate type rather than a null**, because "this is not an archive" and "there are no archives" are different
/// answers and a screen has to be able to say which happened.
final class ArchiveUnreadable implements Exception {
  const ArchiveUnreadable(this.path, this.reason);

  final String path;
  final String reason;

  @override
  String toString() => 'the archive at $path cannot be read: $reason';
}
