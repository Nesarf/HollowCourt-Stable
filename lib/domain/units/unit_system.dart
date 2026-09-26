import 'quantity.dart';
import 'rational.dart';
import 'unit.dart';

/// Which fluid ounce a set of measures is built on.
///
/// Section 5.3 puts the difference first because it is the largest one that
/// hides behind a familiar symbol: a US fluid ounce is 29.5735295625 ml and an
/// imperial one is 28.4131 ml, four percent apart. In a three-ingredient drink
/// that is a difference somebody can taste, and the two are both written `oz`.
enum FluidOunce {
  /// 29.5735295625 ml, from the US gallon of 231 cubic inches.
  us,

  /// 28.4131 ml.
  imperial,
}

/// Raised when a unit has no size to convert, because it is a ratio or a count.
///
/// Not a programmer error in the sense of being impossible: a recipe written
/// in parts and a shopping list written in leaves both exist, and neither can
/// be turned into microlitres without being told what it is a share *of*.
final class UnitNotConvertible implements Exception {
  const UnitNotConvertible(this.unit, this.reason);

  final Unit unit;
  final String reason;

  @override
  String toString() => 'UnitNotConvertible(${unit.id}): $reason';
}

/// The units this application knows, and what they are worth.
///
/// The factors live here rather than on [Unit] because they are not properties
/// of a unit so much as properties of a *user*: section 5.3 requires that a
/// bar calibrate its own dash and barspoon, and a unit that carried its own
/// size could not be re-measured.
final class UnitSystem {
  UnitSystem._(this.fluidOunce, Map<String, UnitFactor> factors)
    : _factors = factors;

  /// The measures a bar starts with: US fluid ounce, and dash and barspoon at
  /// the suggested values below, both marked as estimates.
  factory UnitSystem.standard({FluidOunce fluidOunce = FluidOunce.us}) {
    final ounce = fluidOunce == FluidOunce.us
        ? _usFluidOunceMicrolitres
        : _imperialFluidOunceMicrolitres;

    return UnitSystem._(fluidOunce, {
      millilitre.id: UnitFactor.exact(Rational.fromInt(1000)),
      centilitre.id: UnitFactor.exact(Rational.fromInt(10000)),
      litre.id: UnitFactor.exact(Rational.fromInt(1000000)),

      fluidOunceUnit.id: UnitFactor.exact(ounce),

      // Mass, in milligrams. Every one of these is a definition rather than a
      // measurement, which is why none is marked as an estimate: the gram is the
      // base, the kilogram is a thousand of them, and the two imperial units are
      // exact by the international avoirdupois definitions.
      milligram.id: UnitFactor.exact(Rational.fromInt(1)),
      gram.id: UnitFactor.exact(Rational.fromInt(1000)),
      kilogram.id: UnitFactor.exact(Rational.fromInt(1000000)),
      ounceMass.id: UnitFactor.exact(_avoirdupoisOunceMilligrams),
      pound.id: UnitFactor.exact(_avoirdupoisPoundMilligrams),

      // A teaspoon is a sixth of a fluid ounce and a tablespoon is a half, by
      // definition. Deriving them from the ounce rather than writing a rounded
      // millilitre figure means the two can never disagree with each other.
      teaspoon.id: UnitFactor.exact(ounce / Rational.fromInt(6)),
      tablespoon.id: UnitFactor.exact(ounce / Rational.fromInt(2)),

      // Section 5.2 files `drop` with the absolute units, so it is given a
      // fixed size here: the metric drop of 0.05 ml. Worth knowing, and worth
      // saying out loud, that this is the one place the section's own
      // classification sits uneasily -- a drop from a bitters bottle depends
      // on the orifice and the wrist exactly as a dash does. A bar that cares
      // should express the amount as a calibrated dash instead.
      drop.id: UnitFactor.exact(Rational.fromInt(50)),

      // The two that cannot be constants. See the notes on [_suggestedDash] and
      // [_suggestedBarspoon].
      dash.id: UnitFactor(_suggestedDash, isEstimate: true),
      barspoon.id: UnitFactor(_suggestedBarspoon, isEstimate: true),

      // Derived from the ounce for the same reason teaspoons are: a sixteenth
      // of a teaspoon and a jigger of an ounce are definitions, and writing a
      // rounded millilitre figure instead would let them drift apart from the
      // ounce they are defined against.
      pinch.id: UnitFactor(ounce / Rational.fromInt(96), isEstimate: true),
      shot.id: UnitFactor(
        ounce * Rational.fromInt(3) / Rational.fromInt(2),
        isEstimate: true,
      ),
    });
  }

