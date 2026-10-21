import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// **A finished thing may be an ingredient, and it has to arrive with its method attached.**
///
/// The owner's instruction: rather than writing `espressoCoffee` into an item list and leaving the reader to wonder
/// where it came from, the ingredient carries `extras.madeBy` pointing at the recipe that makes it. The interface
/// opens that: a row with a link grows a small tree button, and what opens is the base's own method.
///
/// **The failure this guards is a pointer with nothing behind it**, which would be a row whose button does nothing
/// -- worse than no button, because the reader learns the interface is unreliable rather than that the data is
/// missing.
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

  Map<String, Object?>? extrasOf(Map<String, Object?> row) =>
      (row['extras'] as Map?)?.cast<String, Object?>();

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
    };
    for (final entry in expected.entries) {
      expect(
        linked[entry.key],
        entry.value,
        reason: '${entry.key} is the finished thing the tree exists for',
      );
    }
  });

  test('**a base is a recipe with a method, and it never names itself**', () {
    final bases = recipes().where((row) => extrasOf(row)?['category'] == 'Base').toList();
    expect(bases, hasLength(7));

    for (final base in bases) {
      final steps = (base['methodSteps']! as List).cast<String>();
      expect(steps, isNotEmpty, reason: '${base['id']} opens from a row, so it has to say something');

      for (final item in (base['items']! as List).cast<Map<String, Object?>>()) {
        expect(
          item['ingredientId'],
          isNot(base['id']),
          reason: '${base['id']} names itself, which is a tree with no bottom',
        );
        // **And the tree stops after one level in the data it ships**, which is what lets the interface bound the
        // depth instead of trusting the data not to loop.
        final ingredient = ingredients().firstWhere(
          (row) => row['id'] == item['ingredientId'],
          orElse: () => <String, Object?>{},
        );
        if (ingredient.isEmpty) continue;
        final madeBy = extrasOf(ingredient)?['madeBy'];
        if (madeBy is String) {
          final target = bases.firstWhere(
            (row) => row['id'] == madeBy,
            orElse: () => <String, Object?>{},
          );
          expect(
            target,
            isEmpty,
            reason: '${base['id']} uses ${item['ingredientId']}, which is itself a base: the shipped tree is '
                'meant to be one level deep',
          );
        }
      }
    }
  });
}
