import 'package:hollow_court/domain/model/glass.dart';
import 'package:hollow_court/domain/model/ice.dart';
import 'package:hollow_court/domain/model/ingredient_category.dart';
import 'package:hollow_court/domain/model/liquid_visual.dart';
import 'package:test/test.dart';

void main() {
  group('glass', () {
    test('reads the eight section 12.1 names, whatever the case', () {
      for (final name in [
        'Cocktail',
        'Coupe',
        'Highball',
        'Lowball',
        'Flute',
        'Shot',
        'Pint',
        'Wine',
        'COCKTAIL',
        ' highball ',
      ]) {
        expect(Glass.fromSource(name), isNotNull, reason: name);
      }
      expect(Glass.fromSource('Cocktail'), Glass.cocktail);
      expect(Glass.fromSource('coupe'), Glass.coupe);
    });

    test('maps the another source names that are the same vessel', () {
      expect(Glass.fromSource('martini'), Glass.cocktail);
      expect(Glass.fromSource('rocks'), Glass.lowball);
      expect(Glass.fromSource('collins'), Glass.highball);
    });

    test('there are exactly eight, and coupe is the newest', () {
      expect(Glass.values, hasLength(8));
      // Appended, not inserted: no existing value's index moves.
      expect(Glass.values[0], Glass.cocktail);
      expect(Glass.values[1], Glass.coupe);
    });

    test('refuses the four that are still not one of the eight', () {
      // Four real glasses remain outside the enum. Mapping them onto the
      // nearest would be a drawing decision taken by a data importer, and the
      // enum would grow until it stopped meaning anything.
      //
      // `coupe` was the fifth until the sources were read properly: leaving it
      // out cost fifteen recipes their glassware, Margarita and Daiquiri among
      // them, and the source dataset is itself named one source.
      for (final name in ['irish', 'snifter', 'mule', 'tropical']) {
        expect(Glass.fromSource(name), isNull, reason: name);
        expect(GlassAliases.unmapped, contains(name));
      }
      expect(GlassAliases.unmapped, hasLength(4));
      expect(GlassAliases.unmapped, isNot(contains('coupe')));
      expect(Glass.fromSource('teacup'), isNull);
      expect(Glass.fromSource(''), isNull);
    });
  });

  group('ice', () {
    test('reads what the source writes', () {
      expect(IceKind.fromSource('none'), IceKind.none);
      expect(IceKind.fromSource('cubes'), IceKind.cubes);
      expect(IceKind.fromSource('crushed'), IceKind.crushed);
      expect(IceKind.fromSource('rock'), IceKind.rock);
    });

    test('an empty field is a gap, not a decision', () {
      // Three of one source's 414 recipes leave it blank. "No ice" is a statement
      // the recipe makes; a blank is the recipe not saying.
      expect(IceKind.fromSource(''), isNull);
      expect(IceKind.fromSource('   '), isNull);
      expect(IceKind.fromSource('none'), isNot(isNull));
    });

    test('tolerates singular and plural', () {
      expect(IceKind.fromSource('cube'), IceKind.cubes);
      expect(IceKind.fromSource('rocks'), IceKind.rock);
    });
  });

  group('liquid colour', () {
    test('all 28 colours round-trip their source spelling', () {
      // sourceName is derived from the enum name by a camel-to-snake
      // conversion, which is exactly the kind of code that is wrong in one
      // place and passes everywhere else.
      //
      // **This test used to assert that a hand-copied list of 24 names was
      // equal to the enum.** Both were wrong in the same way: the list was an
      // incomplete reading of the export, missing `pink`, `purple_light`,
      // `neutral_darkest` and `turquoise` while containing `neutral_dark`,
      // `green_dark`, `purple` and `purple_dark`, which the export never
      // writes. Comparing a hand-copied list against an enum cannot detect that
      // both are wrong -- which is why the assertion is now about the direction
      // that can be checked, and why the real check lives in the one source
      // importer's test against the actual export.
      for (final colour in LiquidColour.values) {
        final name = colour.sourceName;
        expect(LiquidColour.fromSource(name), colour,
            reason: 'round-trip of $name');
      }
      expect(LiquidColour.values, hasLength(28));
    });

    test('the four that the first reading missed are here now', () {
      // Each was producing 18 recipes with no colour at all.
      expect(LiquidColour.fromSource('pink'), LiquidColour.pink);
      expect(LiquidColour.fromSource('purple_light'), LiquidColour.purpleLight);
      expect(LiquidColour.fromSource('neutral_darkest'),
          LiquidColour.neutralDarkest);
      expect(LiquidColour.fromSource('turquoise'), LiquidColour.turquoise);
    });

    test('darkest is a tone, because the source contains one', () {
      expect(LiquidColour.neutralDarkest.tone, Tone.darkest);
      expect(Tone.values, hasLength(5));
    });

    test('an empty secondary colour is null, not a colour', () {
      expect(LiquidColour.fromSource(''), isNull);
    });

    test('family and tone are derived, not the other way round', () {
      expect(LiquidColour.orangeDark.family, 'orange');
      expect(LiquidColour.orangeDark.tone, Tone.dark);
      expect(LiquidColour.red.tone, Tone.base);

      // The grid would also allow orange_lightest. one source never wrote one, so it
      // is not a value here.
      expect(LiquidColour.fromSource('orange_lightest'), isNull);
    });
  });

  group('liquid visual', () {
    test('a sound value has nothing to report', () {
      const visual = LiquidVisual(colour: LiquidColour.orangeDark, opacityPercent: 75);
      expect(visual.validate(), isEmpty);
      expect(visual.hasSecondColour, isFalse);
      expect(visual.toString(), 'orange_dark @75%');
    });

    test('opacity outside 0 to 100 is reported', () {
      const visual = LiquidVisual(colour: LiquidColour.red, opacityPercent: 120);
      expect(visual.validate(), hasLength(1));
      expect(visual.validate().single, contains('120'));
    });

    test('a second opacity without a second colour is reported', () {
      // Nobody can draw this: there is a transparency for a layer that does
      // not exist.
      const visual = LiquidVisual(
        colour: LiquidColour.red,
        opacityPercent: 75,
        opacitySecondary: 25,
      );
      expect(visual.validate().single, contains('no colourSecondary'));
    });

    test('layered with one colour is reported from the other side', () {
      const visual = LiquidVisual(
        colour: LiquidColour.red,
        opacityPercent: 75,
        layered: true,
      );
      expect(visual.validate().single, contains('layered'));
    });

    test('a layered drink with two colours is sound', () {
      const visual = LiquidVisual(
        colour: LiquidColour.red,
        colourSecondary: LiquidColour.yellowLight,
        opacityPercent: 75,
        opacitySecondary: 25,
        layered: true,
      );
      expect(visual.validate(), isEmpty);
      expect(visual.hasSecondColour, isTrue);
    });

    test('every problem is collected, not just the first', () {
      const visual = LiquidVisual(
        colour: LiquidColour.red,
        opacityPercent: 500,
        opacitySecondary: 900,
        layered: true,
      );
      expect(visual.validate().length, greaterThanOrEqualTo(2));
    });
  });

  group('ingredient categories', () {
    test('every name section 4.2 writes resolves', () {
      // Verbatim from the design document, both layers.
      const alcoholic = [
        'Whisk(e)y', 'Gin', 'R(h)um', 'Tequila & Mezcal', 'Vodka & Similar',
        'Brandy', 'Beer & Cider', 'Wine', 'Common Liqueurs', 'Vermouth',
        'Port & Sherry', 'Aperitifs', 'Common Amaro', 'Common Bitters',
      ];
      const nonAlcoholic = [
        'Citrus', 'Juices', 'Fruit & Veg', 'Syrups', 'Jams & Preserves',
        'Herbs & Spices', 'Sodas', 'Pantry Items', 'Grocery Items',
        'Mock Spirits', 'Items You Can Make', 'The Modern Bar',
        'Top 25 Most Used',
      ];

      for (final name in alcoholic) {
        final category = IngredientCategory.fromSource(name);
        expect(category, isNotNull, reason: name);
        expect(category!.isAlcoholic, isTrue, reason: name);
      }
      for (final name in nonAlcoholic) {
        expect(IngredientCategory.fromSource(name), isNotNull, reason: name);
      }
    });

    test('the three browse groupings are not substances', () {
      // The section annotates them as "makeable at home", "preset
      // configurations" and "frequency" -- none of which says what an
      // ingredient is made of.
      for (final grouping in [
        IngredientCategory.itemsYouCanMake,
        IngredientCategory.theModernBar,
        IngredientCategory.top25MostUsed,
      ]) {
        expect(grouping.isBrowseGrouping, isTrue, reason: grouping.name);
        expect(grouping.isSubstance, isFalse, reason: grouping.name);
        expect(grouping.level, Level.grouping);
      }

      expect(IngredientCategory.gin.isSubstance, isTrue);
      expect(IngredientCategory.gin.isBrowseGrouping, isFalse);
    });

    test('an unknown name is refused', () {
      expect(IngredientCategory.fromSource('Vibes'), isNull);
      expect(IngredientCategory.fromSource(''), isNull);
    });

    test('the ampersand expands rather than disappearing', () {
      // "Fruit & Veg" must not become "fruitveg".
      expect(IngredientCategory.fromSource('Fruit & Veg'), IngredientCategory.fruitAndVeg);
      expect(IngredientCategory.fromSource('fruit and veg'), IngredientCategory.fruitAndVeg);
    });
  });

  group('source buckets', () {
    test('reads the six one source uses', () {
      const buckets = [
        'Spirits', 'Liqueurs', 'Mixers & Soft Drinks', 'Fruits & Juices',
        'Beers & Wines', 'Staples',
      ];
      for (final name in buckets) {
        expect(SourceBucket.fromSource(name), isNotNull, reason: name);
      }
    });

    test('carries a level, and the level is all it claims', () {
      expect(SourceBucket.spirits.level, Level.alcoholic);
      expect(SourceBucket.liqueurs.level, Level.alcoholic);
      expect(SourceBucket.beersAndWines.level, Level.alcoholic);
      expect(SourceBucket.staples.level, Level.nonAlcoholic);
    });

    test('is provenance, not a category', () {
      // one source files vermouth under Beers & Wines and Angostura under Mixers &
      // Soft Drinks. Both are defensible and neither is section 4.2, which is
      // why the bucket is kept beside the category rather than mapped onto it.
      expect(SourceBucket.fromSource('Beers & Wines'), SourceBucket.beersAndWines);
      expect(IngredientCategory.fromSource('Beers & Wines'), isNull);
    });
  });
}