  /// 1 avoirdupois ounce: exactly 28.349523125 g, in milligrams.
  ///
  /// Written as the digits of the definition rather than as a rounded decimal, so
  /// that a pound divided by sixteen lands on the same number rather than near it.
  static final Rational _avoirdupoisOunceMilligrams = Rational(
    BigInt.from(28349523125),
    BigInt.from(1000000),
  );

  /// 1 avoirdupois pound: exactly 453.59237 g, in milligrams.
  static final Rational _avoirdupoisPoundMilligrams = Rational(
    BigInt.from(45359237),
    BigInt.from(100),
  );

  /// 1 US fluid ounce: exactly 29.5735295625 ml, in microlitres.
  static final Rational _usFluidOunceMicrolitres = Rational(
    BigInt.parse('295735295625'),
    BigInt.from(10000000),
  );

  /// 1 imperial fluid ounce: exactly 28.4131 ml, in microlitres.
  static final Rational _imperialFluidOunceMicrolitres = Rational(
    BigInt.from(284131),
    BigInt.from(10),
  );

  /// The starting value for a dash, in microlitres.
  ///
  /// 0.7 ml, the middle of the 0.6 to 0.8 ml that a bottle of aromatic bitters
  /// is usually said to deliver. Section 5.3 notes there is no international
  /// standard for a dash at all, which is why this is a suggestion and is
  /// flagged as one wherever it is used.
  static final Rational _suggestedDash = Rational.fromInt(700);

  /// The starting value for a barspoon, in microlitres.
  ///
  /// The two conventions are 2.5 ml at a Japanese bar and 5 ml at an American
  /// one, which is a factor of two in a drink. This starts at the smaller of
  /// the two on purpose: a barspoon is usually carrying a modifier or a bitter
  /// component, and under-measuring one is a smaller error than doubling it.
  /// A bar that measures differently is expected to say so, which is what
  /// [withCalibration] is for.
  static final Rational _suggestedBarspoon = Rational.fromInt(2500);

  // ------------------------------------------------------------- the units

  static const Unit millilitre = Unit(
    'ml',
    'ml',
    UnitDimension.volume,
    UnitKind.absolute,
  );
  static const Unit centilitre = Unit(
    'cl',
    'cl',
    UnitDimension.volume,
    UnitKind.absolute,
  );
  static const Unit litre = Unit(
    'l',
    'l',
    UnitDimension.volume,
    UnitKind.absolute,
  );
  static const Unit fluidOunceUnit = Unit(
    'oz',
    'oz',
    UnitDimension.volume,
    UnitKind.absolute,
  );
  // ---------------------------------------------------------------- mass
  //
  // The dimension was always here -- `UnitDimension.mass` is documented as based on
  // the milligram -- and no unit ever used it, so a solid had no unit at all while
  // `Mass` had a type. That is the gap section 5.1's "固体用克、液体用毫升" needs
  // closed before a measure set can name a unit for a solid.

  /// The mass base, and the only unit whose factor is one.
  static const Unit milligram = Unit(
    'mg',
    'mg',
    UnitDimension.mass,
    UnitKind.absolute,
  );
  static const Unit gram = Unit('g', 'g', UnitDimension.mass, UnitKind.absolute);
  static const Unit kilogram = Unit(
    'kg',
    'kg',
    UnitDimension.mass,
    UnitKind.absolute,
  );

  /// The avoirdupois ounce, by definition 28.349523125 g.
  ///
  /// **Its id is `ozm` and its symbol is `oz`, and both halves are deliberate.** A
  /// fluid ounce and an ounce are different things with the same symbol, which is
  /// the real world's problem and not one a screen can solve; what a person matches
  /// on is the symbol, so the symbol stays. The id is a wire format and has to be
  /// unambiguous, and the bare `oz` was already taken by the volume ounce --
  /// changing that now would rewrite every recipe written against it, so the mass
  /// one is the one that moves.
  static const Unit ounceMass = Unit(
    'ozm',
    'oz',
    UnitDimension.mass,
    UnitKind.absolute,
  );
  static const Unit pound = Unit(
    'lb',
    'lb',
    UnitDimension.mass,
    UnitKind.absolute,
  );

  static const Unit teaspoon = Unit(
    'tsp',
    'tsp',
    UnitDimension.volume,
    UnitKind.absolute,
  );
  static const Unit tablespoon = Unit(
    'tbsp',
    'tbsp',
    UnitDimension.volume,
    UnitKind.absolute,
  );
  static const Unit drop = Unit(
    'drop',
    'drop',
    UnitDimension.volume,
    UnitKind.absolute,
  );

  static const Unit dash = Unit(
    'dash',
    'dash',
    UnitDimension.volume,
    UnitKind.cultural,
  );
  static const Unit barspoon = Unit(
    'barspoon',
    'barspoon',
    UnitDimension.volume,
    UnitKind.cultural,
  );

