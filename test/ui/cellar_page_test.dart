import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/data/event_log.dart';
import 'package:hollow_court/domain/events/event.dart';
import 'package:hollow_court/domain/events/hlc.dart';
import 'package:hollow_court/domain/events/stock.dart';
import 'package:hollow_court/domain/units/quantity.dart';
import 'package:hollow_court/ui/cellar_page.dart';
import 'package:hollow_court/ui/library.dart';
import 'package:hollow_court/ui/theme.dart';

/// Hands the page a real cellar, built outside the test's fake clock.
///
/// The same `runAsync` requirement `bar_page_test` records: `testWidgets` runs in a
/// FakeAsync zone where a real file write never completes, so the log has to be built on
/// the real clock. Once it exists the page only reads it, and reading needs no I/O.
Future<Cellar> _cellar(WidgetTester tester, List<Event> events) async {
  final cellar = await tester.runAsync(() async {
    final dir = Directory.systemTemp.createTempSync('hollow_cellar_test');
    var clock = 1000;
    final log = await EventLog.open(
      file: File('${dir.path}${Platform.pathSeparator}cellar.ndjson'),
      nodeId: 'test',
      nowMillis: () => clock++,
    );
    for (final event in events) {
      await log.record((_) => event);
    }
    return Cellar.of(log);
  });
  return cellar!;
}

class _Seeded extends CellarNotifier {
  _Seeded(this._initial);

  final Cellar _initial;

  @override
  Future<Cellar> build() async => _initial;
}

/// Reading numbers that advance on their own.
///
/// **The same trap `shelf_test` records, met again in the same week.** Two helper-built
/// events with the same `Hlc` are the same event as far as any device can tell, so the log
/// dropped the second bottle and a test about two bottles of different prices silently ran
/// with one. An HLC orders one node's events only if the node moves it.
int _clock = 1000;

Event _added(String id, String sku, int millilitres, {int? priceMinor}) =>
    StockEvents.bottleAdded(
      hlc: Hlc(physicalMillis: ++_clock, counter: 0, nodeId: 'test'),
      bottleId: id,
      sku: sku,
      volume: Volume.fromMillilitres(millilitres),
      priceMinor: priceMinor,
    );

Event _poured(String id, int millilitres) =>
    StockEvents.bottleConsumed(
      hlc: Hlc(physicalMillis: ++_clock, counter: 0, nodeId: 'test'),
      bottleId: id,
      volume: Volume.fromMillilitres(millilitres),
    );

Future<void> _pump(WidgetTester tester, Cellar cellar) async {
  // Tall and scrollable: this page is much taller than the default 800x600 and is hosted
  // in a ListView, so a bare Scaffold body overflows. Found the same way in
  // settings_section_test.
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [cellarProvider.overrideWith(() => _Seeded(cellar))],
      child: const MaterialApp(home: Scaffold(body: CellarPage())),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('a fresh cellar says there is nothing to count', (tester) async {
    await _pump(tester, await _cellar(tester, const []));

    expect(find.text(Copy.cellarStats.primary.text), findsOneWidget);
    expect(find.text(Copy.cellarStatsEmpty.primary.text), findsOneWidget);
    // And the value has no prices to add, which the page says rather than showing zero.
    expect(find.text(Copy.cellarNoPrices.primary.text), findsOneWidget);
  });

  testWidgets('the value and the unpriced count appear together', (tester) async {
    // Section 7's total is a sum over the bottles that have a price, and the page shows the
    // qualifier with it or not at all: a figure on its own goes up when somebody enters a
    // price, which reads as the cellar becoming more valuable rather than as the estimate
    // becoming less wrong.
    await _pump(
      tester,
      await _cellar(tester, [
        _added('b1', 'gin', 700, priceMinor: 3200),
        _added('b2', 'rum', 700),
      ]),
    );

    // `moneyText` appends the currency code, and the assertion names the whole string:
    // checking only the digits would pass for a screen that had lost the currency, which is
    // the failure `money_text.dart` exists to prevent.
    expect(find.text('32.00 CNY'), findsOneWidget);
    expect(find.textContaining(Copy.cellarUnpriced), findsOneWidget);
    expect(find.text(Copy.cellarNoPrices.primary.text), findsNothing);
  });

  testWidgets('a cellar drunk dry shows its statistics and not the empty line',
      (tester) async {
    // **The distinction the panel turns on.** `isBare` is shown and `isEmpty` is not: a
    // cellar with a history and nothing left is a different reading from a cellar nobody
    // has used, and a page that showed the second for the first would be lying about which.
    await _pump(
      tester,
      await _cellar(tester, [
        _added('b1', 'gin', 700),
        _poured('b1', 700),
      ]),
    );

    expect(find.text(Copy.cellarStatsEmpty.primary.text), findsNothing);

    // The counts: one bottle, none standing, one empty, and the most-poured sku named.
    final stats = find.textContaining(Copy.cellarStatsBottles);
    expect(stats, findsWidgets);
    expect(find.textContaining('0 ${Copy.cellarStatsStanding}'), findsOneWidget);
    expect(find.textContaining('1 ${Copy.cellarStatsEmptyBottles}'), findsOneWidget);
    expect(
      find.textContaining('${Copy.cellarStatsMostPoured} gin'),
      findsOneWidget,
    );
  });

  testWidgets('the consumption curve appears once something has been poured',
      (tester) async {
    await _pump(
      tester,
      await _cellar(tester, [
        _added('b1', 'gin', 700),
        _poured('b1', 45),
      ]),
    );

    expect(find.text(Copy.cellarConsumption.primary.text), findsOneWidget);
    expect(find.text(Copy.cellarConsumptionEmpty.primary.text), findsNothing);
    // The two columns are named beside the chart, so a person does not have to guess which
    // bar is which.
    expect(find.textContaining(Copy.cellarDrunk.primary.text), findsWidgets);
    expect(find.textContaining(Copy.cellarDiscarded.primary.text), findsWidgets);
  });

  testWidgets('the settings are not on this tab any more, and what is stays', (tester) async {
    // **This test used to assert the opposite**, and its own name said why: "because section 12.3
    // has no others". The owner asked for a settings tab, so 12.3 names five and the reader's
    // language, units and money moved to it. What this tab keeps is what 12.3 gives it -- statistics,
    // the curve, value, the shopping list, devices and sync -- which are facts about this cellar
    // rather than about the program.
    //
    // Inverted rather than deleted, because "the settings are not here" is a claim worth holding: the
    // way this goes wrong next time is a second copy of the controls appearing on both screens.
    // `widget_test` asserts the other half, that the Settings tab reaches them.
    await _pump(tester, await _cellar(tester, const []));

    expect(find.text(Copy.settingsTitle.primary.text), findsNothing);
    expect(find.text(Copy.settingsUnits.primary.text), findsNothing);
    expect(find.text(Copy.settingsMoney.primary.text), findsNothing);
    expect(find.text(Copy.cellarConsumption.primary.text), findsOneWidget);
  });
}
