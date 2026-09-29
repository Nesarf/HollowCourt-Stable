/// The `price.*` events, and the fold from the log to a [PriceSeries].
///
/// **Section 7's first source -- manual entry -- means recording a price is an event,
/// not a field.** So it goes into the same append-only log as everything else, for the
/// reasons section 2 gives: the same bytes are the storage format, the sync format and
/// the audit trail. A price that was paid is exactly the kind of fact worth being able
/// to replay.
///
/// **Two shapes in the log are price observations, and the fold reads both.**
///
/// * `price.paid`, this layer's own event, which carries its own currency and source.
/// * `stock.bottle.added` **when it carries a `priceMinor`**, because a bottle bought
///   with its price written down *is* an observation. The alternative -- requiring
///   somebody to re-enter the same number through a second form -- would mean the
///   chart was empty for every bottle already in the cellar, and section 7's first
///   source is manual entry, so wherever a person types a price is a source.
///
/// **A stock-derived observation is dated by `purchasedAtMillis`, not by the event's
/// clock reading**, and the difference is not cosmetic: a cellar entered in one sitting
/// has every event within the same second, so a chart bucketed by the log's clock would
/// draw one candle for a decade of purchases. The purchase date is the axis a price
/// belongs on; the clock reading is only its identity.
///
/// A stock event carries no currency, so one has to be assumed for it -- see
/// [stockPriceCurrency], which is marked as the decision it is.
///
/// **The type string is open, not an enum**, which is `event.dart`'s rule and it
/// applies here more than anywhere: two versions meet during a sync and the older must
/// carry the newer's events across without understanding them. A closed set would force
/// the older build to drop an event, and a dropped price is a price somebody paid and
/// the ledger no longer remembers. So the fold ignores what it does not recognise
/// instead of failing.
library;

import '../pricing/price.dart';
import '../units/quantity.dart';
import 'event.dart';
import 'hlc.dart';
import 'stock.dart';

/// The event type names this layer owns. ASCII and dotted, per section 12.4.
abstract final class PriceEventTypes {
  /// A purchase, recorded by hand. Section 7's first source and the only one version
  /// one produces.
  static const String paid = 'price.paid';
}

/// **[decision] The currency a price taken off a stock event is read in.**
///
/// `stock.bottle.added` has a `priceMinor` and no currency field, which is a real gap
/// in an older event rather than something to paper over silently. The choice is
/// between refusing those observations and naming a currency for them, and refusing
/// would leave the chart empty for a cellar somebody has already entered.
///
/// So it is named, here, in one place, and the newer path is the correct one:
/// [PricePaid] carries its own currency, so anything recorded from now on is right
/// regardless of what this constant says.
///
/// **The prediction this comment used to make was wrong, and the correction is worth more than
/// the sentence it replaced.** It said: *"The day the add-bottle form asks for a currency, this
/// constant stops being reachable and should be deleted rather than left as a default."* That day
/// has arrived -- the form asks, and it writes the currency it was told -- and the constant did
/// **not** stop being reachable. What made it reachable was never the form: it is every
/// `stock.bottle.added` already written without a currency, including the ones in the owner's own
/// log on the phone. Deleting it would drop those observations out of the chart, which is the
/// outcome the paragraph above rejects.
///
/// So it stays, with a narrower job than it had: a **read** fallback for events that predate the
/// field, and for nothing else. Nothing may use it to *write* a price, because a price whose
/// denomination comes from a constant is a number that means something else the day the constant
/// is wrong.
const Currency stockPriceCurrency = Currency.cny;

/// One price operation, as read back off the log.
///
/// Sealed and not a single class with a nullable field, matching `StockOp`: the three
/// sources in section 7 are three different claims about how a number is known, and a
/// union is the honest shape for "one of these, and a caller must handle each".
sealed class PriceOp {
  const PriceOp(this.hlc);

  final Hlc hlc;

  /// Reads an op off an event, or returns null when this is not one of ours.
  ///
  /// Returning null rather than throwing is what lets an older build carry a newer
  /// build's events: unrecognised is the normal case during a sync, not an error.
  static PriceOp? tryParse(Event event) {
    switch (event.type) {
      case PriceEventTypes.paid:
        return PricePaid.fromEvent(event);
      default:
        return null;
    }
  }

