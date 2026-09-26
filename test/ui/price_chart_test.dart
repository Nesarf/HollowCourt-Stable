import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hollow_court/domain/events/hlc.dart';
import 'package:hollow_court/domain/pricing/ohlc.dart';
import 'package:hollow_court/domain/pricing/price.dart';
import 'package:hollow_court/domain/units/quantity.dart';
import 'package:hollow_court/domain/units/rational.dart';
import 'package:hollow_court/ui/price_chart.dart';

/// The candlestick chart, tested the way `theme_and_swatch_test.dart` tests the liquid
/// swatch: **over every shape of data, and for not throwing.** A pixel-level assertion
/// would pin the drawing to a golden file that nobody reads, while the failures that
/// actually happen here are arithmetic ones -- a zero-height band, a doji of zero
/// height, an empty series -- and each of those is exercised below by name.

PriceCandle candle(
  Rational open,
  Rational high,
  Rational low,
  Rational close, {
  int observations = 1,
  int millis = 0,
}) => PriceCandle(
  open: open,
  high: high,
  low: low,
  close: close,
  observations: observations,
  openHlc: Hlc(physicalMillis: millis, counter: 0, nodeId: 'laptop'),
  closeHlc: Hlc(physicalMillis: millis, counter: 0, nodeId: 'laptop'),
);

/// Candles built from real observations, so the chart is tested against what the fold
/// actually produces rather than against hand-written numbers that might not be
/// reachable.
List<PriceCandle> candlesFrom(List<(int, int, int)> purchases, {int widthMillis = 86400000}) {
  final series = PriceSeries(
    purchases.map(
      ((int, int, int) p) => PricePoint(
        hlc: Hlc(physicalMillis: p.$1, counter: 0, nodeId: 'laptop'),
        paid: Money.fromMinorUnits(p.$2, Currency.cny),
        volume: Volume.fromMicrolitres(p.$3),
        source: PriceSource.manual,
      ),
    ),
  );
  return candlesOf(series, widthMillis: widthMillis);
}

Future<void> pumpChart(WidgetTester tester, List<PriceCandle> candles) async {
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: PriceChart(candles: candles))),
  );
}

void main() {
  group('PriceChart draws', () {
    testWidgets('nothing recorded, without inventing a sentence about it', (tester) async {
      await pumpChart(tester, const <PriceCandle>[]);

      expect(tester.takeException(), isNull);
      expect(find.byType(CustomPaint), findsWidgets);
      // The layer rule: section 12.4 sends every reader-visible string through the
      // dual-copy machinery, so a painter with no copy of its own must not produce one.
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('one candle, which is the thinnest real case', (tester) async {
      await pumpChart(tester, candlesFrom(<(int, int, int)>[(0, 1000, 500000)]));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a series that never moved, which is the divide-by-zero case',
        (tester) async {
      // Every high equals every low, so the band is zero height. Without the guard in
      // the painter this is a division by zero on the way to a pixel.
      await pumpChart(
        tester,
        candlesFrom(<(int, int, int)>[
          (0, 1000, 500000),
          (86400000, 1000, 500000),
          (172800000, 1000, 500000),
        ]),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a doji: a period that opened and closed at the same rate',
        (tester) async {
      // The body has no height, so the rectangle would draw nothing. One pixel is the
      // smallest honest statement that the period exists.
      await pumpChart(
        tester,
        <PriceCandle>[
          candle(Rational.of(1, 100), Rational.of(3, 100), Rational.of(1, 200), Rational.of(1, 100)),
        ],
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('rises, falls and flats in one run', (tester) async {
      await pumpChart(
        tester,
        candlesFrom(<(int, int, int)>[
          (0, 1000, 500000), // 1/500
          (86400000, 2000, 500000), // 1/250, a rise
          (172800000, 1000, 500000), // 1/500, a fall
          (259200000, 1000, 500000), // flat against the previous
        ]),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a price of zero, which must not collapse the band', (tester) async {
      // `magnitude * 0.02` would be zero, so the painter floors it. A free item is a
      // real entry and its chart must not be a crash or a blank.
      await pumpChart(
        tester,
        <PriceCandle>[
          candle(Rational.zero, Rational.of(1, 100), Rational.zero, Rational.zero),
          candle(Rational.zero, Rational.zero, Rational.zero, Rational.zero),
        ],
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('many candles, and a very small box', (tester) async {
      final many = candlesFrom(
        List<(int, int, int)>.generate(
          120,
          (int i) => (i * 86400000, 1000 + (i % 7) * 50, 500000),
        ),
      );
      expect(many.length, 120);
      await pumpChart(tester, many);
      expect(tester.takeException(), isNull);

      // A chart squeezed into a few pixels must degrade rather than assert.
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: PriceChart(candles: many, height: 8))),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('fills the height it was given', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: PriceChart(candles: const [], height: 200))),
      );
      final box = tester.getSize(find.byType(PriceChart));
      expect(box.height, 200);
    });
  });
}
