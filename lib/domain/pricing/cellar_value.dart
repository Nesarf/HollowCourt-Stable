/// Section 7's `Total cellar value`, and the part of it that could not be counted.
///
/// **The un-counted part is not an implementation detail, it is half the answer.** A
/// total built from the bottles that happen to have a price is a number that looks
/// complete and is not, and the failure is invisible: the figure goes up when somebody
/// enters a price, which reads as the cellar becoming more valuable rather than as the
/// estimate becoming less wrong. So [CellarValue] carries `unpriced` beside the total,
/// and a caller that shows one without the other is choosing to.
///
/// **A holding with nothing left is skipped rather than counted as unpriced.** An empty
/// bottle on the shelf is worth zero, which is a known answer; reporting it as a missing
/// price would turn "I drank it" into "I forgot to write down what it cost".
library;

import '../events/event.dart';
import '../events/price.dart';
import '../units/quantity.dart';
import 'price.dart';

/// What the shelf is worth, and how much of it that figure covers.
final class CellarValue {
  const CellarValue({
    required this.total,
    required this.priced,
    required this.unpriced,
  });

  /// The sum, or null when not one holding could be valued.
  ///
  /// Null rather than a zero [Money], because a cellar nobody has priced is not a
  /// cellar worth nothing -- the same distinction `PriceSeries.costOf` makes, one layer
  /// up. The currency is the one every contributing holding agreed on.
  final Money? total;

  /// How many holdings the total is built from.
  final int priced;

  /// How many had volume on hand and no price to value it with.
  final int unpriced;

  /// Whether the total covers the whole shelf.
  bool get isComplete => unpriced == 0;

  bool get isKnown => total != null;

  @override
  String toString() => 'CellarValue($total, $priced priced, $unpriced unpriced)';
}

/// Sums volume on hand against the current price of each item.
///
/// [holdings] is what is on the shelf, as a sku and a volume. Deliberately a pair rather
/// than a `BottleState`: what a bottle *is* belongs to the stock layer, and this only
/// needs to know what to multiply.
///
/// **Two currencies meeting is refused rather than added**, which is what `Money.+` and
/// `candlesOf` already do. A total that quietly summed CNY and USD would be a number
/// with no unit, and the only symptom would be a cellar that looked expensive.
///
/// **The fold is repeated per holding, and that is a known cost.** Each item re-reads the
/// event list to build its series, so this is O(holdings x events) rather than one pass.
/// It is left that way on purpose: the obvious next step is a single grouped fold, and
/// doing that now would be optimising a figure that is computed once when a screen is
/// opened. Naming it here is cheaper than a reader wondering whether it was noticed.
CellarValue cellarValueOf(
  Iterable<({String sku, Volume onHand})> holdings,
  Iterable<Event> events,
) {
  // Materialised once, because it is walked per holding below.
  final log = events.toList(growable: false);

  Money? total;
  var priced = 0;
  var unpriced = 0;

  for (final holding in holdings) {
    if (holding.onHand.microlitres <= 0) continue;

    final worth = priceSeriesOf(log, sku: holding.sku).costOf(holding.onHand);
    if (worth == null) {
      unpriced++;
      continue;
    }

    if (total == null) {
      total = worth;
    } else {
      if (total.currency != worth.currency) {
        throw ArgumentError.value(
          worth.currency.code,
          'holdings',
          'a cellar value cannot add two currencies: the total would be a number with '
              'no unit, and the only symptom would be a cellar that looked expensive',
        );
      }
      total = total + worth;
    }
    priced++;
  }

  return CellarValue(total: total, priced: priced, unpriced: unpriced);
}
