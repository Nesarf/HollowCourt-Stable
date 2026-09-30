import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/domain/events/hlc.dart';
import 'package:hollow_court/domain/events/price.dart';
import 'package:hollow_court/domain/pricing/cashflow.dart';
import 'package:hollow_court/domain/pricing/price.dart';
import 'package:hollow_court/data/event_log.dart';
import 'package:hollow_court/ui/cash_settings.dart';
import 'package:hollow_court/ui/cashflow_section.dart';
import 'package:hollow_court/ui/library.dart';
import 'package:hollow_court/ui/money_text.dart';
import 'package:hollow_court/ui/theme.dart';
import 'package:hollow_court/ui/cashflow_providers.dart';

/// **The takings view, whose domain has existed since 2026-09-21 with nothing reading it.**
///
/// These cover the three things that had to be true for it to be a feature rather than a drawing: the log's
/// prices reach the fold, the two figures only the reader knows are stored, and the screen says out loud that
/// the income side cannot be recorded. The last one is the reason this file exists -- a zero in a takings
/// column reads as "nothing came in", and the domain's own comment says that would show a bar that only ever
/// loses money.
void main() {
  setUpAll(() async {
    _fixture = await _build([('gin', 20000), ('vermouth', 10000)]);
    _emptyCellar = await _build(const []);
  });

  group('the store', () {
    test('a deposit and a count survive a write and a read', () async {
      final directory = Directory.systemTemp.createTempSync('cash_settings');
      addTearDown(() => directory.deleteSync(recursive: true));
      final store = CashSettingsStore(File('${directory.path}/cash.json'));
      const cny = Currency('CNY', 2);

      expect(await store.read(), isNull, reason: 'nothing written yet is a first run, not an error');

      final saved = const CashSettings()
          .withDeposit(cny, 50000)
          .withCounted(cny, 42300, 1727000000000);
      await store.write(saved);

      final back = await store.read();
      expect(back, isNotNull);
      expect(back!.depositIn(cny)!.minorUnits, 50000);
      expect(back.countedIn(cny)!.minorUnits, 42300);
      expect(back.countedAtMillis, 1727000000000);
    });

    test('**two currencies keep two tills**', () async {
      // A reader who buys in two currencies has two floats, and a single stored figure would silently be in
      // whichever currency happened to be written first. This is the reason the fields are maps.
      final directory = Directory.systemTemp.createTempSync('cash_settings_two');
      addTearDown(() => directory.deleteSync(recursive: true));
      final store = CashSettingsStore(File('${directory.path}/cash.json'));
      const cny = Currency('CNY', 2);
      const jpy = Currency('JPY', 0);

      await store.write(const CashSettings().withDeposit(cny, 50000).withDeposit(jpy, 8000));
      final back = await store.read();

      expect(back!.depositIn(cny)!.minorUnits, 50000);
      expect(back.depositIn(jpy)!.minorUnits, 8000);
      expect(back.depositIn(const Currency('USD', 2)), isNull, reason: 'an unset currency is null, not zero');
    });

    test('a count of zero is not the same as never having counted', () async {
      final directory = Directory.systemTemp.createTempSync('cash_settings_zero');
      addTearDown(() => directory.deleteSync(recursive: true));
      final store = CashSettingsStore(File('${directory.path}/cash.json'));
      const cny = Currency('CNY', 2);

      await store.write(const CashSettings().withDeposit(cny, 10000).withCounted(cny, 0, 1));
      final back = await store.read();

      expect(back!.hasCounted, isTrue);
      expect(back.countedIn(cny)!.minorUnits, 0);
      expect(back.countedIn(cny)!.isZero, isTrue);
    });

    test('**a hand-edited file falls back per field rather than failing whole**', () async {
      // The rule every store in this project follows: a preference must never be able to stop the application
      // from opening. This file has one good field, one wrong-typed field and one that is not a map at all.
      final directory = Directory.systemTemp.createTempSync('cash_settings_broken');
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/cash.json');
      await file.writeAsString(
        '{"deposits":{"CNY":50000,"JPY":"eighty"},"counted":"not a map","countedAtMillis":"yesterday"}',
      );

      final back = await CashSettingsStore(file).read();
      expect(back, isNotNull);
      expect(back!.deposits['CNY'], 50000, reason: 'the readable key is kept');
      expect(back.deposits.containsKey('JPY'), isFalse, reason: 'the unreadable value is dropped, not guessed');
      expect(back.counted, isEmpty);
      expect(back.countedAtMillis, isNull);
      expect(back.hasCounted, isFalse);
    });
  });

  group('the fold', () {
    test('**prices in the log become spending in the windows**', () {
      final windows = _foldFor(_fixture, DateTime.now());
      expect(windows, hasLength(4), reason: 'one per CashflowWindow');

      // **Two days back, and that is what makes this meaningful.** An event recorded "now" would land in every
      // window including 当日, so a fold that ignored its own bounds would still pass. Two days puts it outside
      // 当日 and inside the other three, which is a shape the fold has to compute rather than receive.
      final byWindow = {for (final c in windows) c.window.name: c};
      expect(byWindow['today']!.expense.minorUnits, 0);
      expect(byWindow['week']!.expense.minorUnits, 30000, reason: '200.00 and 100.00, in minor units');
      expect(byWindow['quarter']!.expense.minorUnits, 30000);
      expect(
        byWindow['quarter']!.income.minorUnits,
        0,
        reason: 'nothing in the log records income, and the view states that rather than inventing it',
      );
    });
  });

  group('the screen', () {
    testWidgets('**an amount that arrives after the first build still reaches the box**', (tester) async {
      // **The handset case this exists for: changing the currency.** The deposit is stored per currency, so
      // switching the reader's money resolves a different float -- and the controller is created in `initState`
      // with whatever was there then. Without `didUpdateWidget` the box keeps the previous currency's number
      // beside a new currency's label, which is worse than an empty box because it looks like a value.
      //
      // Driven through the container rather than by pumping twice: two `pumpWidget` calls in one case reuse the
      // first call's container, which is the trap this file records above.
      await _pumpSection(tester, settings: const CashSettings(deposits: {'CNY': 30000}));

      TextField box() => tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const ValueKey('cash-deposit')),
          matching: find.byType(TextField),
        ),
      );
      expect(box().controller!.text, '300.00');

      // The same widget, handed a different amount: `element.update` rather than a fresh mount.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: _container,
          child: const MaterialApp(
            home: Scaffold(body: SingleChildScrollView(child: CashflowSection())),
          ),
        ),
      );
      _container.read(cashSettingsProvider.notifier).state =
          const CashSettings(deposits: {'CNY': 12550});
      await tester.pump();
      expect(box().controller!.text, '125.50', reason: 'the box follows the amount');
    });

    testWidgets('**the four windows are labelled and the income gap is named**', (tester) async {
      await _pumpSection(tester);

      expect(find.text(Copy.cellarCashflow.primary.text), findsOneWidget);
      for (final label in [
        Copy.cashflowToday,
        Copy.cashflowWeek,
        Copy.cashflowMonth,
        Copy.cashflowQuarter,
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      // The reason this section is worth having rather than a zero: the reader is told which of the two things
      // a zero would mean, in their own language and in the register they chose.
      expect(find.text(Copy.cashflowNoIncome.primary.text), findsOneWidget);
    });

    testWidgets('a window with nothing spent draws a dash rather than a zero', (tester) async {
      // `0.00` reads as a total that was arrived at; an em dash reads as nothing to total. The distinction is
      // the same one `cellarNoPrices` draws for the cellar's value.
      await _pumpSection(tester, emptyCellar: true);
      expect(find.text('—'), findsWidgets);
    });

    testWidgets('**the starting float seeds the field as a number, not as a formatted amount**',
        (tester) async {
      // `moneyText` renders `500.00 CNY`, and seeding an editable field with that makes it unreadable back --
      // the currency code is not part of what a person types. This is the round trip that would fail.
      await _pumpSection(tester, settings: const CashSettings(deposits: {'CNY': 50000}));

      final field = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const ValueKey('cash-deposit')),
          matching: find.byType(TextField),
        ),
      );
      expect(field.controller!.text, '500.00');
      expect(field.controller!.text.contains('CNY'), isFalse);
      // And it converts back to exactly what was stored.
      expect(minorUnitsTyped(field.controller!.text, const Currency('CNY', 2)), 50000);
    });

    testWidgets('**the log-implied figure is absent until a float has been entered**', (tester) async {
      // Without a starting figure there is nothing to imply, and a comparison against an unset float would
      // compare the reader's count against all recorded history and call the difference a discrepancy.
      //
      // **One pump per case, and that is a rule these tests learned the hard way.** Two `pumpWidget` calls in one
      // `testWidgets` reuse the container the first call built, so the second call's overrides never reach the
      // widget -- the section kept drawing the first case's empty settings, and the failure read as a missing row
      // rather than a missing override.
      await _pumpSection(tester, settings: const CashSettings());
      expect(find.text(Copy.cashflowImplied.primary.text), findsNothing);
    });

    testWidgets('**the log-implied figure appears once a float has been entered**', (tester) async {
      await _pumpSection(tester, settings: const CashSettings(deposits: {'CNY': 30000}));

      // The field first, then the row: if the override had not reached the widget the box would be empty, and
      // this would be reporting a missing row when the cause was a missing setting.
      final field = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const ValueKey('cash-deposit')),
          matching: find.byType(TextField),
        ),
      );
      expect(field.controller!.text, '300.00', reason: 'the override reached the widget');
      expect(find.text(Copy.cashflowImplied.primary.text), findsOneWidget);
    });

    testWidgets('**a count that agrees with the log says so**', (tester) async {
      // Float 300.00 and 300.00 of spending implies nothing left -- the log's own arithmetic, not this test's.
      await _pumpSection(
        tester,
        settings: const CashSettings(deposits: {'CNY': 30000}, counted: {'CNY': 0}, countedAtMillis: 1),
      );
      expect(find.text(Copy.cashflowBalances.primary.text), findsOneWidget);
    });

    testWidgets('**a count that does not agree explains itself without deciding which cause it is**',
        (tester) async {
      await _pumpSection(
        tester,
        settings: const CashSettings(deposits: {'CNY': 30000}, counted: {'CNY': 7500}, countedAtMillis: 1),
      );
      expect(find.text(Copy.cashflowDifference.primary.text), findsOneWidget);
      expect(find.text(Copy.cashflowDifferenceNote.primary.text), findsOneWidget);
      // `CashReconciliation` sets that rule: the application shows the difference, it does not guess whether the
      // gap was a sale or a purchase.
    });
  });
}

