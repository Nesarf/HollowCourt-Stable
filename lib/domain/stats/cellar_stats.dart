import '../consumption/consumption.dart';
import '../events/event.dart';
import '../events/stock.dart';
import '../units/quantity.dart';

/// Section 12.3's statistics, folded from the log the rest of the app already folds.
///
/// **Nothing here is a new source of truth.** The counts come from [StockLedger] and the
/// volumes come from a [ConsumptionCurve]; this class joins them and presents one screen's
/// worth of numbers. A statistics fold that recomputed the ledger would be a second answer
/// to "how much is left", and the two would eventually differ.
///
/// **The curve is built with one bucket.** A statistics panel asks about the whole history
/// and not about periods -- the periods are the chart's business -- so the bucket function
/// returns a constant and the curve collapses to its totals. That is a use of the curve
/// rather than a special case of it: the fold already knows how to sum a log, and the
/// bucketing is what the caller supplies.
final class CellarStats {
  const CellarStats._({
    required this.bottles,
    required this.standing,
    required this.emptyBottles,
    required this.overdrawn,
    required this.distinctSkus,
    required this.onHand,
    required this.drunk,
    required this.discarded,
    required this.pours,
    required this.mostPouredSku,
    required this.mostPoured,
    required this.onHandBySku,
  });

  /// The whole log, summarised.
  ///
  /// [stock] and [events] must be of the **same log**, which is the same requirement
  /// `Cellar.of` states and for the same reason: a summary built from one and a curve from
  /// another would show a shelf and a history that disagree, and nothing on the screen would
  /// say which was wrong.
  factory CellarStats.of({
    required StockLedger stock,
    required Iterable<Event> events,
  }) {
    var bottles = 0;
    var standing = 0;
    var empty = 0;
    var overdrawn = 0;
    var onHand = Volume.zero;
    final bySku = <String, Volume>{};

    for (final bottle in stock.bottles) {
      bottles++;
      if (bottle.isEmpty) {
        empty++;
      } else {
        standing++;
        onHand = onHand + bottle.remaining;
        bySku[bottle.sku] = (bySku[bottle.sku] ?? Volume.zero) + bottle.remaining;
      }
      // Counted apart from `empty` on purpose: a bottle that is emptier than it ever was
      // full is a real problem, and it is not the same fact as a bottle that was finished.
      if (bottle.isOverdrawn) overdrawn++;
    }

    final curve = ConsumptionCurve.of(events, bucketOf: (_) => 0);

    // The per-sku split is the one thing the curve cannot answer, because a pour names a
    // bottle and a bottle names its sku -- so this is the join, and it needs both folds.
    final pouredBySku = <String, Volume>{};
    for (final event in events) {
      if (event.type != StockEvent.bottleConsumed) continue;
      final millilitres = event.optional<int>('volumeMicrolitres');
      final bottleId = event.optional<String>('bottleId');
      if (millilitres == null || millilitres <= 0 || bottleId == null) continue;
      final sku = stock.bottle(bottleId)?.sku;
      // A pour whose bottle is not in the ledger is not counted rather than attributed to
      // a made-up sku. It is the same kind of gap `consumption` reports as an ignored event.
      if (sku == null) continue;
      pouredBySku[sku] =
          (pouredBySku[sku] ?? Volume.zero) + Volume.fromMicrolitres(millilitres);
    }

    String? top;
    var topVolume = Volume.zero;
    for (final entry in pouredBySku.entries) {
      // Ties break by sku so that the answer does not depend on map iteration order -- the
      // same rule `ShelfLayout.onShelf` applies to two bottles in one place.
      if (entry.value > topVolume ||
          (entry.value == topVolume && top != null && entry.key.compareTo(top) < 0)) {
        top = entry.key;
        topVolume = entry.value;
      }
    }

    return CellarStats._(
      bottles: bottles,
      standing: standing,
      emptyBottles: empty,
      overdrawn: overdrawn,
      distinctSkus: bySku.length,
      onHand: onHand,
      drunk: curve.drunkTotal,
      discarded: curve.discardedTotal,
      pours: curve.pourEvents,
      mostPouredSku: topVolume.isZero ? null : top,
      mostPoured: topVolume,
      onHandBySku: Map.unmodifiable(bySku),
    );
  }

  /// Every bottle the log has ever recorded.
  final int bottles;

  /// Bottles with something left.
  final int standing;

  /// Bottles that are finished.
  final int emptyBottles;

  /// Bottles that are emptier than they were ever full. A defect, counted apart.
  final int overdrawn;

  /// How many different things stand on the shelf. Bottles that are empty do not count,
  /// because a sku nobody can pour from is not a sku the shelf holds.
  final int distinctSkus;

  final Volume onHand;
  final Volume drunk;
  final Volume discarded;
  final int pours;

  /// The sku most has been poured from, or null when nothing has been poured.
  ///
  /// **Null and not an empty string.** "Nothing has been poured" and "the most-poured thing
  /// is unknown" are different readings, and the first is the common one in a new cellar.
  final String? mostPouredSku;

  final Volume mostPoured;

  /// What is left, per sku.
  final Map<String, Volume> onHandBySku;

  /// Whether the log holds nothing at all.
  bool get isEmpty => bottles == 0 && pours == 0;

  /// Whether the shelf holds nothing, whatever the history says.
  bool get isBare => standing == 0;
}
