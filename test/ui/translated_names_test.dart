import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/data/event_log.dart';
import 'package:hollow_court/data/seed/seed_repository.dart';
import 'package:hollow_court/domain/model/glass.dart';
import 'package:hollow_court/domain/model/ice.dart';
import 'package:hollow_court/domain/model/ingredient.dart';
import 'package:hollow_court/domain/model/ingredient_category.dart';
import 'package:hollow_court/domain/model/item_role.dart';
import 'package:hollow_court/domain/model/recipe.dart';
import 'package:hollow_court/domain/units/unit_system.dart';
import 'package:hollow_court/ui/library.dart';
import 'package:hollow_court/ui/l10n/locale_providers.dart';
import 'package:hollow_court/ui/l10n/locale_settings.dart';
import 'package:hollow_court/ui/recipes_page.dart';
import 'package:hollow_court/ui/seed_names.dart';
import 'package:hollow_court/ui/stock_page.dart';
import 'package:hollow_court/ui/theme.dart';

/// **The names the reader sees are the names in their language** -- the reported defect, as tests.
///
/// *"IBA官方鸡尾酒中文下还是原名（英文），原料名虽然用中文可以搜出来对应的英文但显示的仍旧是英文"*: the translation table
/// had every name in four languages and the screens drew the seed's English. Search already asked the table
/// (`_namesOf`), which is why a Chinese query found the ingredient and the row it found said "Gin".
///
/// So each test here is the *same* data reaching a different drawing site: the drinks list, the recipe sheet,
/// the ingredient picker. The coverage of the shipped data itself is asserted in
/// `test/data/seed/seed_translation_coverage_test.dart`, which is a different claim.
void main() {
  // The names file as this build would have it, trimmed to what these tests draw.
  const namesJson = '''
  {
    "format": "hollow-court-seed-names",
    "version": 1,
    "ingredients": {
      "gin": {"zh-Hans": "金酒", "ja": "ジン"},
      "sweetVermouth": {"zh-Hans": "甜味美思", "ja": "スイートベルモット"},
      "campari": {"zh-Hans": "金巴利", "ja": "カンパリ"}
    },
    "recipes": {
      "ibaNegroni": {"zh-Hans": "内格罗尼", "ja": "ネグローニ"}
    },
    "steps": {
      "ibaNegroni": {
        "zh-Hans": ["把三样倒进加冰的调酒杯里搅匀。", "滤进冰镇过的杯中。", "以橙皮装饰。"],
        "ja": ["氷を入れたミキシンググラスで三つを混ぜる。", "冷やしたグラスに濾す。", "オレンジピールを添える。"]
      }
    }
  }
  ''';

  Ingredient ingredient(String id, String name) =>
      Ingredient(id: id, name: name, category: IngredientCategory.gin);

  Recipe negroni() => Recipe(
    id: 'ibaNegroni',
    name: 'Negroni',
    packId: 'official',
    // The folder a drink is filed under is read off these two, so a fixture without them lands in a folder with
    // no label -- which is how this test first failed: the drink was there and the folder it was inside had no
    // name to tap.
    extras: const {'source': 'iba', 'category': 'The Unforgettables'},
    glass: Glass.lowball,
    ice: IceKind.cubes,
    method: Method.stirred,
    methodSteps: const ['Stir the three with ice.', 'Strain into a chilled glass.', 'Garnish with orange peel.'],
    // Amounts are whole microlitres (§5.1), so 30 ml is 30000.
    items: const [
      RecipeItem(ingredientId: 'gin', amount: 30000, unit: UnitSystem.millilitre, role: ItemRole.base),
      RecipeItem(ingredientId: 'sweetVermouth', amount: 30000, unit: UnitSystem.millilitre, role: ItemRole.modifier),
      RecipeItem(ingredientId: 'campari', amount: 30000, unit: UnitSystem.millilitre, role: ItemRole.modifier),
    ],
  );

  late Directory home;

  setUp(() => home = Directory.systemTemp.createTempSync('hollow-names'));
  tearDown(() {
    if (home.existsSync()) home.deleteSync(recursive: true);
  });

  /// A cellar with nothing in it, built on the real clock -- the same `runAsync` requirement every page test
  /// records, because a widget test's fake clock never completes a real file write.
  Future<Cellar> cellar(WidgetTester tester) async {
    final built = await tester.runAsync(() async {
      final log = await EventLog.open(
        file: File('${home.path}${Platform.pathSeparator}cellar.ndjson'),
        nodeId: 'test',
        nowMillis: () => 1000,
      );
      return Cellar.of(log);
    });
    return built!;
  }

  Future<void> pump(WidgetTester tester, Widget page, {String locale = 'zh-Hans'}) async {
    final built = await cellar(tester);
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
                recipes: [negroni()],
              ),
            ),
          ),
          seedNamesProvider.overrideWith((ref) async => SeedNames.fromJson(namesJson)),
          localeSettingsProvider.overrideWith(
            () => _FixedLocale(
              LocaleSettings(primaryTag: locale, secondaryTag: 'en', dualCopy: false),
            ),
          ),
        ],
        child: MaterialApp(theme: HollowTheme.build(), home: Scaffold(body: page)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('**the drinks list is written in the reader\'s language**', (tester) async {
    await pump(tester, const RecipesPage());

    // **The list opens on folders, so the official pack is one tap away.** The drink row only exists once its
    // folder is open -- which is also why the first version of this test found no name at all and not merely the
    // wrong name.
    await tester.tap(find.text('The Unforgettables'));
    await tester.pumpAndSettle();

    expect(find.text('内格罗尼'), findsOneWidget, reason: 'the drink the library calls Negroni');
    expect(find.text('Negroni'), findsNothing, reason: 'the harvested English name is not what a reader reads');
  });

  testWidgets('**and so are the ingredients under it, and the instructions**', (tester) async {
    await pump(tester, const RecipesPage());

    await tester.tap(find.text('The Unforgettables'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('内格罗尼'));
    await tester.pumpAndSettle();

    // The sheet: every ingredient line, then the steps.
    expect(find.text('金酒'), findsWidgets, reason: 'gin');
    expect(find.text('甜味美思'), findsWidgets, reason: 'sweet vermouth');
    expect(find.text('金巴利'), findsWidgets, reason: 'campari');
    expect(find.text('Gin'), findsNothing);
    expect(find.text('把三样倒进加冰的调酒杯里搅匀。'), findsOneWidget);
    expect(find.text('Stir the three with ice.'), findsNothing);
  });

  testWidgets('**the ingredient a Chinese query finds is drawn in Chinese**', (tester) async {
    // The reported asymmetry, in one test: `金酒` finds gin -- and the row it finds must say 金酒.
    await pump(tester, const StockPage());

    await tester.tap(find.text(Copy.stockAddBottle.primary.text).first);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '金酒');
    await tester.pumpAndSettle();

    expect(find.text('金酒'), findsWidgets, reason: 'the option the search returned');
    expect(find.text('Gin'), findsNothing, reason: 'the seed name must not be what is drawn');
  });
}

/// A seed that is already loaded, so a test does not depend on the asset bundle.
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

final class _FixedLocale extends LocaleSettingsNotifier {
  _FixedLocale(this.settings);

  final LocaleSettings settings;

  @override
  LocaleSettings build() => settings;
}
