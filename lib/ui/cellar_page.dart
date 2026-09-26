import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/consumption/consumption.dart';
import '../domain/pricing/cellar_value.dart';
import '../domain/stats/cellar_stats.dart';
import '../domain/stats/shopping_list.dart';
import '../domain/units/measure_set.dart';
import '../domain/units/unit.dart';
import '../domain/units/unit_system.dart';
import 'consumption_chart.dart';
import 'l10n/copy_resolution.dart';
import 'l10n/dual_copy_text.dart';
import 'library.dart';
import 'seed_names.dart';
import 'money_text.dart';
import 'price_period.dart';
import 'preferences_providers.dart';
import 'prism.dart';
import 'sync_section.dart';
import 'synonym_section.dart';
import 'measure_text.dart';
import 'theme.dart';

/// Section 12.3's Cellar tab, as far as a value and nothing further.
///
/// **Four of section 12.3's six things are here now**, and the page still says which:
/// the value, the consumption curve, the reader's own language settings, and the
/// adapters that stand in for devices. A shopping list and the rest of the statistics
/// are not built, so the sentence naming them stays -- replacing it outright would
/// claim six features and ship four.
///
/// The settings live on this tab rather than in a settings screen because section
/// 12.3 has four tabs and none of them is settings: they belong with "devices and
/// sync", since both are facts about this device and not about the cellar.
///
/// **The unpriced count is shown with the total or not at all.** Section 7's total is a
/// sum over the bottles that have a price, and a figure without that qualifier goes up
/// when somebody enters one -- which reads as the cellar becoming more valuable rather
/// than as the estimate becoming less wrong.
/// What to buy, one line per ingredient with how many planned drinks want it.
class _ShoppingRows extends StatelessWidget {
  const _ShoppingRows({required this.list, required this.nameOf});

  final ShoppingList list;

  /// **What this ingredient is called, resolved by the caller.** A function rather than the table and the
  /// locale, because the answer needs three things -- the translation, the reader's language, and the library --
  /// and only one of them belongs to a row.
  ///
  /// **[defect] The row used to draw `entry.ingredientId`.** Not even English: 要买什么 listed `sweetVermouth`
  /// and `campari`, which is a database key on a screen somebody reads with a shopping list in their hand.
  final String Function(String ingredientId) nameOf;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final entry in list.entries)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(nameOf(entry.ingredientId), style: HollowType.body),
              ),
              Text(
                '${Copy.cellarShoppingNeededBy} ${entry.neededBy}',
                style: HollowType.caption.copyWith(color: HollowPalette.inkFaint),
              ),
            ],
          ),
        ),
    ],
  );
}

/// A summary as rows of numbers, not as a chart.
///
/// **`isBare` is shown and `isEmpty` is not**, which is the distinction the whole panel
/// turns on: a cellar that has been drunk dry and a cellar nobody has used are different
/// readings, and the first is the one worth saying out loud.
class _StatsRows extends StatelessWidget {
  const _StatsRows({required this.stats, required this.unit});

  final CellarStats stats;
  final Unit unit;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _row(
        '${stats.bottles} ${Copy.cellarStatsBottles}',
        '${stats.standing} ${Copy.cellarStatsStanding} · '
            '${stats.emptyBottles} ${Copy.cellarStatsEmptyBottles}',
      ),
      _row(
        '${Copy.cellarStatsOnHand} ${volumeText(stats.onHand, unit)}',
        '${stats.distinctSkus} sku',
      ),
      _row(
        '${Copy.cellarStatsDrunk} ${volumeText(stats.drunk, unit)}',
        '${Copy.cellarStatsDiscarded} '
            '${volumeText(stats.discarded, unit)} · ${stats.pours}',
      ),
      if (stats.mostPouredSku != null)
        _row(
          '${Copy.cellarStatsMostPoured} ${stats.mostPouredSku}',
          volumeText(stats.mostPoured, unit),
        ),
      // Named rather than folded into the counts, because a bottle that is emptier than it
      // was ever full is a defect and not a statistic.
      if (stats.overdrawn > 0)
        Text(
          '${Copy.cellarStatsOverdrawn}: ${stats.overdrawn}',
          style: HollowType.caption.copyWith(color: HollowPalette.rose),
        ),
    ],
  );

  Widget _row(String left, String right) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      children: [
        Expanded(child: Text(left, style: HollowType.body)),
        Text(
          right,
          style: HollowType.caption.copyWith(color: HollowPalette.inkFaint),
        ),
      ],
    ),
  );
}

class CellarPage extends ConsumerWidget {
  const CellarPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cellar = ref.watch(cellarProvider);

