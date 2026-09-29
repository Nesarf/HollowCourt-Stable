import 'package:test/test.dart';

import 'package:hollow_court/domain/events/event.dart';
import 'package:hollow_court/domain/events/hlc.dart';
import 'package:hollow_court/domain/events/price.dart';
import 'package:hollow_court/domain/pricing/ohlc.dart';
import 'package:hollow_court/domain/pricing/price.dart';

/// A bottle's own currency, and the date it was bought on.
///
/// `StockEvents.bottleAdded` has always accepted a `currency` and written it into the
/// payload, and `BottleAdded` did not read it -- so a price recorded in USD came back
/// denominated in whatever the fold assumed. **A payload key the writer sets and the reader
/// drops is worse than one that does not exist**, because the first looks like data. These
/// tests are mostly about that.
const int _day = 86400000;

Hlc at(int millis) => Hlc(physicalMillis: millis, counter: 0, nodeId: 'laptop');

Event bottle({
  required int hlcMillis,
  String sku = 'gin',
  int microlitres = 700000,
  int? priceMinor,
  String? currency,
  int? purchasedAtMillis,
}) => Event(
  hlc: at(hlcMillis),
  type: 'stock.bottle.added',
  data: <String, Object?>{
    'bottleId': 'bottle-$sku-$hlcMillis',
    'sku': sku,
    'volumeMicrolitres': microlitres,
    'priceMinor': ?priceMinor,
    'currency': ?currency,
    'purchasedAtMillis': ?purchasedAtMillis,
  },
);

void main() {
  group('a bottle price is denominated in what the event says', () {
    test('the currency on the event is read, not substituted', () {
      final series = priceSeriesOf(<Event>[
        bottle(hlcMillis: 0, priceMinor: 2000, currency: 'USD'),
      ]);

      // 2000 USD minor units, not 2000 CNY. Before this field was read the two were the
      // same number and only one of them was the amount somebody paid.
      expect(series.points.single.paid, Money.fromMinorUnits(2000, Currency.usd));
      expect(series.currency, Currency.usd);
    });

    test('and a series of two currencies is then refused, as it must be', () {
      // The visible consequence of reading the field: a cellar with a dollar bottle and a
      // yuan bottle is now known to be two currencies rather than silently one.
      final series = priceSeriesOf(<Event>[
        bottle(hlcMillis: 0, sku: 'gin', priceMinor: 12000, currency: 'CNY'),
        bottle(hlcMillis: 1, sku: 'bourbon', priceMinor: 2000, currency: 'USD'),
      ]);

      expect(series.isSingleCurrency, isFalse);
      expect(() => candlesOf(series, widthMillis: _day), throwsArgumentError);
    });

    test('an event with no currency keeps the documented fallback', () {
      // Written before this field existed, or by a build that did not state one. The
      // fallback is what `stockPriceCurrency` is for and it is marked as a decision.
      final series = priceSeriesOf(<Event>[
        bottle(hlcMillis: 0, priceMinor: 12000),
      ]);
      expect(series.points.single.paid.currency, stockPriceCurrency);
    });

    test('a currency this build cannot name is refused rather than substituted', () {
      // Not read as CNY, because that would move a number by whatever the rate is, and
      // nothing about the result would look wrong.
      expect(
        () => priceSeriesOf(<Event>[
          bottle(hlcMillis: 0, priceMinor: 100, currency: 'XYZ'),
        ]),
        throwsArgumentError,
      );
    });
  });

  group('the purchase date is what a chart is built on', () {
    test('two bottles entered in one second are a year apart on the chart', () {
      // The whole reason the form gained a date field. Without it, a cellar recorded in one
      // evening produces a single candle and there is no way to enter last month's receipt.
      final series = priceSeriesOf(<Event>[
        bottle(hlcMillis: 1000, priceMinor: 10000, purchasedAtMillis: 0),
        bottle(
          hlcMillis: 2000,
          priceMinor: 14000,
          purchasedAtMillis: _day * 365,
        ),
      ]);

      final candles = candlesOf(series, widthMillis: _day);
      expect(candles.length, 2,
          reason: 'the log clock says one second; the purchases are a year apart');
    });

    test('an event with no purchase date falls back to the clock reading', () {
      final series = priceSeriesOf(<Event>[
        bottle(hlcMillis: 5000, priceMinor: 10000),
      ]);
      expect(series.points.single.hlc.physicalMillis, 5000);
    });
  });
}