  /// Back to an event, so the log can hold it.
  Event toEvent();
}

/// A price was paid for a volume of something.
///
/// **[sku] is required, and it is not a nicety.** Section 7's metrics are per item --
/// a cost per glass is the cost of *this* ingredient -- so an observation that could
/// not say what it was about would build a chart of the whole cellar mixed together,
/// which is a number with no meaning. A `PricePoint` does not carry it, because a point
/// is a price at a time; the sku belongs to the question being asked, and the filter
/// belongs in [pricePointsOf].
/// Builders for the price events.
///
/// **The writer was missing while the reader was complete**, which is the shape of gap this project
/// keeps finding: `PricePaid.fromEvent` and `toEvent` were both here and nothing ever called the
/// second one, so section 7's "manual entry, the first version's only source" had no way in until a
/// correction needed one. Same rule as `StockEvents`: the clock reading is passed in and nothing here
/// reads the system clock, so an event's contents can be asserted exactly.
abstract final class PriceEvents {
  static Event paid({
    required Hlc hlc,
    required String sku,
    required int minorUnits,
    required Currency currency,
    required int microlitres,
    required PriceSource source,
    int? purchasedAtMillis,
  }) => PricePaid(
    hlc: hlc,
    sku: sku,
    minorUnits: minorUnits,
    currency: currency,
    microlitres: microlitres,
    source: source,
    purchasedAtMillis: purchasedAtMillis,
  ).toEvent();
}

final class PricePaid extends PriceOp {
  const PricePaid({
    required Hlc hlc,
    required this.sku,
    required this.minorUnits,
    required this.currency,
    required this.microlitres,
    required this.source,
    this.purchasedAtMillis,
  }) : super(hlc);

  /// Which ingredient this price is for: the same string a bottle carries and a recipe
  /// item names, so the join is the one `Cellar.has` already makes.
  final String sku;

  final int minorUnits;
  final Currency currency;
  final int microlitres;
  final PriceSource source;

  /// When it was bought, when that is known and different from when it was typed.
  ///
  /// Null means "the clock reading is the best available answer", which is honest for a
  /// price entered on the day it was paid and wrong for one entered from a receipt
  /// months later. The bottle event carries this field for exactly that reason.
  final int? purchasedAtMillis;

  factory PricePaid.fromEvent(Event event) => PricePaid(
    hlc: event.hlc,
    sku: event.require<String>('sku'),
    minorUnits: event.require<int>('minorUnits'),
    currency: _currencyOf(event),
    microlitres: event.require<int>('microlitres'),
    source: _sourceByName(event.require<String>('source')),
    purchasedAtMillis: event.optional<int>('purchasedAtMillis'),
  );

  @override
  Event toEvent() => Event(
    hlc: hlc,
    type: PriceEventTypes.paid,
    data: <String, Object?>{
      'sku': sku,
      'minorUnits': minorUnits,
      'currency': currency.code,
      'microlitres': microlitres,
      'source': source.name,
      'purchasedAtMillis': ?purchasedAtMillis,
    },
  );

  /// The instant this observation belongs at, which is the purchase when we have one.
  int get atMillis => purchasedAtMillis ?? hlc.physicalMillis;

  static Currency _currencyOf(Event event) {
    final code = event.require<String>('currency');
    final currency = Currency.byCode(code);
    if (currency == null) {
      throw ArgumentError.value(
        code,
        'currency',
        'a price in a currency this build does not know is not a price it can total '
            'against anything',
      );
    }
    return currency;
  }

  static PriceSource _sourceByName(String name) {
    for (final source in PriceSource.values) {
      if (source.name == name) return source;
    }
    // A source written by a newer build. It is still a price, and refusing to read it
    // would lose a purchase; `manual` is the conservative reading because it is the
    // one that claims nothing about where the number came from.
    return PriceSource.manual;
  }
}

