import 'package:test/test.dart';

import 'package:hollow_court/domain/events/hlc.dart';
import 'package:hollow_court/domain/pricing/ohlc.dart';
import 'package:hollow_court/domain/pricing/price.dart';
import 'package:hollow_court/domain/units/quantity.dart';
import 'package:hollow_court/domain/units/rational.dart';

/// Section 7's series folded into candles.
///
/// Written against `package:test` and living under `test/domain`, so section 3's
/// "the domain layer imports no Flutter" is enforced by the suite refusing to run
/// rather than by anybody remembering to check.
const int _day = 86400000;

Hlc at(int millis) => Hlc(physicalMillis: millis, counter: 0, nodeId: 'laptop');

PricePoint obs(int millis, int minorUnits, int microlitres) => PricePoint(
  hlc: at(millis),
  paid: Money.fromMinorUnits(minorUnits, Currency.cny),
  volume: Volume.fromMicrolitres(microlitres),
  source: PriceSource.manual,
);

PriceSeries series(List<PricePoint> points) => PriceSeries(points);

void main() {
  group('candlesOf', () {
    test('folds one period into open, high, low, close and a count', () {
      // Half a litre each time, so the totals are directly proportional to the rates
      // and this test is about the fold rather than about the design point below.
      final candles = candlesOf(
        series(<PricePoint>[
          obs(0, 1000, 500000), // 1/500
          obs(1000, 2000, 500000), // 1/250
          obs(2000, 500, 500000), // 1/1000
        ]),
        widthMillis: _day,
      );

      expect(candles.length, 1);
      final candle = candles.single;
      expect(candle.open, Rational.of(1, 500));
      expect(candle.high, Rational.of(1, 250));
      expect(candle.low, Rational.of(1, 1000));
      expect(candle.close, Rational.of(1, 1000));
      expect(candle.observations, 3);
      expect(candle.isFalling, isTrue);
      expect(candle.change, Rational.of(1, 1000) - Rational.of(1, 500));
      expect(candle.range, Rational.of(1, 250) - Rational.of(1, 1000));
    });

    test('buckets by the period, and keeps them oldest first', () {
      final candles = candlesOf(
        series(<PricePoint>[
          obs(_day * 2, 300, 300000),
          obs(0, 100, 300000),
          obs(_day, 200, 300000),
        ]),
        widthMillis: _day,
      );

      expect(candles.length, 3);
      expect(candles[0].open, Rational.of(1, 3000));
      expect(candles[1].open, Rational.of(1, 1500));
      expect(candles[2].open, Rational.of(1, 1000));
    });

    test('charts a rate, not a total, and that is the whole design', () {
      // The same money for twice the volume. A chart of totals would draw this as a
      // period that did not move; the price per unit halved, which is what the person
      // buying the next bottle actually cares about, and what makes a candle of a
      // large bottle comparable to one of a miniature.
      final candles = candlesOf(
        series(<PricePoint>[
          obs(0, 3000, 300000), // 1/100
          obs(1000, 3000, 600000), // 1/200
        ]),
        widthMillis: _day,
      );

      final candle = candles.single;
      expect(candle.open, Rational.of(1, 100));
      expect(candle.close, Rational.of(1, 200));
      expect(candle.high, Rational.of(1, 100));
      expect(candle.low, Rational.of(1, 200));
      expect(candle.isFalling, isTrue,
          reason: 'the totals are identical, so this can only be a rate');
      expect(candle.range, Rational.of(1, 200));
    });

    test('a period that opened and closed alike is neither rising nor falling', () {
      final candle = candlesOf(
        series(<PricePoint>[obs(0, 500, 500000), obs(1000, 1000, 1000000)]),
        widthMillis: _day,
      ).single;

      expect(candle.isFlat, isTrue);
      expect(candle.isRising, isFalse);
      expect(candle.isFalling, isFalse);
      expect(candle.change, Rational.zero);
      expect(candle.range, Rational.zero);
    });

    test('leaves out an observation with no volume, because it has no rate', () {
      final candles = candlesOf(
        series(<PricePoint>[
          obs(0, 500, 0), // a receipt line with the volume missing
          obs(1000, 1000, 500000),
        ]),
        widthMillis: _day,
      );

      expect(candles.single.observations, 1);
      expect(candles.single.open, Rational.of(1, 500));
    });

    test('keeps the trailing period even though it is partial', () {
      // Dropping it would hide the most recent price, which is the one somebody opened
      // the chart to look at. The count is how a caller finds out it is partial.
      final candles = candlesOf(
        series(<PricePoint>[
          obs(0, 1000, 500000),
          obs(1000, 2000, 500000),
          obs(_day, 3000, 500000),
        ]),
        widthMillis: _day,
      );

      expect(candles.length, 2);
      expect(candles.first.observations, 2);
      expect(candles.last.observations, 1);
    });

    test('a flat period still has a candle, which is not the same as no data', () {
      final candles = candlesOf(
        series(<PricePoint>[obs(0, 1000, 500000)]),
        widthMillis: _day,
      );

      expect(candles.length, 1);
      expect(candles.single.observations, 1);
      expect(candles.single.open, candles.single.close);
    });

    test('an empty series has no candles rather than an empty one', () {
      expect(candlesOf(series(const <PricePoint>[]), widthMillis: _day), isEmpty);
    });

    test('aligns the cut points where the caller asks, so a zone can use its own '
        'midnight', () {
      // Two observations one millisecond apart, on opposite sides of an alignment
      // point that is not the epoch. Without the shift they would share a bucket.
      final candles = candlesOf(
        series(<PricePoint>[obs(999, 1000, 500000), obs(1001, 2000, 500000)]),
        widthMillis: _day,
        alignMillis: 1000,
      );

      expect(candles.length, 2);
      expect(candles.first.openHlc, at(999));
      expect(candles.last.openHlc, at(1001));
    });

    test('an observation before the alignment point falls into the period before '
        'it, not into period zero', () {
      // Floor division, not `~/`. Truncation toward zero would put millis 0 and
      // millis 1000 in the same bucket and silently mix a period with its successor.
      final candles = candlesOf(
        series(<PricePoint>[obs(0, 1000, 500000), obs(1000, 2000, 500000)]),
        widthMillis: _day,
        alignMillis: 1000,
      );

      expect(candles.length, 2);
    });

    test('refuses a period with no width', () {
      expect(
        () => candlesOf(series(<PricePoint>[]), widthMillis: 0),
        throwsArgumentError,
      );
      expect(
        () => candlesOf(series(<PricePoint>[]), widthMillis: -1),
        throwsArgumentError,
      );
    });

    test('orders the candles by their own clock reading, not by input order', () {
      final candles = candlesOf(
        series(<PricePoint>[
          obs(_day * 3, 400, 400000),
          obs(0, 100, 400000),
          obs(_day, 200, 400000),
        ]),
        widthMillis: _day,
      );

      final opens = candles.map((c) => c.open).toList();
      expect(opens, [Rational.of(1, 4000), Rational.of(1, 2000), Rational.of(1, 1000)]);
      for (var i = 1; i < candles.length; i++) {
        expect(
          candles[i].openHlc > candles[i - 1].closeHlc,
          isTrue,
          reason: 'candle $i must come after candle ${i - 1}',
        );
      }
    });
  });
}
