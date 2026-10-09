import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../data/archive_package.dart';

/// Where a reader's archives live: **in their own documents directory, beside `.courtpack` files.**
///
/// The same rule everything else a reader owns follows -- `cellar.ndjson`, `display.json`, the packages themselves --
/// and it is the rule that makes the promise true. **An archive is a data file rather than an application file**, and
/// that is exactly why "for ever" is a promise this project can keep: it does not depend on this build, on a protocol,
/// or on this application existing in five years.
final archivesDirectoryProvider = FutureProvider<Directory>((Ref ref) async {
  final documents = await getApplicationDocumentsDirectory();
  return Directory('${documents.path}${Platform.pathSeparator}archives');
});

/// **Every package the reader has, as the list a screen shows.**
///
/// ## Why a package is read rather than merely listed
///
/// A name says a range and says nothing about whether the file is intact. **Reading the manifest is what lets the list
/// say how many events and which years**, and it is also the only moment the digest is checked -- so a damaged package
/// is found when the reader is looking at the list rather than when they have already attached it and are wondering
/// why a chart looks short.
///
/// **A package that cannot be read is still listed, with its reason.** Dropping it would be the silent failure this
/// project keeps meeting: a file the reader can see in their directory and not in the application, with nothing to
/// explain the difference.
final archiveCatalogProvider = FutureProvider<List<ArchiveEntry>>((Ref ref) async {
  final directory = await ref.watch(archivesDirectoryProvider.future);
  if (!await directory.exists()) return const [];

  final files = await directory
      .list()
      .where((entry) => entry is File && entry.path.endsWith('.courtarchive'))
      .cast<File>()
      .toList();
  // **Oldest first**, so the list reads like the history it holds rather than like a directory listing.
  files.sort((a, b) => a.path.compareTo(b.path));

  final entries = <ArchiveEntry>[];
  for (final file in files) {
    entries.add(await ArchiveEntry.of(file));
  }
  return entries;
});

/// One package as a list shows it: what it is, or why it cannot be read.
final class ArchiveEntry {
  const ArchiveEntry({required this.file, this.package, this.problem});

  final File file;

  /// The package, when it could be read.
  final ArchivePackage? package;

  /// Why it could not be, when it could not. **Never null when [package] is null**, so a list always has something to
  /// say about a row.
  final String? problem;

  /// Whether this entry can be selected at all -- **an unreadable package can be seen and not attached**, which is the
  /// honest state: the reader is told the file is there and that this build cannot use it.
  bool get isUsable => package != null;

  String get fileName => file.uri.pathSegments.last;

  /// How many events it holds, or null when unknown.
  int? get count => package?.manifest.count;

  static Future<ArchiveEntry> of(File file) async {
    try {
      return ArchiveEntry(file: file, package: await ArchivePackage.read(file));
    } on ArchiveUnreadable catch (error) {
      return ArchiveEntry(file: file, problem: error.reason);
    } on Object catch (error) {
      // A file that is not readable at all -- permissions, a vanished directory -- is a problem like any other rather
      // than a reason to fail the whole list.
      return ArchiveEntry(file: file, problem: '$error');
    }
  }
}

/// **Which packages the reader has attached.**
///
/// `docs/archival.md`, and it is the owner's decision: **no archive is read unless it was chosen.** That is what makes
/// the consequences safe -- **a package the reader deletes is simply not in the list**, so nothing has to notice and no
/// history changes behind their back, which is the property a retention horizon cannot have.
///
/// **In memory rather than on disk, and that is deliberate.** It is a choice about what to *look at*, not a setting
/// about the cellar: a reader who wants to see ten years of price history selects the packages for the session, and a
/// reader who does not is never asked. Persisting it would turn "I am looking at old history" into a state they have to
/// remember they are in -- and the failure of forgetting is a screen that silently means something different from what
/// they think. **If it turns out to be worth persisting, that is a decision to take with the annoyance in hand.**
class ArchiveSelection extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void toggle(String fileName) => state = state.contains(fileName)
      ? ({...state}..remove(fileName))
      : {...state, fileName};

  /// **Everything, or nothing** -- the owner asked for both of these by name.
  void selectAll(Iterable<String> names) => state = {...names};

  /// **The inverse of what is selected**, which is what the owner asked for and what select-all alone cannot do: a
  /// reader with twenty packages who wants all but one should not have to tick nineteen.
  void invert(Iterable<String> names) {
    final all = names.toSet();
    state = all.difference(state);
  }

  void clear() => state = const {};
}

final archiveSelectionProvider = NotifierProvider<ArchiveSelection, Set<String>>(
  ArchiveSelection.new,
);
