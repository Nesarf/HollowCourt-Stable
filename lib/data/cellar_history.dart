import 'dart:io';

import '../domain/events/event.dart';
import 'archive_package.dart';

/// **The events of a cellar, from the working log and from the packages the reader selected.**
///
/// ## Why the two are not folded separately
///
/// Every projection in this application -- the stock, the overlay, the arrangement, the recipes, the ingredients, the
/// collections, the packs -- sorts its events by clock and applies them in that order. **So history cannot be folded in
/// two halves and combined**: a bottle added in a package and poured in the log would fold as a pour of nothing
/// followed by an unopened bottle. **The two have to be merged and *then* folded**, exactly as a merge from a peer
/// already is.
///
/// That is why this returns events rather than a folded state, and why it is the only thing a caller needs: the
/// existing folds do not change at all.
///
/// ## What the reader selected is what is read
///
/// `docs/archival.md`, and it is the owner's decision: **no package is read unless it was chosen.** A package the
/// reader deleted is simply not in the list, so **nothing has to notice and no history changes behind their back** --
/// which is the property a retention horizon cannot have, because a horizon is a guess about devices that have gone
/// away and it is wrong exactly when somebody finds an old phone.
final class CellarHistory {
  const CellarHistory({required this.logEvents, required this.archived, required this.packages});

  final List<Event> logEvents;

  /// The events that came out of packages, in clock order.
  final List<Event> archived;

  /// What was read, for a screen that has to say which packages are in play.
  final List<ArchivePackage> packages;

  /// **Everything, in clock order** -- what a fold is given.
  ///
  /// A merge rather than a concatenation: the log's events and a package's interleave by clock, and the whole point of
  /// the format is that the order is decided by the readings rather than by which file an event happened to be in.
  List<Event> get all {
    final merged = [...archived, ...logEvents]..sort((a, b) => a.hlc.compareTo(b.hlc));
    return merged;
  }

  bool get hasArchives => packages.isNotEmpty;

  /// How many events came from packages, for a count a screen can show.
  int get archivedCount => archived.length;

  /// Reads the packages [files] name and merges them with [logEvents].
  ///
  /// **[files] is the reader's selection and nothing else.** An empty selection is an ordinary state -- a cellar whose
  /// history fits in the log -- and is not an error.
  ///
  /// **A package that cannot be read is skipped rather than fatal.** It is one file out of several, it may be damaged
  /// or written by a newer build, and **refusing to open the cellar because one ancient archive is unreadable would
  /// trade the reader's whole library for a part of its history.** What it must not do is skip *silently*, so the
  /// unreadable ones come back beside the readable ones.
  static Future<CellarHistory> read({
    required List<Event> logEvents,
    required Iterable<File> files,
  }) async {
    final packages = <ArchivePackage>[];
    final events = <Event>[];
    for (final file in files) {
      try {
        final package = await ArchivePackage.read(file);
        packages.add(package);
        events.addAll(package.events);
      } on Object {
        // Skipped, and reported as a count rather than hidden -- see the note above. A screen that wants to say which
        // one can read the file list itself.
        continue;
      }
    }
    return CellarHistory(logEvents: logEvents, archived: events, packages: packages);
  }
}
