import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/seed/seed_repository.dart';
import '../domain/model/ingredient.dart';
import '../domain/model/barcode.dart';
import 'barcode_providers.dart';
import '../domain/overlay/synonyms.dart';
import '../domain/preferences/cellar_preferences.dart';
import '../domain/pricing/price.dart';
import '../domain/units/measure_set.dart';
import '../domain/units/quantity.dart';
import '../domain/units/matter_inference.dart';
import '../domain/units/unit.dart';
import '../domain/units/unit_system.dart';
import 'l10n/copy_resolution.dart';
import 'l10n/dual_copy.dart';
import 'l10n/dual_copy_text.dart';
import 'library.dart';
import 'bottle_edit_sheet.dart';
import 'measure_field.dart';
import 'seed_names.dart';
import 'measure_text.dart';
import 'money_text.dart';
import 'preferences_providers.dart';
import 'price_field.dart';
import 'price_history_sheet.dart';
import 'theme.dart';

/// Section 12.3's Stock tab, at P1's scope.
///
/// What P1 asks for is that a person can **enter a bottle** and see what is on
/// the shelf. Browsing by category, expiry and price history are section 12.3's
/// fuller description and section 14 puts the price work in P2, so this screen
/// deliberately does one job: record a bottle, and list what is recorded.
///
/// The sku is an **ingredient id** rather than a free-text name, because that is
/// the string the recipe side matches on. A bottle recorded under a name no
/// recipe uses is a bottle the shelf can never offer for anything, so the field
/// autocompletes against the seed's own vocabulary -- and when there is no seed
/// it says so instead of accepting a string that will never match.
class StockPage extends ConsumerWidget {
  const StockPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seed = ref.watch(seedProvider);
    final cellar = ref.watch(cellarProvider);

