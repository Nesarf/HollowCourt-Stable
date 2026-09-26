import 'package:hollow_court/domain/model/flavor.dart';
import 'package:hollow_court/domain/model/glass.dart';
import 'package:hollow_court/domain/model/ice.dart';
import 'package:hollow_court/domain/model/ingredient.dart';
import 'package:hollow_court/domain/model/ingredient_category.dart';
import 'package:hollow_court/domain/model/item_role.dart';
import 'package:hollow_court/domain/model/liquid_visual.dart';
import 'package:hollow_court/domain/model/recipe.dart';
import 'package:hollow_court/domain/units/rational.dart';
import 'package:hollow_court/domain/units/unit_system.dart';
import 'package:test/test.dart';

RecipeItem item(String ingredientId, {int amount = 30000, ItemRole? role}) =>
    RecipeItem(
      ingredientId: ingredientId,
      amount: amount,
      role: role ?? ItemRole.base,
    );

Recipe recipe({
  String id = 'dry_manhattan00001',
  String name = 'Manhattan, Dry',
  List<RecipeItem>? items,
}) => Recipe(
  id: id,
  name: name,
  glass: Glass.cocktail,
  ice: IceKind.none,
  method: Method.stirred,
  liquid: const LiquidVisual(colour: LiquidColour.orangeDark, opacityPercent: 75),
  items: items ?? [item('ryeWhiskey'), item('vermouthDry', role: ItemRole.modifier)],
);

