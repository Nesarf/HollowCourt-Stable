import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/events/event.dart';
import '../domain/stats/reorder.dart';
import 'l10n/copy_resolution.dart';
import 'l10n/dual_copy_text.dart';
import 'library.dart';
import 'preferences_providers.dart';
import 'theme.dart';

/// **What is worth buying again** -- stage ④ of `docs/catalogue-and-stock.md`.
///
/// **A section of its own rather than rows in the shopping list**, which is the owner's choice and the right one: the
/// shopping list answers *what do the drinks I plan to make need*, and this answers *what is running out*. They
/// overlap, and a reader at the shop wants one list -- but the two are made of different evidence, and merging them
/// would produce rows nobody could account for. This one sits above the other, so the two are read together and
/// still say which is which.
///
/// **Nothing here is stored.** The bottles, their volumes and their pours are all in the log already, and the reader
/// has nothing to buy in a long time.
class ReorderSection extends ConsumerWidget {
  const ReorderSection({super.key, required this.nameOf, required this.events});

  /// What an ingredient is called, resolved by the caller -- the same function the shopping rows take and for the
  /// same reason: the answer needs the translation table, the reader's language and the library, and only one of
  /// those belongs to a row.
  final String Function(String ingredientId) nameOf;

  /// The events the pours are read from. Passed in rather than reached for, because the caller already has the
  /// merged set -- log plus whatever archives the reader attached -- and a section that read `cellar.log.events`
  /// would quietly ignore the packages.
  final List<Event> events;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cellar = ref.watch(cellarProvider).value;
    if (cellar == null) return const SizedBox.shrink();

    final thresholds = ref.watch(preferencesProvider).reorder;
    final list = ReorderList.of(
      stock: cellar.stock,
      events: events,
      thresholds: thresholds,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: DualCopyText(Copy.reorderTitle, style: HollowType.heading)),
            if (!list.isEmpty)
              Text('${list.entries.length}', style: HollowType.numeric),
          ],
        ),
        const SizedBox(height: 8),
        if (list.isEmpty)
          DualCopyText(Copy.reorderNothing, style: HollowType.caption)
        else
          for (final entry in list.entries) _ReorderRow(entry: entry, nameOf: nameOf),
        const SizedBox(height: 10),
        // **What the list was asked for, on the list.** A reader who thinks a bottle should not be here can see which
        // of the three numbers put it here, and change it from the same place -- which is why the control is beside
        // the sentence rather than in a settings screen three taps away.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                _thresholdsText(ref, thresholds),
                style: HollowType.caption,
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              key: const ValueKey('reorder-edit'),
              onPressed: () => showReorderThresholds(context, ref),
              child: Text(ref.copy(Copy.reorderEdit)),
            ),
          ],
        ),
      ],
    );
  }

  /// The three numbers, in the reader's language.
  ///
  /// **Substituted after resolving rather than before**, so that each language keeps its own word order: the
  /// placeholders are named, and a translator who needs the millilitres first can put them first.
  static String _thresholdsText(WidgetRef ref, ReorderPoint point) => ref
      .copy(Copy.reorderThresholds)
      .replaceFirst('{percent}', '${point.fillPercent}')
      .replaceFirst('{ml}', '${point.millilitres}')
      .replaceFirst('{days}', '${point.horizonDays}');
}

/// One bottle worth buying again, and why.
class _ReorderRow extends StatelessWidget {
  const _ReorderRow({required this.entry, required this.nameOf});

  final ReorderEntry entry;
  final String Function(String ingredientId) nameOf;

