import 'dart:convert';
import 'dart:io';

import 'package:cryptography/dart.dart';

import '../../domain/events/event.dart';

/// **The container an archival lands in, and the manifest that makes it self-describing.**
///
/// ## What this is for
///
/// `docs/archival.md` settles what compaction is here: **not deletion but a move.** Events older than the grain leave
/// the working log and arrive in a file the reader owns, under `Documents/`, so **the log shrinks while the history
/// stays complete.**
///
/// **That dissolves the obstacle rather than solving it.** `EventLog.missingFrom` decides what to send by clock
/// identity, so *dropping* a reading would make a peer that still holds it indistinguishable from one that does not --
/// a stale write invisible to both sides. **Moving a reading keeps it in the world**, in a file, where it can be found
/// again.
///
/// ## Why a container rather than a bare `.ndjson`
///
/// The owner asked for a manifest, and the reason is that **a file of events cannot describe itself.** Which clock
/// range does it hold? How many events? Which device wrote it, and when? Is it complete, or was it interrupted? A
/// bare list of lines answers none of those, and a reader five years from now has no other place to ask.
///
/// **What is inside is deliberately unchanged.** The container is new; `events.ndjson` is **the same
/// line-delimited JSON the log is written in**, so the promise that a reader can verify the file without trusting
/// this application still holds: they open it, and the lines are the lines.
///
/// ## `.courtarchive`, not `.courtpack`
///
/// The two mean different things and `Documents/` holds both kinds. **A `.courtpack` is imported** -- its events
/// merge into the log. **An archive is read beside it.** A reader who confused them would delete their history
/// believing they were restoring it, which is why the suffix and the manifest both say which one this is.
final class ArchivePackage {
  const ArchivePackage({
    required this.first,
    required this.last,
    required this.events,
    required this.manifest,
  });

  /// The events this package holds, in clock order.
  final List<Event> events;

  /// The clock readings at each end of [events], which is what the manifest records and what a screen lists.
  final String first;
  final String last;

  final ArchiveManifest manifest;

  /// The file name a package of this range is called by.
  ///
  /// **Named after its range rather than a sequence number**, because a reader looking at a directory should be able
  /// to tell what is inside without opening anything -- and because two archives made on two devices must not collide
  /// on `0001`.
  String get fileName {
    final safeFirst = first.replaceAll(RegExp(r'[^0-9A-Za-z]'), '');
    final safeLast = last.replaceAll(RegExp(r'[^0-9A-Za-z]'), '');
    return 'cellar-archive-$safeFirst-$safeLast.courtarchive';
  }

  /// Writes the package, **to a temporary name and then renamed.**
  ///
  /// The same shape `identity_store.dart` uses for the device key, and for the same reason: a reader must never find
  /// a half-written archive, because **a package is the thing they are meant to be able to trust in five years.** A
  /// crash during the write leaves nothing under the real name rather than something that looks like an archive.
  Future<File> writeTo(Directory directory) async {
    await directory.create(recursive: true);
    final target = File('${directory.path}${Platform.pathSeparator}$fileName');
    final temporary = File('${target.path}.writing');
    final sink = temporary.openWrite();
    try {
      sink.writeln(jsonEncode({'manifest': manifest.toJson()}));
      for (final event in events) {
        sink.writeln(jsonEncode(event.toJson()));
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    return temporary.rename(target.path);
  }

  /// Reads a package back, or throws when the file is not one.
  ///
  /// **The manifest is verified against the events**, and a mismatch is refused rather than tolerated: a package whose
  /// digest does not match its own lines has been damaged or edited, and **silently reading it would put events into
  /// a projection that the manifest says are not there.** That is the failure shape this project keeps meeting, and
  /// an archive is the worst place for it -- it is the file nobody will ever check by hand.
  static Future<ArchivePackage> read(File file) async {
    final lines = await file.readAsLines();
    if (lines.isEmpty) throw ArchiveUnreadable(file.path, 'the file is empty');

    final Object? decoded;
    try {
      decoded = jsonDecode(lines.first);
    } on FormatException catch (error) {
      throw ArchiveUnreadable(file.path, 'the first line is not JSON: $error');
    }
    if (decoded is! Map<String, Object?> || decoded['manifest'] is! Map) {
      throw ArchiveUnreadable(file.path, 'the first line carries no manifest');
    }
    final manifest = ArchiveManifest.fromJson(
      Map<String, Object?>.from(decoded['manifest']! as Map),
    );

    final events = <Event>[];
    for (var i = 1; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim().isEmpty) continue;
      try {
        events.add(Event.fromJson(jsonDecode(line) as Map<String, Object?>));
      } on Object catch (error) {
        throw ArchiveUnreadable(file.path, 'line ${i + 1} is not an event: $error');
      }
    }

    if (events.length != manifest.count) {
      throw ArchiveUnreadable(
        file.path,
        'the manifest says ${manifest.count} events and the file holds ${events.length}',
      );
    }
    if (ArchiveManifest.digestOf(events) != manifest.digest) {
      throw ArchiveUnreadable(
        file.path,
        'the events do not match the manifest digest, so this package has been damaged or edited',
      );
    }
    return ArchivePackage(
      events: events,
      first: events.isEmpty ? '' : events.first.hlc.toString(),
      last: events.isEmpty ? '' : events.last.hlc.toString(),
      manifest: manifest,
    );
  }
}

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