// ---------------------------------------------------------------- helpers

class _Seeded extends CellarNotifier {
  _Seeded(this._initial);

  final Cellar _initial;

  @override
  Future<Cellar> build() async => _initial;
}

/// A cellar whose log holds two purchases, 300.00 CNY between them.
///
/// Built on the real clock through `runAsync`, for the reason `cellar_page_test` records: `testWidgets` runs in
/// a FakeAsync zone where a real file write never completes.
/// The built cellar, filled by [_ensureCellar] and read by the overrides.
///
/// **A holder rather than a call inside the override.** `overrideWith(() => _Seeded(_builtCellar()))` looks
/// equivalent and is not: the closure is evaluated when the provider is first built, so a fixture that fills the
/// The two cellars every case reads: one with two purchases in it, one with nothing.
///
/// **Built in `setUpAll`, which runs outside the fake-async zone.** Lazy-building them from inside a
/// `testWidgets` body needs `runAsync` to reach a real file write, and that is what left pending timers behind;
/// a hook does not run in the widget binding's zone at all, so the log is just built.
late Cellar _fixture;
late Cellar _emptyCellar;

Future<Cellar> _build(List<(String, int)> purchases) async {
  final directory = Directory.systemTemp.createTempSync('cashflow_test');
  var clock = 1000;
  final log = await EventLog.open(
    file: File('${directory.path}${Platform.pathSeparator}cellar.ndjson'),
    nodeId: 'test',
    nowMillis: () => clock++,
  );
  // **Stamped two days back, and that is what makes the tests meaningful.** An event recorded "now" would land
  // in every window including 当日, so a fold that ignored its own bounds would still pass. Two days puts it
  // outside 当日 and inside 7/30/90, which is a shape the fold has to compute rather than receive.
  final twoDaysAgo = DateTime.now().subtract(const Duration(days: 2)).millisecondsSinceEpoch;
  for (final (sku, minor) in purchases) {
    await log.record(
      (_) => PriceEvents.paid(
        hlc: Hlc(physicalMillis: clock++, counter: 0, nodeId: 'test'),
        sku: sku,
        minorUnits: minor,
        currency: const Currency('CNY', 2),
        microlitres: 700000,
        source: PriceSource.manual,
        purchasedAtMillis: twoDaysAgo,
      ),
    );
  }
  return Cellar.of(log);
}

