import 'dart:convert';

import 'event.dart';
import 'hlc.dart';

/// The event type names for packs the reader defined.
///
/// **The sixth family of user-written operations**, after the overlay, the stock ledger, the collections and the
/// authored recipes and ingredients -- and the one `docs/proposal-recipes-and-packs.md` §1 puts *first* in its order
/// of work: *"Folders (`packId`) become real, and the user defines them."*
///
/// **What a pack is**: *where a recipe came from*, so it is a thing the reader owns rather than an enum in the code.
/// A recipe already carries a `packId`; what was missing is that the pack itself had no record, so the reader's own
/// name for a folder lived in `folder_styles.json` -- **a file beside the cellar rather than in the log**, which is
/// why renaming a folder has never travelled to another device while everything else does.
///
/// **A whole record, like a recipe and an ingredient.** A pack is a small structure, and "rename" events would let a
/// device that missed one fold to a folder nobody described.
abstract final class CourtPackEvent {
  /// A pack was defined, or replaced wholesale.
  static const set = 'pack.set';

  /// A pack the reader defined was removed.
  ///
  /// **Only ever their own.** `official` ships with the build, and this event naming it is a payload the fold refuses
  /// rather than a way to delete something out of the library.
  static const removed = 'pack.removed';

  static const all = {set, removed};
}

/// Why a pack could not be defined.
sealed class PackProblem {
  const PackProblem();
}

/// The name was empty, or only spaces.
final class PackUnnamed extends PackProblem {
  const PackUnnamed();
}

/// The id belongs to a pack that ships with the build.
final class PackIsBuiltIn extends PackProblem {
  const PackIsBuiltIn(this.id);

  final String id;
}

/// The id a pack the build ships carries, and which cannot be deleted.
///
/// **One constant rather than a per-pack flag the reader could set**, because "this came with the application" is a
/// fact about the build and not a property somebody chooses. The proposal writes it as `builtIn: false` beside
/// `official` being `true`; the id is what actually decides, so it is the id that is checked.
const officialPackId = 'official';

/// A pack the reader defined, as the log carries it.
///
/// **Carries what `FolderStyle` carried, and exactly that.** The proposal's record is
/// `id / name / note / accent / order / builtIn`, and the first five are what the separate style file already held --
/// so this is a migration as much as a new feature, and `FolderStyle` is what it replaces rather than something it
/// sits beside. Two records of the same name is the duplication `docs/ingredient-gap.md` spent a step removing.
final class CourtPack {
  const CourtPack({
    required this.id,
    required this.name,
    this.note,
    this.accent,
    this.order,
  });

  final String id;

  /// The reader's own words, in their own language.
  final String name;

  /// Free text, optional.
  final String? note;

  /// `#RRGGBB`, so a folder can look like itself.
  final String? accent;

  /// Where it sits among the folders. Null means the derived order stands.
  final int? order;

  /// Whether this ships with the build.
  bool get isBuiltIn => id == officialPackId;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    if (note != null) 'note': note,
    if (accent != null) 'accent': accent,
    if (order != null) 'order': order,
  };

  static CourtPack fromJson(Map<String, Object?> json) => CourtPack(
    id: json['id']! as String,
    name: json['name']! as String,
    note: json['note'] as String?,
    accent: json['accent'] as String?,
    order: (json['order'] as num?)?.toInt(),
  );
}

/// Checks a pack, returning everything wrong with it.
List<PackProblem> validatePack(CourtPack pack) {
  final problems = <PackProblem>[];
  if (pack.name.trim().isEmpty) problems.add(const PackUnnamed());
  if (pack.isBuiltIn) problems.add(const PackIsBuiltIn(officialPackId));
  return problems;
}

/// A pack operation read off the log.
final class CourtPackOp {
  const CourtPackOp({required this.hlc, required this.pack});

  final Hlc hlc;

  /// The pack as written. Null for [CourtPackEvent.removed], which carries only an id.
  final CourtPack? pack;

  static CourtPackOp? tryParse(Event event) {
    if (!CourtPackEvent.all.contains(event.type)) return null;
    return switch (event.type) {
      CourtPackEvent.set => CourtPackOp(
        hlc: event.hlc,
        pack: CourtPack.fromJson(
          jsonDecode(event.require<String>('pack')) as Map<String, Object?>,
        ),
      ),
      CourtPackEvent.removed => CourtPackOp(hlc: event.hlc, pack: null),
      _ => null,
    };
  }

  static String? removedId(Event event) {
    if (event.type != CourtPackEvent.removed) return null;
    return event.require<String>('id');
  }
}

abstract final class CourtPackEvents {
  /// Defines a pack, whole.
  static Event set({required Hlc hlc, required CourtPack pack}) =>
      Event(hlc: hlc, type: CourtPackEvent.set, data: {'pack': jsonEncode(pack.toJson())});

  /// Removes a pack the reader defined.
  ///
  /// **Refused for `official`**, so no caller can take the shipped pack out of the library by getting an argument
  /// wrong -- the guard is here rather than in a screen, which is the same place the ingredient and recipe removals
  /// put theirs.
  static Event removed({required Hlc hlc, required String id}) {
    if (id == officialPackId) {
      throw ArgumentError.value(
        id,
        'id',
        'the official pack ships with the build and cannot be removed',
      );
    }
    return Event(hlc: hlc, type: CourtPackEvent.removed, data: {'id': id});
  }
}
