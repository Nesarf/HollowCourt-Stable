import '../model/drink.dart';
import '../units/quantity.dart';
import '../units/rational.dart';
import 'abv.dart';
import 'dilution.dart';

/// Resizing a drink, and the four things section 5.6 wants to resize it by.
///
/// Every factor here is exact. The only rounding in a resized drink happens
/// once per component, at the moment its amount becomes a whole number of
/// microlitres -- which is the same place the original recipe was rounded, and
/// the reason the ratio is carried rather than the volume.
abstract final class Scaling {
  /// Scales so that the liquid totals [target], before the ice.
  static Drink toUndilutedVolume(Drink drink, Volume target) {
    final current = drink.undilutedVolume;
    if (current.isZero) {
      throw ArgumentError.value(
        drink,
        'drink',
        'a drink with no liquid has no ratio to scale',
      );
    }
    return drink.scaledBy(target.toRational() / current.toRational());
  }

  /// Scales so that the drink, after dilution, fills [target].
  ///
  /// This is the one that matters for a glass: a recipe written for a coupe
  /// does not fit a highball, and what has to match the glass is the volume
  /// the ice leaves behind rather than the volume that went in.
  static Drink toServedVolume(Drink drink, Volume target, Dilution dilution) {
    final served = dilution.dilutedVolumeOf(drink);
    if (served.isZero) {
      throw ArgumentError.value(
        drink,
        'drink',
        'a drink with no volume has no ratio to scale',
      );
    }
    return drink.scaledBy(target.toRational() / served.toRational());
  }

  /// Scales a drink so it fits a glass, after dilution.
  ///
  /// [workingVolume] is the space the liquid actually has, which section 5.6
  /// spells out as the glass's capacity minus what the ice occupies: a 200 ml
  /// glass with ice in it is about 120 ml of room.
  static Drink toFit(Drink drink, Volume workingVolume, Dilution dilution) =>
      toServedVolume(drink, workingVolume, dilution);

  /// The room a glass actually has for liquid.
  ///
  /// Kept separate from [toFit] so that the subtraction is its own named
  /// thing. The displacement figure is a property of the ice a bar uses, not
  /// of the glass and not of the recipe.
  static Volume workingVolumeOf(
    Volume glassCapacity, {
    required Volume iceDisplacement,
  }) {
    final working = glassCapacity - iceDisplacement;
    return working.isNegative ? Volume.zero : working;
  }

  /// Scales so that the component at [index] measures [amount].
  ///
  /// This is "by parts" in section 5.6: a drink written as two parts of one
  /// thing to one of another is resized by saying how much of the one thing
  /// there is, and letting the rest follow from the ratio.
  static Drink toComponentVolume(Drink drink, int index, Volume amount) {
    if (index < 0 || index >= drink.components.length) {
      throw RangeError.index(index, drink.components, 'index');
    }
    final current = drink.components[index].volume;
    if (current.isZero) {
      throw ArgumentError.value(
        index,
        'index',
        'a component with no volume cannot be scaled to',
      );
    }
    return drink.scaledBy(amount.toRational() / current.toRational());
  }

  /// The largest batch of this drink that stays under [maxAbvPercent] once
  /// diluted, given that it cannot be made stronger or weaker by resizing.
  ///
  /// Always returns the drink unchanged, because resizing it cannot change its
  /// strength -- and that is the point of the method existing rather than the
  /// caller assuming otherwise. What actually helps is
  /// [AbvArithmetic.volumeToAddForAbvCeiling], which reports how much
  /// non-alcoholic liquid to add.
  static Drink toAbvCeiling(Drink drink, Rational maxAbvPercent) => drink;
}

/// A drink's strength, and the batch size it implies for a ceiling.
extension AbvScaling on Drink {
  /// Whether this drink already sits at or under [maxAbvPercent] once diluted.
  bool fitsUnderAbv(Rational maxAbvPercent, Dilution dilution) =>
      abvPercentServed(dilution) <= maxAbvPercent;

  /// The ceiling this drink would land on if it were diluted once more by
  /// [extraFraction] of its served volume.
  ///
  /// For showing somebody what one more splash of soda would do.
  Rational abvPercentWithExtraDiluent(Rational extraFraction, Dilution dilution) {
    if (extraFraction.isNegative) {
      throw ArgumentError.value(
        extraFraction,
        'extraFraction',
        'a drink cannot be un-diluted by adding nothing',
      );
    }
    final served = dilution.dilutedVolumeOf(this).toRational();
    final total = served * (Rational.one + extraFraction);
    if (total.isZero) return Rational.zero;
    return alcoholMicrolitres() / total * Rational.fromInt(100);
  }
}
