import 'dart:io';

import '../domain/events/archive.dart';
import '../domain/events/event.dart';
import '../domain/events/hlc.dart';
import 'archive_package.dart';
import 'event_log.dart';

/// **Takes the oldest events out of the working log and puts them in a package the reader owns.**
///
/// `docs/archival.md`: compaction here is a move rather than a deletion, so **nothing is lost and the log gets
/// smaller.** The obstacle that made true deletion unacceptable -- `EventLog.missingFrom` deciding by clock identity,
/// so a dropped reading makes a peer that still holds it indistinguishable from one that does not -- **never arises,
/// because no reading is dropped.**
///
/// ## The grain, and why it is this number
///
/// **Five years**, by the owner's decision. `price_period.dart` reads **120 monthly candles -- ten years** -- so a
/// five-year grain **never cuts a window in half**: the widest view spans two packages and both of them exist. A
/// shorter grain would mean a reader attaching archives and still seeing a truncated chart, which is the
/// silent-failure shape this project keeps meeting.
///
/// ## What it does, in order
///
/// 1. Finds the cut: the first event at or after `now - grain`. **Everything before it goes.**
/// 2. Writes the package under the reader's documents directory.
/// 3. **Then** records the marker event, so a crash between (2) and (3) leaves a package nothing knows about rather
///    than a log naming an archive that is not there -- **the second is visible and the first is not, and a visible
///    inconsistency is the one a reader can act on.**
///
/// ## What it refuses to do
///
/// **Nothing is deleted from the working log here.** That is a separate and harder operation -- it means rewriting the
/// file, which the torn-tail reader and the append-only format are built around -- and it is not needed for the
/// promise: the reader's history is complete the moment the package exists and the log says so. **Removing the moved
/// events from the log is a second step, and it should be taken only once this one is proven in use.**
final class ArchivalService {
  const ArchivalService({required this.log, required this.packagesDirectory});

  final EventLog log;

  /// Where the packages go. The reader's own directory, beside the cellar log and the `.courtpack` files.
  final Directory packagesDirectory;

  /// The grain: **five years**, and see the class documentation for why the number is not arbitrary.
  static const Duration grain = Duration(days: 365 * 5 + 1);

  /// What an archival would take, or null when there is nothing old enough.
  ///
  /// **A dry run, and it exists so a screen can say what will happen before it happens.** A reader being asked to
  /// archive is being asked to accept a file they will have to look after, and "N events up to X" is the least a
  /// prompt can tell them.
  Future<ArchiveProposal?> propose({required int nowMillis}) async {
    final cutoff = nowMillis - grain.inMilliseconds;
    final events = log.events;
    // **The cut is the first event at or after the cutoff**, so everything strictly before it leaves. Cutting *at* an
    // event rather than between two would either drop that event or duplicate it, and which one depended on a
    // comparison nobody would remember.
    var cut = 0;
    while (cut < events.length && events[cut].hlc.physicalMillis < cutoff) {
      cut++;
    }
    if (cut == 0) return null;
    final moving = events.take(cut).toList(growable: false);
    return ArchiveProposal(
      events: moving,
      throughClock: moving.last.hlc.toString(),
      cutoffMillis: cutoff,
    );
  }

  /// Archives what [propose] described: writes the package, then records the marker.
  ///
  /// Returns the file it wrote, or null when there was nothing to do. **Throws if the package cannot be written**,
  /// because a marker naming a package that is not there is the one outcome this ordering exists to avoid.
  Future<File?> archive({required int nowMillis, required String nodeId}) async {
    final proposal = await propose(nowMillis: nowMillis);
    if (proposal == null) return null;

    final package = ArchivePackage(
      events: proposal.events,
      first: proposal.events.first.hlc.toString(),
      last: proposal.throughClock,
      manifest: ArchiveManifest(
        format: ArchiveManifest.formatVersion,
        createdMillis: nowMillis,
        firstClock: proposal.events.first.hlc.toString(),
        lastClock: proposal.throughClock,
        count: proposal.events.length,
        nodeId: nodeId,
        digest: ArchiveManifest.digestOf(proposal.events),
      ),
    );
    final file = await package.writeTo(packagesDirectory);

    // **The marker is written only after the file exists.** The other order would let a crash leave a log claiming an
    // archive that is not on disk -- and a reader who believed it would stop looking.
    await log.record(
      (hlc) => ArchiveEvents.made(
        hlc: hlc,
        packageName: package.fileName,
        throughClock: proposal.throughClock,
        count: proposal.events.length,
      ),
    );
    return file;
  }
}

/// What an archival would take, as a screen needs to describe it.
final class ArchiveProposal {
  const ArchiveProposal({
    required this.events,
    required this.throughClock,
    required this.cutoffMillis,
  });

  final List<Event> events;

  /// The last reading that would leave, which is what the marker will name.
  final String throughClock;

  /// The instant the grain drew the line at.
  final int cutoffMillis;

  int get count => events.length;
  Hlc? get firstClock => events.isEmpty ? null : events.first.hlc;
  Hlc? get lastClock => events.isEmpty ? null : events.last.hlc;
}