/// Folds the log into a price series.
///
/// Reads both observation shapes and ignores everything else, including events this
/// build does not recognise. Duplicates are removed by [PriceSeries] itself, which
/// dedupes on [Hlc] -- the same defence `StockLedger.of` needs, and for the same
/// reason: a sync sends everything the other side is missing, and a device missing a
/// stretch of the log rather than one event will send a duplicate.
PriceSeries priceSeriesOf(
  Iterable<Event> events, {
  String? sku,
  Set<String> removedBottles = const {},
}) => PriceSeries(pricePointsOf(events, sku: sku, removedBottles: removedBottles));

/// The observations in the log, from either shape, in no particular order.
///
/// [sku] narrows it to one ingredient, which is the only way a per-item metric can be
/// asked for: section 7's cost per glass is the cost of *this* bottle, and a series
/// that mixed the gin with the vermouth would answer a question nobody asked. Null
/// means every item, which is what a cellar-wide total wants.
///
/// **A retracted line contributes nothing, which is what [removedBottles] is for.** This fold
/// walks events and knows nothing about the stock ledger, so without being told it would keep the
/// price of a bottle that `StockEvents.bottleRemoved` has already taken off the shelf -- and a chart
/// showing a purchase that no longer exists is worse than an empty one, because it looks like data.
/// The caller passes `StockLedger.removedBottleIds`, which is the set the shelf itself was built
/// from, so the two folds cannot disagree about whether a line happened.
///
/// Split out from [priceSeriesOf] so that a caller which already has points can build a
/// series from its own fold without going back to raw events.
List<PricePoint> pricePointsOf(
  Iterable<Event> events, {
  String? sku,
  Set<String> removedBottles = const {},
}) {
  final points = <PricePoint>[];
  for (final event in events) {
    final paid = PriceOp.tryParse(event);
    if (paid is PricePaid) {
      if (sku != null && paid.sku != sku) continue;
      points.add(_pointOf(paid));
      continue;
    }
    final stock = StockOp.tryParse(event);
    if (stock is BottleAdded) {
      if (sku != null && stock.sku != sku) continue;
      if (removedBottles.contains(stock.bottleId)) continue;
      final point = _pointOfBottle(stock);
      if (point != null) points.add(point);
    }
  }
  return points;
}

PricePoint _pointOf(PricePaid op) => PricePoint(
  hlc: Hlc(
    physicalMillis: op.atMillis,
    counter: op.hlc.counter,
    nodeId: op.hlc.nodeId,
  ),
  paid: Money.fromMinorUnits(op.minorUnits, op.currency),
  volume: Volume.fromMicrolitres(op.microlitres),
  source: op.source,
);

/// A bottle that was bought with its price recorded, or null when it was not.
///
/// Null is the common case and not a failure: a bottle added without a price is a
/// bottle whose price nobody knows yet, and inventing zero for it would put a crash to
/// the bottom of every chart in the cellar.
///
/// **The currency is read off the event when the writer stated one**, and only falls back
/// to [stockPriceCurrency] when it did not. That fallback is for events written before the
/// field was read at all; a price whose denomination is silently substituted is a number
/// that means something else, and nothing about it would look wrong.
PricePoint? _pointOfBottle(BottleAdded op) {
  if (op.priceMinor == null) return null;
  final at = op.purchasedAtMillis ?? op.hlc.physicalMillis;
  return PricePoint(
    hlc: Hlc(
      physicalMillis: at,
      counter: op.hlc.counter,
      nodeId: op.hlc.nodeId,
    ),
    paid: Money.fromMinorUnits(op.priceMinor!, _currencyOfBottle(op)),
    volume: op.volume,
    source: PriceSource.manual,
  );
}

Currency _currencyOfBottle(BottleAdded op) {
  final code = op.currency;
  if (code == null || code.isEmpty) return stockPriceCurrency;
  final currency = Currency.byCode(code);
  if (currency == null) {
    // Refused rather than substituted, for the reason `PricePaid` refuses one: a price in
    // a currency this build cannot name is a price it cannot total against anything, and
    // quietly reading it as CNY would move a number by whatever the exchange rate is.
    throw ArgumentError.value(
      code,
      'currency',
      'a bottle priced in a currency this build does not know cannot be charted',
    );
  }
  return currency;
}
