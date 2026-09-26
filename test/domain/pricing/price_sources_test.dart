import 'package:test/test.dart';

import 'package:hollow_court/domain/events/event.dart';
import 'package:hollow_court/domain/events/hlc.dart';
import 'package:hollow_court/domain/events/price.dart';
import 'package:hollow_court/domain/pricing/ohlc.dart';
import 'package:hollow_court/domain/pricing/price.dart';
import 'package:hollow_court/domain/units/quantity.dart';
import 'package:hollow_court/domain/units/rational.dart';

/// Where a price observation comes from, and what happens when two currencies meet.
///
/// Two shapes in the log are observations -- this layer's own `price.paid`, and a
/// `stock.bottle.added` that carries a price -- and the second one is what makes the
/// chart non-empty for a cellar somebody has already entered. The tests below are
/// mostly about the second shape's *time axis*, because that is the part which is
/// wrong by default and looks right.
const int _day = 86400000;

Hlc at(int millis) => Hlc(physicalMillis: millis, counter: 0, nodeId: 'laptop');

/// A bottle event exactly as `StockOp.tryParse` reads one.
Event bottle({
  required int hlcMillis,
  required String sku,
  required int microlitres,
  int? priceMinor,
  int? purchasedAtMillis,
}) => Event(
  hlc: at(hlcMillis),
  type: 'stock.bottle.added',
  data: <String, Object?>{
    'bottleId': 'bottle-$sku-$hlcMillis',
    'sku': sku,
    'volumeMicrolitres': microlitres,
    'priceMinor': ?priceMinor,
    'purchasedAtMillis': ?purchasedAtMillis,
  },
);

Event pricePaid({
  required int hlcMillis,
  required int minorUnits,
  required int microlitres,
  String currency = 'CNY',
  int? purchasedAtMillis,
}) => PricePaid(
  hlc: at(hlcMillis),
  sku: 'gin',
  minorUnits: minorUnits,
  currency: Currency.byCode(currency)!,
  microlitres: microlitres,
  source: PriceSource.manual,
  purchasedAtMillis: purchasedAtMillis,
).toEvent();

