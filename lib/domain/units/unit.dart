import 'rational.dart';

/// What a unit measures.
///
/// Kept apart from [UnitKind] because the two answer different questions: this
/// one is "what is it", the other is "how does it behave when the amounts
/// change". A `dash` and a `drop` are both volumes but behave differently; a
/// `part` and a `sprig` behave differently in opposite ways.
enum UnitDimension {
  /// Volume. Base: the microlitre, as a whole number.
  volume,

  /// Mass. Base: the milligram, as a whole number.
  mass,

  /// A count of physical things.
  count,

  /// A share of a recipe's total, with no size of its own.
  ///
  /// `part` lives here. The design document groups it with the cultural units
  /// and that is right -- what a drink's "one part" amounts to is a decision,
  /// not a constant -- but it is not a volume, and calling it one would let a
  /// recipe in parts be added to one in millilitres without anybody noticing.
  ratio,
}

/// How a unit behaves when a recipe is scaled (design section 5.2).
enum UnitKind {
  /// Fixed by definition: millilitres, ounces, teaspoons.
  ///
  /// Scaling a recipe multiplies these exactly, and the arithmetic is exact
  /// because of [Rational].
  absolute,

  /// Set by the bar rather than by any standard: `dash`, `barspoon`.
  ///
  /// Section 5.3 is blunt about why these cannot be constants. A dash of
  /// bitters varies with the bottle's orifice, the fill level and the wrist;
  /// a barspoon is 2.5 ml at a Japanese bar and 5 ml at an American one, which
  /// is a factor of two in a drink. So the system offers a starting value,
  /// marks it as a guess rather than a fact, and lets the user replace it with
  /// a measurement of their own equipment.
  cultural,

  /// Counted, never scaled: a leaf, a sprig, a twist of peel.
  ///
  /// Doubling a recipe does not mean two orange wheels in one glass, so these
  /// are carried through scaling unchanged rather than multiplied.
  discrete,
}

/// A unit, identified by name and nothing else.
///
/// Deliberately carries no number. The conversion factor lives in [UnitSystem]
/// because it can be calibrated per user, and a unit that knew its own size
/// would be a unit that could not be re-measured.
final class Unit {
  const Unit(this.id, this.symbol, this.dimension, this.kind);

  /// The stable identifier: `oz`, `dash`, `ml`.
  final String id;

  /// What a person sees: `oz`, `dash`, `ml`.
  final String symbol;

  final UnitDimension dimension;
  final UnitKind kind;

  bool get isCultural => kind == UnitKind.cultural;
  bool get isDiscrete => kind == UnitKind.discrete;

  @override
  String toString() => id;

  @override
  bool operator ==(Object other) => other is Unit && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// A conversion factor, and whether it is a definition or a guess.
///
/// The distinction is carried in the type rather than left to a comment,
/// because section 5.3's whole point is that a dash has no international
/// standard while a millilitre does. A caller that shows a number to a user
/// has to decide what to do about [isEstimate]; a caller that does not look
/// cannot accidentally present a guess as arithmetic.
final class UnitFactor {
  const UnitFactor(this.perUnit, {required this.isEstimate});

  /// A factor that is true by definition.
  const UnitFactor.exact(Rational perUnit) : this(perUnit, isEstimate: false);

  /// Base units -- microlitres or milligrams -- in one of this unit.
  final Rational perUnit;

  /// True when this number is a convention rather than a standard.
  ///
  /// True for every cultural unit until the user measures their own.
  final bool isEstimate;

  /// The same factor with a measurement substituted for the suggestion.
  ///
  /// Whatever the user measured is by definition no longer an estimate.
  UnitFactor calibratedTo(Rational measured) =>
      UnitFactor(measured, isEstimate: false);

  @override
  String toString() => isEstimate ? '$perUnit (estimate)' : '$perUnit';
}
