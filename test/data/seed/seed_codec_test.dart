import 'dart:io';

import 'package:hollow_court/data/seed/seed_codec.dart';
import 'package:hollow_court/data/seed/seed_repository.dart';
import 'package:hollow_court/domain/model/flavor.dart';
import 'package:hollow_court/domain/model/glass.dart';
import 'package:hollow_court/domain/model/ice.dart';
import 'package:hollow_court/domain/model/ingredient.dart';
import 'package:hollow_court/domain/model/item_role.dart';
import 'package:hollow_court/domain/model/liquid_visual.dart';
import 'package:hollow_court/domain/model/recipe.dart';
import 'package:hollow_court/domain/units/rational.dart';
import 'package:hollow_court/domain/units/unit_system.dart';
import 'package:test/test.dart';

const artifactPath = 'data/drinks/library.json';

/// A recipe with **every optional field set**, which is what makes the round
/// trip worth testing: a codec that drops one of these is a codec that silently
/// loses a fact.
Recipe fullRecipe() => Recipe(
  id: 'martini00003',
  name: 'Martini',
  subtitle: 'Rye No. 6',
  packId: 'free',
  description: 'The elixir of quietude.',
  origin: 'Travel Finds, Italy, 1919',
  glass: Glass.coupe,
  ice: IceKind.cubes,
  method: Method.stirred,
  methodSteps: const ['Pour into a mixing glass.', 'Strain.'],
  liquid: const LiquidVisual(
    colour: LiquidColour.yellowLight,
    colourSecondary: LiquidColour.orangeDark,
    opacityPercent: 25,
    opacitySecondary: 50,
    layered: true,
  ),
  flavors: const FlavorProfile(
    primary: Flavor.dry,
    secondary: Flavor.herbal,
    tertiary: Flavor.fresh,
  ),
  rating: Rating(value: Rational.of(137, 50), count: 78),
  isSeed: false,
  extras: const {'source': 'imported', 'sourceId': '3'},
  items: [
    RecipeItem(
      ingredientId: 'gin',
      amount: 60000,
      unit: UnitSystem.millilitre,
      role: ItemRole.base,
      originalText: '60 ml Gin',
      note: 'a note',
      substitutes: const ['vodka'],
    ),
    RecipeItem(
      ingredientId: 'mintLeaf',
      amount: 0,
      count: Rational.of(9, 2),
      unit: UnitSystem.leaf,
      role: ItemRole.garnish,
      originalText: '4.5 leaf of mint',
    ),
  ],
);

/// A recipe with **none** of them, so the codec is checked for inventing values
/// as well as for losing them.
Recipe bareRecipe() => const Recipe(
  id: 'water00000',
  name: 'Water',
  items: [
    RecipeItem(ingredientId: 'water', amount: 200000),
  ],
);

Recipe roundTrip(Recipe recipe) {
  final encoded = SeedCodec.encode(ingredients: const [], recipes: [recipe]);
  return SeedCodec.decode(encoded).recipes.single;
}

