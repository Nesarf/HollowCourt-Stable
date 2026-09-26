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
enum IngredientCategory {
  // ---- alcoholic --------------------------------------------------------
  whiskey(Level.alcoholic),
  gin(Level.alcoholic),
  rum(Level.alcoholic),
  tequilaAndMezcal(Level.alcoholic),
  vodkaAndSimilar(Level.alcoholic),
  brandy(Level.alcoholic),
  beerAndCider(Level.alcoholic),
  wine(Level.alcoholic),
  commonLiqueurs(Level.alcoholic),
  vermouth(Level.alcoholic),
  portAndSherry(Level.alcoholic),
  aperitifs(Level.alcoholic),
  commonAmaro(Level.alcoholic),
  commonBitters(Level.alcoholic),

  // ---- non-alcoholic ----------------------------------------------------
  citrus(Level.nonAlcoholic),
  juices(Level.nonAlcoholic),
  fruitAndVeg(Level.nonAlcoholic),
  syrups(Level.nonAlcoholic),
  jamsAndPreserves(Level.nonAlcoholic),
  herbsAndSpices(Level.nonAlcoholic),
  sodas(Level.nonAlcoholic),
  pantryItems(Level.nonAlcoholic),
  groceryItems(Level.nonAlcoholic),
  mockSpirits(Level.nonAlcoholic),

  // ---- groupings, not substances ----------------------------------------
  itemsYouCanMake(Level.grouping),
  theModernBar(Level.grouping),
  top25MostUsed(Level.grouping);

  const IngredientCategory(this.level);

  final Level level;

  /// True when this says what the ingredient is made of.
  bool get isSubstance => level != Level.grouping;

  /// True when this is a way of finding an ingredient rather than a kind of one.
  bool get isBrowseGrouping => level == Level.grouping;

  /// True when the ingredient carries alcohol.
  bool get isAlcoholic => level == Level.alcoholic;

  /// Reads a name from a document, or returns null.
  ///
  /// Section 4.2 is written in prose with spaces, ampersands and parentheses,
  /// so the matching is on a normalised key. The ampersand becomes `and` rather
  /// than being deleted: `Fruit & Veg` has to land on [fruitAndVeg], and simply
  /// stripping non-letters would turn it into `fruitveg` and miss.
  static IngredientCategory? fromSource(String raw) {
    final key = _normalise(raw);
    if (key.isEmpty) return null;
    return _byKey[key];
  }

  static String _normalise(String raw) => raw
      .trim()
      .toLowerCase()
      .replaceAll('&', 'and')
      .replaceAll(RegExp(r'[^a-z]'), '');

  static final Map<String, IngredientCategory> _byKey = {
    for (final category in IngredientCategory.values)
      _normalise(category.name): category,

    // Spellings the design document uses that normalise to something the enum
    // identifier does not. Each is a name section 4.2 actually writes.
    'whisky': whiskey, // Whisk(e)y
    'rhum': rum, // R(h)um
  };
}

/// The top layer of section 4.2.
///
/// Three values rather than two, because the section's own annotations force
/// the distinction: a browse grouping is neither alcoholic nor non-alcoholic,
/// and squeezing `Top 25 Most Used` into one of those would be false whichever
/// one it was put in.
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
