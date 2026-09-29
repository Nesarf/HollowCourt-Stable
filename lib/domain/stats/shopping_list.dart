import '../model/recipe.dart';

/// What to buy, given what the reader plans to make and what the cellar holds.
///
/// **The plan is the overlay's, and this fold is what makes it useful.** A recipe marked
/// `计划做` is a statement about a person, so it lives in section 8's overlay beside their
/// notes rather than in the seed; this is the fold that turns a set of those marks into a
/// list of things to buy. No storage was invented for it -- `OverlayKey.recipe(id, 'plan')`
/// is a field on a key that already existed.
///
/// **An ingredient appears once with a count, not once per recipe.** Two planned drinks that
/// both need gin are one line saying gin, twice, because that is what a shopping list is
/// for: a person buys one bottle. The count is what tells them whether it matters.
final class ShoppingList {
  const ShoppingList._(
    this.entries, {
    required this.plannedRecipes,
    required this.missingRecipes,
  });

  /// Builds the list from a library, the ids a reader has planned, and what is on the shelf.
  ///
  /// [have] is a predicate rather than a set of ids, because what "have" means is the
  /// cellar's business: `Cellar.has` is the join between a recipe item and a bottle's sku,
  /// and a fold that took a `Set<String>` would be re-deciding that join here.
  factory ShoppingList.of({
    required Iterable<Recipe> recipes,
    required Set<String> plannedRecipeIds,
    required bool Function(String ingredientId) have,
  }) {
    final byId = {for (final recipe in recipes) recipe.id: recipe};
    final needed = <String, int>{};
    final planned = <String>[];
    final missing = <String>[];

    for (final id in plannedRecipeIds) {
      final recipe = byId[id];
      if (recipe == null) {
        // A planned recipe the library does not hold. Counted rather than dropped silently:
        // it happens when a seed changes under a reader's plan, and a list that quietly
        // shrank would look like the plan had been forgotten instead of like the library
        // having moved.
        missing.add(id);
        continue;
      }
      planned.add(id);
      for (final item in recipe.items) {
        if (have(item.ingredientId)) continue;
        needed[item.ingredientId] = (needed[item.ingredientId] ?? 0) + 1;
      }
    }

    final entries = [
      for (final entry in needed.entries)
        ShoppingEntry(ingredientId: entry.key, neededBy: entry.value),
    ]..sort((a, b) {
      // Most-needed first, and ties broken by id so the order does not depend on map
      // iteration. The same rule the shelf and the statistics fold apply, for the same
      // reason: a list that reshuffles between two identical reads looks like it changed.
      final byCount = b.neededBy.compareTo(a.neededBy);
      if (byCount != 0) return byCount;
      return a.ingredientId.compareTo(b.ingredientId);
    });

    // Sorted BEFORE being wrapped, and the first version got this wrong in a way worth
    // keeping: `List.unmodifiable(planned)..sort()` parses as `(List.unmodifiable(planned))
    // ..sort()`, so the cascade applies to the unmodifiable WRAPPER rather than to the list
    // inside it, and every call threw `Cannot modify an unmodifiable list`.
    planned.sort();
    missing.sort();

    return ShoppingList._(
      List.unmodifiable(entries),
      plannedRecipes: List.unmodifiable(planned),
      missingRecipes: List.unmodifiable(missing),
    );
  }

  /// One line per ingredient to buy, ordered.
  final List<ShoppingEntry> entries;

  /// The planned recipes the library could resolve, sorted.
  final List<String> plannedRecipes;

  /// Planned ids the library does not hold, sorted.
  final List<String> missingRecipes;

  /// Whether there is nothing to buy.
  ///
  /// **True for two different situations and it is worth knowing which**: nothing planned,
  /// and everything planned is already on the shelf. A screen that said "nothing to buy"
  /// without saying which would be ambiguous exactly when a reader is checking whether their
  /// plan took.
  bool get isEmpty => entries.isEmpty;

  /// Whether anything is planned at all.
  bool get hasPlans => plannedRecipes.isNotEmpty || missingRecipes.isNotEmpty;

  @override
  String toString() =>
      'ShoppingList(${entries.length} to buy from ${plannedRecipes.length} planned)';
}

/// One thing to buy, and how many of the planned drinks want it.
final class ShoppingEntry {
  const ShoppingEntry({required this.ingredientId, required this.neededBy});

  /// The canonical ingredient id, which is what a bottle's sku matches on.
  final String ingredientId;

  /// How many planned recipes name it.
  final int neededBy;

  @override
  bool operator ==(Object other) =>
      other is ShoppingEntry &&
      other.ingredientId == ingredientId &&
      other.neededBy == neededBy;

  @override
  int get hashCode => Object.hash(ingredientId, neededBy);

  @override
  String toString() => '$ingredientId x$neededBy';
}
