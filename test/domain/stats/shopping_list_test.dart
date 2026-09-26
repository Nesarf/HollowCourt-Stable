import 'package:hollow_court/domain/model/glass.dart';
import 'package:hollow_court/domain/model/ice.dart';
import 'package:hollow_court/domain/model/item_role.dart';
import 'package:hollow_court/domain/model/liquid_visual.dart';
import 'package:hollow_court/domain/model/recipe.dart';
import 'package:hollow_court/domain/stats/shopping_list.dart';
import 'package:test/test.dart';

RecipeItem item(String ingredientId, {ItemRole role = ItemRole.base}) =>
    RecipeItem(ingredientId: ingredientId, amount: 30000, role: role);

Recipe recipe(String id, List<String> ingredients) => Recipe(
  id: id,
  name: id,
  glass: Glass.cocktail,
  ice: IceKind.none,
  method: Method.stirred,
  liquid: const LiquidVisual(colour: LiquidColour.orangeDark, opacityPercent: 75),
  items: [for (final ingredient in ingredients) item(ingredient)],
);

/// A cellar that holds nothing, which is the case a shopping list is for.
bool nothing(String _) => false;

void main() {
  group('a shopping list is a set of things, not a set of recipes', () {
    test('an ingredient two planned drinks want is one line saying two', () {
      // The whole point of the fold: a person buys one bottle of gin for two drinks, and the
      // count is what tells them whether it matters.
      final list = ShoppingList.of(
        recipes: [
          recipe('negroni', ['gin', 'campari', 'vermouthSweet']),
          recipe('martini', ['gin', 'vermouthDry']),
        ],
        plannedRecipeIds: {'negroni', 'martini'},
        have: nothing,
      );

      expect(list.entries.first.ingredientId, 'gin');
      expect(list.entries.first.neededBy, 2);
      expect(list.entries.map((e) => e.ingredientId), [
        'gin',
        'campari',
        'vermouthDry',
        'vermouthSweet',
      ]);
    });

    test('what the shelf already holds is not on the list', () {
      final list = ShoppingList.of(
        recipes: [
          recipe('negroni', ['gin', 'campari', 'vermouthSweet']),
        ],
        plannedRecipeIds: {'negroni'},
        have: (id) => id == 'gin',
      );

      expect(list.entries.map((e) => e.ingredientId), ['campari', 'vermouthSweet']);
    });

    test('a recipe nobody planned contributes nothing', () {
      final list = ShoppingList.of(
        recipes: [
          recipe('negroni', ['gin', 'campari']),
          recipe('martini', ['gin', 'vermouthDry']),
        ],
        plannedRecipeIds: {'negroni'},
        have: nothing,
      );

      expect(list.entries.map((e) => e.ingredientId), ['campari', 'gin']);
      expect(list.plannedRecipes, ['negroni']);
    });

    test('the order is most-needed first, and ties break by id', () {
      // Not by map iteration: a list that reshuffles between two identical reads looks like
      // it changed. The same rule the shelf and the statistics fold apply.
      final list = ShoppingList.of(
        recipes: [
          recipe('a', ['gin', 'campari']),
          recipe('b', ['gin', 'vermouthSweet']),
        ],
        plannedRecipeIds: {'a', 'b'},
        have: nothing,
      );

      expect(list.entries.map((e) => e.ingredientId), [
        'gin',
        'campari',
        'vermouthSweet',
      ]);
    });
  });

  group('nothing to buy is two different readings', () {
    test('nothing planned at all', () {
      final list = ShoppingList.of(
        recipes: [recipe('negroni', ['gin'])],
        plannedRecipeIds: const {},
        have: nothing,
      );

      expect(list.isEmpty, isTrue);
      expect(list.hasPlans, isFalse);
    });

    test('everything planned is already on the shelf', () {
      // **The ambiguity the screen has to resolve, and the reason `hasPlans` exists.** Both
      // situations give an empty list, and a reader checking whether their plan took cannot
      // tell them apart from the list alone.
      final list = ShoppingList.of(
        recipes: [recipe('negroni', ['gin', 'campari'])],
        plannedRecipeIds: {'negroni'},
        have: (_) => true,
      );

      expect(list.isEmpty, isTrue);
      expect(list.hasPlans, isTrue);
      expect(list.plannedRecipes, ['negroni']);
    });
  });

  group('a plan outlives the library it was made against', () {
    test('a planned id the library does not hold is counted, not dropped', () {
      // It happens when a seed changes under a reader's plan. A list that quietly shrank
      // would look like the plan had been forgotten rather than like the library having
      // moved -- and the mark is still in the overlay, so something has to account for it.
      final list = ShoppingList.of(
        recipes: [recipe('negroni', ['gin'])],
        plannedRecipeIds: {'negroni', 'a-recipe-that-left-the-seed'},
        have: nothing,
      );

      expect(list.entries.map((e) => e.ingredientId), ['gin']);
      expect(list.plannedRecipes, ['negroni']);
      expect(list.missingRecipes, ['a-recipe-that-left-the-seed']);
      expect(list.hasPlans, isTrue);
    });

    test('an unresolvable plan alone is still a plan', () {
      final list = ShoppingList.of(
        recipes: const [],
        plannedRecipeIds: {'gone'},
        have: nothing,
      );

      expect(list.isEmpty, isTrue);
      expect(list.hasPlans, isTrue);
      expect(list.missingRecipes, ['gone']);
    });
  });
}
