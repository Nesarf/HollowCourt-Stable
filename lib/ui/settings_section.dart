import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/pricing/price.dart';
import '../domain/units/measure_set.dart';
import '../domain/units/unit.dart';
import '../domain/units/unit_system.dart';
import 'choice_set_editor.dart';
import 'l10n/locale_choices.dart';
import 'l10n/voice.dart';
import 'l10n/copy_resolution.dart';
import 'l10n/dual_copy.dart';
import 'l10n/dual_copy_text.dart';
import 'l10n/locale_providers.dart';
import 'preferences_providers.dart';
import 'prism.dart';
import 'theme.dart';
import 'unit_labels.dart';

/// Section 12.4's settings, on the Cellar tab.
///
/// **The three fields were already there and had no screen.** `LocaleSettings`,
/// its provider, its persistence and its guards are all built and tested; what was
/// missing was the one place a reader can change them, which is why the tab that
/// section 12.3 gives "devices and sync" is also where the reader's own settings
/// live -- they are the same kind of thing, facts about this device rather than
/// about the cellar.
///
/// **Both pickers offer every shipped locale, and the screen says what happens when
/// they collide.** `LocaleSettings.guarded` resolves a primary and secondary that
/// name the same language by moving the *secondary*, because the primary is the line
/// a reader actually reads. Hiding the collision would be worse than resolving it:
/// a picker that quietly omitted one option looks broken, and one that accepted it
/// silently would leave the reader wondering which of their two choices took.
class SettingsSection extends ConsumerWidget {
  const SettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(localeSettingsProvider);
    final notifier = ref.read(localeSettingsProvider.notifier);


    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DualCopyText(Copy.settingsTitle, style: HollowType.heading),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: PrismDivider(),
        ),
        DualCopyText(Copy.settingsPrimary, style: HollowType.caption),
        const SizedBox(height: 4),
        // **The reason, under the control** -- the settings-row convention borrowed in 12.9.1: a row is a
        // label, a description, a value and a control, and the description says what the choice costs or does.
        DualCopyText(Copy.settingsPrimaryNote, style: HollowType.caption),
        const SizedBox(height: 6),
        _LocalePicker(
          key: const ValueKey('primary-locale-picker'),
          // **The entry, matched on both halves.** 伊丽莎白 and 简中 share a tag, so a lookup by
          // tag alone would return whichever came first and quietly drop the register. When the
          // stored pair matches nothing -- a tag an older build shipped -- a synthetic entry is
          // handed over and the picker draws it as the unknown one, which is what keeps the
          // screen up instead of throwing.
          value: localeChoices().firstWhere(
            (choice) =>
                choice.tag == settings.primaryTag && choice.voice == settings.primaryVoice,
            orElse: () => LocaleChoice(settings.primaryTag, settings.primaryTag, Voice.plain),
          ),
          onChanged: (choice) => notifier.setPrimary(choice.tag, voice: choice.voice),
        ),
        const SizedBox(height: 14),
        DualCopyText(Copy.settingsSecondary, style: HollowType.caption),
        const SizedBox(height: 4),
        DualCopyText(Copy.settingsSecondaryNote, style: HollowType.caption),
        const SizedBox(height: 6),
        _LocalePicker(
          key: const ValueKey('secondary-locale-picker'),
          // **It offers the voices now, and this reverses a decision made here on purpose.** The note that stood in
          // this place read the shipped *languages* alone, on the reasoning that "the register has nothing to do with
          // the second line". **That was wrong**, and a reader on Windows said so on 2026-10-08: *"无法在副语言里选择"*.
          // There is nothing about a second line that makes a register inapplicable to it -- that reasoning was a
          // description of the storage, not of the reader's choice, since one flat `voice` field could only ever
          // belong to one of the two lines. The field is per line now, so the picker is too.
          //
          // **Matched on the pair, like the primary**, because `ja` is two entries: the plain 日语 and
          // ツンデレお嬢様 written for it. Matching on the tag alone would draw whichever came first and quietly drop
          // the register -- which is the same fault the primary picker's own note records.
          value: localeChoices().firstWhere(
            (choice) =>
                choice.tag == settings.secondaryTag && choice.voice == settings.secondaryVoice,
            orElse: () => LocaleChoice(settings.secondaryTag, settings.secondaryTag, Voice.plain),
          ),
          // **The voice travels with the tag.** `setSecondary` drops a register that does not speak the language it
          // was paired with, so a reader cannot end up with a second line reading in a language they did not choose.
          onChanged: (choice) => notifier.setSecondary(choice.tag, voice: choice.voice),
        ),
        const SizedBox(height: 6),
        // Said rather than enforced silently, so a reader who picks the same tag
        // twice knows why one of them moved.
        DualCopyText(Copy.settingsSameTagNote, style: HollowType.caption),
        const SizedBox(height: 10),
        SwitchListTile(
          key: const ValueKey('dual-copy-switch'),
          contentPadding: EdgeInsets.zero,
          value: settings.dualCopy,
          onChanged: notifier.setDualCopy,
          title: Text(
            ref.copy(Copy.settingsDualCopy),
            style: HollowType.body,
          ),
          // **The subtitle was the English line of the label itself**, which is a translation and not an
          // explanation. It is now the reason: what turning this on does, and what it costs.
          subtitle: Text(
            ref.copy(Copy.settingsDualCopyNote),
            style: HollowType.caption,
          ),
        ),
        // **The motif, in the furniture.** A shape that only appears in special places is decoration; one that
        // appears in the dividers is the interface's handwriting (DESIGN.md 12.9.1 / 8.9).
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 14),
          child: PrismDivider(),
        ),
        // 都可以替换，都不可重复, and the editor enforces the second half by producing a
        // legal `ChoiceSet` or nothing -- the widget never has to decide what to do
        // about a duplicate, because a duplicate cannot be constructed.
        const _UnitsAndMoney(),
      ],
    );
  }
}

