/// What an ingredient is, from section 4.2.
///
/// The section calls its list two-layer, and the second layer is the one worth
/// modelling carefully: of the twenty-seven names it gives, **three are not
/// categories of substance at all**. `Items You Can Make`, `The Modern Bar` and
/// `Top 25 Most Used` are browse groupings -- the section itself annotates them
/// as "makeable at home", "preset configurations" and "frequency". An ingredient
/// does not *become* a different thing by being popular.
///
/// So they are in the enum, because a stock screen has to offer them, and they
/// answer [isBrowseGrouping] rather than pretending to be a kind of gin. Code
/// that means "what is this made of" filters on [isSubstance]; code that builds
/// a picker does not filter at all.
/// **A way of finding an ingredient, and no longer a kind of one.**
///
/// This enum used to carry twenty-seven *substances* as well -- whiskey, gin, citrus, syrups and so on -- beside the
/// three groupings below. **Those are gone, retired on 2026-10-01 to `Ingredient.kind` and `Ingredient.family`**,
/// which is the two-level shape `docs/proposal-recipes-and-packs.md` §3 asks for and which
/// `docs/ingredient-gap.md` measured the need for.
///
/// **Why the split rather than a rename.** The twenty-seven were a closed list in a build, covering 47 of 189
/// ingredients, and **nothing read them**: `isSubstance`, `isBrowseGrouping` and `isAlcoholic` had no callers, no
/// screen grouped or filtered by category, and the field travelled from the seed to the model to the codec without
/// deciding anything. The 189 now each carry a `kind`, and the kinds are *data* -- so a reader can add 茶 or 酊剂
/// the way they add a collection, which a closed enum could not allow without a build.
///
/// **These three are left because they are a different kind of thing**, and this file already argued it: an
/// ingredient does not *become* a different thing by being popular or by being makeable at home, so they are not
/// kinds of substance at all. They are ways a choice screen can cut the list, and that is a real affordance rather
/// than a classification -- which is exactly why they could not be folded into `kind` with the rest.
enum IngredientCategory {
  /// **Grouped by what can be made at home.** How several sections of the library present themselves.
  itemsYouCanMake,

  /// **The source's presets**: the drinks it groups as its own furniture.
  theModernBar,

  /// **Grouped by how often a thing is used.** A frequency, which is not a property of the ingredient.
  top25MostUsed;

  /// True, and kept as a named answer rather than a comment.
  ///
  /// **Every member of this enum is now a grouping**, which is the guarantee the split bought: the old enum mixed
  /// twenty-seven substances with three groupings and carried `isSubstance` to tell them apart, so a caller that
  /// meant "what is this made of" had to remember to filter. There is nothing left to filter -- a caller that wants
  /// what a thing is made of reads `Ingredient.kind`.
  bool get isBrowseGrouping => true;
}

/// Whether a bucket holds alcohol, and -- for the enum above -- whether it is a classification at all.
///
/// **Kept because `SourceBucket` still needs it.** `IngredientCategory` has no use for the distinction now that
/// every one of its members is a grouping; the six source buckets are still three-to-three, and the caveat below
/// is still worth carrying.
enum Level { alcoholic, nonAlcoholic, grouping }

/// Which of one source's six buckets an ingredient was filed under.
///
/// Kept as provenance rather than as a category, because the two do not line
/// up and pretending otherwise would be the exact mistake section 18 warns
/// about. one source files vermouth under `Beers & Wines` and Angostura under
/// `Mixers & Soft Drinks`; both are defensible, neither is section 4.2.
///
/// What *is* reliable is the level, and only that. `Spirits`, `Liqueurs` and
/// `Beers & Wines` are alcoholic; `Mixers & Soft Drinks`, `Fruits & Juices` and
/// `Staples` are not -- with the caveat that one source's own recipes put Angostura
/// bitters in a non-alcoholic bucket, so even the level is a claim about the
/// bucket rather than about the bottle.
enum SourceBucket {
  spirits('Spirits', Level.alcoholic),
  liqueurs('Liqueurs', Level.alcoholic),
  beersAndWines('Beers & Wines', Level.alcoholic),
  mixersAndSoftDrinks('Mixers & Soft Drinks', Level.nonAlcoholic),
  fruitsAndJuices('Fruits & Juices', Level.nonAlcoholic),
  staples('Staples', Level.nonAlcoholic);

  const SourceBucket(this.sourceName, this.level);

  final String sourceName;
  final Level level;

  static SourceBucket? fromSource(String raw) {
    final key = raw.trim().toLowerCase();
    for (final bucket in SourceBucket.values) {
      if (bucket.sourceName.toLowerCase() == key) return bucket;
    }
    return null;
  }
}
