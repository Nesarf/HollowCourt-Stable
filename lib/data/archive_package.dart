import 'dart:convert';
import 'dart:io';


import '../../domain/archive/archive_manifest.dart';
import '../../domain/events/event.dart';

// **Re-exported, so a caller that reaches for the container also gets the vocabulary it speaks in**, and so that
// moving the manifest and the error into the domain cost no import at any call site.
export '../../domain/archive/archive_manifest.dart';

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

