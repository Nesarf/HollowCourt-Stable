import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/events/stock.dart';
import '../domain/pricing/price.dart';
import '../domain/units/measure_set.dart';
import '../domain/units/quantity.dart';
import '../domain/units/unit.dart';
import '../domain/units/unit_system.dart';
import 'l10n/dual_copy.dart';
import 'l10n/dual_copy_text.dart';
import 'library.dart';
import 'measure_field.dart';
import 'measure_text.dart';
import 'money_text.dart';
import 'preferences_providers.dart';
import 'price_field.dart';
import 'theme.dart';

/// Corrects a bottle that has already been recorded.
///
/// **The screen section 6 implied and never had.** Four operations -- recounted, discarded, removed,
/// priced -- have existed in the domain since the beginning, reduced by the fold, and **not one of them
/// had a writer**, so a bottle entered wrong stayed wrong. That is the same shape as the missing
/// `massOf` and the missing `price.paid` builder: the model was ahead of the interface, and the gap
/// only shows when somebody tries to do the thing.
///
/// WHY A SHEET AND NOT AN EDIT FORM ON THE ROW.
///
/// A row on a shelf is a *description*; this is a set of decisions about one bottle, and two of them
/// are destructive. Putting them in a sheet means the destructive ones are behind a deliberate press
/// and can say what they will do before they do it, which a row of inline controls cannot.
///
/// **Six things, and each is the verb the domain already has** rather than a shape invented here:
/// renaming this bottle (an overlay field), renaming its ingredient (the other overlay field),
/// recounting what is left (`BottleRecounted`), recording what it cost (`PricePaid` -- a *new point*,
/// because section 7 keeps a series and not a field), pouring the rest away (`BottleDiscarded`), and
/// retracting the line entirely (`BottleRemoved`).
Future<void> showBottleEditor(
  BuildContext context, {
  required BottleState bottle,
  required String name,
  required String ingredientName,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: HollowPalette.surface,
  builder: (_) => _BottleEditor(
    bottle: bottle,
    name: name,
    ingredientName: ingredientName,
  ),
);

class _BottleEditor extends ConsumerStatefulWidget {
  const _BottleEditor({
    required this.bottle,
    required this.name,
    required this.ingredientName,
  });

  final BottleState bottle;
  final String name;
  final String ingredientName;

  @override
  ConsumerState<_BottleEditor> createState() => _BottleEditorState();
}

class _BottleEditorState extends ConsumerState<_BottleEditor> {
  /// The three things that can be typed into: a name, an amount, and a price.
  ///
  /// **One controller per field rather than one per action**, because the actions are alternatives
  /// rather than a sequence: a reader fixes one thing, sees the shelf change, and comes back for the
  /// next if there is one.
  final _bottleName = TextEditingController();
  final _ingredientName = TextEditingController();
  final _amount = TextEditingController();
  final _price = TextEditingController();

  Unit? _pickedUnit;
  Currency? _pickedCurrency;
  CopyLine? _problem;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _bottleName.text = widget.name;
    _ingredientName.text = widget.ingredientName;
    // What is left, as the starting point: a recount is almost always a correction *of* that number
    // rather than a new one from nothing.
    _amount.text = _amountText(widget.bottle.remaining);
  }

  String _amountText(Volume volume) =>
      volumeNumber(volume, _unit);

  Unit get _unit =>
      _pickedUnit ??
      ref.read(preferencesProvider).measuresFor(MatterState.liquid)?.primary ??
      UnitSystem.millilitre;

  List<Unit> get _units =>
      ref.read(preferencesProvider).measuresFor(MatterState.liquid)?.all ??
      const <Unit>[UnitSystem.millilitre];

  List<Currency> get _currencies =>
      ref.read(preferencesProvider).currencies.all;

  Currency get _currency =>
      _pickedCurrency ?? _currencies.first;

  @override
  void dispose() {
    _bottleName.dispose();
    _ingredientName.dispose();
    _amount.dispose();
    _price.dispose();
    super.dispose();
  }

  /// Runs one correction, saying so if it could not be done.
  ///
  /// **The refusal is the interesting case**, and it is why these return a bool rather than nothing:
  /// the one action that can be refused is the retraction of a bottle somebody has already poured
  /// from, and a screen that closed anyway would leave the reader believing the line was gone.
  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      await action();
      if (mounted) Navigator.of(context).pop();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _problem = Copy.bottleEditFailed;
        });
      }
      // The error itself is not shown: it is a transport or file failure, and the reader's next move
      // is the same either way -- try again, or leave it alone.
      debugPrint('bottle edit failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(cellarProvider.notifier);
    final insets = MediaQuery.viewInsetsOf(context);
    final padding = MediaQuery.paddingOf(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + insets.bottom + padding.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DualCopyText(Copy.bottleEditTitle, style: HollowType.heading),
            const SizedBox(height: 4),
            DualCopyText(Copy.bottleEditHint, style: HollowType.caption),
            const SizedBox(height: 18),

            // ---- the two names ------------------------------------------------------------
            DualCopyText(Copy.bottleEditName, style: HollowType.caption),
            const SizedBox(height: 6),
            TextField(
              controller: _bottleName,
              style: HollowType.body,
              decoration: const InputDecoration(isDense: true),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(
                          () => notifier.renameBottle(
                            widget.bottle.bottleId,
                            _bottleName.text,
                          ),
                        ),
                child: DualCopyText(Copy.bottleEditNameSave, style: HollowType.caption),
              ),
            ),
            const SizedBox(height: 10),
            DualCopyText(Copy.bottleEditIngredient, style: HollowType.caption),
            const SizedBox(height: 6),
            TextField(
              controller: _ingredientName,
              style: HollowType.body,
              decoration: const InputDecoration(isDense: true),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(
                          () => notifier.renameIngredient(
                            widget.bottle.sku,
                            _ingredientName.text,
                          ),
                        ),
                child: DualCopyText(
                  Copy.bottleEditIngredientSave,
                  style: HollowType.caption,
                ),
              ),
            ),

            const SizedBox(height: 18),
            // ---- what is left -------------------------------------------------------------
            DualCopyText(Copy.bottleEditAmount, style: HollowType.caption),
            const SizedBox(height: 8),
            MeasureField(
              id: 'bottle-amount',
              label: Copy.stockVolume,
              unitLabel: Copy.stockUnit,
              controller: _amount,
              units: _units,
              unit: _unit,
              onUnitChanged: (unit) => setState(() => _pickedUnit = unit),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    key: const ValueKey('recount'),
                    onPressed: _busy ? null : _recount,
                    child: DualCopyText(Copy.bottleEditRecount, style: HollowType.caption),
                  ),
                ),
                Expanded(
                  child: TextButton(
                    key: const ValueKey('discard'),
                    onPressed: _busy ? null : _discard,
                    child: DualCopyText(Copy.bottleEditDiscard, style: HollowType.caption),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),
            // ---- what it cost -------------------------------------------------------------
            DualCopyText(Copy.bottleEditPrice, style: HollowType.caption),
            const SizedBox(height: 8),
            PriceField(
              id: 'bottle-price',
              label: Copy.stockPrice,
              currencyLabel: Copy.stockCurrency,
              controller: _price,
              currencies: _currencies,
              currency: _currency,
              onCurrencyChanged: (currency) =>
                  setState(() => _pickedCurrency = currency),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const ValueKey('record-price'),
                onPressed: _busy ? null : _recordPrice,
                child: DualCopyText(Copy.bottleEditPriceSave, style: HollowType.caption),
              ),
            ),

            const SizedBox(height: 18),
            // ---- and the destructive one --------------------------------------------------
            DualCopyText(Copy.bottleEditRemoveNote, style: HollowType.caption),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const ValueKey('remove-line'),
              onPressed: _busy ? null : _remove,
              child: DualCopyText(Copy.bottleEditRemove, style: HollowType.body),
            ),

            if (_problem != null) ...[
              const SizedBox(height: 14),
              DualCopyText(
                _problem!,
                style: HollowType.caption.copyWith(color: HollowPalette.rose),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _recount() async {
    final microlitres = microlitresTyped(_amount.text, _unit);
    if (microlitres == null) {
      setState(() => _problem = Copy.stockVolumeProblem);
      return;
    }
    await _run(
      () => ref
          .read(cellarProvider.notifier)
          .recountBottle(
            widget.bottle.bottleId,
            Volume.fromMicrolitres(microlitres),
          ),
    );
  }

  Future<void> _discard() async {
    final microlitres = microlitresTyped(_amount.text, _unit);
    if (microlitres == null) {
      setState(() => _problem = Copy.stockVolumeProblem);
      return;
    }
    await _run(
      () => ref
          .read(cellarProvider.notifier)
          .discardBottle(
            widget.bottle.bottleId,
            Volume.fromMicrolitres(microlitres),
          ),
    );
  }

  Future<void> _recordPrice() async {
    final typed = _price.text.trim();
    final minorUnits = minorUnitsTyped(typed, _currency);
    if (typed.isEmpty || minorUnits == null) {
      setState(() => _problem = Copy.stockPriceProblem);
      return;
    }
    await _run(
      () => ref.read(cellarProvider.notifier).recordPrice(
            sku: widget.bottle.sku,
            price: Money.fromMinorUnits(minorUnits, _currency),
            bottleId: widget.bottle.bottleId,
          ),
    );
  }

  /// Retracts the line, **or says why it cannot be retracted**.
  ///
  /// The refusal is a rule and not a nicety: once a drink has been poured from this bottle, the pour is
  /// in the log and the consumption curve counts it, so deleting the bottle would leave a glass with
  /// nothing to belong to. What such a bottle needs is a discard, not a retraction.
  Future<void> _remove() async {
    final removed = await ref
        .read(cellarProvider.notifier)
        .removeBottle(widget.bottle.bottleId);
    if (!mounted) return;
    if (removed) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _problem = Copy.bottleEditRemoveRefused);
  }
}
