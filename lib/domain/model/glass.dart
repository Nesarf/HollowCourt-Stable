/// The glass a drink is served in.
///
/// This began as section 12.1's list of seven -- the shapes the liquid-colour
/// renderer knows how to draw -- and is now **eight**, because reading the two
/// sources showed that seven cannot name the drinks they contain.
///
/// **`coupe` is the eighth, and it is a correction rather than an addition.**
/// that source serves fifteen of its eighty-eight recipes in a glass that is not one
/// of the first seven, and the commonest of them is the coupe. Leaving it out
/// costs *Margarita, Daiquiri, White Lady and Grasshopper* their glassware
/// entirely. The argument for adding it rather than widening the enum further:
/// **the source dataset's own name for this vessel is 'coupe', and section 12.1 took its whole
/// colour system from it.** A project that borrowed that app's palette and then
/// could not draw its signature glass had made a mistake, not a choice.
///
/// The remaining four that source names -- `irish`, `snifter`, `mule`, `tropical` --
/// stay out, and [GlassAliases.unmapped] says why.
enum Glass {
  cocktail,

  /// A stemmed bowl, shallower and wider than a cocktail glass.
  ///
  /// Appended rather than inserted, so that no existing value's index moves.
  /// Nothing persists a [Glass] by index today, and appending means nothing
  /// will have to care if something ever does.
  coupe,
  highball,
  lowball,
  flute,
  shot,
  pint,
  wine;

  /// Reads a source's spelling, or returns null.
  ///
  /// Case- and punctuation-insensitive, because a spreadsheet and a scraper
  /// will not agree about capitalisation and neither is wrong. Null rather
  /// than a default: section 18's whole warning is about an enum that was
  /// defined and then not enforced, and a fallback value is exactly how that
  /// happens.
  static Glass? fromSource(String raw) {
    final key = normalise(raw);
    if (key.isEmpty) return null;
    for (final glass in Glass.values) {
      if (glass.name == key) return glass;
    }
    final alias = GlassAliases.toCanonical[key];
    return alias;
  }

  static String normalise(String raw) =>
      raw.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
}

/// Source spellings that mean one of the seven, and why.
///
/// Kept apart from [Glass.fromSource] so the guesswork is visible. An entry
/// here is a claim that two bars would call the same object by these two names,
/// and each one is a claim somebody can disagree with.
abstract final class GlassAliases {
  static const Map<String, Glass> toCanonical = {
    // another source's names for the same vessels.
    'martini': Glass.cocktail,
    'rocks': Glass.lowball,
    'collins': Glass.highball,
    'winewhite': Glass.wine,
    'winered': Glass.wine,
    'cocktailtumbler': Glass.lowball,
  };

  /// another source names deliberately left unmapped.
  ///
  /// Each of these is a real glass that is not one of the eight: an Irish coffee
  /// glass, a copper mule mug, a snifter, a tropical. Mapping them onto the
  /// nearest of the eight would be a drawing decision taken by the importer, and
  /// it is not the importer's decision to take.
  ///
  /// **`coupe` used to be in this set and is not any more.** It was here on the
  /// reasoning that it is a real glass nobody had drawn a renderer for, which
  /// was true and beside the point: the cost of leaving it was fifteen recipes
  /// with no glassware, including Margarita and Daiquiri. See [Glass].
  static const Set<String> unmapped = {
    'irish',
    'snifter',
    'mule',
    'tropical',
  };
}