    return SafeArea(
      child: cellar.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          // The one place the title is *composed* rather than drawn, so it takes the
          // primary and says so: an error string is a diagnostic, and a pair inside
          // a diagnostic is noise.
          child: Text(
            '${ref.copy(Copy.stockTitle)}: $error',
            style: HollowType.body,
          ),
        ),
        data: (state) {
          final bottles = state.stock.bottles.toList()
            ..sort((a, b) => a.sku.compareTo(b.sku));
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DualCopyText(
                              Copy.stockTitle,
                              style: HollowType.display,
                            ),
                            const SizedBox(height: 4),
                            // **Two widgets instead of one ternary, because the two
                            // branches no longer share a type.** The empty state is
                            // copy and may pair; the count is an interpolation and
                            // may not. The ternary was what made them look like the
                            // same kind of string.
                            if (bottles.isEmpty)
                              DualCopyText(
                                Copy.stockEmpty,
                                style: HollowType.caption,
                              )
                            else
                              Text(
                                '${Copy.stockBottles} · ${bottles.length}',
                                style: HollowType.caption,
                              ),
                          ],
                        ),
                      ),
                      FilledButton.tonal(
                        onPressed: () => _showAddBottle(context, seed),
                        // **A button has one line, and it says which reason.** Not
                        // `dualCopy: false` -- the reader's setting is on, and it is
                        // the room that is missing.
                        child: Text(
                          Copy.stockAddBottle
                              .present(
                                dualCopy: ref.watch(dualCopyProvider),
                                roomForSecondary: false,
                              )
                              .primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (bottles.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
                    child: DualCopyText(
                      Copy.stockEmptyHint,
                      style: HollowType.body,
                    ),
                  ),
                )
              else
                SliverList.builder(
                  itemCount: bottles.length,
                  itemBuilder: (context, index) {
                    final bottle = bottles[index];
                    // **Three names, and the order is the whole point of section 8.**
                    // What this bottle is called if somebody renamed the bottle, else what they call
                    // the ingredient, else the seed's word for it. The two overlay layers are
                    // different sentences -- one about this object, one about the vocabulary -- and
                    // the object wins because it is the more specific answer.
                    // **Four names, in order of who is most specific.** What this bottle is called, what
                    // the reader calls the ingredient, what the seed calls it **in the reader's language**,
                    // and finally the seed's own English name or the raw id. The translation sits below the
                    // reader's own words on purpose: a name somebody typed is a fact, and a translation is a
                    // label.
                    final seedName = seed.value?.ingredientById(bottle.sku)?.name ?? bottle.sku;
                    final name =
                        state.overlay.bottleName(bottle.bottleId) ??
                        state.overlay.ingredientAlias(bottle.sku) ??
                        ref.watch(seedNamesProvider).value?.nameFor(
                              bottle.sku,
                              ref.watch(seedNameLocaleProvider),
                              fallback: seedName,
                            ) ??
                        seedName;
                    // Tapping a bottle asks about that bottle. Section 12.3 puts prices
                    // on this tab and a price is about a sku, so the join is the same
                    // one the shelf already makes. The gesture lives here rather than
                    // inside the row so that the row stays a description of a bottle
                    // instead of becoming a thing that knows what a sheet is.
                    return InkWell(
                      onTap: () => showPriceHistory(
                        context,
                        sku: bottle.sku,
                        name: name,
                      ),
                      // **Long press, because tap is taken.** Tapping a bottle asks about its prices,
                      // which is section 12.3's gesture on this tab; correcting a bottle is the rarer
                      // and more deliberate act, so it is the one that costs a press and hold.
                      onLongPress: () => showBottleEditor(
                        context,
                        bottle: bottle,
                        name: name,
                        // **In the reader's language**, like the name above it: the field is what they read and
                        // edit, and a form that opens on an English noun beside a Chinese one is the same defect
                        // this round is about, one layer down.
                        ingredientName:
                            ref.watch(seedNamesProvider).value?.nameFor(
                              bottle.sku,
                              ref.watch(seedNameLocaleProvider),
                              fallback:
                                  seed.value?.ingredientById(bottle.sku)?.name ?? bottle.sku,
                            ) ??
                            seed.value?.ingredientById(bottle.sku)?.name ??
                            bottle.sku,
                      ),
                      child: _BottleRow(
                        name: name,
                        sku: bottle.sku,
                        remainingMicrolitres: bottle.remaining.microlitres,
                        addedMicrolitres: bottle.added.microlitres,
                        // **The unit this bottle is measured in, which now depends on what it holds.** A
                        // bottle of sugar is offered grams and a bottle of gin millilitres, because the
                        // drinks in the library say how each of them is measured -- falling back to the
                        // liquid set, which is what every bottle used to get.
                        unit: ref
                                .watch(preferencesProvider)
                                .measuresFor(
                                  ref.watch(matterReadingsProvider)[bottle.sku]?.state ??
                                      MatterState.liquid,
                                )
                                ?.primary ??
                            UnitSystem.millilitre,
                        overdrawn: bottle.isOverdrawn,
                      ),
                    );
                  },
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showAddBottle(
    BuildContext context,
    AsyncValue<SeedRepository?> seed,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: HollowPalette.surface,
      builder: (_) => _AddBottleSheet(
        ingredients: seed.value?.ingredients ?? const [],
      ),
    );
  }
}

class _BottleRow extends StatelessWidget {
  const _BottleRow({
    required this.name,
    required this.sku,
    required this.remainingMicrolitres,
    required this.addedMicrolitres,
    required this.unit,
    required this.overdrawn,
  });

  final String name;
  final String sku;

  /// Whole microlitres, as everywhere else. The share below divides them, which is a
  /// `double` and stays one because a progress bar is a length and not a quantity.
  final int remainingMicrolitres;
  final int addedMicrolitres;

  /// The unit this reader measures liquids in.
  final Unit unit;

  final bool overdrawn;

  @override
  Widget build(BuildContext context) {
    // The bar is the remaining share of what went in, which is the only quantity
    // a person glancing at a shelf actually wants.
    final share = addedMicrolitres <= 0
        ? 0.0
        : (remainingMicrolitres / addedMicrolitres).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: Text(name, style: HollowType.title)),
              Text(
                // Was the literal `ml` in a string. The unit is a preference, and a
                // figure that says ml while the reader measures in ounces is a figure
                // that is wrong by a factor of thirty and looks entirely reasonable.
                microlitreText(remainingMicrolitres, unit),
                style: HollowType.numeric.copyWith(
                  color: overdrawn ? HollowPalette.rose : HollowPalette.inkSoft,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: const BorderRadius.all(Radius.circular(3)),
            child: LinearProgressIndicator(
              value: overdrawn ? 1.0 : share,
              minHeight: 3,
              backgroundColor: HollowPalette.line,
              valueColor: AlwaysStoppedAnimation(
                overdrawn ? HollowPalette.rose : HollowPalette.gold,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(sku, style: HollowType.caption),
        ],
      ),
    );
  }
}