void main() {
  group('a bottle bought with its price written down is an observation', () {
    test('it appears, read in the currency a stock event has to assume', () {
      final points = pricePointsOf(<Event>[
        bottle(hlcMillis: 0, sku: 'gin', microlitres: 700000, priceMinor: 12000),
      ]);

      expect(points.length, 1);
      expect(points.single.paid, Money.fromMinorUnits(12000, stockPriceCurrency));
      expect(points.single.volume, Volume.fromMillilitres(700));
      expect(points.single.source, PriceSource.manual);
    });

    test('a bottle with no price contributes nothing rather than contributing zero',
        () {
      // Zero would be a price of nothing and would put a crash to the bottom of every
      // chart in the cellar.
      expect(
        pricePointsOf(<Event>[
          bottle(hlcMillis: 0, sku: 'gin', microlitres: 700000),
        ]),
        isEmpty,
      );
    });

    test('it is dated by the purchase date, not by when somebody typed it in', () {
      // The decisive test. Both bottles were entered in the same second, so a chart
      // bucketed by the log's clock would draw one candle for two purchases a year
      // apart -- and every number in it would be self-consistent.
      final points = pricePointsOf(<Event>[
        bottle(
          hlcMillis: 1000,
          sku: 'gin',
          microlitres: 700000,
          priceMinor: 10000,
          purchasedAtMillis: 0,
        ),
        bottle(
          hlcMillis: 2000,
          sku: 'gin',
          microlitres: 700000,
          priceMinor: 14000,
          purchasedAtMillis: _day * 365,
        ),
      ]);

      final candles = candlesOf(PriceSeries(points), widthMillis: _day);
      expect(candles.length, 2,
          reason: 'the two purchases are a year apart, whatever the log says');
      expect(candles.first.open, Rational.of(1, 70));
      expect(candles.last.open, Rational.of(1, 50));
    });

    test('without a purchase date the clock reading is the honest fallback', () {
      final points = pricePointsOf(<Event>[
        bottle(hlcMillis: 5000, sku: 'gin', microlitres: 700000, priceMinor: 10000),
      ]);
      expect(points.single.hlc.physicalMillis, 5000);
    });

    test('a price paid and a bottle bought are both read from one log', () {
      final series = priceSeriesOf(<Event>[
        bottle(hlcMillis: 0, sku: 'gin', microlitres: 700000, priceMinor: 10000),
        pricePaid(hlcMillis: 100, minorUnits: 14000, microlitres: 700000),
        // Somebody else's event, which this build understands and must not eat.
        Event(hlc: at(50), type: 'stock.bottle.consumed', data: const <String, Object?>{
          'bottleId': 'bottle-gin-0',
          'volumeMicrolitres': 45000,
        }),
      ]);

      expect(series.points.length, 2);
    });

    test('a price paid carries its own purchase date through the round trip', () {
      final read = PriceOp.tryParse(
        pricePaid(
          hlcMillis: 9000,
          minorUnits: 100,
          microlitres: 1000,
          purchasedAtMillis: 42,
        ),
      )! as PricePaid;
      expect(read.atMillis, 42);
      expect(read.hlc.physicalMillis, 9000,
          reason: 'the identity is still the clock reading');
    });
  });

  group('two currencies in one series', () {
    test('is a fact the series reports rather than one it assumes away', () {
      final mixed = priceSeriesOf(<Event>[
        pricePaid(hlcMillis: 0, minorUnits: 10000, microlitres: 700000),
        pricePaid(hlcMillis: 100, minorUnits: 2000, microlitres: 700000, currency: 'USD'),
      ]);

      expect(mixed.isSingleCurrency, isFalse);
      expect(mixed.currency, Currency.usd);
    });

    test('is refused by the chart rather than drawn', () {
      final mixed = priceSeriesOf(<Event>[
        pricePaid(hlcMillis: 0, minorUnits: 10000, microlitres: 700000),
        pricePaid(hlcMillis: 100, minorUnits: 2000, microlitres: 700000, currency: 'USD'),
      ]);

      expect(
        () => candlesOf(mixed, widthMillis: _day),
        throwsArgumentError,
        reason: 'the candles would draw, the axis would be plausible, and only a spike '
            'on a holiday abroad would give it away',
      );
    });

    test('one currency is not a problem', () {
      final single = priceSeriesOf(<Event>[
        pricePaid(hlcMillis: 0, minorUnits: 10000, microlitres: 700000),
        pricePaid(hlcMillis: 86400000, minorUnits: 12000, microlitres: 700000),
      ]);

      expect(single.isSingleCurrency, isTrue);
      expect(candlesOf(single, widthMillis: _day).length, 2);
    });
  });

  group('cost per glass', () {
    test('uses the named pour rather than a literal at the call site', () {
      expect(standardPour, Volume.fromMillilitres(45));
    });

    test('is the exact rate times the pour, rounded once', () {
      // 12000 minor units for 700 ml: 12000/700000 per ul. A 45 ml pour is 45000 ul.
      final series = priceSeriesOf(<Event>[
        bottle(hlcMillis: 0, sku: 'gin', microlitres: 700000, priceMinor: 12000),
      ]);
      // 12000 * 45000 / 700000 = 540000000/700000 = 771.43 -> round half up -> 771
      expect(series.costOf(standardPour), Money.fromMinorUnits(771, Currency.cny));
    });

    test('a shelf with no price has no cost, which is not a cost of zero', () {
      final series = priceSeriesOf(<Event>[
        bottle(hlcMillis: 0, sku: 'gin', microlitres: 700000),
      ]);
      expect(series.costOf(standardPour), isNull);
    });
  });
}
