import 'dart:convert';

import 'event.dart';
import 'hlc.dart';

/// The event type names for ingredients the reader added.
///
/// **The fifth family of user-written operations**, after the overlay, the stock ledger, the collections and the
/// authored recipes -- and the one that makes `docs/proposal-recipes-and-packs.md` §3 possible. That section's point
/// is that the shipped catalogue cannot be the whole of anybody's shelf: a reader who keeps something the library
/// has never heard of can write a bottle of it, price it, pour it, and file it in the wrong category for ever.
///
/// **A whole record, like a recipe.** An ingredient is a small structure rather than a field, and "change the name"
/// events would let a device that missed one fold to an ingredient nobody described. The same argument the
/// collections and the recipes each make.
abstract final class IngredientAuthoredEvent {
  /// An ingredient was added, or replaced wholesale.
  static const set = 'ingredient.authored.set';

  /// An ingredient the reader added was removed.
  ///
  /// **Only ever their own.** The catalogue is part of the build, and this event naming a shipped id is a payload
  /// the fold refuses rather than a way to delete something out of the library.
  static const removed = 'ingredient.authored.removed';

  static const all = {set, removed};
}

/// Why an ingredient could not be added.
sealed class IngredientProblem {
  const IngredientProblem();
}

/// The name was empty, or only spaces.
final class IngredientUnnamed extends IngredientProblem {
  const IngredientUnnamed();
}

/// An id that belongs to the shipped catalogue rather than to the reader.
///
/// **The guard that keeps `removed` from meaning "delete anything".** A reader's ingredients carry an `own.` prefix
/// (see [AuthoredIngredientId]) and the library's do not, so an id without it is refused here rather than at the
/// point where somebody's bottle quietly loses its name.
final class IngredientIdNotMine extends IngredientProblem {
  const IngredientIdNotMine(this.id);

  final String id;
}

/// The reader's own ingredients carry this prefix, so a collision with the catalogue is impossible.
///
/// The same device `AuthoredRecipeId` uses and for the same reason: the catalogue's ids are of the form
/// `ginPlymouth` and `juiceLime`, and anything beginning `own.` came from somebody at a keyboard. A collision would
/// let one record overwrite the other, which looks like a save that did not work.
abstract final class AuthoredIngredientId {
  static const prefix = 'own.';

  static bool isMine(String id) => id.startsWith(prefix);

  /// A stable id derived from the name and a clock reading.
  ///
  /// **Not random**, for the reason the recipes give: an id derived from the same inputs is one that two devices
  /// which saw the same edit agree on, and `Hlc` already carries a wall clock and a counter. The name is folded in
  /// so that two ingredients made in the same millisecond do not compete, and sanitised so that the result is
  /// usable in a filename and a URL.
  static String from(String name, Hlc hlc) {
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return '$prefix${slug.isEmpty ? 'ingredient' : slug}-${hlc.physicalMillis}-${hlc.counter}';
  }
}

/// An ingredient the reader described, as the log carries it.
///
/// **A separate class from the domain's `Ingredient`, and deliberately narrower.** The model carries alcohol by
/// volume, sugar per litre, density, bottle sizes and a source bucket; a person adding "the plum wine my neighbour
/// makes" knows none of those, and a form that asked would be asking them to guess numbers that feed the arithmetic
/// in section 5. What is carried is what somebody can actually state: what it is called, what it is, what else it is
/// called, and a note. **The rest stays absent rather than defaulted**, which is the same rule the seed follows for
/// the 139 ingredients whose category nobody recorded.
final class AuthoredIngredient {
  const AuthoredIngredient({
    required this.id,
    required this.name,
    this.category,
    this.aliases = const [],
    this.note,
  });

  final String id;
  final String name;

  /// The catalogue category, by name, or null when the reader did not say.
  ///
  /// **A string rather than the enum.** `IngredientCategory` is a closed list in this build, and an ingredient
  /// written by a newer one naming a category this build does not carry has to be readable rather than rejected --
  /// the same reasoning the recipe's `method` follows.
  final String? category;

  final List<String> aliases;
  final String? note;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    if (category != null) 'category': category,
    if (aliases.isNotEmpty) 'aliases': aliases,
    if (note != null) 'note': note,
  };

  static AuthoredIngredient fromJson(Map<String, Object?> json) => AuthoredIngredient(
    id: json['id']! as String,
    name: json['name']! as String,
    category: json['category'] as String?,
    aliases: [
      for (final a in (json['aliases'] as List<Object?>? ?? const []))
        if (a is String) a,
    ],
    note: json['note'] as String?,
  );
}

/// Checks an ingredient against the rules above, returning everything wrong with it.
///
/// A list rather than the first problem, so a form can say all of it at once -- the shape `validateAuthored` uses for
/// recipes and `Rating.validate` before it.
List<IngredientProblem> validateAuthoredIngredient(
  AuthoredIngredient ingredient, {
  required Set<String> existingIds,
}) {
  final problems = <IngredientProblem>[];
  if (ingredient.name.trim().isEmpty) problems.add(const IngredientUnnamed());
  if (!AuthoredIngredientId.isMine(ingredient.id)) {
    problems.add(IngredientIdNotMine(ingredient.id));
  }
  return problems;
}

/// An ingredient operation read off the log.
final class IngredientAuthoredOp {
  const IngredientAuthoredOp({required this.hlc, required this.ingredient});

  final Hlc hlc;

  /// The ingredient as written. Null for [IngredientAuthoredEvent.removed], which carries only an id.
  final AuthoredIngredient? ingredient;

  /// Reads an op off an event, or returns null when this is not one of ours.
  ///
  /// **An event of a type this build does not know is a peer from a future version and is carried untouched**, so
  /// "not mine" is ordinary. **A malformed payload of a type this build does know throws** through `Event.require` --
  /// that is drift, and drift is worth surfacing.
  static IngredientAuthoredOp? tryParse(Event event) {
    if (!IngredientAuthoredEvent.all.contains(event.type)) return null;
    return switch (event.type) {
      IngredientAuthoredEvent.set => IngredientAuthoredOp(
        hlc: event.hlc,
        ingredient: AuthoredIngredient.fromJson(
          jsonDecode(event.require<String>('ingredient')) as Map<String, Object?>,
        ),
      ),
      IngredientAuthoredEvent.removed => IngredientAuthoredOp(
        hlc: event.hlc,
        ingredient: null,
      ),
      _ => null,
    };
  }

  /// The id a removal names, or null when this is not a removal.
  static String? removedId(Event event) {
    if (event.type != IngredientAuthoredEvent.removed) return null;
    return event.require<String>('id');
  }
}

abstract final class IngredientAuthoredEvents {
  /// Writes an ingredient, whole.
  static Event set({required Hlc hlc, required AuthoredIngredient ingredient}) => Event(
    hlc: hlc,
    type: IngredientAuthoredEvent.set,
    data: {'ingredient': jsonEncode(ingredient.toJson())},
  );

  /// Removes an ingredient the reader added.
  static Event removed({required Hlc hlc, required String id}) {
    if (!AuthoredIngredientId.isMine(id)) {
      throw ArgumentError.value(
        id,
        'id',
        'only an ingredient the reader added can be removed; the catalogue is part of the build',
      );
    }
    return Event(hlc: hlc, type: IngredientAuthoredEvent.removed, data: {'id': id});
  }
}
