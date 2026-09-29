/// A flavour, as a taste rather than as a word.
///
/// The two sources keep different vocabularies and neither is wrong: one source has
/// 21 names, another source has 11, and they share seven. This is their union, because a
/// drink that tastes citrussy tastes citrussy whether or not the app that
/// recorded it had a word for it.
///
/// **One collision had to be resolved.** one source writes `Savoury` and another source writes
/// `Savory`, and they mean the same taste. Two enum values would have split one
/// flavour across two buckets, and every count over flavours would then have
/// been wrong in a way nobody would notice -- which is the failure mode section
/// 18 names. Both spellings resolve to [savoury].
///
/// The vocabulary is *taste*, not strength and not temperature: another source's palette
/// includes `Strong` and `Hot` alongside the tastes, and both are kept here
/// because the data carries them and a filter that silently dropped two of the
/// source's eleven values would be lying about the source.
enum Flavor {
  bitter,
  bubbly,
  citrussy,
  creamy,
  crisp,
  dry,
  earthy,
  floral,
  fresh,
  grassy,
  herbal,
  hot,
  nutty,
  roasted,
  salty,
  savoury,
  smokey,
  smooth,
  sour,
  spicy,
  strong,
  sweet,
  tart,
  woody;

  /// Reads a source's spelling, or returns null.
  static Flavor? fromSource(String raw) {
    final key = raw.trim().toLowerCase();
    if (key.isEmpty) return null;
    for (final flavour in Flavor.values) {
      if (flavour.name == key) return flavour;
    }
    // The one reconciliation. Listed rather than fuzzy-matched, so the claim
    // that these are one taste is visible and arguable.
    return switch (key) {
      'savory' => Flavor.savoury,
      'smoky' => Flavor.smokey,
      'citrusy' => Flavor.citrussy,
      _ => null,
    };
  }

  /// The three levels section 4.4 asks for, in order.
  ///
  /// one source fills all three; another source gives an unordered list of up to three. A
  /// recipe that only knows its primary flavour leaves the rest null rather
  /// than repeating the first, because [tertiary] equalling [primary] would
  /// read as a fact about the drink.
}

/// A recipe's flavour profile, in the three levels section 4.4 names.
final class FlavorProfile {
  const FlavorProfile({this.primary, this.secondary, this.tertiary});

  final Flavor? primary;
  final Flavor? secondary;
  final Flavor? tertiary;

  bool get isEmpty => primary == null && secondary == null && tertiary == null;

  Iterable<Flavor> get all => [primary, secondary, tertiary].whereType<Flavor>();

  /// Problems that make this value unusable, empty when it is sound.
  List<String> validate() {
    final problems = <String>[];

    // A secondary or tertiary flavour with nothing above it is a gap dressed as
    // a value: the list has a hole in it and a screen would render the hole.
    if (secondary != null && primary == null) {
      problems.add('secondary flavour ${secondary!.name} with no primary');
    }
    if (tertiary != null && secondary == null) {
      problems.add('tertiary flavour ${tertiary!.name} with no secondary');
    }

    final seen = <Flavor>{};
    for (final flavour in all) {
      if (!seen.add(flavour)) {
        problems.add('${flavour.name} appears twice in one profile');
      }
    }

    return problems;
  }

  @override
  String toString() => all.map((f) => f.name).join(' > ');
}
