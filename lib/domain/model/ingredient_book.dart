import '../events/event.dart';
import '../events/ingredient_authoring.dart';
import 'ingredient_category.dart';

/// The ingredients the reader added, folded from the log.
///
/// **The fold that makes an added ingredient real.** The event family says what one looks like on disk; this says
/// what a set of those events *means*, which is what a screen needs in order to show somebody the ingredient they
/// typed -- and what the rest of the application needs in order to resolve its name.
///
/// **Why this is a fold and not an edit to the catalogue.** `SeedRepository` is read from an asset and is the same
/// on every install; its indexes (`ingredientById`, `recipesUsing`) are built once at load. An ingredient the reader
/// adds is an *event*, so it merges, it replays and it survives a restart -- and keeping it out of the catalogue is
/// what stops a reader's own additions from being shipped to anybody else.
///
/// **The two are asked in one place**, though, because a name has to resolve for both: `resolve` below answers for
/// either, and it is the only thing a screen should call.
final class IngredientBook {
  const IngredientBook(this.ingredients);

  final Map<String, AuthoredIngredient> ingredients;

  static const IngredientBook none = IngredientBook({});

  bool get isEmpty => ingredients.isEmpty;
  int get length => ingredients.length;

  /// The reader's ingredients, in the order they were written.
  List<AuthoredIngredient> get all => ingredients.values.toList(growable: false);

  AuthoredIngredient? operator [](String id) => ingredients[id];

  /// Whether [id] names an ingredient the reader added.
  ///
  /// **The question a screen asks before offering to delete one**, and the question `validateAuthored` asks when it
  /// decides whether a recipe line is resolvable.
  bool isMine(String id) => ingredients.containsKey(id);

  /// The category of [id], as the enum this build carries, or null.
  ///
  /// **Null for a name this build does not know**, which is the case a newer build's ingredient produces. Returning
  /// a nearest match would silently reclassify somebody's record, and the same reasoning is written into the
  /// recipe's `method` and `unit` handling.
  IngredientCategory? categoryOf(String id) {
    final named = ingredients[id]?.category;
    if (named == null || named.isEmpty) return null;
    for (final category in IngredientCategory.values) {
      if (category.name == named) return category;
    }
    return null;
  }

  /// Folds every authored-ingredient event in [events].
  ///
  /// **Sorted by clock rather than read in file order**, the rule every fold here follows: a merged log holds a
  /// peer's events interleaved with local ones, and a write that replaced an ingredient has to be applied after the
  /// write it replaced however the arrivals happened to land. Two devices folding the same set therefore agree.
  factory IngredientBook.of(Iterable<Event> events) {
    final ordered = events
        .where((event) => IngredientAuthoredEvent.all.contains(event.type))
        .toList()
      ..sort((a, b) => a.hlc.compareTo(b.hlc));

    final out = <String, AuthoredIngredient>{};
    for (final event in ordered) {
      if (event.type == IngredientAuthoredEvent.removed) {
        // A removal of something never seen is not an error: it is what a device that has just been sent a deletion
        // sees, and the fold's answer -- that this ingredient is not held -- is right either way.
        final id = IngredientAuthoredOp.removedId(event);
        if (id != null) out.remove(id);
        continue;
      }
      if (event.type != IngredientAuthoredEvent.set) continue;
      final ingredient = IngredientAuthoredOp.tryParse(event)?.ingredient;
      // A malformed payload of a known type throws inside `tryParse` rather than arriving null, so null here means
      // the event was not one of ours after all -- skipped rather than guessed at.
      if (ingredient == null) continue;
      out[ingredient.id] = ingredient;
    }
    return IngredientBook(out);
  }
}
