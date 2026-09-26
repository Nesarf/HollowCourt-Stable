import '../domain/units/quantity.dart';
import 'unit_labels.dart';
import '../domain/units/rational.dart';
import '../domain/units/unit.dart';
import '../domain/units/unit_system.dart';

/// A volume, written in the unit the reader measures in.
///
/// **A `Rational` becomes a `double` below this line and nowhere else, and the display is
/// the only caller `rational.dart` allows to throw that away** -- `UnitSystem.amountIn`
/// returns a `Rational`, and a person reads a number and not a fraction. The rounding and
/// the one throw-away are both in [_oneDecimal], which every formatter in this file uses.
///
/// **The unit is passed in rather than looked up.** Which unit a reader measures in is
/// a preference, and a formatter that reached for one would be a formatter that could
/// not be tested without a provider. The caller decides; this decides how many digits.
///
/// **[volumeNumber] is the same number without the symbol**, because a box to type in wants
/// the number and a control beside it says the unit.
String volumeText(
  Volume volume,
  Unit unit, {
  UnitSystem? system,
  String? locale,
}) => '${volumeNumber(volume, unit, system: system)} '
    '${locale == null ? unit.symbol : unitSymbolFor(unit, locale)}';

/// The number alone, with no symbol after it.
///
/// **Split out of [volumeText] because an entry field needs the number without the
/// unit.** The unit beside that field is a control rather than a word, so `700 ml` is
/// what a shelf says and `700` is what goes in the box -- and the box has to be filled
/// with the number the shelf would print, or a person would type what they read and be
/// stored something else. One rounding rule, two callers.
String volumeNumber(Volume volume, Unit unit, {UnitSystem? system}) {
  final measures = system ?? UnitSystem.standard();
  return _oneDecimal(measures.amountIn(volume, unit));
}

/// One decimal, and a trailing `.0` dropped.
///
/// **The one rounding rule, and it is shared by all three formatters.** The first version
/// asked whether the exact `Rational` was whole and printed no decimals if it was -- which is
/// right for millilitres and wrong for ounces, because an integer microlitre cannot represent
/// 29.5735295625 µl and so no count of fluid ounces is ever exactly whole. The rule that works
/// for both is to round to one decimal and then drop a `.0`, so a bottle reads `700 ml` and
/// `4 oz` rather than `700.0 ml` and `4.0 oz`.
///
/// **This is also where a `Rational` becomes a `double`, and the display is the only caller
/// `rational.dart` allows to throw that away**, because a person reads a number and not a
/// fraction. Every formatter in this file goes through here so that there is exactly one
/// place it happens.
String _oneDecimal(Rational amount) {
  final roundedToOne = amount.toDouble().toStringAsFixed(1);
  return roundedToOne.endsWith('.0')
      ? roundedToOne.substring(0, roundedToOne.length - 2)
      : roundedToOne;
}

/// A volume in microlitres, for a caller that has the integer base and not a [Volume].
String microlitreText(int microlitres, Unit unit, {UnitSystem? system}) =>
    volumeText(Volume.fromMicrolitres(microlitres), unit, system: system);

/// The microlitres a person typed in [unit], or null when the text cannot be read.
///
/// **The inverse of [volumeText], and the reason both live in one file.** Every volume a
/// screen shows passes through here, so every volume a screen *hears* should too --
/// otherwise the two ends could disagree about what `4,5` means and only one of them
/// would be right.
///
/// [milligramsTyped] is the twin for the other base. The two are separate functions rather
/// than one generic over the dimension, for the reason [massText] gives.
int? microlitresTyped(String text, Unit unit, {UnitSystem? system}) {
  final amount = _amountTyped(text);
  if (amount == null) return null;

  final measures = system ?? UnitSystem.standard();
  return _baseTyped(
    amount,
    measures.microlitresPer(unit),
    (exact) => measures.volumeOf(exact, unit).microlitres,
  );
}

