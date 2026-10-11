import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hollow_court/data/seed/seed_repository.dart';
import 'package:hollow_court/domain/events/event.dart';
import 'package:hollow_court/domain/events/hlc.dart';
import 'package:hollow_court/domain/events/ingredient_authoring.dart';
import 'package:hollow_court/domain/events/recipe_authoring.dart';
import 'package:hollow_court/domain/events/shelf.dart';
import 'package:hollow_court/domain/events/shelf_authoring.dart';
import 'package:hollow_court/domain/events/stock.dart';
import 'package:hollow_court/domain/model/glass.dart';
import 'package:hollow_court/domain/model/ice.dart';
import 'package:hollow_court/domain/model/ingredient.dart';
import 'package:hollow_court/domain/model/ingredient_category.dart';
import 'package:hollow_court/domain/model/item_role.dart';
import 'package:hollow_court/domain/model/recipe.dart';
import 'package:hollow_court/domain/units/quantity.dart';
import 'package:hollow_court/domain/units/unit_system.dart';
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

  Future<void> pump(WidgetTester tester, Cellar built, {List<Recipe> recipes = const []}) async {
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
                  ingredient('yuzu', 'Yuzu'),
                ],
                recipes: recipes,
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

  /// A recipe that calls for [ids]; nothing else about it matters here.
  Recipe drink(String id, List<String> ids) => Recipe(
    id: id,
    name: id,
    packId: 'official',
    glass: Glass.lowball,
    ice: IceKind.cubes,
    method: Method.stirred,
    methodSteps: const ['Stir.'],
    items: [
      for (final ingredientId in ids)
        RecipeItem(
          ingredientId: ingredientId,
          amount: 30000,
          unit: UnitSystem.millilitre,
          role: ItemRole.base,
        ),
    ],
  );

  /// Four recipes naming gin, two naming vermouth, one naming campari, and **none naming yuzu** -- the measured
  /// shape of the library in miniature: a core, an occasional, a rare, and a piece of dead stock.
  List<Recipe> theFourClasses() => [
    drink('r1', ['gin']),
    drink('r2', ['gin', 'sweetVermouth']),
    drink('r3', ['gin', 'sweetVermouth']),
    drink('r4', ['gin', 'campari']),
  ];

  /// The same finder a reader's eye is: which of the two grids is this card inside?
  Finder inMine(String id) => find.descendant(
    of: find.byKey(const ValueKey('ingredient-group-mine')),
    matching: find.byKey(ValueKey('ingredient-$id')),
  );
  Finder inLibrary(String id) => find.descendant(
    of: find.byKey(const ValueKey('ingredient-group-library')),
    matching: find.byKey(ValueKey('ingredient-$id')),
  );
  Finder inClass(String name, String id) => find.descendant(
    of: find.byKey(ValueKey('ingredient-demand-$name')),
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

  // ---------------------------------------------------------------------------------------------------------------
  // Stage ②: the library's half, cut again by how much is actually asked of it.
  // ---------------------------------------------------------------------------------------------------------------

  testWidgets('**the library is drawn as four classes, and each ingredient is in the right one**', (tester) async {
    await pump(tester, await cellar(tester, const []), recipes: theFourClasses());

    // gin is named by four recipes, vermouth by two, campari by one, and yuzu by none -- the four buckets of
    // `docs/ingredient-gap.md`, reached from the interface rather than asserted about the seed.
    expect(inClass('core', 'gin'), findsOneWidget);
    expect(inClass('occasional', 'sweetVermouth'), findsOneWidget);
    expect(inClass('rare', 'campari'), findsOneWidget);
    expect(inClass('dead', 'yuzu'), findsOneWidget);

    // **And each is in exactly one class.** A row drawn twice would be a reader counting an ingredient twice and
    // concluding the library is bigger than it is.
    expect(inClass('dead', 'gin'), findsNothing);
    expect(inClass('rare', 'gin'), findsNothing);
    expect(inClass('core', 'yuzu'), findsNothing);
  });

  testWidgets('**the classes are drawn most-wanted first, and dead stock last**', (tester) async {
    await pump(tester, await cellar(tester, const []), recipes: theFourClasses());

    // Compared by position rather than by the order of a list in the source, because what a reader gets is the
    // vertical arrangement: `DemandClass.values` being right and the loop iterating it in another order would look
    // identical in the code and completely different on the screen.
    double top(String name) => tester.getTopLeft(find.byKey(ValueKey('ingredient-demand-$name'))).dy;
    expect(top('core'), lessThan(top('occasional')));
    expect(top('occasional'), lessThan(top('rare')));
    expect(top('rare'), lessThan(top('dead')));
  });

  testWidgets('**a class nothing falls into is not drawn at all**', (tester) async {
    // Every one of the four ingredients is called for by something, so there is no dead stock -- and a heading
    // saying "0" over an empty grid would be a line of furniture reporting the absence of things nobody had.
    // **The first version of this test was wrong rather than the code**: it named only gin, which left three of the
    // four in dead stock and the assertion failing for the opposite of the reason it was written.
    await pump(
      tester,
      await cellar(tester, const []),
      recipes: [
        drink('r1', ['gin']),
        drink('r2', ['gin', 'sweetVermouth']),
        drink('r3', ['gin', 'sweetVermouth']),
        drink('r4', ['gin', 'campari', 'yuzu']),
      ],
    );

    for (final drawn in ['core', 'occasional', 'rare']) {
      expect(find.byKey(ValueKey('ingredient-demand-$drawn')), findsOneWidget, reason: '$drawn holds something');
    }
    expect(find.byKey(const ValueKey('ingredient-demand-dead')), findsNothing);
  });

  testWidgets('**a recipe the reader wrote counts, so their own drink rescues dead stock**', (tester) async {
    // **The same rule every fold here follows**: a drink the reader wrote is a drink. Yuzu is called for by nothing
    // in the library, and one recipe of their own is enough to move it out of dead stock -- with nothing to
    // invalidate, because the count is derived rather than stored.
    final built = await cellar(tester, [
      RecipeAuthoredEvents.set(
        hlc: tick(),
        recipe: const AuthoredRecipe(
          id: 'own.yuzu-sour',
          name: 'Yuzu Sour',
          items: [AuthoredItem(ingredientId: 'yuzu', amount: '30')],
        ),
      ),
    ]);
    await pump(tester, built, recipes: theFourClasses());

    expect(inClass('rare', 'yuzu'), findsOneWidget);
    expect(inClass('dead', 'yuzu'), findsNothing);
  });

  testWidgets('**an ingredient the reader holds is on their side, not in a class**', (tester) async {
    // The two cuts are on different halves. A held ingredient left the catalogue in stage ①, and its class is not
    // shown at all -- it is something the reader already has, which is a better answer than how wanted it is.
    final built = await cellar(tester, [
      StockEvents.bottleAdded(
        hlc: tick(),
        bottleId: 'b1',
        sku: 'yuzu',
        volume: Volume.fromMillilitres(700),
      ),
    ]);
    await pump(tester, built, recipes: theFourClasses());

    expect(inMine('yuzu'), findsOneWidget);
    expect(find.byKey(const ValueKey('ingredient-demand-dead')), findsNothing);
  });

  testWidgets('**a query that matches nothing says so, instead of saying the half is empty**', (tester) async {
    // **The false sentence this replaces.** With a query typed, "nothing here yet" over a half that holds twenty
    // things the query did not match is simply untrue -- so an empty half says nothing and one line at the foot
    // says what happened.
    await pump(tester, await cellar(tester, const []), recipes: theFourClasses());

    await tester.enterText(find.byKey(const ValueKey('ingredient-search')), 'zzzz');
    await tester.pumpAndSettle();

    expect(find.text(Copy.ingredientNoMatch.textFor('zh-Hans')), findsOneWidget);
    expect(find.text(Copy.ingredientMineEmpty.textFor('zh-Hans')), findsNothing);
    expect(find.text(Copy.ingredientLibraryEmpty.textFor('zh-Hans')), findsNothing);
  });

  testWidgets('**a query cuts the classes as well as the halves**', (tester) async {
    await pump(tester, await cellar(tester, const []), recipes: theFourClasses());

    await tester.enterText(find.byKey(const ValueKey('ingredient-search')), 'campari');
    await tester.pumpAndSettle();

    expect(inClass('rare', 'campari'), findsOneWidget);
    // And the three classes the query emptied are gone, so the page is one heading rather than four.
    expect(find.byKey(const ValueKey('ingredient-demand-core')), findsNothing);
    expect(find.byKey(const ValueKey('ingredient-demand-dead')), findsNothing);
  });

  // ---------------------------------------------------------------------------------------------------------------
  // Stage ③: where the bottle of it actually stands.
  // ---------------------------------------------------------------------------------------------------------------

  /// A bottle of [sku], standing on [shelfId].
  List<Event> standing(String sku, String shelfId) => [
    StockEvents.bottleAdded(
      hlc: tick(),
      bottleId: 'b-$sku',
      sku: sku,
      volume: Volume.fromMillilitres(700),
    ),
    ShelfEvents.bottlePlaced(
      hlc: tick(),
      bottleId: 'b-$sku',
      shelfId: shelfId,
      posXPermille: 100,
      posYPermille: 100,
    ),
  ];

  testWidgets('**an ingredient the reader holds says which shelf it stands on**', (tester) async {
    // The join, on the screen it is for: ingredient id -> bottle -> placement -> the shelf book's word for it.
    final built = await cellar(tester, [
      ...standing('gin', 'own.fridge-1-0'),
      ShelfAuthoredEvents.declared(
        hlc: tick(),
        shelf: const AuthoredShelf(id: 'own.fridge-1-0', name: '冰箱'),
      ),
    ]);
    await pump(tester, built, recipes: theFourClasses());

    expect(inMine('gin'), findsOneWidget);
    expect(
      find.descendant(of: inMine('gin'), matching: find.text('冰箱')),
      findsOneWidget,
      reason: 'the reader\'s own word for the shelf, not the id',
    );
  });

  testWidgets('**the built-in shelf is named rather than shown as its key**', (tester) async {
    // A bottle of gin on `bar`, which nobody declared -- the state every existing cellar is in. The card must say
    // what the shelf is called, and `bar` is a key rather than a word.
    await pump(tester, await cellar(tester, standing('gin', 'bar')), recipes: theFourClasses());

    expect(find.descendant(of: inMine('gin'), matching: find.text('主架')), findsOneWidget);
    expect(find.text('bar'), findsNothing);
  });

  testWidgets('**a bottle nobody has stood anywhere marks nothing**', (tester) async {
    // Most of the catalogue, and the whole of a reader's first day: a card with a shelf on it means they own the
    // thing *and* have put it somewhere, which is what makes the mark worth looking at.
    await pump(
      tester,
      await cellar(tester, [
        StockEvents.bottleAdded(
          hlc: tick(),
          bottleId: 'b1',
          sku: 'gin',
          volume: Volume.fromMillilitres(700),
        ),
      ]),
      recipes: theFourClasses(),
    );

    expect(inMine('gin'), findsOneWidget, reason: 'it is held, so it is on the reader\'s side');
    expect(find.descendant(of: inMine('gin'), matching: find.text('主架')), findsNothing);
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
