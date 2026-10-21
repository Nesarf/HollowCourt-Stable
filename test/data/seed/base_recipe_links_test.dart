import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// **A finished thing may be an ingredient, and it has to arrive with its method attached.**
///
/// The owner's instruction: rather than writing `espressoCoffee` into an item list and leaving the reader to wonder
/// where it came from, the ingredient carries `extras.madeBy` pointing at the recipe that makes it. The interface
/// opens that: a row with a link grows a small tree button, and what opens is the base's own method.
///
/// **Two failures are worth guarding here.** A pointer with nothing behind it is a button that does nothing -- worse
/// than no button, because the reader learns the interface is unreliable rather than that the data is missing. And a
/// loop is a sheet that opens for ever, which is why the interface carries a visited set and this file proves the
/// shipped data needs it: the tree is two levels deep today, not one.
void main() {
  late Map<String, Object?> library;

  setUpAll(() {
    final file = File('data/drinks/library.json');
    expect(file.existsSync(), isTrue, reason: 'run this from the repository root');
    library = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  });

  List<Map<String, Object?>> recipes() => (library['recipes']! as List).cast<Map<String, Object?>>();
  List<Map<String, Object?>> ingredients() =>
      (library['ingredients']! as List).cast<Map<String, Object?>>();

  Map<String, Object?>? extrasOf(Map<String, Object?>? row) =>
      (row?['extras'] as Map?)?.cast<String, Object?>();

  test('**every finished ingredient that points at a recipe points at one that exists**', () {
    final ids = {for (final recipe in recipes()) recipe['id']! as String};
    final dangling = <String>[];
    final linked = <String, String>{};

    for (final ingredient in ingredients()) {
      final madeBy = extrasOf(ingredient)?['madeBy'];
      if (madeBy is! String) continue;
      linked[ingredient['id']! as String] = madeBy;
      if (!ids.contains(madeBy)) dangling.add('${ingredient['id']} -> $madeBy');
    }

    expect(dangling, isEmpty, reason: 'a sub-recipe pointer with no recipe behind it: $dangling');

    const expected = <String, String>{
      'espressoCoffee': 'baseEspresso',
      'filterCoffee': 'baseFilterBrew',
      'mokaCoffee': 'baseMokaBrew',
      'coldBrewCoffee': 'baseColdBrew',
      'whippedCream': 'baseWhippedCream',
      'lemonSorbet': 'baseLemonSorbet',
      'iceCream': 'baseIceCream',
      'coffeeIceCream': 'baseCoffeeIceCream',
    };
    for (final entry in expected.entries) {
      expect(
        linked[entry.key],
        entry.value,
        reason: '${entry.key} is a finished thing the tree exists for',
      );
    }
  });

  test('**the tree has no loop, and nothing is deeper than three**', () {
    final byIngredient = {for (final row in ingredients()) row['id']! as String: row};
    final byRecipe = {for (final row in recipes()) row['id']! as String: row};

    String? madeByOf(String ingredientId) {
      final madeBy = extrasOf(byIngredient[ingredientId])?['madeBy'];
      return madeBy is String ? madeBy : null;
    }

    /// How many base recipes sit below this one. A loop fails here rather than hanging the test.
    int depthOf(String recipeId, Set<String> open) {
      expect(open.contains(recipeId), isFalse, reason: 'a loop goes through $recipeId');
      final next = {...open, recipeId};
      var deepest = 0;
      for (final item in (byRecipe[recipeId]!['items']! as List).cast<Map<String, Object?>>()) {
        final base = madeByOf(item['ingredientId']! as String);
        if (base == null) continue;
        final below = 1 + depthOf(base, next);
        if (below > deepest) deepest = below;
      }
      return deepest;
    }

    for (final recipe in recipes()) {
      final depth = depthOf(recipe['id']! as String, <String>{});
      expect(
        depth,
        lessThanOrEqualTo(3),
        reason: '${recipe['id']} opens more than three sheets; the interface stops at three',
      );
    }

    // **The reason the visited set is not decoration.** Affogato names coffee ice cream, which is made by a base,
    // and that base names ice cream, which is made by another base. Two hops of data, three sheets of interface.
    expect(depthOf('houseAffogato', <String>{}), 2);
    expect(depthOf('houseLatte', <String>{}), 1);
  });

  test('**a base is a recipe with a method, and it never names itself**', () {
    final bases = recipes().where((row) => extrasOf(row)?['category'] == 'Base').toList();
    expect(bases, hasLength(8));

    for (final base in bases) {
      final steps = (base['methodSteps']! as List).cast<String>();
      expect(steps, isNotEmpty, reason: '${base['id']} opens from a row, so it has to say something');
      for (final item in (base['items']! as List).cast<Map<String, Object?>>()) {
        expect(
          item['ingredientId'],
          isNot(base['id']),
          reason: '${base['id']} names itself, which is a tree with no bottom',
        );
      }
    }
  });

  test('**a finished thing is an ordinary ingredient, not a special case for bases**', () {
    // The owner's rule, stated as a test: any finished thing may be the ingredient of another finished thing. If
    // only the bases ever named a finished thing, the tree would be a feature for bases rather than a property of
    // the model, and this is the assertion that keeps it the second one.
    final finished = {
      for (final ingredient in ingredients())
        if (extrasOf(ingredient)?['madeBy'] != null) ingredient['id']! as String,
    };
    expect(finished, hasLength(8));

    final users = <String>{};
    for (final recipe in recipes()) {
      for (final item in (recipe['items']! as List).cast<Map<String, Object?>>()) {
        if (finished.contains(item['ingredientId'])) users.add(recipe['id']! as String);
      }
    }

    expect(
      users.length,
      greaterThanOrEqualTo(12),
      reason: 'only ${users.length} recipes name a finished thing, which reads like a special case',
    );
    expect(users, contains('houseLatte'), reason: 'a drink naming a finished thing');
    expect(users, contains('houseIceCreamSoda'), reason: 'two finished things in one drink');
    expect(users, contains('baseCoffeeIceCream'), reason: 'one finished thing naming another');
  });
}
