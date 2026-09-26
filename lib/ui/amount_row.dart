import 'package:flutter/material.dart';

import 'theme.dart';

/// A number on the left and something that names it on the right.
///
/// **The row that a measurement and a price are both made of**, and it is one widget for the
/// reason `ChoiceSetEditor` is one widget for money and for measures: they are the same
/// sentence with a different noun, and a second copy of this row would be a second copy of
/// the layout decisions below -- which is where the two would eventually disagree about how
/// tall a box is.
///
/// What the two callers do *not* share is what happens when the menu changes, and that is
/// deliberately left out of here: `MeasureField` converts, `PriceField` does not, and the
/// reason each is right is in its own file. This widget only draws the row and reports the
/// choice.
///
/// **The menu is an `InputDecorator` around a `DropdownButton`, not a
/// `DropdownButtonFormField`.** The caller owns the chosen value, so the control has to follow
/// the screen; a form field keeps its own copy through `initialValue`, its `value` parameter
/// having been deprecated for exactly that reason. What is borrowed from the decorator is the
/// box and the label, so the menu and the number sit on one line.
///
/// **`isDense: true`, and it is the difference between one row and two heights.** A
/// `DropdownButton` keeps a 48-pixel minimum, so inside a decorator it made the menu 80 pixels
/// tall beside a 56-pixel number box. Measured: dense gives 56 and 56, which is what every
/// other field in these forms is. The tap target stays the whole decorator, so nothing is lost
/// but padding.
class AmountRow<T> extends StatelessWidget {
  const AmountRow({
    super.key,
    required this.id,
    required this.label,
    required this.menuLabel,
    required this.controller,
    required this.options,
    required this.value,
    required this.labelOf,
    required this.onChanged,
    this.hint,
    this.errorText,
  });

  /// The machine name the widget's keys are built from, in English like every identifier.
  ///
  /// Separate from [label] for the reason `ChoiceSetEditor` separates `keyOf` from `labelOf`:
  /// what a person reads is copy and gets translated, and a widget key that moved with a
  /// translation would be a key no test could name.
  final String id;

  /// What a person reads above the number box.
  final String label;

  /// What a person reads above the menu.
  final String menuLabel;

  /// The number as typed. Owned by the caller, because the form is the thing that refuses a
  /// bad one and stores a good one.
  final TextEditingController controller;

  /// Everything that may be chosen, in the order a screen should offer it.
  ///
  /// **[value] must be one of these.** A `DropdownButton` cannot display a value it was not
  /// offered, and the assertion that says so is the right place to find a caller that got it
  /// wrong.
  final List<T> options;

  final T value;

  /// What a person reads in the menu: a unit symbol, or a currency code.
  final String Function(T) labelOf;

  final ValueChanged<T> onChanged;

  final String? hint;
  final String? errorText;

  /// The key the number box answers to, for a test or a screen that needs to type in it.
  static Key valueKeyFor(String id) => ValueKey('$id-value');

  /// The key the menu answers to.
  static Key menuKeyFor(String id) => ValueKey('$id-menu');

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            key: valueKeyFor(id),
            controller: controller,
            // Decimal, because the thing beside it is a choice: `l`, `cl` and `oz` all make a
            // fraction of a unit an ordinary thing to type, and so does `45.50` beside a
            // currency. A field with a menu can never insist on a whole number.
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: label,
              hintText: hint,
              errorText: errorText,
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 108,
          child: InputDecorator(
            decoration: InputDecoration(labelText: menuLabel),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                key: menuKeyFor(id),
                isExpanded: true,
                isDense: true,
                value: value,
                dropdownColor: HollowPalette.surfaceRaised,
                style: HollowType.numeric,
                items: [
                  for (final option in options)
                    DropdownMenuItem(value: option, child: Text(labelOf(option))),
                ],
                onChanged: (option) {
                  if (option == null) return;
                  onChanged(option);
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