/// Pumps the section with everything already resolved.
///
/// **No `runAsync`, and the reason is a failure worth recording.** An earlier version let the real (async)
/// `cellarProvider` resolve inside the fake clock by calling `tester.runAsync` mid-test, and every case then
/// failed with *"A Timer is still pending even after the widget tree was disposed"* -- the real `Future.delayed`
/// that gave the microtask a chance was itself a pending timer by the time the binding checked its invariants.
/// So the cellar is built once, outside, and handed over as a resolved value; nothing in here touches a clock.
/// The container the last [_pumpSection] built, so a case can change a provider and pump again.
late ProviderContainer _container;

Future<void> _pumpSection(
  WidgetTester tester, {
  bool emptyCellar = false,
  CashSettings settings = const CashSettings(),
}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final cellar = emptyCellar ? _emptyCellar : _fixture;
  final now = DateTime.now();
  final overrides = [
    cellarProvider.overrideWith(() => _Seeded(cellar)),
    cashSettingsProvider.overrideWith(() => _FixedCash(settings)),
    // The fold itself, done here on a cellar that is already in hand.
    cashflowsProvider.overrideWithValue(AsyncValue.data(_foldFor(cellar, now))),
    cashflowCurrencyProvider.overrideWithValue(const Currency('CNY', 2)),
  ];

  _container = ProviderContainer(overrides: overrides);
  addTearDown(_container.dispose);

  // **`UncontrolledProviderScope` rather than `ProviderScope`, so the test owns the container.** With
  // `ProviderScope` a second `pumpWidget` in the same case rebuilds the scope, and the widget keeps drawing the
  // first case's values -- which is what made two earlier versions of these tests fail on their overrides.
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: _container,
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: CashflowSection())),
      ),
    ),
  );
  await tester.pump();
}

/// The same fold `cashflowsProvider` does, written here so a test can hand it over already resolved.
List<Cashflow> _foldFor(Cellar cellar, DateTime now) {
  final expenses = <CashflowEntry>[];
  for (final event in cellar.log.events) {
    final op = PriceOp.tryParse(event);
    if (op is! PricePaid) continue;
    expenses.add(CashflowEntry(
      minorUnits: op.minorUnits,
      currency: op.currency,
      at: DateTime.fromMillisecondsSinceEpoch(op.atMillis),
      label: op.sku,
    ));
  }
  return [
    for (final window in CashflowWindow.values)
      cashflowOf(window: window, now: now, expense: expenses),
  ];
}

class _FixedCash extends CashSettingsNotifier {
  _FixedCash(this._initial);

  final CashSettings _initial;

  @override
  CashSettings build() => _initial;
}
