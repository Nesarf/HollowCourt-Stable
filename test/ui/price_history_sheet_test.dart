import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hollow_court/domain/events/hlc.dart';
import 'package:hollow_court/domain/pricing/price.dart';
import 'package:hollow_court/domain/units/quantity.dart';
import 'package:hollow_court/ui/library.dart';
import 'package:hollow_court/ui/price_chart.dart';
import 'package:hollow_court/ui/price_history_sheet.dart';
import 'package:hollow_court/ui/theme.dart';

/// The price history sheet, checked for the thing a screen can actually get wrong here.
///
/// **A widget test rather than a golden file**, for the reason `price_chart_test.dart`
/// gives: the failures that happen are about *which state is shown*, not about pixels.
/// The sheet has two states -- nothing recorded, and something recorded -- and a person
/// must be able to tell them apart, because an empty chart drawn as if it were data is
/// section 14's "a page that showed an empty shelf would be indistinguishable from a
/// cellar that is genuinely empty", one layer down.
///
/// **The provider is overridden rather than a cellar faked.** `Cellar.of` takes a real
/// `EventLog`, so building one for a widget test would mean a temporary file and a fold
/// of the whole log to ask one question about one screen. Overriding the leaf keeps the
/// test about the sheet.
PricePoint price(int millis, int minorUnits, int microlitres) => PricePoint(
  hlc: Hlc(physicalMillis: millis, counter: 0, nodeId: 'laptop'),
  paid: Money.fromMinorUnits(minorUnits, Currency.cny),
  volume: Volume.fromMicrolitres(microlitres),
  source: PriceSource.manual,
);

Future<void> pumpSheet(
  WidgetTester tester,
  List<PricePoint> points, {
  String sku = 'gin',
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        priceSeriesForProvider(sku).overrideWith((ref) => PriceSeries(points)),
      ],
      child: MaterialApp(
        home: Scaffold(body: PriceHistorySheet(sku: sku, name: 'Gin')),
      ),
    ),
  );
}

void main() {
  testWidgets('a bottle with no price says so, and still draws the chart',
      (tester) async {
    await pumpSheet(tester, const <PricePoint>[]);

    expect(tester.takeException(), isNull);
    // The sentence that tells "nothing recorded" apart from "the chart broke". Without
    // it the block is a bare baseline and reads as a failed drawing.
    expect(find.text(Copy.priceNone.primary.text), findsOneWidget);
    // The chart is still there, so the block is never a blank box.
    expect(find.byType(PriceChart), findsOneWidget);
  });

  testWidgets('a purchase with no volume is a price nobody can chart', (tester) async {
    // The observation is a fact and stays in the series, but v1 has no rate from it, so
    // the sheet must show the same "nothing recorded" as an empty log rather than an
    // axis built from one unusable number.
    await pumpSheet(tester, <PricePoint>[price(0, 12000, 0)]);

    expect(tester.takeException(), isNull);
    expect(find.text(Copy.priceNone.primary.text), findsOneWidget);
  });

  testWidgets('a recorded price shows the chart and both readings', (tester) async {
    await pumpSheet(tester, <PricePoint>[
      price(0, 10000, 700000),
      price(86400000, 12000, 700000),
    ]);

    expect(tester.takeException(), isNull);
    expect(find.text(Copy.priceNone.primary.text), findsNothing);
    expect(find.byType(PriceChart), findsOneWidget);

    // 12000 minor units for 700 ml: 12000/700000 per ul, which is 17142.857 per litre.
    expect(find.text('17142.86 / L'), findsOneWidget);
    // And a 45 ml pour of it: 12000 x 45000/700000 = 771.43, rounded half up once.
    expect(find.text('7.71 CNY'), findsOneWidget);
    // The pour is a number beside the label rather than inside a translated sentence,
    // so that changing `standardPour` cannot leave fourteen locales lying about it.
    expect(find.text('45 ml'), findsOneWidget);
  });

  testWidgets('one price is not a trend, and the sheet does not pretend it is',
      (tester) async {
    await pumpSheet(tester, <PricePoint>[price(0, 12000, 700000)]);

    expect(tester.takeException(), isNull);
    expect(find.byType(PriceChart), findsOneWidget);
    // A single observation still has a rate and a cost; it just has no change, which is
    // `PriceSeries.change` returning null rather than zero.
    expect(find.text('7.71 CNY'), findsOneWidget);
  });
}
