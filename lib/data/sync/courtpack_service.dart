import 'dart:io';

import '../../domain/events/hlc.dart';
import '../../domain/sync/courtpack.dart';
import '../event_log.dart';

/// **The carrier that needs no network at all: a file.**
///
/// `.courtpack` was written, tested by nobody and called from nowhere, which made it a design with an
/// implementation rather than a feature. This is the half that makes it usable: writing one out of a cellar's
/// log, and reading one back in.
///
/// ## Why a file, when there is a socket
///
/// Because the socket needs two devices on **one reachable network**, and a great many of the places somebody
/// would want to move a cellar are exactly where that is not true: a hotel wireless with client isolation, a
/// phone that has been offline for a week, a desktop and a laptop that are never switched on at the same time,
/// or two buildings. A pack travels on a USB stick, in a chat message, on a share -- and it is the only carrier
/// in this application that works when nothing else does.
///
/// ## What a pack is, and what it is not
///
/// **It is not a backup and it is not trusted.** The header carries a count and a hash of the body, so a pack
/// that was truncated in transit or altered by hand is refused rather than half-imported; the header also
/// carries who wrote it and when, and **nothing proves that** -- a pack says what it says. What protects the
/// reader is the same thing that protects them over the network: the events themselves are the log's own
/// records, and an import is a *merge* into that log rather than a replacement of it. Merging is additive
/// where the log's semantics are additive and ordered by HLC where they are not, which is 10.4's rule and is
/// why a pack can be imported twice, or from three devices in any order, without inventing stock.
///
/// ## Files rather than a picker
///
/// The application has no file-picker plugin, and adding one for this would be a platform dependency on three
/// targets to open a dialog. So an export writes into a directory the reader can find (`[directory]`, which the
/// screen passes as the documents directory) under a name that says what it is, and an import **scans that same
/// directory**: copy the pack beside the others on the machine that needs it, and it appears in the list.
/// Clumsier than a dialog and honest about why -- and it works on every target without a plugin.
final class CourtPackService {
  const CourtPackService();

  /// The extension every pack carries, so a scan can find them and a reader can recognise one.
  static const String extension = '.courtpack';

  /// **Writes the whole log into a pack.** Returns the file, which the screen shows the path of.
  ///
  /// [theirClocks] is empty for an export, which is what makes it the *whole* cellar: `missingFrom` answers
  /// "what do they not have", and a pack for somebody who has nothing is everything.
  Future<File> write(
    EventLog log, {
    required String directory,
    required String source,
    String fingerprint = '',
    String shelfId = '',
    Set<Hlc> theirClocks = const {},
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final events = log.missingFrom(theirClocks);
    final text = CourtPack.encode(
      source: source,
      fingerprint: fingerprint,
      shelfId: shelfId,
      exportedAtMillis: at.millisecondsSinceEpoch,
      events: events,
    );

    final dir = Directory(directory);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final file = File('${dir.path}${Platform.pathSeparator}${_name(at, source)}$extension');
    await file.writeAsString(text, flush: true);
    return file;
  }

  /// A name that sorts by time and says whose cellar it is, because a directory of packs is otherwise a
  /// directory of identical-looking names.
  String _name(DateTime at, String source) {
    String two(int value) => value.toString().padLeft(2, '0');
    final safe = source.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '-');
    return 'hollow-court-${at.year}${two(at.month)}${two(at.day)}'
        '-${two(at.hour)}${two(at.minute)}-${safe.isEmpty ? 'device' : safe}';
  }

  /// **Reads a pack and merges it into the log**, returning what happened.
  ///
  /// A refusal comes back as a [CourtPackImport] with its [CourtPackProblem] rather than as an exception: a
  /// file that arrived damaged is a normal thing to meet, and the screen has to say which of the four reasons
  /// it was -- a pack from a newer version is a different sentence from one that was truncated.
  Future<CourtPackImport> read(File file, EventLog log) async {
    final String text;
    try {
      text = await file.readAsString();
    } on Object catch (error) {
      return CourtPackImport.refused(CourtPackProblem.notAPack, detail: '$error');
    }

    final read = CourtPack.read(text);
    if (read.problem != null) {
      return CourtPackImport.refused(
        read.problem!,
        detail: read.problem == CourtPackProblem.damaged
            ? '${read.found} events, header promised ${read.expected}'
            : '',
      );
    }

    // **A merge, never a replacement.** Doing this twice imports nothing the second time, because the log
    // already holds those clocks -- which is what makes a pack safe to import from somebody who is unsure
    // whether they already did.
    final applied = await log.merge(read.events);
    return CourtPackImport.merged(
      header: read.header,
      applied: applied.length,
      offered: read.events.length,
    );
  }

  /// The packs sitting in [directory], newest first -- what the screen lists.
  List<File> find(String directory) {
    final dir = Directory(directory);
    if (!dir.existsSync()) return const [];
    final files = dir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith(extension))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    return files;
  }
}

/// What an import did, or why it did not.
final class CourtPackImport {
  const CourtPackImport.merged({
    required this.header,
    required this.applied,
    required this.offered,
  }) : problem = null,
       detail = '';

  const CourtPackImport.refused(CourtPackProblem this.problem, {this.detail = ''})
    : header = null,
      applied = 0,
      offered = 0;

  /// Null when the pack was refused.
  final CourtPackHeader? header;

  /// How many events the pack carried, and how many were new to this log. **They differ, and the difference is
  /// the interesting number**: importing a pack this device already has applies nothing, which is a success
  /// rather than a no-op to hide.
  final int offered;
  final int applied;

  final CourtPackProblem? problem;
  final String detail;

  bool get ok => problem == null;
}

/// The four reasons a pack is refused, in the words the screen uses.
///
/// Kept beside the import because they are the same vocabulary: `CourtPackProblem` is the domain's name for
/// what went wrong, and this is how a reader hears it.
String describePackProblem(CourtPackProblem problem) => switch (problem) {
  CourtPackProblem.notAPack => 'this file is not a 空庭 pack',
  CourtPackProblem.tooNew => 'this pack was written by a newer version of the application',
  CourtPackProblem.truncated => 'this pack is missing its end -- it was cut short in transit',
  CourtPackProblem.damaged => 'this pack arrived damaged: the events do not match the count or the hash',
  CourtPackProblem.altered => 'this pack was altered after it was written',
};
