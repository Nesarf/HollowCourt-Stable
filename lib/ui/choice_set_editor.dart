import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/preferences/choice_set.dart';
import 'theme.dart';

/// The tallest an expanded menu may get, so it scrolls instead of covering the screen.
///
/// **A menu that fills the window is a menu nobody can see the result in.** These editors offer
/// every unit of a dimension -- eleven for a liquid, sixteen for `either` -- and a
/// `DropdownButton` sizes its menu to its items, so sixteen rows at the default 48 pixels is 768
/// tall: taller than a phone's usable height and taller than a 720-pixel desktop window. The menu
/// then covers the very setting it is changing, on all three platforms, which is what made this
/// worth a number rather than a shrug.
///
/// Half the window with a ceiling of 320, so a phone gets about five rows and a short desktop
/// window still gets half of itself. Not the ceiling alone, because a 400-pixel-tall window would
/// still have four fifths of itself covered, which is the complaint this answers.
double menuMaxHeightFor(BuildContext context) =>
    math.min(320, MediaQuery.sizeOf(context).height * 0.5);

/// One primary choice, up to three secondaries, and no repetition -- edited.
///
/// **The same widget for money and for measures, because they are the same sentence
/// with a different noun.** `ChoiceSet` says so in its own doc comment, and a second
/// copy of this editor would be a second copy of the uniqueness rule as the reader
/// experiences it -- which is where the two would eventually disagree.
///
/// **The rule is enforced by the type, not by the screen.** `ChoiceSet` refuses a
/// duplicate and refuses a fourth secondary at construction, so this widget never has
/// to decide what to do about either: it offers what is legal and the value it produces
/// is legal by the time it exists. What it *does* decide is presentation -- a duplicate
/// in the add-list is marked rather than hidden, because a picker that quietly omits one
/// option looks broken, and one that accepts it silently leaves the reader guessing
/// which of their two choices took.
class ChoiceSetEditor<T> extends StatelessWidget {
  const ChoiceSetEditor({
    super.key,
    required this.value,
    required this.options,
    required this.labelOf,
    required this.keyOf,
    required this.onChanged,
    this.addPrompt,
  });

  final ChoiceSet<T> value;

  /// Everything that may be chosen, in the order a screen should offer it.
  final List<T> options;

  /// What a person reads.
  final String Function(T) labelOf;

  /// What a program matches on, and what makes two options the same option.
  final String Function(T) keyOf;

  final void Function(ChoiceSet<T>) onChanged;

  final String? addPrompt;

  @override
  Widget build(BuildContext context) {
    final taken = {for (final option in value.all) keyOf(option)};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButton<String>(
          isExpanded: true,
          value: keyOf(value.primary),
          dropdownColor: HollowPalette.surfaceRaised,
          style: HollowType.body,
          // See [menuMaxHeightFor]: without it the expanded list is as tall as its items want to
          // be, which for sixteen units is taller than the window it is being chosen in.
          menuMaxHeight: menuMaxHeightFor(context),
          items: [
            for (final option in options)
              DropdownMenuItem(
                value: keyOf(option),
                child: Text(
                  labelOf(option) +
                      (taken.contains(keyOf(option)) && option != value.primary
                          ? '  ·'
                          : ''),
                ),
              ),
          ],
          onChanged: (key) {
            if (key == null) return;
            final chosen = options.firstWhere((o) => keyOf(o) == key);
            // Promoting to primary is `promote`, which swaps when the choice was
            // already a secondary rather than dropping it: a reader who moves euro to
            // the front has not asked to lose it from the second slot.
            onChanged(value.promote(chosen));
          },
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final option in value.secondary)
              InputChip(
                key: ValueKey('secondary-${keyOf(option)}'),
                label: Text(labelOf(option), style: HollowType.caption),
                backgroundColor: HollowPalette.surfaceRaised,
                side: BorderSide(color: HollowPalette.line),
                onDeleted: () => onChanged(value.removeSecondary(option)),
                deleteIcon: const Icon(Icons.close, size: 15),
              ),
            _AddSecondary<T>(
                value: value,
                options: options,
                taken: taken,
                labelOf: labelOf,
                keyOf: keyOf,
                prompt: addPrompt,
                onChanged: onChanged,
              ),
          ],
        ),
      ],
    );
  }
}

/// The add-a-secondary control, which is a menu rather than a button.
///
/// Disabled-looking when every option is already in the set, because a control that
/// opens a menu with nothing selectable in it is worse than one that says so. It stays
/// present rather than vanishing, so the row does not reflow when the last option is
/// taken.
class _AddSecondary<T> extends StatelessWidget {
  const _AddSecondary({
    required this.value,
    required this.options,
    required this.taken,
    required this.labelOf,
    required this.keyOf,
    required this.prompt,
    required this.onChanged,
  });

  final ChoiceSet<T> value;
  final List<T> options;
  final Set<String> taken;
  final String Function(T) labelOf;
  final String Function(T) keyOf;
  final String? prompt;
  final void Function(ChoiceSet<T>) onChanged;

  @override
  Widget build(BuildContext context) {
    final available = [
      for (final option in options)
        if (!taken.contains(keyOf(option))) option,
    ];

    return PopupMenuButton<T>(
      key: const ValueKey('add-secondary'),
      // The second door onto the same list, so it gets the same ceiling. A `PopupMenuButton` sizes
      // itself to its items too, and the add-list is at its longest when nothing has been chosen
      // yet -- which is exactly when a reader is looking for one unit among sixteen.
      constraints: BoxConstraints(
        maxHeight: menuMaxHeightFor(context),
        minWidth: 200,
      ),
      // Disabled when the set is full as well as when nothing is left to add, so the
      // chip stays on screen in both cases. The comment above this widget claimed that
      // and the code omitted the chip entirely when full, which its own test found.
      enabled: !value.isFull && available.isNotEmpty,
      tooltip: prompt ?? '',
      color: HollowPalette.surfaceRaised,
      onSelected: (option) => onChanged(value.addSecondary(option)),
      itemBuilder: (context) => [
        for (final option in available)
          PopupMenuItem(value: option, child: Text(labelOf(option))),
      ],
      child: Chip(
        label: Text(prompt ?? '+', style: HollowType.caption),
        backgroundColor: Colors.transparent,
        side: BorderSide(color: HollowPalette.line),
        avatar: !value.isFull && available.isNotEmpty
            ? Icon(Icons.add, size: 15, color: HollowPalette.inkFaint)
            : null,
      ),
    );
  }
}
