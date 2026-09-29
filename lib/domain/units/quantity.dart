import 'rational.dart';

/// A volume, stored as a whole number of microlitres.
///
/// Section 5.1 makes the microlitre the base because a recipe is a ratio and
/// ratios have to be added up without drifting. The count is a plain `int`: a
/// cellar of bottles and an evening of drinks do not come near the range where
/// a 64-bit integer runs out, so nothing is gained by reaching for `BigInt`.
///
/// This and [Mass] are separate types on purpose. Section 2 chooses a strongly
/// typed language expressly for arithmetic like this, and the one mistake that
/// must not be possible is adding a volume to a mass.
final class Volume implements Comparable<Volume> {
  const Volume.fromMicrolitres(this.microlitres);

  /// The exact whole number of microlitres.
  final int microlitres;

  /// Convenience for the common case of a whole number of millilitres, which
  /// is exact because a millilitre is a thousand microlitres by definition.
  const Volume.fromMillilitres(int millilitres)
    : microlitres = millilitres * 1000;

  static const Volume zero = Volume.fromMicrolitres(0);

  bool get isZero => microlitres == 0;
  bool get isNegative => microlitres < 0;

  /// This volume as an exact fraction, for arithmetic that must not round.
  Rational toRational() => Rational.fromInt(microlitres);

  Volume operator +(Volume other) =>
      Volume.fromMicrolitres(microlitres + other.microlitres);

  Volume operator -(Volume other) =>
      Volume.fromMicrolitres(microlitres - other.microlitres);

  /// Scales by a whole number. Exact, and the common case in a recipe.
  Volume scaleBy(int factor) => Volume.fromMicrolitres(microlitres * factor);

  Volume operator -() => Volume.fromMicrolitres(-microlitres);

  @override
  int compareTo(Volume other) => microlitres.compareTo(other.microlitres);

  bool operator <(Volume other) => microlitres < other.microlitres;
  bool operator <=(Volume other) => microlitres <= other.microlitres;
  bool operator >(Volume other) => microlitres > other.microlitres;
  bool operator >=(Volume other) => microlitres >= other.microlitres;

  @override
  bool operator ==(Object other) =>
      other is Volume && other.microlitres == microlitres;

  @override
  int get hashCode => microlitres.hashCode;

  /// The raw number, with its unit named, so that a stray interpolation in a
  /// log line cannot be mistaken for a display value.
  ///
  /// ASCII only. This string is written to logs, test output and consoles, and
  /// those pass through encodings this code does not control -- a Windows
  /// console at code page 936 turns a micro sign into mojibake. The display
  /// layer is free to render it with the micro sign; a diagnostic is not worth
  /// the risk.
  @override
  String toString() => '$microlitres ul';
}

/// A mass, stored as a whole number of milligrams.
///
/// The other half of section 5.4's bridge. Precision work weighs rather than
/// measures, because volume moves with temperature and mass does not, so this
/// type is not a convenience -- it is the unit a serious bar actually uses.
final class Mass implements Comparable<Mass> {
  const Mass.fromMilligrams(this.milligrams);

  /// The exact whole number of milligrams.
  final int milligrams;

  /// Convenience for whole grams, exact by definition.
  const Mass.fromGrams(int grams) : milligrams = grams * 1000;

  static const Mass zero = Mass.fromMilligrams(0);

  bool get isZero => milligrams == 0;
  bool get isNegative => milligrams < 0;

  Rational toRational() => Rational.fromInt(milligrams);

  Mass operator +(Mass other) => Mass.fromMilligrams(milligrams + other.milligrams);

  Mass operator -(Mass other) => Mass.fromMilligrams(milligrams - other.milligrams);

  Mass scaleBy(int factor) => Mass.fromMilligrams(milligrams * factor);

  Mass operator -() => Mass.fromMilligrams(-milligrams);

  @override
  int compareTo(Mass other) => milligrams.compareTo(other.milligrams);

  bool operator <(Mass other) => milligrams < other.milligrams;
  bool operator <=(Mass other) => milligrams <= other.milligrams;
  bool operator >(Mass other) => milligrams > other.milligrams;
  bool operator >=(Mass other) => milligrams >= other.milligrams;

  @override
  bool operator ==(Object other) =>
      other is Mass && other.milligrams == milligrams;

  @override
  int get hashCode => milligrams.hashCode;

  @override
  String toString() => '$milligrams mg';
}
