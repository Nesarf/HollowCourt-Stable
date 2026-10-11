/// How many recipes call for each ingredient -- stage ② of `docs/catalogue-and-stock.md`.
///
/// **The measurement this exists for**, from `docs/ingredient-gap.md`: of the library's 189 ingredients, 33 are
/// called for by four or more recipes, 31 by two or three, 57 by exactly one, and **68 by none at all.** The reason
/// is that the library was derived *from* the 103 recipes and the derivation kept every item of every drink -- so
/// about a third of the catalogue serves nothing, and no screen has ever told a reader which third that is.
///
/// **A count derived on every read rather than a stored field.** The number is a function of the recipes, so storing
/// it would only be a second copy of a fact that already exists -- and `docs/log-compaction.md`'s rule applies to
/// anything of the kind. What falls out of deriving it is better than the saving: a reader who writes a recipe
/// calling for one of the 68 moves it out of [DemandClass.dead] the moment they save it, and there is nothing to
/// invalidate and no cache to go stale.
///
/// **It is not a score and it does not rank the reader's own taste.** A recipe is evidence that somebody wanted the
/// thing, and 103 drinks written by an authority is a great deal of evidence; the point of putting it in front of a
/// reader is that *"68 of these are not your responsibility"* is information they cannot get today, and it is what
/// makes a long list stop reading like a backlog.
final class IngredientDemand {
  const IngredientDemand._(this._counts);

  /// [recipes] is **one list of ingredient ids per recipe** -- ids rather than recipes, so that this does not have
  /// to know the seed's record shape or the reader's; the two differ and neither belongs here.
  factory IngredientDemand.of(Iterable<Iterable<String>> recipes) {
    final counts = <String, int>{};
    for (final recipe in recipes) {
      // **Each recipe counts once per ingredient, not once per line.** A drink that names the same modifier twice
      // -- which the reader's own editor permits -- is still *one drink* that wants it, and counting lines would
      // make a drink a heavier piece of evidence for a duplicate than for a mention.
      for (final id in recipe.toSet()) {
        counts[id] = (counts[id] ?? 0) + 1;
      }
    }
    return IngredientDemand._(counts);
  }

  /// Nothing is used by anything: what a screen built before the recipes loaded should see, and what an empty
  /// catalogue honestly is.
  static const none = IngredientDemand._(<String, int>{});

  final Map<String, int> _counts;

  /// The recipes that call for this ingredient, or zero -- an ingredient nothing names is the ordinary case here
  /// rather than an error, which is the whole finding.
  int countOf(String ingredientId) => _counts[ingredientId] ?? 0;

  DemandClass classOf(String ingredientId) => DemandClass.of(countOf(ingredientId));

  /// How many ingredients fall in each class, over [ids].
  ///
  /// **[ids] is passed in rather than taken from the counts**, because the two are different sets: the counts cover
  /// every ingredient any recipe names, and a screen is listing the ones it actually draws. Counting the map would
  /// report a class the reader cannot see.
  Map<DemandClass, int> histogramOf(Iterable<String> ids) {
    final out = <DemandClass, int>{};
    for (final id in ids) {
      final bucket = classOf(id);
      out[bucket] = (out[bucket] ?? 0) + 1;
    }
    return out;
  }
}

/// The four classes, in the order a reader should meet them -- most wanted first, and the dead last.
///
/// **Four rather than ABC's three**, because the measurement has four buckets and two of them are genuinely
/// different things: *called for by one recipe* is a real ingredient that happens to be in one drink, and *called
/// for by nothing* is a record the library kept because the derivation kept everything. Merging them -- which is
/// what "ABC" would do, treating both as class C -- would hide exactly the number this stage exists to show.
enum DemandClass {
  /// Four or more recipes. 33 of the library's 189, measured 2026-10-01.
  core,

  /// Two or three. 31 of them.
  occasional,

  /// Exactly one. 57 of them.
  rare,

  /// **None at all. 68 of them -- 36% of the catalogue.** The class this stage is for.
  dead;

  static DemandClass of(int recipes) => switch (recipes) {
    >= 4 => core,
    2 || 3 => occasional,
    1 => rare,
    _ => dead,
  };
}
