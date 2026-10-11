import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hollow_court/domain/events/event.dart';
import 'package:hollow_court/domain/events/hlc.dart';
import 'package:hollow_court/domain/events/stock.dart';
import 'package:hollow_court/domain/stats/reorder.dart';
import 'package:hollow_court/domain/units/quantity.dart';
import 'package:hollow_court/ui/library.dart';
import 'package:hollow_court/ui/preferences_providers.dart';
import 'package:hollow_court/ui/reorder_section.dart';
import 'package:hollow_court/ui/theme.dart';
import '../support/open_logs.dart';

/// **What is worth buying again** -- stage ④ of `docs/catalogue-and-stock.md`, on the screen.
///
/// The domain arithmetic is `test/domain/stats/reorder_test.dart`'s. What is held to here is the two things only a
/// screen can be wrong about: that the reasons a bottle is on the list are **drawn** rather than scored, and that
/// "reader-adjustable" is true rather than a word in a design note.
void main() {
  late Directory home;
  setUp(() => home = Directory.systemTemp.createTempSync('hollow-reorder'));
  tearDown(() async {
    await releaseCellars();
    if (home.existsSync()) home.deleteSync(recursive: true);
  });

  var clock = 1000;
  Hlc tick() => Hlc(physicalMillis: ++clock, counter: 0, nodeId: 'test');

  /// A cellar built on the real clock -- a widget test's fake clock never completes a real file write.
  Future<Cellar> cellar(WidgetTester tester, List<Event> events) async {
    final built = await tester.runAsync(() async {
      final log = await openTracked(
        file: File('${home.path}${Platform.pathSeparator}cellar.ndjson'),
        nodeId: 'test',
        nowMillis: () => ++clock,
      );
      for (final event in events) {
        await log.record((_) => event);
      }
      return Cellar.of(log);
    });
    return built!;
  }

  Event added(String id, String sku, int millilitres) => StockEvents.bottleAdded(
    hlc: tick(),
    bottleId: id,
    sku: sku,
    volume: Volume.fromMillilitres(millilitres),
  );

  Event poured(String id, int millilitres) => StockEvents.bottleConsumed(
    hlc: tick(),
    bottleId: id,
    volume: Volume.fromMillilitres(millilitres),
  );

  late _RecordingPreferences prefs;

  Future<void> pump(WidgetTester tester, Cellar built) async {
    prefs = _RecordingPreferences();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cellarProvider.overrideWith(() => _Seeded(built)),
          preferencesProvider.overrideWith(() => prefs),
        ],
        child: MaterialApp(
          theme: HollowTheme.build(),
          // **Left at the framework's default on purpose, and it cost a run to decide.**
          //
          // The reasons are drawn in whatever `Localizations.localeOf` answers, so the test looked as though it had
          // to pin the locale. Two attempts that did: `locale: Locale('zh','Hans')` is *declined*, because
          // `MaterialApp` resolves against `supportedLocales` whose default is `en-US` alone; and adding
          // `supportedLocales: [zh-Hans]` then picked a locale this build's `DefaultMaterialLocalizations` does not
          // support, which broke every case in the file rather than the one being written.
          //
          // So the app is left alone and the assertion is written against what the default resolves to -- English --
          // which makes the claim *the reason line is drawn, in the language the framework resolved* rather than
          // *the reason line is drawn in Chinese*. **The five translations themselves are
          // `translation_coverage_test`'s claim**, and duplicating it here would be a second place to keep true.
          home: Scaffold(
            body: SingleChildScrollView(
              child: ReorderSection(
                nameOf: (id) => id,
                events: built.events,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('**a nearly empty bottle is listed, and with the reason it is on the list**', (tester) async {
    final built = await cellar(tester, [added('b1', 'gin', 700), poured('b1', 650)]);
    await pump(tester, built);

    expect(find.text('gin'), findsOneWidget);
    // 650 of 700 poured is 93% gone -- the number a reader recognises from looking at the bottle in front of them.
    expect(find.text('93%'), findsOneWidget);
    // **The reason, named.** A single "lowness" score would let the section sort itself and tell the reader nothing
    // about why, and the three reasons do not agree about what is wrong.
    expect(find.textContaining('Nearly empty'), findsOneWidget);
  });

  testWidgets('**a healthy cellar says so rather than showing nothing**', (tester) async {
    // An absence with no explanation reads as a feature that did not load -- the same reason the shopping list has a
    // sentence for "nothing planned" beside its own empty state.
    final built = await cellar(tester, [added('b1', 'gin', 1000), poured('b1', 50)]);
    await pump(tester, built);

    expect(find.textContaining(Copy.reorderNothing.primary.text), findsOneWidget);
  });

  testWidgets('**the list says what it was asked for**', (tester) async {
    // A list that warns about a bottle and does not say which numbers put it there is a list a reader cannot argue
    // with -- and the numbers are the whole of the argument.
    await pump(tester, await cellar(tester, const []));

    expect(find.textContaining('20'), findsWidgets);
    expect(find.textContaining('100'), findsWidgets);
    expect(find.textContaining('30'), findsWidgets);
  });

  testWidgets('**the thresholds are changeable, and the change reaches the store**', (tester) async {
    await pump(tester, await cellar(tester, const []));

    await tester.tap(find.byKey(const ValueKey('reorder-edit')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('reorder-percent')), '40');
    await tester.enterText(find.byKey(const ValueKey('reorder-ml')), '250');
    await tester.tap(find.byKey(const ValueKey('reorder-save')));
    await tester.pumpAndSettle();

    expect(prefs.written, hasLength(1));
    expect(prefs.written.single.fillPercent, 40);
    expect(prefs.written.single.millilitres, 250);
    // **And the one nobody touched is kept**, which is what a sheet that minted a fresh `ReorderPoint` from its three
    // fields would have got wrong if it had read them as zero.
    expect(prefs.written.single.horizonDays, ReorderPoint.defaults.horizonDays);
  });

  testWidgets('**a field that cannot be read keeps what was there rather than becoming zero**', (tester) async {
    // Zero turns a signal off silently, and a reader who typed a stray letter would find the list shorter with
    // nothing on the screen to explain it.
    await pump(tester, await cellar(tester, const []));

    await tester.tap(find.byKey(const ValueKey('reorder-edit')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('reorder-percent')), 'abc');
    await tester.tap(find.byKey(const ValueKey('reorder-save')));
    await tester.pumpAndSettle();

    expect(prefs.written.single.fillPercent, ReorderPoint.defaults.fillPercent);
  });
}

final class _RecordingPreferences extends PreferencesNotifier {
  final List<ReorderPoint> written = [];

  @override
  Future<void> setReorder(ReorderPoint point) async => written.add(point);
}

final class _Seeded extends CellarNotifier {
  _Seeded(this._initial);

  final Cellar _initial;

  @override
  Future<Cellar> build() async => _initial;
}
