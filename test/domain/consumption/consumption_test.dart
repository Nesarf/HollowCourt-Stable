import 'package:hollow_court/domain/consumption/consumption.dart';
import 'package:hollow_court/domain/events/event.dart';
import 'package:hollow_court/domain/events/hlc.dart';
import 'package:hollow_court/domain/events/stock.dart';
import 'package:hollow_court/domain/units/quantity.dart';
import 'package:test/test.dart';

Hlc at(int millis) => Hlc(physicalMillis: millis, counter: 0, nodeId: 'test');

Event pour(String bottle, int millilitres, int millis) =>
    StockEvents.bottleConsumed(
      hlc: at(millis),
      bottleId: bottle,
      volume: Volume.fromMillilitres(millilitres),
    );

Event discard(String bottle, int millilitres, int millis) =>
    StockEvents.bottleDiscarded(
      hlc: at(millis),
      bottleId: bottle,
      volume: Volume.fromMillilitres(millilitres),
    );

/// One bucket per second, which is a calendar a test can state exactly.
int perSecond(int millis) => millis ~/ 1000;

void main() {
  group('a pour and a discard are two columns', () {
    test('the same period keeps them apart and adds them only when asked', () {
      // The reason the stock family split these two events in the first place:
      // both reduce the bottle, only one of them was a drink. A curve that merged
      // them would report a broken bottle as a busy evening.
      final curve = ConsumptionCurve.of([
        pour('b1', 45, 5000),
        discard('b1', 500, 5500),
      ], bucketOf: perSecond);

      final bucket = curve.buckets.single;
      expect(bucket.drunk, Volume.fromMillilitres(45));
      expect(bucket.discarded, Volume.fromMillilitres(500));
      expect(bucket.total, Volume.fromMillilitres(545));
      expect(curve.drunkTotal, Volume.fromMillilitres(45));
      expect(curve.discardedTotal, Volume.fromMillilitres(500));
    });

    test('a cellar that only discarded has a curve and no drinks in it', () {
      // `isEmpty` and `hasNoDrinks` are different questions, and a screen that
      // treated them as one would say nothing has happened.
      final curve = ConsumptionCurve.of([
        discard('b1', 700, 1000),
      ], bucketOf: perSecond);

      expect(curve.isEmpty, isFalse);
      expect(curve.hasNoDrinks, isTrue);
    });

    test('an empty log gives an empty curve rather than a zero', () {
      final curve = ConsumptionCurve.of(const <Event>[], bucketOf: perSecond);

      expect(curve.isEmpty, isTrue);
      expect(curve.buckets, isEmpty);
      expect(curve.drunkTotal, Volume.zero);
      expect(curve.peak, Volume.zero);
    });
  });

  group('the shape of the curve is the caller’s calendar', () {
    test('a gap between two active periods is drawn as an empty bucket', () {
      // A period with nothing in it and a period that was never measured are
      // different readings, and a chart that closed the gap would draw them the
      // same way. The same distinction ohlc_test records when it insists a flat
      // period still has a candle.
      final curve = ConsumptionCurve.of([
        pour('b1', 30, 1000),
        pour('b1', 30, 4000),
      ], bucketOf: perSecond);

      expect(curve.buckets.map((b) => b.bucket), [1, 2, 3, 4]);
      expect(curve.buckets[1].isEmpty, isTrue);
      expect(curve.buckets[2].isEmpty, isTrue);
      expect(curve.buckets[1].total, Volume.zero);
    });

    test('no empty bucket is invented after the last one', () {
      // A trailing empty period would make every curve end in a fall to zero, and
      // the fall would be the chart's own invention.
      final curve = ConsumptionCurve.of([
        pour('b1', 30, 1000),
      ], bucketOf: perSecond);

      expect(curve.buckets, hasLength(1));
      expect(curve.buckets.last.bucket, 1);
    });

    test('the same events cut on a wider calendar give a different shape', () {
      // The domain has no idea what a day is, and this is what that buys: the same
      // log reads as three buckets by the second and one by the four-second mark.
      final events = [
        pour('b1', 30, 1000),
        pour('b1', 30, 3000),
        pour('b1', 30, 5000),
      ];

      expect(
        ConsumptionCurve.of(events, bucketOf: perSecond).buckets,
        hasLength(5),
      );
      final wide = ConsumptionCurve.of(
        events,
        bucketOf: (millis) => millis ~/ 4000,
      );
      expect(wide.buckets, hasLength(2));
      expect(wide.buckets.first.drunk, Volume.fromMillilitres(60));
      expect(wide.buckets.last.drunk, Volume.fromMillilitres(30));
    });
  });

  group('what the fold refuses to count', () {
    test('a pour of nothing is counted as ignored, not added as zero', () {
      final curve = ConsumptionCurve.of([
        pour('b1', 0, 1000),
        pour('b1', 40, 1000),
      ], bucketOf: perSecond);

      expect(curve.ignoredVolumeEvents, 1);
      expect(curve.pourEvents, 1);
      expect(curve.drunkTotal, Volume.fromMillilitres(40));
    });

    test('a negative volume is a defect and is not subtracted from the curve', () {
      // Adding it would make a mistyped measurement quietly reduce a total, which
      // is the one repair a ledger must never perform on its own.
      final curve = ConsumptionCurve.of([
        StockEvents.bottleConsumed(
          hlc: at(1000),
          bottleId: 'b1',
          volume: Volume.fromMicrolitres(-5000),
        ),
      ], bucketOf: perSecond);

      expect(curve.ignoredVolumeEvents, 1);
      expect(curve.drunkTotal, Volume.zero);
      expect(curve.buckets, isEmpty);
    });

    test('an event with no volume in it at all is ignored rather than zero', () {
      final curve = ConsumptionCurve.of([
        Event(hlc: at(1000), type: StockEvent.bottleConsumed, data: const {}),
      ], bucketOf: perSecond);

      expect(curve.ignoredVolumeEvents, 1);
      expect(curve.drunkTotal, Volume.zero);
    });

    test('a stock event is not consumption, and is not reported as a defect', () {
      // The two families share one log. A fold that counted every foreign event as
      // malformed would report the whole cellar as broken -- the same point
      // shelf_test makes about `ShelfLayout`.
      final curve = ConsumptionCurve.of([
        pour('b1', 40, 1000),
        StockEvents.bottleAdded(
          hlc: at(1500),
          bottleId: 'b2',
          sku: 'gin',
          volume: Volume.fromMillilitres(700),
        ),
      ], bucketOf: perSecond);

      expect(curve.ignoredTypeEvents, 1);
      expect(curve.ignoredVolumeEvents, 0);
      expect(curve.drunkTotal, Volume.fromMillilitres(40));
    });
  });

  group('numbers a chart can scale from', () {
    test('the peak covers the discard column as well as the drinks', () {
      // Scaling on the drinks alone would let a discarded bottle draw outside the
      // plot, which reads as a rendering fault rather than as a fact.
      final curve = ConsumptionCurve.of([
        pour('b1', 45, 1000),
        discard('b1', 700, 2000),
      ], bucketOf: perSecond);

      expect(curve.peak, Volume.fromMillilitres(700));
    });

    test('the totals stay whole microlitres, summed exactly', () {
      // A third of a litre three times is a litre, and it is a litre here for the
      // same reason it is in the dosing layer: nothing is ever a double.
      final third = 333333;
      final curve = ConsumptionCurve.of([
        StockEvents.bottleConsumed(
          hlc: at(1000),
          bottleId: 'b1',
          volume: Volume.fromMicrolitres(third),
        ),
        StockEvents.bottleConsumed(
          hlc: at(1000),
          bottleId: 'b2',
          volume: Volume.fromMicrolitres(third),
        ),
        StockEvents.bottleConsumed(
          hlc: at(1000),
          bottleId: 'b3',
          volume: Volume.fromMicrolitres(third),
        ),
      ], bucketOf: perSecond);

      expect(curve.buckets.single.drunk.microlitres, third * 3);
      expect(curve.buckets.single.pours, 3);
    });

    test('a bucket counts the events as well as the volume', () {
      final curve = ConsumptionCurve.of([
        pour('b1', 30, 1000),
        pour('b2', 30, 1200),
        discard('b1', 100, 1500),
      ], bucketOf: perSecond);

      expect(curve.buckets.single.pours, 2);
      expect(curve.buckets.single.discards, 1);
      expect(curve.pourEvents, 2);
      expect(curve.discardEvents, 1);
    });
  });
}