/// **Every name this ingredient answers to**: what the library calls it, what the reader's language calls it,
/// and every synonym the reader has attached to either.
///
/// A plain function rather than a method, because it is a fact about a name and a dictionary rather than about
/// a screen -- and it is what the search uses, so it is also what a test can check without a widget.
List<String> _namesOf(
  Ingredient ingredient,
  List<SynonymGroup> groups,
  SeedNames? names,
  String locale,
) {
  final base = <String>{
    ingredient.name,
    if (names != null) names.nameFor(ingredient.id, locale, fallback: ingredient.name),
  }..removeWhere((name) => name.trim().isEmpty);

  // And the reader's own words for it, in both directions: a synonym of the library's name, and a synonym of
  // the name the reader chose.
  final all = <String>{...base};
  for (final name in base) {
    all.addAll(synonymsOf(name, groups));
  }
  return all.toList();
}

/// The form that enters one bottle.
class _AddBottleSheet extends ConsumerStatefulWidget {
  const _AddBottleSheet({required this.ingredients});

  final List<Ingredient> ingredients;

  @override
  ConsumerState<_AddBottleSheet> createState() => _AddBottleSheetState();
}

class _AddBottleSheetState extends ConsumerState<_AddBottleSheet> {
  Ingredient? _ingredient;
  final _volume = TextEditingController(text: '700');

  /// **The barcode, typed or scanned.** The owner asked for manual entry on 2026-09-25, and it is a first-class
  /// way in rather than a fallback: a desktop has no camera, a label wears away, and a number off a receipt is
  /// typed. It is also what makes this whole feature usable before any camera plugin exists.
  final _barcode = TextEditingController();

  /// What the digits turned out to be: not a barcode, a barcode nobody has described, or one that resolves.
  BarcodeResolution? _barcodeVerdict;

  /// The unit this entry is being typed in, or null while the reader has not picked one.
  ///
  /// **Null means "whatever the preference says", not "no unit".** Resolving the preference
  /// into a field at `initState` would freeze the default at the moment the sheet opened, and
  /// a reader who changed their measuring system in another window would be typing into a
  /// form that disagreed with the shelf behind it. Held as an override instead, so the
  /// default stays live and a choice made here outranks it until the sheet closes -- a bottle
  /// bought in ounces is a fact about that bottle, not a request to re-measure the cellar.
  Unit? _pickedUnit;

  /// **The state of matter this ingredient is measured in, worked out from the drinks.**
  ///
  /// It used to be `MatterState.liquid` for every ingredient in the library, which is right for the great
  /// majority and wrong in the two cases a reader notices: a sugar nobody can pour, and a honey that both are
  /// true of. The owner asked for the recognition on 2026-09-22, and this is where it lands -- `matterReadings`
  /// holds the answer per ingredient, computed from the drinks themselves (see `matter_inference.dart`).
  ///
  /// [reading] is kept as well as the state so the form can say *why*, which is the difference between a
  /// default somebody can disagree with and one they can only work around.
  /// Resolves whatever is in the barcode field and, when it names an ingredient, chooses it.
  ///
  /// Asynchronous because a registry read is a file read, and `mounted` is checked after it for the obvious
  /// reason: a reader can close the sheet while the disk is answering.
  Future<void> _checkBarcode(String typed) async {
    if (typed.trim().isEmpty) {
      setState(() => _barcodeVerdict = null);
      return;
    }
    final registry = await ref.read(barcodeRegistryProvider.future);
    final entries = await registry.read();
    final verdict = resolveBarcode(typed, entries, widget.ingredients);
    if (!mounted) return;
    setState(() {
      _barcodeVerdict = verdict;
      if (verdict is BarcodeResolved && verdict.ingredient != null) {
        _ingredient = verdict.ingredient;
      }
    });
  }

  MatterReading? get _reading =>
      _ingredient == null ? null : ref.read(matterReadingsProvider)[_ingredient!.id];

  MatterState get _stateForIngredient => _reading?.state ?? MatterState.liquid;

