import '../domain/pricing/price.dart';
import '../domain/units/rational.dart';

/// Renders a [Money] the way a person reads one, and **the only place that does**.
///
/// `rational.dart` and `price.dart` both refuse to format anything, because section 3
/// keeps display text out of the domain layer; this is the UI-layer counterpart, so that
/// "CNY is two digits and JPY is none" is read from [Currency.minorUnitDigits] in one
/// place rather than assumed in each screen. Two screens each dividing by a hundred is
/// how a Japanese price ends up shown at a hundredth of itself on exactly one of them.
///
/// A plain function and not a widget: the number is drawn inside a `Row` beside a
/// `DualCopyText` label at one site and inside a caption at another, and a widget would
/// have to be unpicked at both.
String moneyText(Money amount) {
  final major = amount.minorUnits / _pow10(amount.currency.minorUnitDigits);
  return '${major.toStringAsFixed(amount.currency.minorUnitDigits)} '
      '${amount.currency.code}';
}

/// The minor units a person typed in [currency], or null when the text cannot be read.
///
/// **The inverse of [moneyText], and it lives here for the reason the volume formatter's
/// inverse lives in `measure_text.dart`.** Every price a screen shows passes through this file,
/// so every price a screen *hears* should too -- otherwise the two ends could disagree about
/// what `4,5` means and only one of them would be right.
///
/// **The number typed is the major unit and the currency decides how many digits it has.** The
/// add-bottle field used to ask for a whole number of fen, which is one currency's minor unit
/// written into a label: the same box under JPY means one yen and under KWD a thousandth of a
/// dinar. `1200` in a JPY slot and `1200` in a CNY slot are now 1200 minor units and 120 000,
/// and the menu beside the box is what says which.
///
/// **Exact, because the multiplication is where a `double` would have crept in.** `Rational.parse`
/// reads the decimal, the currency's own digit count scales it, and the result is a whole number
/// of minor units -- `45.50` in CNY is 4550, not 4549.999999999999 and not 4550 after a float
/// round-trip that would fail on some other amount.
///
/// **An amount the currency cannot hold is refused rather than rounded.** `45.50` in a JPY slot
/// is forty-five and a half yen, and there is no such thing: rounding it would take a number a
/// person typed and store a different one, silently, which is the failure this whole file exists
/// to prevent. `0.001` in CNY is refused for the same reason -- it is a tenth of a fen. The
/// caller gets null and has a sentence for it, exactly as it does for text that is not a number.
///
/// Null rather than an exception, because typing is not a bug: an empty box means "no price
/// recorded" and a box holding something unusable is refused out loud, both of which the form
/// decides. Negative is refused here as well -- a price below zero is a refund, and nothing in
/// this build records one.
int? minorUnitsTyped(String text, Currency currency) {
  final Rational amount;
  try {
    // The comma is `Rational.parse`'s, deliberately shared with the measurement fields: one
    // number reader for the whole application, so `4,5` cannot mean two things in two boxes.
    amount = Rational.parse(text);
  } on FormatException {
    return null;
  }
  if (amount.isNegative) return null;

  final exact = amount * Rational.fromInt(_pow10(currency.minorUnitDigits));
  if (!exact.isInteger) return null;

  // **Checked before converting, because the base is an `int`** -- the same guard the
  // measurement fields carry, for the same reason: `BigInt.toInt` clamps, and a price past
  // 2^63 minor units would silently become the largest integer there is. `2^63` is one past
  // the largest `int`, so no magic number is written down.
  final whole = exact.roundHalfUpToBigInt();
  if (whole >= _pastTheIntRange.numerator) return null;
  return whole.toInt();
}

/// `2^63`, exactly: the first whole number an `int` cannot hold.
final Rational _pastTheIntRange = Rational.fromBigInt(BigInt.one << 63);

int _pow10(int exponent) {
  var value = 1;
  for (var i = 0; i < exponent; i++) {
    value *= 10;
  }
  return value;
}
