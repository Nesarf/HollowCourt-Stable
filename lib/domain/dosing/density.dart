import '../units/quantity.dart';
import '../units/rational.dart';

/// The bridge between volume and mass (design section 5.4).
///
/// Precision work weighs rather than measures: a millilitre of gin is not the
/// same number of grams at four degrees as at twenty, while a gram is a gram
/// wherever it is. So a bar that cares about the difference keeps a density
/// per material and converts, and the arithmetic lives here.
///
/// The unit of density is grams per millilitre, which makes the conversions
/// unusually tidy: a microlitre times grams-per-millilitre is a milligram,
/// with no constant to remember. That is not a coincidence -- both bases are
/// thousandths of the unit the density is quoted in.
extension DensityBridge on Rational {
  /// The mass of [volume] of a substance with this density.
  Mass massOf(Volume volume) {
    if (isNegative) {
      throw ArgumentError.value(this, 'density', 'a density cannot be negative');
    }
    // ul * g/ml = mg, exactly.
    return Mass.fromMilligrams(
      (volume.toRational() * this).roundHalfUpToBigInt().toInt(),
    );
  }

  /// The volume that [mass] of a substance with this density occupies.
  Volume volumeOf(Mass mass) {
    if (isZero) {
      throw ArgumentError.value(
        this,
        'density',
        'a substance with no density has no volume for a given mass',
      );
    }
    if (isNegative) {
      throw ArgumentError.value(this, 'density', 'a density cannot be negative');
    }
    return Volume.fromMicrolitres(
      (mass.toRational() / this).roundHalfUpToBigInt().toInt(),
    );
  }
}

/// Densities worth having to hand, in grams per millilitre.
///
/// Section 5.4 names three, and they are the three that matter: water is the
/// reference a density is defined against, a sugar syrup is the commonest
/// thing in the well that is much heavier than water, and a spirit is the
/// commonest thing that is lighter. Everything else belongs in the ingredient
/// catalogue, where a user can correct it.
///
/// They are marked as estimates because they are: a syrup's density depends on
/// its ratio and a spirit's on its strength. A catalogue that carries a
/// measured figure should use that instead.
abstract final class Densities {
  /// Water, by definition the reference.
  static final Rational water = Rational.one;

  /// A simple syrup, roughly one part sugar to one part water.
  static final Rational simpleSyrup = Rational.of(130, 100);

  /// A spirit around 40 percent ABV. Ethanol is lighter than water and the
  /// mixture is lighter still, which is why this sits below one.
  static final Rational spirit = Rational.of(94, 100);
}
