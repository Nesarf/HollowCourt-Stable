import '../model/drink.dart';
import '../units/quantity.dart';
import '../units/rational.dart';

// The percentages, written once. Fractions rather than decimals because these
// feed straight into exact arithmetic and a decimal would reintroduce exactly
// the drift section 5.1 forbids.
final Rational _zeroPercent = Rational.zero;
final Rational _fifteenPercent = Rational.of(15, 100);
final Rational _twentyPercent = Rational.of(20, 100);
final Rational _twentyFivePercent = Rational.of(25, 100);

/// How much water the ice contributes, per method.
///
/// Section 5.5 gives ranges rather than figures, because the amount depends on
/// how cold the ice is, how hard the drink is shaken and how long it stands.
/// Treating that spread as noise would be wrong: it is a fifth of the volume,
/// and it is the difference between a drink somebody can drive after and one
/// they cannot.
final class Dilution {
  const Dilution(this.low, this.high);

  /// No ice, so no water.
  static final Dilution none = Dilution(_zeroPercent, _zeroPercent);

  /// Stirred: 15 to 20 percent.
  static final Dilution stirred = Dilution(_fifteenPercent, _twentyPercent);

  /// Shaken: 20 to 25 percent. More than stirring, because a shaker breaks the
  /// ice up and throws more of its surface into the liquid.
  static final Dilution shaken = Dilution(_twentyPercent, _twentyFivePercent);

  /// The lowest fraction of the original volume that ends up as water.
  final Rational low;

  /// The highest.
  final Rational high;

  /// The fraction in the middle of the range.
  ///
  /// This is what a single answer uses. Section 5.5's own worked example -- a
  /// three-ounce Negroni stirred down to about three and a half ounces -- is
  /// the midpoint of the stirred range, so a midpoint is what the document
  /// itself reaches for when it has to give one number.
  Rational get typical => (low + high) / Rational.fromInt(2);

  /// The dilution for [method].
  ///
  /// Blending takes the shaken range. The document gives ranges for the three
  /// methods a bar uses most and does not give blending one of its own; the
  /// shaken figures are the conservative reading, since a blender agitates at
  /// least as much as a shaker. This is the one number here that the document
  /// does not state, and it is stated here instead of being left implicit.
  static Dilution forMethod(Method method) => switch (method) {
    Method.stirred => stirred,
    Method.shaken => shaken,
    Method.blended => shaken,
    Method.built => none,
    Method.poured => none,
  };

  bool get isNone => low.isZero && high.isZero;

  /// The water [volume] picks up under this dilution, exactly.
  Rational waterFor(Volume volume) => volume.toRational() * typical;

  /// [volume] once the ice has finished with it.
  Volume dilutedVolume(Volume volume) => Volume.fromMicrolitres(
    (volume.toRational() * (Rational.one + typical)).roundHalfUpToBigInt().toInt(),
  );

  /// The whole drink once the ice has finished with it.
  Volume dilutedVolumeOf(Drink drink) => dilutedVolume(drink.undilutedVolume);

  @override
  String toString() => isNone ? 'no dilution' : '$low to $high';
}
