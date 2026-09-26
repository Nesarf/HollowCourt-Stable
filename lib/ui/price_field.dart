import 'package:flutter/material.dart';

import '../domain/pricing/price.dart';
import 'amount_row.dart';

/// A price typed as a number on the left and a currency on the right.
///
/// **The same row as [`MeasureField`] with the opposite rule about changing the menu**, and
/// the difference is the whole reason this is a second widget rather than a flag on the first.
///
/// A millilitre and a centilitre are two names for one quantity with a fixed ratio between
/// them, so switching the menu beside a *measurement* **converts** the number: 700 ml becomes
/// 70 cl and the bottle did not change. A yuan and a yen are two different quantities with no
/// ratio this program can know -- it has no exchange rates, and section 7's series is
/// denominated per currency -- so switching the menu beside a *price* **reinterprets** it: the
/// number stays exactly as typed and only its denomination changes. Converting would need a
/// rate nobody has, and inventing one would move a number by an amount no screen would show.
///
/// **The number is what a person reads, not the minor unit.** It used to be `价格（分）`, a
/// whole number of fen, because the minor unit is what gets stored and the field had no way to
/// say otherwise. That only works for a currency with two digits: a yen has none and a dinar
/// has three, so `1200` meant twelve yuan in one slot and one thousand two hundred yen in
/// another, with the label naming neither. Now the number is `45.50` and the menu says `CNY`,
/// and `minorUnitsTyped` multiplies by that currency's own [Currency.minorUnitDigits] exactly,
/// once, on the way in.
///
/// **The currencies offered are the reader's own slots**, from `CellarPreferences.currencies`
/// -- one primary and up to three secondaries, the same set the settings screen edits and the
/// price history reads. Picking one here changes this entry rather than the preference.
class PriceField extends StatelessWidget {
  const PriceField({
    super.key,
    required this.id,
    required this.label,
    required this.currencyLabel,
    required this.controller,
    required this.currencies,
    required this.currency,
    required this.onCurrencyChanged,
    this.hint,
    this.errorText,
  });

  /// The machine name the widget's keys are built from -- see [AmountRow.id].
  final String id;

  /// What a person reads above the number box.
  final String label;

  /// What a person reads above the currency menu.
  final String currencyLabel;

  final TextEditingController controller;

  /// Every currency this reader may pick, primary first. [currency] must be one of them.
  final List<Currency> currencies;

  final Currency currency;

  final ValueChanged<Currency> onCurrencyChanged;

  final String? hint;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    // **Nothing is rewritten when this changes**, which is the point of the class comment:
    // `onCurrencyChanged` reports the choice and the text is left exactly as typed. There is
    // no `didUpdateWidget` here and there should not be one.
    return AmountRow<Currency>(
      id: id,
      label: label,
      menuLabel: currencyLabel,
      controller: controller,
      options: currencies,
      value: currency,
      // The code and not a symbol: `¥` is the yuan and the yen, and a menu that showed `¥`
      // twice would be a menu nobody could choose from. Section 12.4's rule -- a person does
      // not read the code -- is about keys on the wire; a picker is exactly where the
      // ambiguity has to be visible.
      labelOf: (currency) => currency.code,
      onChanged: onCurrencyChanged,
      hint: hint,
      errorText: errorText,
    );
  }
}