/// The measuring system and the money, both of them `ChoiceSet`s.
///
/// **Three unit editors and one money editor rather than one per matter state and a
/// list for money**, because 固体液体组合 is three answers to the same question and a
/// currency list is one answer to a different one. Offering them side by side is what
/// makes the shapes comparable: a reader can see that a syrup set holds a unit of each
/// dimension and a currency set does not.
class _UnitsAndMoney extends ConsumerWidget {
  const _UnitsAndMoney();

  static const Map<MatterState, CopyLine> stateLabels = {
    MatterState.liquid: Copy.settingsStateLiquid,
    MatterState.solid: Copy.settingsStateSolid,
    MatterState.either: Copy.settingsStateEither,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(preferencesProvider);
    final notifier = ref.read(preferencesProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DualCopyText(Copy.settingsUnits, style: HollowType.heading),
        const SizedBox(height: 8),
        for (final state in MatterState.values)
          if (preferences.measuresFor(state) != null) ...[
            DualCopyText(stateLabels[state]!, style: HollowType.caption),
            const SizedBox(height: 4),
            ChoiceSetEditor<Unit>(
              key: ValueKey('units-${state.name}'),
              value: preferences.measuresFor(state)!,
              // Only units of the right dimension, except for `either`, which exists
              // to offer both. A picker that offered a gram for a liquid would let a
              // reader build a set the domain would then refuse to convert.
              options: unitsFor(state),
              labelOf: (unit) => unitNameFor(unit, ref.watch(unitLocaleProvider)),
              keyOf: (unit) => unit.id,
              addPrompt: ref.copy(Copy.settingsAdd),
              onChanged: (units) => notifier.setMeasures(state, units),
            ),
            const SizedBox(height: 14),
          ],
        const SizedBox(height: 8),
        DualCopyText(Copy.settingsMoney, style: HollowType.heading),
        const SizedBox(height: 8),
        ChoiceSetEditor<Currency>(
          key: const ValueKey('currencies'),
          value: preferences.currencies,
          options: Currency.all,
          labelOf: (currency) => currency.code,
          keyOf: (currency) => currency.code,
          addPrompt: ref.copy(Copy.settingsAdd),
          onChanged: notifier.setCurrencies,
        ),
      ],
    );
  }
}

/// The units a reader may choose for one state of matter.
///
/// The filter is the type system's, not a hand-written list: a liquid measures in
/// volume units, a solid in mass units, and `either` in both because 糖浆/蜂蜜 are
/// measured either way. Adding a unit to `UnitSystem` therefore makes it selectable
/// without touching this file, which is the property that keeps a picker and the
/// system it picks from in step.
List<Unit> unitsFor(MatterState state) => switch (state) {
  MatterState.liquid => [
    for (final unit in UnitSystem.all)
      if (unit.dimension == UnitDimension.volume) unit,
  ],
  MatterState.solid => [
    for (final unit in UnitSystem.all)
      if (unit.dimension == UnitDimension.mass) unit,
  ],
  MatterState.either => [
    for (final unit in UnitSystem.all)
      if (unit.dimension == UnitDimension.volume ||
          unit.dimension == UnitDimension.mass)
        unit,
  ],
};

/// A locale picker over what this build ships.
///
/// The label is the locale's own name and the tag is beside it, which is the pair
/// `ShippedLocale.toString` already defines and the reason section 12.4 keeps the
/// name UTF-8 and the tag ASCII: a reader picks 简体中文, and the machine matches
/// `zh-Hans`.
class _LocalePicker extends ConsumerWidget {
  const _LocalePicker({super.key, required this.value, required this.onChanged});

  final LocaleChoice value;
  /// **The whole entry, not its tag.** One entry names a language and a register together; see
  /// `ShippedLocale` for why a tag cannot stand in for the choice.
  final void Function(LocaleChoice choice) onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A stored tag the catalogue no longer ships would make `DropdownButton` throw,
    // and the settings file is on disk and outlives a build. Showing the raw tag as
    // a one-entry list keeps the screen up and keeps the value visible instead of
    // losing it, which is the honest reading of "this build does not know that
    // language".
    final choices = localeChoices();
    final known = choices.any((choice) => choice == value);
    final items = [
      for (final choice in choices)
        DropdownMenuItem(value: choice, child: Text(choice.toString())),
      if (!known)
        DropdownMenuItem(
          value: value,
          child: Text('${value.tag} (${ref.copy(Copy.settingsUnknown)})'),
        ),
    ];

    return DropdownButton<LocaleChoice>(
      isExpanded: true,
      value: value,
      dropdownColor: HollowPalette.surfaceRaised,
      style: HollowType.body,
      items: items,
      onChanged: (choice) {
        if (choice != null) onChanged(choice);
      },
    );
  }
}