void main() {
  group('flavours', () {
    test('the union covers both sources', () {
      // one source's 21 spellings.
      const coupe = [
        'Sweet', 'Bubbly', 'Dry', 'Bitter', 'Citrussy', 'Sour', 'Fresh',
        'Creamy', 'Smokey', 'Savoury', 'Herbal', 'Woody', 'Spicy', 'Smooth',
        'Floral', 'Nutty', 'Crisp', 'Roasted', 'Earthy', 'Salty', 'Grassy',
      ];
      // another source's palette, which is exactly its eleven keys.
      const mixel = [
        'Bitter', 'Creamy', 'Dry', 'Fresh', 'Herbal', 'Hot', 'Savory',
        'Spicy', 'Strong', 'Sweet', 'Tart',
      ];

      for (final name in [...coupe, ...mixel]) {
        expect(Flavor.fromSource(name), isNotNull, reason: name);
      }
    });

    test('Savoury and Savory are one flavour, not two', () {
      // Two values would have split one taste across two buckets, and every
      // count over flavours would then have been quietly wrong.
      expect(Flavor.fromSource('Savoury'), Flavor.savoury);
      expect(Flavor.fromSource('Savory'), Flavor.savoury);
      expect(Flavor.values.where((f) => f.name.startsWith('sav')), hasLength(1));
    });

    test('the vocabulary is taste plus strength and heat, all kept', () {
      // another source's palette includes Strong and Hot, which are not tastes. They
      // stay: dropping two of the source's eleven values would misreport it.
      expect(Flavor.fromSource('Strong'), Flavor.strong);
      expect(Flavor.fromSource('Hot'), Flavor.hot);
    });

    test('an unknown flavour is refused', () {
      expect(Flavor.fromSource('Umami'), isNull);
      expect(Flavor.fromSource(''), isNull);
    });
  });

  group('flavour profile', () {
    test('a partial profile is sound', () {
      expect(const FlavorProfile(primary: Flavor.sweet).validate(), isEmpty);
      expect(
        const FlavorProfile(primary: Flavor.sweet, secondary: Flavor.sour).validate(),
        isEmpty,
      );
    });

    test('a hole in the list is reported', () {
      // A tertiary with no secondary renders as a gap on any screen that shows
      // the three levels in order.
      final problems = const FlavorProfile(
        primary: Flavor.sweet,
        tertiary: Flavor.herbal,
      ).validate();
      expect(problems.single, contains('no secondary'));
    });

    test('a repeated flavour is reported', () {
      final problems = const FlavorProfile(
        primary: Flavor.sweet,
        secondary: Flavor.sweet,
      ).validate();
      expect(problems.single, contains('twice'));
    });
  });

  group('ingredient', () {
    test('a sound ingredient has nothing to report', () {
      final gin = Ingredient(
        id: 'ginPlymouth',
        name: 'Plymouth Gin',
        category: IngredientCategory.gin,
        abvPercent: Rational.of(415, 10),
        densityGPerMl: Rational.of(94, 100),
        defaultUnit: UnitSystem.millilitre,
        bottleSizesMillilitres: [700, 1000],
      );
      expect(gin.validate(), isEmpty);
    });

    test('category may be absent, which is not the same as wrong', () {
      // Not one of the 139 another source entries carries a category.
      final uncategorised = const Ingredient(id: 'barSugar', name: 'bar sugar');
      expect(uncategorised.category, isNull);
      expect(uncategorised.validate(), isEmpty);
    });

    test('the id has to be the prefix scheme section 4.1 describes', () {
      expect(const Ingredient(id: '', name: 'x').validate().single, contains('empty'));
      expect(
        const Ingredient(id: 'Gin-Plymouth', name: 'x').validate().single,
        contains('lowerCamelCase'),
      );
      expect(const Ingredient(id: 'ginPlymouth', name: 'x').validate(), isEmpty);
    });

    test('an alcohol figure outside 0 to 100 is reported', () {
      expect(
        Ingredient(id: 'x', name: 'x', abvPercent: Rational.fromInt(140)).validate().single,
        contains('140'),
      );
    });

    test('a density of zero is reported, because it cannot be divided by', () {
      expect(
        Ingredient(id: 'x', name: 'x', densityGPerMl: Rational.zero).validate().single,
        contains('positive density'),
      );
    });

    test('the provenance bucket is carried beside the category', () {
      const ingredient = Ingredient(
        id: 'vermouthDry',
        name: 'Vermouth (Dry)',
        sourceBucket: SourceBucket.beersAndWines,
      );
      expect(ingredient.sourceBucket, SourceBucket.beersAndWines);
      expect(ingredient.category, isNull);
    });
  });

  group('rating', () {
    test('the count is kept because it changes what the number means', () {
      final wellKnown = Rating(value: Rational.of(41, 10), count: 489);
      final barely = Rating(value: Rational.of(41, 10), count: 3);

      expect(wellKnown.validate(), isEmpty);
      expect(wellKnown.value, barely.value);
      expect(wellKnown.count, isNot(barely.count));
    });

    test('a source with no count leaves it null rather than zero', () {
      expect(Rating(value: Rational.one).count, isNull);
    });

    test('out of range is reported', () {
      expect(Rating(value: Rational.fromInt(7)).validate(), hasLength(1));
      expect(Rating(value: Rational.fromInt(-1)).validate(), hasLength(1));
    });
  });

  group('recipe', () {
    test('a sound recipe has nothing to report', () {
      expect(recipe().validate(), isEmpty);
      expect(recipe().undilutedMicrolitres, 60000);
    });

    test('the id must be a slug and five digits', () {
      // Neither source supplies one: one source numbers 0..413 and another source uses a URL
      // path, so the importer mints these and the format is checked.
      expect(recipe(id: '42').validate().first, contains('five digits'));
      expect(recipe(id: 'dry_manhattan').validate().first, contains('five digits'));
      expect(recipe(id: 'dry_manhattan00042').validate(), isEmpty);
      expect(recipe(id: 'Dry-Manhattan00042').validate().first, contains('five digits'));
    });

    test('a recipe with no items cannot be mixed', () {
      expect(recipe(items: []).validate().first, contains('no items'));
    });

    test('a duplicated line is reported, but a base and a garnish are not', () {
      // The same ingredient twice with the same role is a line somebody
      // pasted twice. The same ingredient as a base and then as a garnish is
      // a real drink.
      final duplicated = recipe(
        items: [item('gin'), item('gin')],
      );
      expect(duplicated.validate().any((p) => p.contains('twice')), isTrue);

      final twoRoles = recipe(
        items: [item('gin'), item('gin', role: ItemRole.garnish)],
      );
      expect(twoRoles.validate(), isEmpty);
    });

    test('problems from the parts are collected, not just the first', () {
      final broken = Recipe(
        id: 'bad',
        name: '',
        glass: Glass.cocktail,
        ice: IceKind.none,
        method: Method.stirred,
        liquid: const LiquidVisual(colour: LiquidColour.red, opacityPercent: 500),
        items: [item('')],
        flavors: const FlavorProfile(secondary: Flavor.sweet),
        rating: Rating(value: Rational.fromInt(9)),
      );

      final problems = broken.validate();
      expect(problems.length, greaterThanOrEqualTo(5));
      expect(problems.any((p) => p.contains('five digits')), isTrue);
      expect(problems.any((p) => p.contains('name is empty')), isTrue);
      expect(problems.any((p) => p.contains('liquid')), isTrue);
      expect(problems.any((p) => p.contains('flavours')), isTrue);
      expect(problems.any((p) => p.contains('rating')), isTrue);
    });

    test('a rinse measures nothing and is still an item', () {
      // Zero is an amount. A *missing* amount is a different thing, and a line
      // like "some sugar" cannot be deducted from a bottle, so it does not
      // become an item at all.
      final rinsed = recipe(
        items: [item('gin'), item('absinthe', amount: 0, role: ItemRole.optional)],
      );
      expect(rinsed.validate(), isEmpty);
      expect(rinsed.undilutedMicrolitres, 30000);
    });

    test('seed and user recipes are the same shape', () {
      expect(recipe().isSeed, isTrue);
      expect(
        Recipe(
          id: 'mine00001',
          name: 'Mine',
          glass: Glass.lowball,
          ice: IceKind.cubes,
          method: Method.built,
          liquid: const LiquidVisual(colour: LiquidColour.brown, opacityPercent: 100),
          items: [item('ryeWhiskey')],
          isSeed: false,
        ).validate(),
        isEmpty,
      );
    });
  });
}