  @override
  Widget build(BuildContext context) {
    // **The reasons are drawn, not scored.** A single "lowness" number would let the section sort itself and say
    // nothing: a bottle at 40% going fast and a bottle at 10% sitting still are both worth knowing about and for
    // different reasons, and the reader is the one who decides which matters tonight.
    final reasons = [
      if (entry.reasons.contains(LowReason.nearlyEmpty)) Copy.reorderNearlyEmpty,
      if (entry.reasons.contains(LowReason.smallRemainder)) Copy.reorderSmallRemainder,
      if (entry.reasons.contains(LowReason.runningOutSoon)) Copy.reorderRunningOutSoon,
    ];
    final locale = Localizations.localeOf(context).toLanguageTag();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 54,
            child: Text(
              // **The number that needs no explaining**: how much of the bottle is gone. A bar rather than a
              // fraction, because this is a thing a reader recognises from looking at the bottle in front of them.
              '${(entry.drunk * 100).round()}%',
              style: HollowType.numeric,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nameOf(entry.ingredientId),
                  style: HollowType.body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  [
                    for (final reason in reasons) reason.textFor(locale),
                    // **Only when it can be said.** A young cellar has no speed, and the horizon line is simply
                    // absent rather than shown as "unknown" -- which would read as a fault when it is the ordinary
                    // state of a log a fortnight old.
                    // **A sentence rather than a number and a unit label.** "9 d" is not a thing to say in five
                    // languages, and a separate unit word would need its own line of copy and its own plural rules.
                    if (entry.lastsFor case final lasts?)
                      Copy.reorderLasts
                          .textFor(locale)
                          .replaceFirst('{days}', '${lasts.inDays}'),
                  ].join('  ·  '),
                  style: HollowType.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// **The control that makes "reader-adjustable" true rather than a word in a design note.**
///
/// Three number fields, one per signal, each with the sentence the section is built on. The same
/// `useSafeArea: true` rule every sheet in this application follows.
Future<void> showReorderThresholds(BuildContext context, WidgetRef ref) async {
  final current = ref.read(preferencesProvider).reorder;
  final changed = await showModalBottomSheet<ReorderPoint>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) => _ThresholdSheet(initial: current),
  );
  if (changed == null) return;
  await ref.read(preferencesProvider.notifier).setReorder(changed);
}

class _ThresholdSheet extends ConsumerStatefulWidget {
  const _ThresholdSheet({required this.initial});

  final ReorderPoint initial;

  @override
  ConsumerState<_ThresholdSheet> createState() => _ThresholdSheetState();
}

/// **A `ConsumerState` so that the field labels can be resolved here**, which is the only reason it is not a plain
/// one: the three sentences above the fields are copy in five languages, and a `State` has no `ref` to resolve them
/// with -- handing three strings down from the caller would have put the resolution of a sheet's own labels in the
/// section that opened it.
class _ThresholdSheetState extends ConsumerState<_ThresholdSheet> {
  // **The controllers belong to this widget**, the fault `bar_page.dart` records: creating them in the caller and
  // disposing them when the sheet's future completes disposes them while the route is still popping.
  late final _percent = TextEditingController(text: '${widget.initial.fillPercent}');
  late final _ml = TextEditingController(text: '${widget.initial.millilitres}');
  late final _days = TextEditingController(text: '${widget.initial.horizonDays}');

  @override
  void dispose() {
    _percent.dispose();
    _ml.dispose();
    _days.dispose();
    super.dispose();
  }

  /// A field's number, or the value it started with.
  ///
  /// **An unreadable field keeps what was there rather than becoming zero**, which is not tidiness: zero turns a
  /// signal off silently, and a reader who typed a stray letter would find the list shorter with nothing on the
  /// screen to explain it. The domain refuses out-of-range values too -- `_reorderFromJson` falls back per field --
  /// and this is the same rule at the point a person can see it.
  int _read(TextEditingController field, int fallback) =>
      int.tryParse(field.text.trim()) ?? fallback;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: 20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DualCopyText(Copy.reorderEdit, style: HollowType.title),
          const SizedBox(height: 14),
          _field('reorder-percent', ref.copy(Copy.reorderFieldPercent), _percent, suffix: '%'),
          const SizedBox(height: 12),
          _field('reorder-ml', ref.copy(Copy.reorderFieldMillilitres), _ml, suffix: 'ml'),
          const SizedBox(height: 12),
          _field('reorder-days', ref.copy(Copy.reorderFieldDays), _days, suffix: 'd'),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              key: const ValueKey('reorder-save'),
              onPressed: () => Navigator.of(context).pop(
                widget.initial.copyWith(
                  fillPercent: _read(_percent, widget.initial.fillPercent),
                  millilitres: _read(_ml, widget.initial.millilitres),
                  horizonDays: _read(_days, widget.initial.horizonDays),
                ),
              ),
              child: Text(MaterialLocalizations.of(context).okButtonLabel),
            ),
          ),
        ],
      ),
    ),
  );

  /// **The label arrives resolved rather than as a `CopyLine`**, because this is a `State` and has no `ref`: the
  /// sheet's builder resolves it once and hands the string down, which is the same split `_ReorderRow.nameOf` makes.
  Widget _field(
    String key,
    String label,
    TextEditingController field, {
    required String suffix,
  }) => TextField(
    key: ValueKey(key),
    controller: field,
    keyboardType: TextInputType.number,
    decoration: InputDecoration(labelText: label, suffixText: suffix),
  );
}