  /// A share of the recipe's total. Dimensionless, and deliberately so.
  static const Unit part = Unit(
    'part',
    'part',
    UnitDimension.ratio,
    UnitKind.cultural,
  );

  static const Unit leaf = Unit(
    'leaf',
    'leaf',
    UnitDimension.count,
    UnitKind.discrete,
  );
  static const Unit sprig = Unit(
    'sprig',
    'sprig',
    UnitDimension.count,
    UnitKind.discrete,
  );
  static const Unit wheel = Unit(
    'wheel',
    'wheel',
    UnitDimension.count,
    UnitKind.discrete,
  );
  static const Unit twist = Unit(
    'twist',
    'twist',
    UnitDimension.count,
    UnitKind.discrete,
  );
  static const Unit peel = Unit(
    'peel',
    'peel',
    UnitDimension.count,
    UnitKind.discrete,
  );
  static const Unit cube = Unit(
    'cube',
    'cube',
    UnitDimension.count,
    UnitKind.discrete,
  );
  static const Unit wedge = Unit(
    'wedge',
    'wedge',
    UnitDimension.count,
    UnitKind.discrete,
  );
  static const Unit slice = Unit(
    'slice',
    'slice',
    UnitDimension.count,
    UnitKind.discrete,
  );

  /// One whole item, with no unit word of its own.
  ///
  /// Both source datasets need this and neither names it the same way: another source
  /// writes `1 of cherry` and one source puts `Single` in its unit column. A bare
  /// count is a real thing a recipe can say, so it gets a unit rather than a
  /// null, and it counts rather than measures -- four cherries doubled is eight
  /// cherries in the spec, not eight in the glass, which is the distinction
  /// [UnitKind.discrete] exists to make.
  static const Unit each = Unit(
    'each',
    'each',
    UnitDimension.count,
    UnitKind.discrete,
  );

  /// A pinch, treated as a volume rather than a count.
  ///
  /// Culinary convention puts it at a sixteenth of a teaspoon, which is what
  /// the factor below derives, but the honest description is that a pinch is
  /// defined by a hand -- exactly the situation section 5.3 describes for a
  /// dash. It is a cultural unit with a suggested size, and a bar that cares
  /// should calibrate it the same way.
  static const Unit pinch = Unit(
    'pinch',
    'pinch',
    UnitDimension.volume,
    UnitKind.cultural,
  );

  /// A shot, at the US jigger of 1.5 fluid ounces.
  ///
  /// The widest-spread of the vague ones: 30 ml in much of Europe, 44 ml in the
  /// United States, and anywhere between in a bar that free-pours. Marked as an
  /// estimate for the same reason as [dash], and calibrated the same way.
  static const Unit shot = Unit(
    'shot',
    'shot',
    UnitDimension.volume,
    UnitKind.cultural,
  );

  /// Every unit the system knows, in a stable order.
  static const List<Unit> all = [
    millilitre,
    centilitre,
    litre,
    fluidOunceUnit,
    milligram,
    gram,
    kilogram,
    ounceMass,
    pound,
    teaspoon,
    tablespoon,
    drop,
    dash,
    barspoon,
    pinch,
    shot,
    part,
    leaf,
    sprig,
    wheel,
    twist,
    peel,
    cube,
    wedge,
    slice,
    each,
  ];

  // ------------------------------------------------------------- instance

  final FluidOunce fluidOunce;
  final Map<String, UnitFactor> _factors;

  /// The factor for [unit], or null when it has no size of its own.
  UnitFactor? factorFor(Unit unit) => _factors[unit.id];

  /// Whether [unit] can be turned into microlitres without more information.
  bool isConvertible(Unit unit) {
    final factor = _factors[unit.id];
    return factor != null && unit.dimension == UnitDimension.volume;
  }

  /// Microlitres in one [unit], exactly.
  ///
  /// Throws [UnitNotConvertible] for a ratio or a count, because neither has a
  /// size: the first is a share of something not yet named, the second is not
  /// a volume at all.
  Rational microlitresPer(Unit unit) {
    if (unit.dimension != UnitDimension.volume) {
      throw UnitNotConvertible(
        unit,
        unit.dimension == UnitDimension.ratio
            ? 'a share of a total has no size until the total is known'
            : 'a count is not a volume',
      );
    }

    final factor = _factors[unit.id];
    if (factor == null) {
      throw UnitNotConvertible(unit, 'no factor is known for this unit');
    }
    return factor.perUnit;
  }

