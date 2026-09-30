import 'price.dart';
import '../stats/shopping_list.dart';

/// What the shopping list would cost, priced from what the reader has actually paid.
///
/// **This replaces a question that had no answer.** Section 7 left open which price sources this project may
/// query, and it sat in the record for months as a decision waiting on the owner. Measured on 2026-09-30 it is not
/// a decision: the only open, anonymously-readable price database of any size -- Open Prices, from Open Food
/// Facts, 318,953 records under ODbL -- has no coverage in China at all. Of its eight hundred most recent prices,
/// 44.5% are French, 24.9% Norwegian and 9.5% German; not one is from China and not one is in CNY, while CNY is
/// what this application offers a 简中 reader by default. Everything else the search turns up is retail
/// *scraping*, which is not a source but a way of taking somebody else's.
///
/// **So the comparison is the reader's own receipts.** Every price this application knows was paid by the person
/// reading the screen, at a shop they go to, for a bottle they own -- a better answer to "what will this cost me"
/// than a crowdsourced figure from another country. It needs no network and no account, and it sends nothing
/// anywhere, so it does not touch the promise the application is built on.
///
/// **What it deliberately does not do is guess how many bottles to buy.** A `ShoppingEntry` carries `neededBy`,
/// which counts the planned *recipes* naming an ingredient -- not the bottles a shop sells and not the volume a
/// recipe calls for. Deriving a total from it would be inventing a number. So [total] sums the last known price
/// per ingredient, and the screen says which of the two figures it is showing.
final class ShoppingSpend {
  const ShoppingSpend({required this.lines, required this.currency, required this.unpriced});

  /// One row per ingredient that has a price to show, in the order the shopping list gave them.
  final List<ShoppingSpendLine> lines;

  /// The currency the lines are in, or null when there are no lines or when they disagree.
  ///
  /// **One currency or none.** A reader who buys in two currencies has two of these lists, not one list with a
  /// mixed total -- the rule `PriceSeries.isSingleCurrency` states for the chart, for the same reason: two rates
  /// compared as numbers mean nothing, and the mistake is invisible because the figures still add up.
  final Currency? currency;

  /// How many ingredients of the list have no price at all, so a screen can say the total is not the whole story.
  final int unpriced;

  bool get isEmpty => lines.isEmpty;

  /// The sum of the lines. Meaningless when [currency] is null, and the screen checks that first.
  Money get total => Money.fromMinorUnits(
    lines.fold(0, (sum, line) => sum + line.point.paid.minorUnits),
    currency ?? const Currency('XXX', 2),
  );

  /// Prices a shopping list from what has already been paid for each ingredient.
  ///
  /// [lastPaid] answers "what did this cost the last time" for one ingredient id, or null when nothing has ever
  /// been recorded for it. It hands back the whole `PricePoint` rather than the amount, because **a price without
  /// its volume is not an answer**: `¥128` means nothing as the price of gin, and `¥128 for 700 ml` is a figure a
  /// person can hold against the bottle in front of them. The point already carries both, so this keeps them
  /// together instead of inventing a second type that could drift from it.
  ///
  /// It is a function rather than a map of prices so the caller decides where the answer comes from, which keeps
  /// the arithmetic testable without a log, a clock or a provider.
  factory ShoppingSpend.of(
    ShoppingList list, {
    required PricePoint? Function(String ingredientId) lastPaid,
  }) {
    final lines = <ShoppingSpendLine>[];
    final currencies = <Currency>{};
    var unpriced = 0;

    for (final entry in list.entries) {
      final point = lastPaid(entry.ingredientId);
      if (point == null) {
        unpriced += 1;
        continue;
      }
      currencies.add(point.paid.currency);
      lines.add(ShoppingSpendLine(entry: entry, point: point));
    }

    return ShoppingSpend(
      lines: List<ShoppingSpendLine>.unmodifiable(lines),
      // **Null rather than a guess when two currencies are in play.** The screen draws the lines and withholds the
      // total; a total that added them would be a number with no meaning that looks exactly like one with.
      currency: currencies.length == 1 ? currencies.first : null,
      unpriced: unpriced,
    );
  }
}

/// One ingredient of the shopping list, and what it cost last time.
final class ShoppingSpendLine {
  const ShoppingSpendLine({required this.entry, required this.point});

  final ShoppingEntry entry;

  /// The last observation for this ingredient: what was paid, and for how much of it.
  final PricePoint point;

  String get ingredientId => entry.ingredientId;

  /// How many planned recipes name it -- a count of recipes, not of bottles.
  int get neededBy => entry.neededBy;
}
