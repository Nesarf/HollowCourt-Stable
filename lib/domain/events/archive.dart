import 'event.dart';
import 'hlc.dart';

/// The event an archival leaves behind in the working log.
///
/// **`docs/archival.md`, and the owner's decision of 2026-10-08.** Compaction here is not deletion but a move: events
/// older than the grain leave the log and arrive in a package the reader owns. **Something has to stay behind**, or
/// the log cannot tell *"this is all there ever was"* from *"there is more, in a file"* -- and those two look
/// identical on a screen showing a consumption curve.
///
/// **An ordinary event, and that is deliberate rather than convenient.** It syncs with everything else, so a device
/// that was never told about an archival learns of it the same way it learns of anything -- and a device that has the
/// package can say so, while one that does not can ask for it. A marker kept outside the log would be a second kind of
/// truth about the same history.
abstract final class ArchiveEvent {
  /// An archival happened: the log up to a reading is now in a package.
  static const made = 'archive.made';

  static const all = {made};
}

/// What an archival recorded, as the log carries it.
///
/// **It names the package rather than describing it.** The count and the range are in the package's own manifest, which
/// is the file that has to be trusted anyway; copying them here would be a second record of the same facts, and the two
/// could disagree -- which is the duplication `docs/ingredient-gap.md` spent a step removing in the ingredient
/// taxonomy.
final class ArchiveOp {
  const ArchiveOp({
    required this.hlc,
    required this.packageName,
    required this.throughClock,
    required this.count,
  });

  final Hlc hlc;

  /// The file the events went to, as it is named in the reader's directory.
  final String packageName;

  /// The last reading that left. **Everything at or before this is in the package**, which is what makes the marker
  /// usable for a reader asking "do I have the whole history".
  final String throughClock;

  /// How many events left, said here as well as in the manifest **because a screen wants to say it without opening
  /// the file** -- and a count that disagreed with the manifest would be a real fault rather than a redundancy, which
  /// is exactly what makes it worth having.
  final int count;

  static ArchiveOp? tryParse(Event event) {
    if (!ArchiveEvent.all.contains(event.type)) return null;
    if (event.type == ArchiveEvent.made) {
      return ArchiveOp(
        hlc: event.hlc,
        packageName: event.require<String>('package'),
        throughClock: event.require<String>('through'),
        count: int.parse(event.require<String>('count')),
      );
    }
    return null;
  }
}

abstract final class ArchiveEvents {
  /// Records that a range of events left the log for a package.
  ///
  /// **Written before the package is considered real**, which is the order `docs/archival.md` asks for: a crash
  /// between the two leaves a log naming an archive that is not there -- visible and recoverable -- rather than a
  /// package nothing knows about.
  static Event made({
    required Hlc hlc,
    required String packageName,
    required String throughClock,
    required int count,
  }) => Event(
    hlc: hlc,
    type: ArchiveEvent.made,
    data: {
      // **Every value a string**, which is what `Event.data` carries and what `require<String>` reads back. The count
      // is the one that would be tempting to store as a number, and doing so would make `tryParse` fail on an event
      // this build wrote itself.
      'package': packageName,
      'through': throughClock,
      'count': count.toString(),
    },
  );
}