void main() {
  group('the document', () {
    test('names its format and version on the first two fields', () {
      // Section 4.4's lesson from the rhythm game beatmap format: a format that states
      // which format it is survives its own evolution, because the reader
      // branches on the statement rather than guessing from what it finds.
      final encoded = SeedCodec.encode(ingredients: const [], recipes: const []);
      expect(encoded, startsWith('{"format":"hollow-court-library","version":1,'));
    });

    test('refuses a document that is not a seed', () {
      expect(
        () => SeedCodec.decode('{"hello":"world"}'),
        throwsA(isA<SeedFormatException>()),
      );
    });

    test('refuses something that is not JSON at all', () {
      expect(
        () => SeedCodec.decode('not json'),
        throwsA(isA<SeedFormatException>()),
      );
    });

    test('refuses a seed from a newer version, and says which', () {
      final encoded = SeedCodec.encode(ingredients: const [], recipes: const [])
          .replaceFirst('"version":1', '"version":99');
      expect(
        () => SeedCodec.decode(encoded),
        throwsA(
          isA<SeedFormatException>().having(
            (e) => e.reason,
            'reason',
            allOf(contains('99'), contains('reads up to 1')),
          ),
        ),
      );
    });
  });

  group('a recipe round trip', () {
    test('keeps every field that was set', () {
      final before = fullRecipe();
      final after = roundTrip(before);

      expect(after.id, before.id);
      expect(after.name, before.name);
      expect(after.subtitle, before.subtitle);
      expect(after.packId, before.packId);
      expect(after.description, before.description);
      expect(after.origin, before.origin);
      expect(after.glass, Glass.coupe);
      expect(after.ice, IceKind.cubes);
      expect(after.method, Method.stirred);
      expect(after.methodSteps, before.methodSteps);
      expect(after.isSeed, isFalse);
      expect(after.extras, before.extras);
      expect(after.liquid!.colour, LiquidColour.yellowLight);
      expect(after.liquid!.colourSecondary, LiquidColour.orangeDark);
      expect(after.liquid!.opacityPercent, 25);
      expect(after.liquid!.opacitySecondary, 50);
      expect(after.liquid!.layered, isTrue);
      expect(after.flavors.primary, Flavor.dry);
      expect(after.flavors.secondary, Flavor.herbal);
      expect(after.flavors.tertiary, Flavor.fresh);
      expect(after.rating!.count, 78);
      expect(after.items, hasLength(2));

      // The first item carries everything an item can carry.
      final gin = after.items.first;
      expect(gin.ingredientId, 'gin');
      expect(gin.amount, 60000);
      expect(gin.unit?.id, 'ml');
      expect(gin.role, ItemRole.base);
      expect(gin.originalText, '60 ml Gin');
      expect(gin.note, 'a note');
      expect(gin.substitutes, ['vodka']);
      expect(gin.count, isNull);

      // The second is a counted one, where the number is a fraction.
      final mint = after.items.last;
      expect(mint.amount, 0);
      expect(mint.count, Rational.of(9, 2));
      expect(mint.unit?.id, 'leaf');
      expect(mint.role, ItemRole.garnish);
    });

    test('and produces a recipe as valid as the one that went in', () {
      expect(roundTrip(fullRecipe()).validate(), isEmpty);
      expect(roundTrip(bareRecipe()).validate(), isEmpty);
    });

    test('invents nothing when a field was absent', () {
      final after = roundTrip(bareRecipe());
      expect(after.subtitle, isNull);
      expect(after.packId, isNull);
      expect(after.description, isNull);
      expect(after.origin, isNull);
      expect(after.glass, isNull);
      expect(after.ice, isNull);
      expect(after.method, isNull);
      expect(after.liquid, isNull);
      expect(after.rating, isNull);
      expect(after.methodSteps, isEmpty);
      expect(after.flavors.isEmpty, isTrue);
      expect(after.isSeed, isTrue, reason: 'the default, and it was not set');
      expect(after.items.single.role, ItemRole.base);
      expect(after.items.single.unit, isNull);
      expect(after.items.single.count, isNull);
    });
  });

  group('numbers', () {
    test('a fraction survives exactly, because a float would not', () {
      // Rational.toString gives `9/2` and Rational.parse reads only decimals,
      // so the codec cannot use that pair -- 4.5 written as "4.5" and read
      // through a double is not 4.5.
      final item = RecipeItem(
        ingredientId: 'x',
        amount: 0,
        count: Rational.of(9, 2),
      );
      final encoded = SeedCodec.encode(
        ingredients: const [],
        recipes: [
          Recipe(id: 'x00000', name: 'X', items: [item]),
        ],
      );
      expect(encoded, contains('"count":"9/2"'));

      final after = SeedCodec.decode(encoded).recipes.single.items.single;
      expect(after.count, Rational.of(9, 2));
      expect(after.count!.toString(), '9/2');
    });

    test('an integer is written as an integer, not as a fraction', () {
      const ingredient = Ingredient(id: 'gin', name: 'Gin');
      final encoded = SeedCodec.encode(
        ingredients: [ingredient],
        recipes: [
          Recipe(
            id: 'x00000',
            name: 'X',
            rating: Rating(value: Rational.fromInt(5), count: 3),
            items: const [RecipeItem(ingredientId: 'gin', amount: 30000)],
          ),
        ],
      );
      expect(encoded, contains('"value":"5"'));
      expect(encoded, isNot(contains('"5/1"')));
    });
  });

  group('enum values', () {
    Recipe withGlass(String glassName) {
      final encoded = SeedCodec.encode(
        ingredients: const [],
        recipes: [bareRecipe()],
      );
      return SeedCodec.decode(
        encoded.replaceFirst(
          '"id":"water00000"',
          '"id":"water00000","glass":"$glassName"',
        ),
      ).recipes.single;
    }

    test('an absent value is null, which is a fact the entity allows', () {
      expect(roundTrip(bareRecipe()).glass, isNull);
    });

    test('a value this build cannot read stops the load and says what it saw',
        () {
      // Reading it as null would turn "a glass this build cannot draw" into "no
      // glass", which is a lie the caller cannot detect.
      expect(
        () => withGlass('teacup'),
        throwsA(
          isA<SeedFormatException>().having(
            (e) => e.reason,
            'reason',
            contains('teacup'),
          ),
        ),
      );
    });
  });

  group('an ingredient round trip', () {
    test('keeps the numbers and the provenance', () {
      final ingredient = Ingredient(
        id: 'gin',
        name: 'Gin',
        aliases: const ['gin, Plymouth', 'Plymouth gin'],
        abvPercent: Rational.of(47, 1),
        sugarGPerL: Rational.zero,
        densityGPerMl: Rational.of(94, 100),
        defaultUnit: UnitSystem.millilitre,
        bottleSizesMillilitres: const [700, 750, 1000],
        isCommon: true,
        note: 'a note',
        extras: const {'source': 'legacy'},
      );
      final encoded =
          SeedCodec.encode(ingredients: [ingredient], recipes: const []);
      final after = SeedCodec.decode(encoded).ingredients.single;

      expect(after.id, 'gin');
      expect(after.name, 'Gin');
      expect(after.aliases, ingredient.aliases);
      expect(after.abvPercent, Rational.of(47, 1));
      expect(after.sugarGPerL, Rational.zero);
      expect(after.densityGPerMl, Rational.of(94, 100));
      expect(after.defaultUnit?.id, 'ml');
      expect(after.bottleSizesMillilitres, [700, 750, 1000]);
      expect(after.isCommon, isTrue);
      expect(after.note, 'a note');
      expect(after.extras, {'source': 'legacy'});
      expect(after.validate(), isEmpty);
    });
  });

  group('the repository', () {
    test('looks ingredients and recipes up by id', () {
      final repository = SeedRepository.of(
        ingredients: const [Ingredient(id: 'gin', name: 'Gin')],
        recipes: [fullRecipe()],
      );
      expect(repository.ingredientById('gin')?.name, 'Gin');
      expect(repository.ingredientById('vodka'), isNull);
      expect(repository.recipeById('martini00003')?.name, 'Martini');
      expect(repository.recipeById('nope'), isNull);
    });

    test('answers what a bottle can be used for', () {
      // The question a shelf asks: I have just entered this, what is it for?
      final repository = SeedRepository.of(
        ingredients: const [
          Ingredient(id: 'gin', name: 'Gin'),
          Ingredient(id: 'mintLeaf', name: 'Mint'),
        ],
        recipes: [fullRecipe(), bareRecipe()],
      );
      final mint = repository.recipesUsing('mintLeaf');
      expect(mint, hasLength(1));
      expect(mint.single.id, 'martini00003');
      expect(repository.recipesUsing('gin'), hasLength(1));
      expect(repository.recipesUsing('vodka'), isEmpty);
    });

    test('recomputes problems at load rather than storing them', () {
      // A seed carrying its own problem list would have problems that go stale
      // the moment either the data or the validator changes.
      final repository = SeedRepository.of(
        ingredients: const [],
        recipes: [
          const Recipe(id: 'bad', name: 'Bad', items: []),
        ],
      );
      final problems = repository.validate();
      expect(problems, hasLength(1));
      expect(problems.single.kind, 'recipe');
      expect(problems.single.id, 'bad');
      expect(problems.single.problems.join(' '), contains('five digits'));
    });

    test('reports an ingredient a recipe points at but the seed lacks', () {
      final repository = SeedRepository.of(
        ingredients: const [],
        recipes: [bareRecipe()],
      );
      expect(repository.danglingIngredientIds, ['water']);
    });

    test('round-trips through a repository unchanged', () {
      final before = SeedRepository.of(
        ingredients: const [Ingredient(id: 'gin', name: 'Gin')],
        recipes: [fullRecipe(), bareRecipe()],
      );
      final after = SeedRepository.fromJson(before.toJson());
      expect(after.recipes, hasLength(2));
      expect(after.ingredients, hasLength(1));
      expect(after.recipeById('martini00003')!.liquid!.layered, isTrue);
      expect(after.recipeById('water00000')!.glass, isNull);
      expect(after.validate(), isEmpty);
    });
  });

  group('the library the application ships', () {
    // **These replace the tests of the harvested artifact, which no longer exists.** On 2026-09-22 the owner
    // had the another source and one source data deleted -- their names and measures were each author's own -- so the
    // assertions about 502 recipes, three known problems and 71 name collisions became assertions about a
    // file nobody ships. What replaces them is about *our* list, and one of them is the invariant the next
    // piece of work depends on.
    SeedRepository? open() {
      if (!File(artifactPath).existsSync()) {
        markTestSkipped('data/drinks/library.json is absent; it is tracked, so this means the checkout is partial');
        return null;
      }
      return SeedRepository.fromJson(File(artifactPath).readAsStringSync());
    }

    test('is tracked, so a clone has it and this never skips by accident', () {
      expect(File(artifactPath).existsSync(), isTrue);
    });

    test('**every ingredient a drink names actually exists**', () {
      // The property a hand-written list can lose and a harvested one cannot: nothing generates these ids,
      // so a typo would be a drink with an ingredient that is not in the vocabulary.
      final repository = open();
      if (repository == null) return;
      // **A floor, not an exact count.** The vocabulary and the drink list both grow by writing -- that is
      // how this library is built, one tranche at a time -- so pinning the numbers would make every tranche
      // a test failure to be edited, which teaches people to edit tests. The exact figures belong in the
      // data file's own `counts`, which is generated rather than asserted.
      expect(repository.ingredients.length, greaterThanOrEqualTo(164));
      expect(repository.recipes.length, greaterThanOrEqualTo(24));
      expect(
        repository.danglingIngredientIds,
        isEmpty,
        reason: 'a drink references an ingredient id the vocabulary does not hold',
      );
    });

    test('**every stated default unit is one this build can measure with**', () {
      // The invariant the unit recognition will stand on: an ingredient that says it is measured in a unit
      // the catalogue does not carry would be a default that cannot be applied. Checked here, at the data,
      // rather than at the screen where it would show up as a blank menu.
      final repository = open();
      if (repository == null) return;
      // `UnitSystem.all` is the domain's own list of every unit it knows, which is the right authority for
      // "can this default be applied": a unit the system does not carry cannot be measured in.
      final known = {for (final unit in UnitSystem.all) unit.id};
      for (final ingredient in repository.ingredients) {
        final unit = ingredient.defaultUnit;
        if (unit == null) continue;
        expect(known, contains(unit.id), reason: '${ingredient.id} states ${unit.id}');
      }
    });

    test('every drink is a drink: a name, a glass, a method, and something to pour', () {
      final repository = open();
      if (repository == null) return;
      for (final drink in repository.recipes) {
        expect(drink.name, isNotEmpty, reason: drink.id);
        expect(drink.glass, isNotNull, reason: drink.id);
        expect(drink.method, isNotNull, reason: drink.id);
        expect(
          drink.items.where((item) => item.role != ItemRole.garnish),
          isNotEmpty,
          reason: '${drink.id} is only a garnish',
        );
      }
    });

    test('and a drink loaded from the file is usable, not merely present', () {
      final repository = open();
      if (repository == null) return;
      final boulevardier = repository.recipeById('ibaBoulevardier')!;
      expect(boulevardier.name, 'Boulevardier');
      expect(boulevardier.glass, Glass.cocktail);
      expect(boulevardier.method, Method.stirred);
      // 45 + 30 + 30 millilitres, with the garnish contributing nothing to the volume.
      expect(boulevardier.undilutedMicrolitres, 105000);
    });

    test('the reverse index answers the question a shelf asks', () {
      final repository = open();
      if (repository == null) return;
      final withCampari = repository.recipesUsing('campari');
      expect(withCampari.map((r) => r.name).toSet(), containsAll({'Americano', 'Boulevardier'}));
      expect(repository.recipesUsing('noSuchIngredient'), isEmpty);
    });

    test('no two drinks share a canonical name, which is the point of the list', () {
      final repository = open();
      if (repository == null) return;
      // The harvested library had **71 drinks named in both sources and 70 of those pairs were different
      // formulas** -- which is why it could not be deduplicated and why it could not ship. Our list is one
      // canonical drink per name by construction, and this is that assertion.
      expect(repository.nameCollisions(), isEmpty);
    });
  });
}
