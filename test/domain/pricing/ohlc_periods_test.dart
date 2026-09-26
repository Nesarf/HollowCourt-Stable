import 'package:test/test.dart';

import 'package:hollow_court/domain/events/hlc.dart';
import 'package:hollow_court/domain/pricing/ohlc.dart';
import 'package:hollow_court/domain/pricing/price.dart';
import 'package:hollow_court/domain/units/quantity.dart';
import 'package:hollow_court/domain/units/rational.dart';

/// The general bucketing form, and the case that makes it necessary.
///
/// `candlesOf` takes a width in milliseconds, which is correct for a day and a week and
/// **cannot express a calendar month**. The tests below are mostly about that: a width of
/// thirty days is not a month, and the way it fails is quiet.
Hlc at(int millis) => Hlc(physicalMillis: millis, counter: 0, nodeId: 'laptop');

PricePoint obs(int millis, int minorUnits, int microlitres) => PricePoint(
  hlc: at(millis),
  paid: Money.fromMinorUnits(minorUnits, Currency.cny),
  volume: Volume.fromMicrolitres(microlitres),
  source: PriceSource.manual,
);

int day(int year, int month, int dayOfMonth) =>
    DateTime.utc(year, month, dayOfMonth).millisecondsSinceEpoch;

/// The month an instant falls in, as one integer. **A calendar, not a width**, and the
/// point of [candlesBy]: the caller owns the time zone, and this test proves the shape
/// works without the domain ever learning one.
int monthOf(int millis) {
  final date = DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
  return date.year * 12 + date.month;
}

void main() {
  group('candlesBy takes the boundary from the caller', () {
    test('a constant boundary puts everything in one candle', () {
      final candles = candlesBy(
        PriceSeries(<PricePoint>[
          obs(0, 1000, 500000),
          obs(86400000, 2000, 500000),
          obs(86400000 * 9, 500, 500000),
        ]),
        bucketOf: (millis) => 0,
      );

      expect(candles.length, 1);
      expect(candles.single.observations, 3);
      expect(candles.single.open, Rational.of(1, 500));
      expect(candles.single.close, Rational.of(1, 1000));
    });

    test('a calendar month buckets by the month, not by thirty days', () {
      final candles = candlesBy(
        PriceSeries(<PricePoint>[
          obs(day(2026, 1, 5), 1000, 500000),
          obs(day(2026, 1, 25), 1500, 500000),
          obs(day(2026, 2, 3), 2000, 500000),
          obs(day(2026, 3, 9), 1800, 500000),
        ]),
        bucketOf: monthOf,
      );

      expect(candles.length, 3);
      expect(candles[0].observations, 2, reason: 'January has both its observations');
      expect(candles[1].observations, 1);
      expect(candles[2].observations, 1);
    });

    test('and a thirty-day width gets that same January wrong', () {
      // The case that makes this form necessary rather than decorative. Two purchases
      // twenty days apart in one January: a calendar says one period, a constant width
      // says two, and the chart looks entirely plausible either way.
      final facts = PriceSeries(<PricePoint>[
        obs(day(2026, 1, 5), 1000, 500000),
        obs(day(2026, 1, 25), 1500, 500000),
      ]);

      expect(candlesBy(facts, bucketOf: monthOf).length, 1);
      expect(candlesOf(facts, widthMillis: 30 * 86400000).length, 2,
          reason: 'a width cannot know where January ends');
    });

    test('a month boundary handles February, which no constant could', () {
      final candles = candlesBy(
        PriceSeries(<PricePoint>[
          obs(day(2026, 2, 1), 1000, 500000),
          obs(day(2026, 2, 28), 1200, 500000),
          obs(day(2026, 3, 1), 1400, 500000),
        ]),
        bucketOf: monthOf,
      );

      expect(candles.length, 2);
      expect(candles.first.observations, 2);
    });

    test('agrees with candlesOf when the boundary is a day', () {
      final facts = PriceSeries(<PricePoint>[
        obs(0, 1000, 500000),
        obs(86400000, 2000, 500000),
        obs(86400000 * 2 + 10, 500, 500000),
      ]);

      final general = candlesBy(facts, bucketOf: (m) => m ~/ 86400000);
      final fixed = candlesOf(facts, widthMillis: 86400000);

      expect(general.length, fixed.length);
      for (var i = 0; i < fixed.length; i++) {
        expect(general[i].open, fixed[i].open);
        expect(general[i].close, fixed[i].close);
        expect(general[i].observations, fixed[i].observations);
        expect(general[i].openHlc, fixed[i].openHlc);
      }
    });

    test('refuses two currencies here too, because it is the same fold', () {
      final mixed = PriceSeries(<PricePoint>[
        obs(0, 1000, 500000),
        PricePoint(
          hlc: at(1),
          paid: Money.fromMinorUnits(200, Currency.usd),
          volume: Volume.fromMicrolitres(500000),
          source: PriceSource.manual,
        ),
      ]);

      expect(() => candlesBy(mixed, bucketOf: monthOf), throwsArgumentError);
    });

    test('an empty series has no candles whatever the boundary says', () {
      expect(
        candlesBy(PriceSeries(const <PricePoint>[]), bucketOf: monthOf),
        isEmpty,
      );
    });
  });
}