/// The milligrams a person typed in [unit], or null when the text cannot be read.
///
/// **The twin [microlitresTyped] used to say was missing, and the reason it was missing was
/// in the domain rather than here**: `UnitSystem.massOf` did not exist, so there was no door
/// to enter a mass through while the volume side had one. It exists now, and this is the
/// pair -- which is what makes a solid weighable at all, since 固体用克 is half of the unit
/// instruction and had no way to be followed.
///
/// The two stay separate rather than becoming one function generic over the dimension, for
/// the reason [massText] gives: microlitres and milligrams are not interchangeable and a
/// single entry point invites exactly that.
int? milligramsTyped(String text, Unit unit, {UnitSystem? system}) {
  final amount = _amountTyped(text);
  if (amount == null) return null;

  final measures = system ?? UnitSystem.standard();
  return _baseTyped(
    amount,
    measures.milligramsPer(unit),
    (exact) => measures.massOf(exact, unit).milligrams,
  );
}

/// The exact amount somebody typed, or null when there is nothing readable in the box.
///
/// **Null rather than an exception, which is the opposite of `Rational.parse`'s choice and
/// for the reason that choice gives.** A number in a text field is somebody typing, not a
/// bug, so the caller has to be able to refuse it and say so; `Rational.parse` throws because
/// a caller with a fallback would use it. This *is* that caller, and its fallback is a
/// sentence on the screen. Zero and negative amounts are refused here too: a bottle holding
/// `0 ml` is not a bottle, and the form's own copy says the amount has to be a positive
/// number.
Rational? _amountTyped(String text) {
  final Rational amount;
  try {
    amount = Rational.parse(text);
  } on FormatException {
    return null;
  }
  if (amount <= Rational.zero) return null;
  return amount;
}

/// [amount] of [factor] base units each, converted, with the range checked first.
///
/// **Checked before converting, because the base is an `int`.** The domain's `volumeOf` and
/// `massOf` round exactly and then take the integer; an amount past 64 bits would be clamped
/// by `BigInt.toInt`, and a cellar that quietly stored 2^63 microlitres for a typed
/// `99999999999999999 l` would be worse than one that refused it. The bound is applied to the
/// exact product, so the rounding rule itself stays inside the domain where it belongs. The
/// constant is `2^63`, one past the largest `int`, so no magic number is written down.
int? _baseTyped(Rational amount, Rational factor, int Function(Rational) convert) {
  final exact = amount * factor;
  if (exact >= _pastTheIntRange) return null;
  return convert(amount);
}

/// `2^63`, exactly: the first whole number an `int` cannot hold.
final Rational _pastTheIntRange = Rational.fromBigInt(BigInt.one << 63);

/// A mass, written in the unit the reader measures in.
///
/// **The gap this closes was recorded by `measure_text_test` before it existed.** A
/// volume formatter refuses a mass unit -- correctly, since converting one to the other
/// needs a density that no source in this project carries -- and that refusal meant a
/// solid on a shelf had no way to print its grams. 固体用克 is half of the unit
/// instruction, so the twin belongs here rather than in a fourth layer.
///
/// The two functions are separate rather than one generic over the dimension, for the
/// reason `UnitSystem` gives for having two doors: the bases are different and a single
/// entry point would invite a caller to treat microlitres and milligrams as
/// interchangeable.
String massText(Mass mass, Unit unit, {UnitSystem? system, String? locale}) =>
    '${massNumber(mass, unit, system: system)} '
    '${locale == null ? unit.symbol : unitSymbolFor(unit, locale)}';

/// The number alone, with no symbol after it -- the twin of [volumeNumber].
///
/// It exists for the same caller: a field with a unit menu beside it holds the number and
/// lets the menu say the unit, so changing the menu has to rewrite the number the way the
/// shelf would print it. [massText] is this plus the symbol, and there is one rounding rule
/// under both.
String massNumber(Mass mass, Unit unit, {UnitSystem? system}) {
  final measures = system ?? UnitSystem.standard();
  return _oneDecimal(measures.milligramsOf(mass, unit));
}