  /// The units a bottle may be measured in: this reader's set for this ingredient's state, primary first.
  ///
  /// **The fallback is the shelf's own fallback** -- `_BottleRow` reaches for
  /// `UnitSystem.millilitre` when the preference is silent -- so a form and the shelf beside
  /// it cannot end up disagreeing about what an unconfigured cellar measures in.
  List<Unit> _unitsIn(CellarPreferences preferences, [MatterState? state]) =>
      preferences.measuresFor(state ?? _stateForIngredient)?.all ??
      preferences.measuresFor(MatterState.liquid)?.all ??
      const <Unit>[UnitSystem.millilitre];

  /// The unit the volume box is in, which is the reader's choice or else the primary.
  Unit _unitIn(CellarPreferences preferences) =>
      _pickedUnit ?? _unitsIn(preferences).first;

  /// **Empty is a legitimate answer rather than a missing one.** Section 7's series is
  /// built from observations, and a bottle whose price nobody wrote down simply has no
  /// observation -- which the chart shows as a gap, not as a fall to zero. So the field
  /// is optional on purpose, and "no price" stays a decision this form makes rather than
  /// something it quietly invents.
  final _price = TextEditingController();

  /// The currency this price is being typed in, or null while the reader has not picked one.
  ///
  /// **Null means "whatever the preference says", not "no currency"** -- the same shape as
  /// [_pickedUnit] and for the same reason: the primary stays live under the form instead of
  /// being frozen into a field when the sheet opened. Unlike the unit, picking one here does
  /// **not** convert the number already typed: a yuan and a yen have no ratio this program
  /// knows, so the digits stay and only what they are denominated in changes. `PriceField`
  /// carries that argument.
  Currency? _pickedCurrency;

  /// The currencies a price may be denominated in: this reader's slots, primary first.
  List<Currency> _currenciesIn(CellarPreferences preferences) =>
      preferences.currencies.all;

  /// The currency the price box is in, which is the reader's choice or else the primary.
  Currency _currencyIn(CellarPreferences preferences) =>
      _pickedCurrency ?? _currenciesIn(preferences).first;

