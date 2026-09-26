import '../model/drink.dart';
import '../units/rational.dart';
import 'dilution.dart';

/// The strength of a drink.
///
/// One simplification is worth stating rather than leaving in the code.
/// Ethanol and water do not add their volumes exactly -- a mixture contracts
/// slightly -- which is why published strength tables for spirits differ from
/// straight proportion. The contraction is small enough to ignore for a drink
/// assembled in a glass, and this class ignores it. What it does not ignore is
/// the ice, which changes the answer by a fifth rather than by a percent.
extension AbvArithmetic on Drink {
  /// Alcohol by volume, as a percentage, before the ice has done anything.
  ///
  /// Exact: a ratio of two exact volumes, with no rounding anywhere.
  Rational abvPercentUndiluted() {
    final liquid = liquidComponents.fold(
      Rational.zero,
      (sum, component) => sum + component.volume.toRational(),
    );
    if (liquid.isZero) return Rational.zero;
    return alcoholMicrolitres() / liquid * Rational.fromInt(100);
  }

  /// Alcohol by volume, as a percentage, in the glass.
  ///
  /// This is the figure somebody deciding whether to drive needs, and it is
  /// the one that is wrong if the ice is ignored: a Negroni stirred down from
  /// three ounces to three and a half is a sixth weaker than the recipe's
  /// arithmetic suggests.
  Rational abvPercentServed(Dilution dilution) {
    final served = dilution.dilutedVolumeOf(this).toRational();
    if (served.isZero) return Rational.zero;
    return alcoholMicrolitres() / served * Rational.fromInt(100);
  }

  /// The alcohol in the glass, as a volume.
  Rational alcoholVolumeServed(Dilution dilution) => alcoholMicrolitres();

  /// How much non-alcoholic liquid has to be added to bring this drink to
  /// [maxAbvPercent] or below.
  ///
  /// Zero when it is already under the ceiling.
  ///
  /// Note what this is *not*: it is not a scale factor. A drink's strength is
  /// a ratio, so making the batch larger or smaller leaves it exactly where it
  /// was, and section 5.6's "by ABV ceiling" cannot be reached by resizing. It
  /// is reached by adding something without alcohol -- more soda, more juice,
  /// more melt -- and which of those is right is the drinker's decision. So
  /// this returns an amount to add rather than a drink that has somehow been
  /// fixed.
  Rational volumeToAddForAbvCeiling(Rational maxAbvPercent, Dilution dilution) {
    if (maxAbvPercent.isNegative) {
      throw ArgumentError.value(
        maxAbvPercent,
        'maxAbvPercent',
        'a ceiling cannot be negative',
      );
    }
    if (maxAbvPercent.isZero) {
      throw ArgumentError.value(
        maxAbvPercent,
        'maxAbvPercent',
        'no amount of dilution reaches zero alcohol',
      );
    }

    final alcohol = alcoholMicrolitres();
    if (alcohol.isZero) return Rational.zero;

    // alcohol / (served + x) * 100 <= ceiling
    //   =>  x >= alcohol * 100 / ceiling - served
    final needed =
        alcohol * Rational.fromInt(100) / maxAbvPercent -
        dilution.dilutedVolumeOf(this).toRational();

    return needed.isNegative ? Rational.zero : needed;
  }
}
