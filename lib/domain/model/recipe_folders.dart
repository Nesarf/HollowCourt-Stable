import 'recipe.dart';

/// **Recipes grouped into folders, the way a notes application groups notebooks.**
///
/// The owner's request on 2026-09-22: *"把IBA单开一个配方列（也就是参考小米笔记的类型，做文件夹）"* -- the IBA
/// list gets its own place rather than being mixed into one long alphabetical column, and the shape of that
/// place is a folder you open.
///
/// **A folder is derived, never stored.** Nothing here is written into the log or the library: the grouping
/// is a reading of `extras['source']` and `extras['category']`, which the drinks already carry (`iba` /
/// `The Unforgettables`, `iba` / `Contemporary Classics`, …). That matters for two reasons -- a recipe that
/// gains a category needs no migration, and a reader's own drink (once the application can author them)
/// lands in its own folder without anybody deciding where folders come from.
final class RecipeFolder {
  const RecipeFolder({
    required this.source,
    required this.category,
    required this.recipes,
  });

  /// Who the drinks came from: `iba`, or empty for a drink with no stated source.
  final String source;

  /// The group inside that source: `The Unforgettables`, `Contemporary Classics`, `New Era`.
  final String category;

  final List<Recipe> recipes;

  int get count => recipes.length;

  /// **What the folder is called on screen.** The category alone when the source has only one folder's worth
  /// of drinks to show, and `source · category` otherwise -- because a screen whose every row began with
  /// "iba" would be a screen where the interesting word is in the middle.
  String get label => category.isEmpty ? source : category;

  /// The key that identifies it, stable across renames of either part.
  String get key => '$source/$category';

  /// True for the drinks that came from the IBA's official list -- the folder the owner asked for by name.
  bool get isOfficial => source == 'iba';

  @override
  String toString() => '$label ($count)';
}

/// The recipes, folded into folders.
///
/// Ordering, and it is a decision rather than an accident:
///
/// 1. **The official list first**, because it is the reference and the reader is most likely to be looking
///    for a drink they have heard of;
/// 2. then other sources alphabetically, so a second collection does not appear above the first by luck;
/// 3. inside a source, the categories in the order they were written -- which for the IBA is its own
///    (The Unforgettables, Contemporary Classics, New Era) and is why the category string is kept verbatim
///    rather than sorted;
/// 4. and inside a folder, by name, which is what the flat list already did.
///
/// **A drink with no source is not dropped.** It lands in a folder of its own called by its source-or-nothing,
/// because a grouping that silently hid a recipe would be worse than a folder called "other".
List<RecipeFolder> foldersOf(Iterable<Recipe> recipes) {
  final byKey = <String, List<Recipe>>{};
  final order = <String>[];

  for (final recipe in recipes) {
    final source = (recipe.extras['source'] ?? '').toString();
    final category = (recipe.extras['category'] ?? '').toString();
    final key = '$source/$category';
    if (!byKey.containsKey(key)) {
      byKey[key] = [];
      order.add(key);
    }
    byKey[key]!.add(recipe);
  }

  final folders = <RecipeFolder>[];
  // The official source first, then the rest by name. `order` keeps the categories inside a source in the
  // order the data declared them, which is the order the drinks were written in.
  final sources = <String>{for (final key in order) key.split('/').first};
  final sortedSources = sources.toList()
    ..sort((a, b) {
      if (a == 'iba' || b == 'iba') return a == 'iba' ? -1 : 1;
      return a.compareTo(b);
    });

  for (final source in sortedSources) {
    for (final key in order.where((k) => k.split('/').first == source)) {
      final recipes = byKey[key]!..sort((a, b) => a.name.compareTo(b.name));
      folders.add(
        RecipeFolder(
          source: source,
          category: key.split('/').skip(1).join('/'),
          recipes: recipes,
        ),
      );
    }
  }
  return folders;
}