  /// The day the bottle was bought, defaulting to today.
  ///
  /// **A date and not an instant, held as local midnight.** `PricePeriod` buckets by the
  /// local calendar, so a purchase recorded at 23:50 and one at 00:10 are a day apart --
  /// correct, and not what anybody means by "I bought it on Saturday". Keeping the value at
  /// midnight means the day a person picked is the day the candle lands in.
  ///
  /// **This is the field that makes a chart worth looking at.** Without it every price is
  /// dated by the keystroke, so a cellar recorded in one evening produces one candle, and
  /// there is no way to enter last month's receipt.
  DateTime _purchasedOn = _today();

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  CopyLine? _problem;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _purchasedOn,
      firstDate: DateTime(2000),
      // A day of slack rather than `DateTime.now()`: the picker compares against its own
      // idea of today, and a device whose clock has just crossed midnight would otherwise
      // open on a date it then refuses.
      lastDate: _today().add(const Duration(days: 1)),
    );
    if (picked == null) return;
    setState(() => _purchasedOn = DateTime(picked.year, picked.month, picked.day));
  }

  /// ISO 8601, because a localised date needs `intl` and this build does not have it.
  String get _purchasedLabel =>
      '${_purchasedOn.year.toString().padLeft(4, '0')}-'
      '${_purchasedOn.month.toString().padLeft(2, '0')}-'
      '${_purchasedOn.day.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _barcode.dispose();
    _volume.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final ingredient = _ingredient;
    if (ingredient == null) {
      setState(() => _problem = Copy.stockPickIngredient);
      return;
    }
    // **The unit is read from the form, and the conversion is exact.** What the reader
    // typed is a number in the unit they picked, and it becomes microlitres here -- once,
    // through the same file the shelf prints with. A whole number of millilitres would have
    // been the easy shape and the wrong one: half an ounce is 14 787 µl, not 14 000.
    final microlitres = microlitresTyped(
      _volume.text,
      _unitIn(ref.read(preferencesProvider)),
    );
    if (microlitres == null) {
      setState(() => _problem = Copy.stockVolumeProblem);
      return;
    }
    // Optional, and **refused rather than dropped** when it is not a number: a form that
    // quietly ignored what somebody typed would leave them believing a price had been
    // recorded. This is the path section 7's first source -- manual entry -- actually
    // runs through, so it is the one that has to be honest about failing.
    //
    // **The number is the major unit and the currency beside it says which.** `45.50` in a CNY
    // slot is 4550 minor units and `1200` in a JPY slot is 1200, both exactly: the digit count
    // comes from the currency rather than from a label that assumed two.
    final currency = _currencyIn(ref.read(preferencesProvider));
    final typedPrice = _price.text.trim();
    Money? price;
    if (typedPrice.isNotEmpty) {
      final minorUnits = minorUnitsTyped(typedPrice, currency);
      if (minorUnits == null) {
        setState(() => _problem = Copy.stockPriceProblem);
        return;
      }
      price = Money.fromMinorUnits(minorUnits, currency);
    }
    // **The code is remembered with the ingredient**, which is what makes the second scan of this bottle
    // instant and offline. Remembering only on save is deliberate: a reader who typed a code and then changed
    // their mind about the bottle has not taught the application anything they meant to teach it.
    final typedCode = _barcode.text.trim();
    if (typedCode.isNotEmpty) {
      final registry = await ref.read(barcodeRegistryProvider.future);
      await registry.remember(typedCode, ingredient.id);
    }

    await ref.read(cellarProvider.notifier).addBottle(
      sku: ingredient.id,
      volume: Volume.fromMicrolitres(microlitres),
      name: ingredient.name,
      // **A `Money`, so the currency travels with the price.** The event has carried a
      // `currency` field since the beginning and the form never filled it, which left the
      // price fold naming a denomination for every price this form ever recorded.
      price: price,
      purchasedAtMillis: _purchasedOn.millisecondsSinceEpoch,
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final names = ref.watch(seedNamesProvider).value;
    final locale = ref.watch(seedNameLocaleProvider);
    // **Both insets, and the second one was missing.** viewInsets is the
    // keyboard; padding is the system navigation bar. A sheet that accounts
    // only for the keyboard puts its button under the navigation bar when the
    // keyboard is down, which is exactly what the first run on the phone did.
    final insets = MediaQuery.viewInsetsOf(context);
    final systemPadding = MediaQuery.paddingOf(context);
    // **Watched rather than read**, so a measuring system changed in the settings behind the
    // sheet redraws this form instead of leaving it measuring in the old one. The sheet is a
    // modal, so this is the only thing that can move the default while it is open.
    final preferences = ref.watch(preferencesProvider);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + insets.bottom + systemPadding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DualCopyText(Copy.stockAddBottle, style: HollowType.heading),
          const SizedBox(height: 6),
          // **Here the two branches do share a type**, both being copy, so the
          // ternary stays -- which is exactly the difference between this site and
          // the count above.
          DualCopyText(
            widget.ingredients.isEmpty ? Copy.stockNoVocabulary : Copy.stockPickHint,
            style: HollowType.caption,
          ),
          const SizedBox(height: 18),
          // **The barcode first, because it answers the next question.** Typing or scanning a code the reader
          // has described before fills the ingredient picker below; a code nobody has described is kept and
          // remembered on save. The digits are validated as they are typed, so a mistyped check digit is caught
          // here rather than becoming an ingredient nobody can ever match.
          TextField(
            controller: _barcode,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: ref.copy(Copy.barcodeLabel),
            ),
            onChanged: _checkBarcode,
          ),
          if (_barcodeVerdict case final verdict?) ...[
            const SizedBox(height: 6),
            Text(
              switch (verdict) {
                BarcodeUnusable(problem: BarcodeProblem.length) => ref.copy(Copy.barcodeProblemLength),
                BarcodeUnusable(problem: BarcodeProblem.checkDigit, :final expectedCheckDigit) =>
                  '${ref.copy(Copy.barcodeProblemCheck)}${expectedCheckDigit ?? '?'}',
                BarcodeUnusable() => ref.copy(Copy.barcodeProblemLength),
                BarcodeResolved(:final ingredient, :final entry) => ingredient == null
                    ? '${ref.copy(Copy.barcodeKnown)}${entry.name ?? entry.ingredientId}'
                    : '${ref.copy(Copy.barcodeKnown)}${ingredient.name}',
                BarcodeUnknown() => ref.copy(Copy.barcodeNew),
              },
              style: HollowType.caption.copyWith(
                color: _barcodeVerdict is BarcodeUnusable ? HollowPalette.rose : HollowPalette.inkSoft,
              ),
            ),
          ],
          const SizedBox(height: 18),
          if (widget.ingredients.isNotEmpty)
            Autocomplete<Ingredient>(
              // **The option is drawn in the reader's language now, and the search already was.** The reported
              // symptom was exactly this asymmetry: typing 琴酒 found Gin, and the row it found said "Gin". The
              // matching has asked `_namesOf` since the dictionary existed; the *drawing* asked the seed.
              displayStringForOption: (ingredient) => names?.nameFor(
                    ingredient.id,
                    locale,
                    fallback: ingredient.name,
                  ) ??
                  ingredient.name,
              optionsBuilder: (value) {
                final query = value.text.trim().toLowerCase();
                if (query.isEmpty) return widget.ingredients.take(40);
                // **Every name the reader has for an ingredient finds it, not just the one it is filed
                // under.** Typing 琴酒 has to reach Gin, because a person who calls it 琴酒 and is told there
                // is no such thing will conclude the application is wrong -- and it would be: the dictionary
                // is right there (`synonym_section.dart`, and the owner's examples are the test).
                //
                // The match is still a plain `contains` over a list of names: the synonyms are *added to* the
                // names being searched rather than turned into a second search path, so there is one rule for
                // what matches and no way for the two to disagree.
                final groups = ref.read(cellarProvider).value?.overlay.synonymGroups ?? const [];
                return widget.ingredients.where((ingredient) {
                  for (final name in _namesOf(ingredient, groups, names, locale)) {
                    if (name.toLowerCase().contains(query)) return true;
                  }
                  return ingredient.id.toLowerCase().contains(query);
                });
              },
              onSelected: (ingredient) => _ingredient = ingredient,
              fieldViewBuilder: (context, controller, focus, onSubmit) =>
                  TextField(
                controller: controller,
                focusNode: focus,
                decoration: const InputDecoration(
                  labelText: Copy.stockIngredient,
                  hintText: Copy.stockIngredientHint,
                ),
                onSubmitted: (_) => onSubmit(),
              ),
            ),
          const SizedBox(height: 14),
          // **The number on the left, the unit on the right.** The units are the reader's own
          // liquid set, so a bottle entered in ounces is a bottle the shelf can show in
          // ounces, and the conversion happens once on the way in rather than in somebody's
          // head before they type.
          //
          // The refusal is not repeated into the box: this form says what is wrong in a
          // sentence below the fields, and a red outline saying the same thing in one
          // language would be a second copy of one message.
          MeasureField(
            id: 'stock-volume',
            label: Copy.stockVolume,
            unitLabel: Copy.stockUnit,
            controller: _volume,
            units: _unitsIn(preferences),
            unit: _unitIn(preferences),
            onUnitChanged: (unit) => setState(() => _pickedUnit = unit),
          ),
          // **Why the form chose this unit set, in a sentence.** A default that cannot be explained is one a
          // reader can only work around; this is the line that lets them see the reasoning and disagree with
          // it -- and where the reasoning came from the drinks, it says so.
          if (_reading != null) ...[
            const SizedBox(height: 6),
            Text(
              '${ref.copy(Copy.stockUnitBecause)}${_reading!.because}',
              style: HollowType.caption,
            ),
          ],
          const SizedBox(height: 14),
          // **The same row, and the opposite rule about changing the menu.** A unit converts
          // because a millilitre and a centilitre are two names for one quantity; a currency
          // reinterprets because a yuan and a yen are two quantities and this program has no
          // exchange rate. `PriceField` carries that argument; here it is enough that the
          // digits stay as typed when the menu moves.
          PriceField(
            id: 'stock-price',
            label: Copy.stockPrice,
            currencyLabel: Copy.stockCurrency,
            controller: _price,
            currencies: _currenciesIn(preferences),
            currency: _currencyIn(preferences),
            onCurrencyChanged: (currency) =>
                setState(() => _pickedCurrency = currency),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: DualCopyText(Copy.stockPurchased, style: HollowType.body),
              ),
              TextButton(
                onPressed: _pickDate,
                child: Text(_purchasedLabel, style: HollowType.numeric),
              ),
            ],
          ),
          if (_problem != null) ...[
            const SizedBox(height: 12),
            DualCopyText(
              _problem!,
              style: HollowType.caption.copyWith(color: HollowPalette.rose),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _save,
              child: Text(Copy.stockSave),
            ),
          ),
        ],
      ),
    );
  }
}