  /// Milligrams in one [unit], exactly.
  ///
  /// The twin of [microlitresPer], and separate from it on purpose: a `Mass` is not
  /// a `Volume` and the quantity family refuses to add them, so a single method
  /// returning "the factor" would invite a caller to treat the two bases as
  /// interchangeable when the whole design says they are not. A unit of neither
  /// dimension is refused for the same reason it is there.
  Rational milligramsPer(Unit unit) {
    if (unit.dimension != UnitDimension.mass) {
      throw UnitNotConvertible(
        unit,
        unit.dimension == UnitDimension.ratio
            ? 'a share of a total has no size until the total is known'
            : 'a count is not a mass',
      );
    }

    final factor = _factors[unit.id];
    if (factor == null) {
      throw UnitNotConvertible(unit, 'no factor is known for this unit');
    }
    return factor.perUnit;
  }

  /// Whether [unit] carries a mass rather than a volume.
  ///
  /// [isConvertible] answers the volume question and keeps answering it, so a
  /// caller that meant "can I pour this" is not silently given mass units as an
  /// answer once mass units exist.
  bool isMass(Unit unit) =>
      unit.dimension == UnitDimension.mass && _factors.containsKey(unit.id);

  /// Whether the factor for [unit] is a guess rather than a standard.
  bool isEstimate(Unit unit) => _factors[unit.id]?.isEstimate ?? false;

  /// The same system with [unit] measured to [microlitres].
  ///
  /// This is the operation section 5.3 asks for: a user fills a graduated
  /// cylinder from their own bottle once, and every recipe in the library
  /// benefits. The result is no longer marked as an estimate, because a
  /// measurement is not one.
  UnitSystem withCalibration(Unit unit, Rational microlitres) {
    if (microlitres.isNegative || microlitres.isZero) {
      throw ArgumentError.value(
        microlitres,
        'microlitres',
        'a measured unit has to have a size',
      );
    }
    if (unit.kind != UnitKind.cultural) {
      throw ArgumentError.value(
        unit,
        'unit',
        'only a cultural unit can be calibrated; ${unit.id} is defined',
      );
    }

    final existing = _factors[unit.id];
    if (existing == null) {
      throw ArgumentError.value(
        unit,
        'unit',
        'this unit has no factor to replace',
      );
    }

    return UnitSystem._(fluidOunce, {
      ..._factors,
      unit.id: existing.calibratedTo(microlitres),
    });
  }

  /// Turns an exact [amount] of [unit] into a whole number of microlitres.
  ///
  /// Rounding happens here and nowhere else. Everything above this line stays
  /// exact, so the only error in a scaled recipe is the single half-microlitre
  /// this line can introduce, rather than one per multiplication.
  Volume volumeOf(Rational amount, Unit unit) {
    final exact = amount * microlitresPer(unit);
    return Volume.fromMicrolitres(exact.roundHalfUpToBigInt().toInt());
  }

  /// Turns a whole number of microlitres into an exact amount of [unit].
  ///
  /// Exact, and deliberately not rounded: a pour of 30 ml shown in ounces is
  /// 1.0144... oz, and a display layer that wants two decimal places should be
  /// the one to throw the rest away, not this.
  Rational amountIn(Volume volume, Unit unit) =>
      volume.toRational() / microlitresPer(unit);

  /// Turns a whole number of milligrams into an exact amount of [unit].
  ///
  /// The twin of [amountIn], and separate for the reason [milligramsPer] is separate from
  /// [microlitresPer]: one method that answered both would invite a caller to treat the two
  /// bases as interchangeable when the quantity family refuses to add a `Mass` to a
  /// `Volume`. Exact and not rounded, so the display layer keeps being the only place that
  /// throws digits away.
  Rational milligramsOf(Mass mass, Unit unit) =>
      mass.toRational() / milligramsPer(unit);

  /// Turns an exact [amount] of [unit] into a whole number of milligrams.
  ///
  /// **The twin of [volumeOf], and it was the door that was missing.** The mass side had the
  /// factor ([milligramsPer]) and the inverse ([milligramsOf]) but nothing that went *in*, so
  /// a solid could be printed on a shelf and never weighed into one -- 固体用克 was half an
  /// instruction with no way to follow it. `measure_text.dart` recorded the same gap from the
  /// other end, where `milligramsTyped` could not be written without this.
  ///
  /// Rounding happens here and nowhere else, exactly as it does for volume: everything above
  /// this line stays exact, so the only error is the single half-milligram this line can
  /// introduce rather than one per multiplication.
  Mass massOf(Rational amount, Unit unit) {
    final exact = amount * milligramsPer(unit);
    return Mass.fromMilligrams(exact.roundHalfUpToBigInt().toInt());
  }

  /// The factor for every cultural unit whose value is still a guess.
  ///
  /// A settings screen needs this to know what to offer to calibrate, and a
  /// recipe screen needs it to know whether to say so.
  Map<Unit, UnitFactor> uncalibratedUnits() => {
    for (final unit in all)
      if (isEstimate(unit)) unit: _factors[unit.id]!,
  };
}
