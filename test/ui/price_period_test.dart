import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hollow_court/domain/events/hlc.dart';
import 'package:hollow_court/domain/pricing/price.dart';
import 'package:hollow_court/domain/units/quantity.dart';
import 'package:hollow_court/ui/library.dart';
import 'package:hollow_court/ui/price_history_sheet.dart';
import 'package:hollow_court/ui/price_period.dart';
import 'package:hollow_court/ui/theme.dart';

/// The period control, and the calendar arithmetic behind it.
///
/// Two things are being asserted. That each period resolves an instant to the period a
/// person would name -- **including the local day, which a UTC-epoch shortcut gets wrong**
/// -- and that the control is a fold at read time rather than a stored form, so switching
/// loses nothing.
DateTime local(int year, int month, int day, [int hour = 12]) =>
    DateTime(year, month, day, hour);

int millisOf(DateTime moment) => moment.millisecondsSinceEpoch;

PricePoint obs(DateTime when, int minorUnits) => PricePoint(
  hlc: Hlc(physicalMillis: millisOf(when), counter: 0, nodeId: 'laptop'),
  paid: Money.fromMinorUnits(minorUnits, Currency.cny),
  volume: Volume.fromMicrolitres(500000),
  source: PriceSource.manual,
);

void main() {
  group('a period resolves an instant to the period a person would name', () {
    test('a day is the local day, not a UTC-aligned one', () {
      // Two in the morning and eleven at night, same local date. Under UTC+8 the first
      // of those belongs to the previous UTC day, so a UTC-epoch shortcut would split
      // them and the candle would not be the day somebody remembers buying on.
      final early = millisOf(local(2026, 3, 10, 2));
      final late = millisOf(local(2026, 3, 10, 23));
      expect(PricePeriod.day.bucketOf(early), PricePeriod.day.bucketOf(late));

      // And the next local day is a different period, whatever the hour.
      final nextDay = millisOf(local(2026, 3, 11, 1));
      expect(
        PricePeriod.day.bucketOf(nextDay),
        isNot(PricePeriod.day.bucketOf(late)),
        reason: 'one hour later, but a different local day',
      );
    });

    test('a month is the calendar month, which no width can be', () {
      // The 1st and the 28th, twenty-seven days apart and both in March. A thirty-day
      // width would put them in different periods while looking entirely plausible.
      expect(
        PricePeriod.month.bucketOf(millisOf(local(2026, 3, 1))),
        PricePeriod.month.bucketOf(millisOf(local(2026, 3, 28))),
      );
      expect(
        PricePeriod.month.bucketOf(millisOf(local(2026, 3, 31))),
        isNot(PricePeriod.month.bucketOf(millisOf(local(2026, 4, 1)))),
      );
    });

    test('February is why the month is a calendar and not a constant', () {
      expect(
        PricePeriod.month.bucketOf(millisOf(local(2026, 2, 1))),
        PricePeriod.month.bucketOf(millisOf(local(2026, 2, 28))),
      );
      expect(
        PricePeriod.month.bucketOf(millisOf(local(2026, 2, 28))),
        isNot(PricePeriod.month.bucketOf(millisOf(local(2026, 3, 1)))),
      );
    });

    test('every period is monotonic, which is the contract candlesBy states', () {
      // A boundary that went backwards would emit one candle per observation. Checked
      // over two years of days, because the interesting failures are at DST shifts and
      // year ends rather than in the middle of a week.
      for (final period in PricePeriod.values) {
        var previous = period.bucketOf(millisOf(local(2025, 1, 1)));
        for (var day = 1; day < 730; day++) {
          final at = millisOf(local(2025, 1, 1).add(Duration(days: day)));
          final bucket = period.bucketOf(at);
          expect(bucket, greaterThanOrEqualTo(previous),
              reason: '${period.name} went backwards at day $day');
          previous = bucket;
        }
      }
    });

    test('the periods are ordered by resolution', () {
      final start = millisOf(local(2026, 1, 1));
      int distinct(PricePeriod period) => <int>{
        for (var day = 0; day < 120; day++)
          period.bucketOf(start + day * Duration.millisecondsPerDay),
      }.length;

      expect(distinct(PricePeriod.day), 120);
      expect(distinct(PricePeriod.week), lessThan(distinct(PricePeriod.day)));
      expect(distinct(PricePeriod.month), lessThan(distinct(PricePeriod.week)));
      for (final period in PricePeriod.values) {
        expect(period.windowCandles, greaterThan(0));
      }
    });
  });

  group('the control', () {
    Future<void> pump(WidgetTester tester, List<PricePoint> points) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            priceSeriesForProvider('gin').overrideWith((ref) => PriceSeries(points)),
          ],
          child: const MaterialApp(
            home: Scaffold(body: PriceHistorySheet(sku: 'gin', name: 'Gin')),
          ),
        ),
      );
    }

    testWidgets('offers all three periods, with a pair that cannot be drawn',
        (tester) async {
      await pump(tester, <PricePoint>[
        obs(local(2026, 1, 5), 10000),
        obs(local(2026, 2, 5), 12000),
      ]);

      expect(tester.takeException(), isNull);
      expect(find.byType(SegmentedButton<PricePeriod>), findsOneWidget);
      // One line per option, so the primary alone -- the same wall as the tab labels.
      for (final period in PricePeriod.values) {
        expect(find.text(period.label.primary.text), findsOneWidget);
      }
      expect(find.text(PricePeriod.day.label.secondary!.text), findsNothing);
    });

    testWidgets('switching period redraws rather than losing anything',
        (tester) async {
      // The claim this rests on: a candle is a fold of the observations at read time, so
      // the period is a view and not a stored form. Nothing is saved per period, so
      // switching back has the same input it started with.
      await pump(tester, <PricePoint>[
        obs(local(2026, 1, 5), 10000),
        obs(local(2026, 1, 25), 11000),
        obs(local(2026, 3, 5), 12000),
      ]);

      await tester.tap(find.text(PricePeriod.month.label.primary.text));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.text(PricePeriod.day.label.primary.text));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // And the readings are still on screen, so the picker changed the chart only.
      expect(find.text(Copy.pricePerGlass.primary.text), findsOneWidget);
    });

    testWidgets('no prices means no picker, because there is nothing to resolve',
        (tester) async {
      await pump(tester, const <PricePoint>[]);

      expect(find.byType(SegmentedButton<PricePeriod>), findsNothing);
      expect(find.text(Copy.priceNone.primary.text), findsOneWidget);
    });
  });
}
