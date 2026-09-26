import '../../domain/model/ingredient.dart';
import '../../domain/model/recipe.dart';
import 'seed_codec.dart';

/// One problem found while validating the loaded seed.
final class SeedProblem {
  const SeedProblem({
    required this.kind,
    required this.id,
    required this.problems,
  });

  /// `ingredient` or `recipe`.
  final String kind;
  final String id;
  final List<String> problems;

  @override
  String toString() => '$kind $id: ${problems.join("; ")}';
}

/// The seed as the rest of the app sees it: ingredients, recipes, and lookups.
///
/// **No file system, no asset bundle, no path.** The repository is built from a
/// string or from lists, and where that string came from is the caller's
/// decision -- the app loads it from wherever it ships, a test passes a literal,
/// and the library file is written by hand for the drinks we ship. That
/// is what keeps the loading path testable, and it is the same split the event
/// log uses between what it stores and how it is reached.
final class SeedRepository {
  SeedRepository._({
    required this.ingredients,
    required this.recipes,
    required this.formatVersion,
  })  : _ingredientsById = {for (final i in ingredients) i.id: i},
        _recipesById = {for (final r in recipes) r.id: r},
        _recipesByIngredient = _indexByIngredient(recipes);

  /// The reverse index, built once.
  ///
  /// A static method rather than a closure in the initializer list, which Dart
  /// does not allow -- and a method is the better home for it anyway, because
  /// this is the one piece of real work the constructor does.
  static Map<String, List<Recipe>> _indexByIngredient(List<Recipe> recipes) {
    final index = <String, List<Recipe>>{};
    for (final recipe in recipes) {
      for (final item in recipe.items) {
        index.putIfAbsent(item.ingredientId, () => []).add(recipe);
      }
    }
    return index;
  }

  /// Reads a seed document.
  ///
  /// Throws [SeedFormatException] when the document is not one this build can
  /// read, which is a different failure from a seed with problems in it: this
  /// one means nothing was loaded, and the caller has no repository at all.
  factory SeedRepository.fromJson(String source) {
    final decoded = SeedCodec.decode(source);
    return SeedRepository.of(
      ingredients: decoded.ingredients,
      recipes: decoded.recipes,
    );
  }

  /// Builds a repository from objects already in hand.
  factory SeedRepository.of({
    required List<Ingredient> ingredients,
    required List<Recipe> recipes,
  }) => SeedRepository._(
    ingredients: ingredients,
    recipes: recipes,
    formatVersion: SeedCodec.formatVersion,
  );

  final List<Ingredient> ingredients;
  final List<Recipe> recipes;
  final int formatVersion;

  final Map<String, Ingredient> _ingredientsById;
  final Map<String, Recipe> _recipesById;
  final Map<String, List<Recipe>> _recipesByIngredient;

  String toJson({bool pretty = false}) => SeedCodec.encode(
    ingredients: ingredients,
    recipes: recipes,
    pretty: pretty,
  );

  Ingredient? ingredientById(String id) => _ingredientsById[id];
  Recipe? recipeById(String id) => _recipesById[id];

  /// The recipes that call for [ingredientId], in seed order.
  ///
  /// This is the question a shelf asks: I have just entered a bottle of this,
  /// what can it be used for? The index is built once when the repository is,
  /// because the alternative is scanning every recipe every time somebody types
  /// a name.
  List<Recipe> recipesUsing(String ingredientId) =>
      List.unmodifiable(_recipesByIngredient[ingredientId] ?? const []);

  /// Names that more than one recipe carries, with the recipes that carry them.
  ///
  /// **This is section 15's "pending merge and deduplication", measured, and
  /// the measurement says not to merge.** 71 of the 502 recipes share a name
  /// across the two sources -- 71 out of another source's 88 -- and of those 71 pairs
  /// **only one has identical ingredient lines.** The other 70 are different
  /// formulas: mostly the same drink measured in different units (`Alexander`
  /// is one ounce of each in one source and thirty millilitres in the other),
  /// but sometimes genuinely different recipes. `Aviation` uses maraschino
  /// liqueur in one and cherry liqueur in the other; `Barracuda` has four lines
  /// in one and seven in the other; `Bellini` is built on peach in one and
  /// peach purée in the other.
  ///
  /// So a name is not an identity, and deduplicating by name would delete 70
  /// recipes that somebody wrote down on purpose. What the overlap calls for is
  /// **grouping rather than merging** -- showing both formulas under one drink
  /// and letting a person pick -- and that is a decision for the screen, not for
  /// the importer. Meanwhile the number is here so it cannot be forgotten.
  ///
  /// The key folds case, punctuation and a trailing `IBA`, because the two
  /// sources spell the same drink `Daiquiri, IBA` and `Daiquiri`.
  Map<String, List<Recipe>> nameCollisions() {
    final groups = <String, List<Recipe>>{};
    for (final recipe in recipes) {
      groups.putIfAbsent(_nameKey(recipe.name), () => []).add(recipe);
    }
    return Map<String, List<Recipe>>.unmodifiable({
      for (final entry in groups.entries)
        if (entry.value.length > 1) entry.key: List<Recipe>.unmodifiable(entry.value),
    });
  }

  static String _nameKey(String name) => name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '')
      .replaceAll(RegExp(r'iba$'), '');

  /// Every problem `validate()` reports, ingredient by ingredient.
  ///
  /// **Assembled at load rather than stored in the artifact.** A seed that
  /// carried its own problem list would be a seed whose problems go stale the
  /// moment either the data or the validator changes; recomputing costs a pass
  /// over 502 recipes once, and the answer is then always about the code that
  /// is running.
  List<SeedProblem> validate() {
    final problems = <SeedProblem>[];
    for (final ingredient in ingredients) {
      final found = ingredient.validate();
      if (found.isNotEmpty) {
        problems.add(SeedProblem(
          kind: 'ingredient',
          id: ingredient.id,
          problems: found,
        ));
      }
    }
    for (final recipe in recipes) {
      final found = recipe.validate();
      if (found.isNotEmpty) {
        problems.add(SeedProblem(kind: 'recipe', id: recipe.id, problems: found));
      }
    }
    return problems;
  }

  /// Ingredient ids a recipe points at that the seed does not carry.
  ///
  /// Reported rather than assumed empty: an assembled seed reaches zero here,
  /// and a hand-edited one may not, in which case the shelf has a line it
  /// cannot offer a bottle for.
  List<String> get danglingIngredientIds {
    final missing = <String>{};
    for (final recipe in recipes) {
      for (final item in recipe.items) {
        if (!_ingredientsById.containsKey(item.ingredientId)) {
          missing.add(item.ingredientId);
        }
      }
    }
    return missing.toList()..sort();
  }

  Map<String, int> get stats => {
    'ingredients': ingredients.length,
    'recipes': recipes.length,
    'items': recipes.fold(0, (sum, r) => sum + r.items.length),
    'distinct ingredients used':
        _recipesByIngredient.keys.length,
    'dangling ingredient ids': danglingIngredientIds.length,
    'problems': validate().length,
  };
}
