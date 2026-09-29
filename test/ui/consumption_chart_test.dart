import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/domain/consumption/consumption.dart';
import 'package:hollow_court/domain/events/event.dart';
import 'package:hollow_court/domain/events/hlc.dart';
import 'package:hollow_court/domain/events/stock.dart';
import 'package:hollow_court/domain/units/quantity.dart';
import 'package:hollow_court/ui/consumption_chart.dart';
import 'package:hollow_court/ui/price_period.dart';

Event pour(int millilitres, int millis) => StockEvents.bottleConsumed(
  hlc: Hlc(physicalMillis: millis, counter: 0, nodeId: 'test'),
  bottleId: 'b1',
  volume: Volume.fromMillilitres(millilitres),
);

/// Local midnight, in the zone the test runs in.
int midnight(int year, int month, int day) =>
    DateTime(year, month, day).millisecondsSinceEpoch;

Future<void> pumpChart(WidgetTester tester, ConsumptionCurve curve) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ConsumptionChart(curve: curve, period: PricePeriod.day),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('the calendar the Cellar page cuts on', () {
    test('is the local day, not a fixed 86400000 from the epoch', () {
      // **The choice this screen makes, pinned.** The domain refuses to know what a
      // day is, so the page picks one, and the page picked the same one the price
      // chart uses. Two pours in one local day are one bucket; the same two an hour
      // apart across midnight are two. A cut anchored on the epoch would put both in
      // the same bucket whenever the zone offset is not a whole number of days.
      final evening = midnight(2026, 9, 20) + 23 * 3600 * 1000;
      final morning = midnight(2026, 9, 21) + 1 * 3600 * 1000;

      final sameDay = ConsumptionCurve.of([
        pour(30, evening),
        pour(30, evening + 60000),
      ], bucketOf: PricePeriod.day.bucketOf);
      expect(sameDay.buckets, hasLength(1));
      expect(sameDay.buckets.single.pours, 2);

      final acrossMidnight = ConsumptionCurve.of([
        pour(30, evening),
        pour(30, morning),
      ], bucketOf: PricePeriod.day.bucketOf);
      expect(acrossMidnight.buckets, hasLength(2));
      expect(acrossMidnight.buckets.first.bucket + 1,
          acrossMidnight.buckets.last.bucket);
    });
  });

  group('the chart draws two columns and not their sum', () {
    testWidgets('an empty curve draws nothing and does not throw',
        (tester) async {
      await pumpChart(tester, ConsumptionCurve.of(const <Event>[],
          bucketOf: PricePeriod.day.bucketOf));

      expect(find.byType(CustomPaint), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a curve with a discard draws without throwing', (tester) async {
      // A painter is the one place where a wrong number becomes an exception rather
      // than a wrong picture -- a negative height, a NaN from dividing by a zero
      // peak. An empty curve has a zero peak, so the pair of these two tests is what
      // covers the guard at the top of `paint`.
      await pumpChart(
        tester,
        ConsumptionCurve.of([
          pour(45, midnight(2026, 9, 20) + 3600 * 1000),
          StockEvents.bottleDiscarded(
            hlc: Hlc(
              physicalMillis: midnight(2026, 9, 21) + 3600 * 1000,
              counter: 0,
              nodeId: 'test',
            ),
            bottleId: 'b1',
            volume: Volume.fromMillilitres(700),
          ),
        ], bucketOf: PricePeriod.day.bucketOf),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(CustomPaint), findsWidgets);
    });
  });
}