    return SafeArea(
      child: cellar.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Text(
            '${ref.copy(Copy.cellarTitle)}: $error',
            style: HollowType.body,
          ),
        ),
        data: (state) {
          final value = cellarValueOf(
            state.stock.bottles
                .where((bottle) => bottle.remaining.microlitres > 0)
                .map(
                  (bottle) => (sku: bottle.sku, onHand: bottle.remaining),
                ),
            state.log.events,
          );

          // Cut on the local calendar, which the domain deliberately does not know
          // about: `PricePeriod.bucketOf` is the same calendar the price chart uses,
          // so a day on this screen is a day on that one.
          final curve = ConsumptionCurve.of(
            state.log.events,
            bucketOf: PricePeriod.day.bucketOf,
          );

          // The same log again, joined rather than re-folded: the counts come from the
          // ledger and the volumes from the curve above.
          final stats = CellarStats.of(
            stock: state.stock,
            events: state.log.events,
          );
          final unit =
              ref.watch(preferencesProvider).measuresFor(MatterState.liquid)?.primary ??
                  UnitSystem.millilitre;

          // The plan marks come from the overlay, which is section 8's layer and the reason
          // no storage was invented for this: `OverlayKey.recipe(id, 'plan')` is a field on a
          // key that already existed.
          final seed = ref.watch(seedProvider).value;
          final shopping = seed == null
              ? null
              : ShoppingList.of(
                  recipes: seed.recipes,
                  plannedRecipeIds: {
                    for (final entry in state.overlay.entries.entries)
                      if (entry.key.kind == 'recipe' &&
                          entry.key.field == 'plan' &&
                          entry.value.value == '1')
                        entry.key.id,
                  },
                  // The cellar's own join between a recipe item and a bottle's sku, passed in
                  // as a predicate so this fold does not re-decide it.
                  have: state.has,
                );

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            children: [
              DualCopyText(Copy.cellarTitle, style: HollowType.display),
              const SizedBox(height: 20),
              DualCopyText(Copy.cellarValue, style: HollowType.caption),
              const SizedBox(height: 6),
              Text(
                value.isKnown ? moneyText(value.total!) : '—',
                style: HollowType.numeric.copyWith(
                  fontSize: 30,
                  color: value.isComplete ? HollowPalette.gold : HollowPalette.ink,
                ),
              ),
              const SizedBox(height: 8),
              if (!value.isKnown)
                DualCopyText(Copy.cellarNoPrices, style: HollowType.body)
              else if (!value.isComplete)
                // Single-line, and interpolated: `Copy.cellarUnpriced` is a `String` for
                // that reason, exactly like `Copy.stockBottles`.
                Text(
                  '${value.unpriced} ${Copy.cellarUnpriced}',
                  style: HollowType.caption.copyWith(color: HollowPalette.rose),
                )
              else
                Text(
                  '${value.priced} ${Copy.cellarPriced}',
                  style: HollowType.caption,
                ),
              const SizedBox(height: 28),
              DualCopyText(
                Copy.cellarConsumption,
                style: HollowType.heading,
              ),
              const SizedBox(height: 8),
              if (curve.isEmpty)
                DualCopyText(
                  Copy.cellarConsumptionEmpty,
                  style: HollowType.caption,
                )
              else ...[
                ConsumptionChart(curve: curve, period: PricePeriod.day),
                const SizedBox(height: 6),
                // Both columns named beside the chart, because the chart shows two
                // bars and a person should not have to guess which colour is which.
                Row(
                  children: [
                    Text(
                      '${ref.copy(Copy.cellarDrunk)} '
                      '${curve.drunkTotal.microlitres ~/ 1000} ml',
                      style: HollowType.caption,
                    ),
                    const SizedBox(width: 16),
                    Text(
                      '${ref.copy(Copy.cellarDiscarded)} '
                      '${curve.discardedTotal.microlitres ~/ 1000} ml',
                      style: HollowType.caption.copyWith(
                        color: HollowPalette.inkFaint,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 28),
              DualCopyText(Copy.cellarShopping, style: HollowType.heading),
              const SizedBox(height: 8),
              if (shopping == null)
                const SizedBox.shrink()
              else if (!shopping.hasPlans)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Prism(size: 14, facet: false),
                    const SizedBox(height: 6),
                    DualCopyText(
                      Copy.cellarShoppingNoPlans,
                      style: HollowType.caption,
                    ),
                  ],
                )
              else if (shopping.isEmpty)
                // **An empty list is two readings**, and the screen says which: no plan yet,
                // or a plan the shelf already covers. `hasPlans` is what tells them apart.
                DualCopyText(
                  Copy.cellarShoppingNothing,
                  style: HollowType.caption,
                )
              else
                _ShoppingRows(
                  list: shopping,
                  // The seed's own name in the reader's language; the id only when the library has nothing to
                  // say at all, which is a last resort that should be seen to be one.
                  nameOf: (ingredientId) {
                    final english = seed?.ingredientById(ingredientId)?.name ?? ingredientId;
                    return ref
                            .watch(seedNamesProvider)
                            .value
                            ?.nameFor(ingredientId, ref.watch(seedNameLocaleProvider),
                                fallback: english) ??
                        english;
                  },
                ),
              if (shopping != null && shopping.missingRecipes.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  '${Copy.cellarShoppingOrphaned}: '
                  '${shopping.missingRecipes.length}',
                  style: HollowType.caption.copyWith(color: HollowPalette.rose),
                ),
              ],
              const SizedBox(height: 28),
              DualCopyText(Copy.cellarStats, style: HollowType.heading),
              const SizedBox(height: 8),
              if (stats.isEmpty)
                DualCopyText(
                  Copy.cellarStatsEmpty,
                  style: HollowType.caption,
                )
              else
                _StatsRows(stats: stats, unit: unit),
              // **The settings moved to their own tab.** They were here, under the statistics, on
              // the screen a reader opens to look at their bottles -- which is the wrong place for
              // the controls of the application itself. What remains on this tab is 设备与同步 and
              // the adapters, which are facts about this cellar rather than about the program.
              const SizedBox(height: 28),
              // Section 12.3 lists "devices and sync" on this tab, and it is two halves that were
              // one half for a while. The sync is the half that works: a code to show, a code to
              // type, and an answer. The adapters below are the half that does not -- three doors,
              // all of them shut, and the screen says which of the two reasons applies to each.
              const SyncSection(),
              const SizedBox(height: 28),
              // **The reader's dictionary, and it belongs on this tab rather than in settings.** 设置 is what
              // the application is told about itself; this is what the reader knows about their own bar --
              // and the owner asked for it here by name.
              const SynonymSection(),
            ],
          );
        },
      ),
    );
  }
}
