import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/units/quantity.dart';
import '../domain/units/unit.dart';
import 'amount_row.dart';
import 'measure_text.dart';
import 'unit_labels.dart';

/// A measurement typed as a number on the left and a unit on the right.
///
/// **The unit is a control beside the number rather than a word inside the label.** The
/// volume field's label used to read 容量（毫升）, which is a millilitre bottle and nothing
/// else: a reader who measures in ounces had to convert before typing, and arithmetic done in
/// somebody's head is the one place in this project where a number is allowed to be wrong. So
/// the number goes in a box, the unit is a menu next to it, and the conversion happens once,
/// exactly, on the way in -- through the same file that prints the shelf.
///
/// **The units offered are the reader's own, in the reader's own order.** They come from
/// `CellarPreferences.measuresFor`, the same choice set the shelf renders with, because a form
/// offering every unit this system carries would offer a dash for a bottle of gin. The primary
/// is first, so a metric reader opens on millilitres and an American one on ounces without
/// touching anything. **Choosing a different unit here changes this entry and not the
/// preference**: a bottle bought in ounces is not a request to re-measure the cellar.
///
/// **Changing the unit converts what has already been typed rather than reinterpreting it.**
/// `700` typed in ml and then switched to oz becomes `23.7`, because the number is a statement
/// about a bottle and the unit is only how it is said -- the same reason a changed preference
/// redraws every bottle instead of relabelling it. Reinterpreting would turn `700` into 700 oz
/// under the reader's hands, which is the quiet kind of wrong this project keeps refusing. The
/// text is rounded to the one decimal a shelf uses, so switching back and forth can drift by a
/// tenth of a unit -- nothing is stored until the form is saved, and the stored value is
/// exact.
///
/// **A unit in another dimension is left alone rather than guessed at.** Reading the box as
/// millilitres and writing it as grams needs a density that no source here carries, so a
/// change across dimensions writes nothing at all. [`PriceField`] is the same row with the
/// opposite rule, and the reason is in that file.
// **A `ConsumerStatefulWidget` because the unit's label depends on the reader's language.** The field
// holds a controller and a conversion state, so it stays stateful; it also needs to watch one provider,
// which is the whole difference between this and `StatefulWidget`.
class MeasureField extends ConsumerStatefulWidget {
  const MeasureField({
    super.key,
    required this.id,
    required this.label,
    required this.unitLabel,
    required this.controller,
    required this.units,
    required this.unit,
    required this.onUnitChanged,
    this.hint,
    this.errorText,
  });

  /// The machine name the widget's keys are built from -- see [AmountRow.id].
  final String id;

  /// What a person reads above the number box.
  final String label;

  /// What a person reads above the unit menu.
  final String unitLabel;

  /// The number as typed, owned by the caller.
  final TextEditingController controller;

  /// Every unit this reader may pick for this entry, primary first. [unit] must be one of them.
  final List<Unit> units;

  /// The unit the number is currently in.
  final Unit unit;

  final ValueChanged<Unit> onUnitChanged;

  final String? hint;
  final String? errorText;

  @override
  ConsumerState<MeasureField> createState() => _MeasureFieldState();
}

class _MeasureFieldState extends ConsumerState<MeasureField> {
  @override
  void didUpdateWidget(covariant MeasureField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.unit == widget.unit) return;
    final converted = _converted(oldWidget.unit, widget.unit);
    if (converted != null) widget.controller.text = converted;
  }

  /// What is typed, read in [from] and written in [to], or null when there is nothing to
  /// convert.
  ///
  /// **Rewriting the text rather than the amount**, because while a form is open the text *is*
  /// the amount -- there is no stored value yet to convert. The text is written only when the
  /// box holds something readable: an empty box or a half-typed one is left exactly as the
  /// reader left it, since a unit switch is not a reason to delete what they were saying.
  ///
  /// **Both dimensions, because both have a pair of doors.** This answered only for volume
  /// while `UnitSystem.massOf` did not exist -- there was no way to write a typed number back
  /// as a mass -- and the door exists now, so `milligramsTyped` and `massNumber` complete the
  /// pair and a solid converts exactly as a liquid does.
  String? _converted(Unit from, Unit to) {
    if (from.dimension != to.dimension) return null;
    final typed = widget.controller.text;
    return switch (from.dimension) {
      UnitDimension.volume => switch (microlitresTyped(typed, from)) {
        null => null,
        final microlitres => volumeNumber(
          Volume.fromMicrolitres(microlitres),
          to,
        ),
      },
      UnitDimension.mass => switch (milligramsTyped(typed, from)) {
        null => null,
        final milligrams => massNumber(Mass.fromMilligrams(milligrams), to),
      },
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    return AmountRow<Unit>(
      id: widget.id,
      label: widget.label,
      menuLabel: widget.unitLabel,
      controller: widget.controller,
      options: widget.units,
      value: widget.unit,
      // **The picker shows the unit's *name*, in the reader's language**: a menu of `ml / cl / oz` is a
      // menu of abbreviations, and the reader choosing between a teaspoon and a tablespoon is choosing
      // between two words. The number beside it keeps the international symbol (see `unit_labels.dart`).
      labelOf: (unit) => unitNameFor(unit, ref.watch(unitLocaleProvider)),
      onChanged: widget.onUnitChanged,
      hint: widget.hint,
      errorText: widget.errorText,
    );
  }
}
