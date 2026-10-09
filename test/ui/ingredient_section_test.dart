import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hollow_court/data/seed/seed_repository.dart';
import 'package:hollow_court/domain/events/event.dart';
import 'package:hollow_court/domain/events/hlc.dart';
import 'package:hollow_court/domain/events/ingredient_authoring.dart';
import 'package:hollow_court/domain/events/stock.dart';
import 'package:hollow_court/domain/model/ingredient.dart';
import 'package:hollow_court/domain/model/ingredient_category.dart';
import 'package:hollow_court/domain/units/quantity.dart';
import 'package:hollow_court/ui/ingredient_section.dart';
import 'package:hollow_court/ui/library.dart';
import 'package:hollow_court/ui/l10n/locale_providers.dart';
import 'package:hollow_court/ui/l10n/locale_settings.dart';
import 'package:hollow_court/ui/theme.dart';
import '../support/open_logs.dart';

/// **The catalogue and the stock are two lists, and the tab draws them as two** -- stage ① of
/// `docs/catalogue-and-stock.md`.
///
/// The finding is the owner's: *a warehouse keeps the supplier's catalogue and its own stock as two tables and never
/// mixes them.* The 原料 tab mixed them -- it drew all 189 ingredients the library carries as one list, and a reader
/// who actually manages twenty of them had to find those twenty inside it. Nothing about the data changed for this:
/// the join already existed as `Cellar.has`, the same predicate every recipe score uses.
///
/// **What these tests hold to**: an ingredient the reader holds a bottle of moves to their half and *stays
/// read-only* -- it is theirs to look after and still not theirs to edit, which is the case the single list could
/// not express at all.
void main() {
  late Directory home;

  setUp(() => home = Directory.systemTemp.createTempSync('hollow-ingredients'));
  tearDown(() async {
    await releaseCellars();
    if (home.existsSync()) home.deleteSync(recursive: true);
  });

  /// Reading numbers that advance on their own.
  ///
  /// **The trap `cellar_page_test` records, met again**: two helper-built events carrying the same `Hlc` are the
  /// same event as far as any device can tell, so the log keeps the first and drops the second.
  var clock = 1000;
  Hlc tick() => Hlc(physicalMillis: ++clock, counter: 0, nodeId: 'test');

  Ingredient ingredient(String id, String name) =>
      Ingredient(id: id, name: name, category: IngredientCategory.itemsYouCanMake);

  /// A real cellar, built outside the test's fake clock -- a widget test's fake clock never completes a real file
  /// write, so the log has to be made on the real one. Once it exists the section only reads it.
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

  Future<void> pump(WidgetTester tester, Cellar built) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cellarProvider.overrideWith(() => _Seeded(built)),
          seedProvider.overrideWith(
            () => _FixedSeed(
              SeedRepository.of(
                ingredients: [
                  ingredient('gin', 'Gin'),
                  ingredient('sweetVermouth', 'Sweet vermouth'),
                  ingredient('campari', 'Campari'),
                ],
                recipes: const [],
              ),
            ),
          ),
          localeSettingsProvider.overrideWith(
            () => _FixedLocale(
              const LocaleSettings(primaryTag: 'zh-Hans', secondaryTag: 'en', dualCopy: false),
            ),
          ),
        ],
        child: MaterialApp(
          theme: HollowTheme.build(),
          home: const Scaffold(body: SingleChildScrollView(child: IngredientSection())),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The same finder a reader's eye is: which of the two grids is this card inside?
  Finder inMine(String id) => find.descendant(
    of: find.byKey(const ValueKey('ingredient-group-mine')),
    matching: find.byKey(ValueKey('ingredient-$id')),
  );
  Finder inLibrary(String id) => find.descendant(
    of: find.byKey(const ValueKey('ingredient-group-library')),
    matching: find.byKey(ValueKey('ingredient-$id')),
  );

  testWidgets('**a bottle on the shelf moves its ingredient to the reader\'s half**', (tester) async {
    final built = await cellar(tester, [
      StockEvents.bottleAdded(
        hlc: tick(),
        bottleId: 'b1',
        sku: 'gin',
        volume: Volume.fromMillilitres(700),
      ),
    ]);
    await pump(tester, built);

    expect(inMine('gin'), findsOneWidget, reason: 'the reader holds a bottle of it');
    // **And the rest of the catalogue did not move with it.** One held ingredient is one row, not a sort order.
    expect(inLibrary('sweetVermouth'), findsOneWidget);
    expect(inLibrary('campari'), findsOneWidget);
    expect(inMine('sweetVermouth'), findsNothing);
  });

  testWidgets('**an empty shelf leaves the whole catalogue on the library\'s side**', (tester) async {
    await pump(tester, await cellar(tester, const []));

    expect(find.byKey(const ValueKey('ingredient-group-mine')), findsOneWidget);
    expect(find.byKey(const ValueKey('ingredient-group-library')), findsOneWidget);
    for (final id in ['gin', 'sweetVermouth', 'campari']) {
      expect(inLibrary(id), findsOneWidget, reason: '$id is not held');
    }
  });

  testWidgets('**what the reader wrote is on their side, and held or not does not matter**', (tester) async {
    final built = await cellar(tester, [
      IngredientAuthoredEvents.set(
        hlc: tick(),
        ingredient: const AuthoredIngredient(id: 'own.yuzu-1', name: 'Yuzu'),
      ),
    ]);
    await pump(tester, built);

    // **Authored by construction rather than by asking the shelf.** An ingredient of the reader's own is theirs
    // even with no bottle of it anywhere, which is the thing a predicate over bottles alone could not say.
    expect(inMine('own.yuzu-1'), findsOneWidget);
    expect(inLibrary('own.yuzu-1'), findsNothing);
    // And the catalogue is untouched by their having written one.
    expect(inLibrary('gin'), findsOneWidget);
  });

  testWidgets('**the search cuts both halves at once**', (tester) async {
    final built = await cellar(tester, [
      StockEvents.bottleAdded(
        hlc: tick(),
        bottleId: 'b1',
        sku: 'gin',
        volume: Volume.fromMillilitres(700),
      ),
      IngredientAuthoredEvents.set(
        hlc: tick(),
        ingredient: const AuthoredIngredient(id: 'own.yuzu-1', name: 'Yuzu'),
      ),
    ]);
    await pump(tester, built);

    await tester.enterText(find.byKey(const ValueKey('ingredient-search')), 'vermouth');
    await tester.pumpAndSettle();

    // **A reader who types a name is asking where a thing is, not which list it is in** -- so the query runs over
    // both halves and neither is hidden from it.
    expect(inLibrary('sweetVermouth'), findsOneWidget);
    expect(inMine('gin'), findsNothing);
    expect(inLibrary('gin'), findsNothing);
    expect(inMine('own.yuzu-1'), findsNothing);
  });

  testWidgets('**both halves say what an empty half means**', (tester) async {
    await pump(tester, await cellar(tester, const []));

    // An empty reader's side is empty for the opposite reason an empty library side is, so the two sentences
    // differ -- and the reader's is the one on screen when they have added nothing yet.
    final mineEmpty = Copy.ingredientMineEmpty.textFor('zh-Hans');
    expect(find.text(mineEmpty), findsOneWidget);
    expect(find.text(Copy.ingredientLibraryEmpty.textFor('zh-Hans')), findsNothing);
  });
}

final class _FixedLocale extends LocaleSettingsNotifier {
  _FixedLocale(this._settings);

  final LocaleSettings _settings;

  @override
  LocaleSettings build() => _settings;
}

final class _FixedSeed extends SeedNotifier {
  _FixedSeed(this.repository);

  final SeedRepository repository;

  @override
  Future<SeedRepository?> build() async => repository;
}

final class _Seeded extends CellarNotifier {
  _Seeded(this._initial);

  final Cellar _initial;

  @override
  Future<Cellar> build() async => _initial;
}
