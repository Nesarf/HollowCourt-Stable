import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hollow_court/data/seed/seed_repository.dart';
import 'package:hollow_court/domain/model/glass.dart';
import 'package:hollow_court/domain/model/ice.dart';
import 'package:hollow_court/domain/model/ingredient.dart';
import 'package:hollow_court/domain/model/item_role.dart';
import 'package:hollow_court/domain/model/recipe.dart';
import 'package:hollow_court/domain/units/unit_system.dart';
import 'package:hollow_court/ui/library.dart';
import 'package:hollow_court/ui/sub_recipe_sheet.dart';
import 'package:hollow_court/ui/theme.dart';

/// **The tree button opens the method the link names, and nothing else.**
///
/// `base_recipe_links_test` proves the data: every `madeBy` has a recipe behind it, there is no loop, nothing is
/// deeper than three. This file proves the other half, which that test cannot see -- that the button the interface
/// grows actually opens *that* recipe's steps, and that a row without a link grows no button at all.
///
/// **The gap this closes was written down before it was closed.** The commit that put the button on the ingredient
/// card said there was no widget test for it; this is the test, and `docs/TODO.md` now says so.
void main() {
  final espresso = Ingredient(
    id: 'espressoCoffee',
    name: 'Espresso',
    kind: 'pantry',
    family: 'coffee',
    extras: const {'madeBy': 'baseEspresso'},
  );
  final ground = Ingredient(id: 'coffeeGround', name: 'Ground coffee', kind: 'pantry');
  final water = Ingredient(id: 'water', name: 'Water', kind: 'mixer');

  Recipe baseEspresso() => Recipe(
    id: 'baseEspresso',
    name: 'Espresso',
    packId: 'house',
    glass: Glass.lowball,
    ice: IceKind.none,
    method: Method.built,
    methodSteps: const ['Dose eighteen grams.', 'Stop it at thirty-six millilitres.'],
    items: const [
      RecipeItem(ingredientId: 'coffeeGround', amount: 18000, unit: UnitSystem.gram, role: ItemRole.base),
      RecipeItem(ingredientId: 'water', amount: 36000, unit: UnitSystem.millilitre, role: ItemRole.modifier),
    ],
  );

  ProviderScope scoped(Widget child) => ProviderScope(
    overrides: [
      seedProvider.overrideWith(
        () => _FixedSeed(
          SeedRepository.of(
            ingredients: [espresso, ground, water],
            recipes: [baseEspresso()],
          ),
        ),
      ),
    ],
    child: MaterialApp(theme: HollowTheme.build(), home: Scaffold(body: child)),
  );

  testWidgets('**the button opens the base method behind a finished thing**', (tester) async {
    await tester.pumpWidget(
      scoped(TreeButton(recipe: baseEspresso(), depth: 0, visited: const <String>{})),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('sub-recipe-baseEspresso')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('sub-recipe-baseEspresso')));
    await tester.pumpAndSettle();

    expect(
      find.text('Dose eighteen grams.'),
      findsOneWidget,
      reason: 'the sheet has to show the method, not the name again',
    );
    expect(find.text('Stop it at thirty-six millilitres.'), findsOneWidget);

    // The base's own lines are there, and neither of them has a link, so the sheet grows no further.
    expect(
      find.descendant(
        of: find.byType(SubRecipeSheet),
        matching: find.byIcon(Icons.account_tree_outlined),
      ),
      findsNothing,
      reason: 'a row whose ingredient has no madeBy grows no button',
    );
  });

  testWidgets('**a row whose base is already open grows no button**', (tester) async {
    const item = RecipeItem(
      ingredientId: 'espressoCoffee',
      amount: 30000,
      unit: UnitSystem.millilitre,
      role: ItemRole.base,
    );

    // Nothing open above it: the row carries the button.
    await tester.pumpWidget(
      scoped(
        SubRecipeItemRow(
          item: item,
          available: true,
          depth: 1,
          visited: const <String>{},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sub-recipe-baseEspresso')), findsOneWidget);

    // The same row with that base already open in the stack: no button, which is what keeps a loop from becoming a
    // stack of sheets.
    await tester.pumpWidget(
      scoped(
        SubRecipeItemRow(
          item: item,
          available: true,
          depth: 1,
          visited: const <String>{'baseEspresso'},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('sub-recipe-baseEspresso')),
      findsNothing,
      reason: 'the visited set is what refuses a second opening',
    );
  });
}

/// A seed that is only what this test needs, in the shape `ingredient_section_test` established.
class _FixedSeed extends SeedNotifier {
  _FixedSeed(this.repository);

  final SeedRepository? repository;

  @override
  Future<SeedRepository?> build() async => repository;
}
