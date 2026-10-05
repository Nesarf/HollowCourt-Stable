import 'dart:convert';
import 'dart:io';

import 'package:hollow_court/domain/model/glass.dart';
import 'package:hollow_court/domain/model/ice.dart';
import 'package:hollow_court/domain/model/ingredient_category.dart';
import 'package:hollow_court/domain/model/liquid_visual.dart';
import 'package:test/test.dart';

const artifactPath = 'data/drinks/library.json';

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
    // **The split, asserted.** Until 2026-10-01 this enum carried thirty-three members: twenty-seven *substances*
    // (whiskey, gin, citrus, syrups...) and three *browse groupings*. The substances were retired to
    // `Ingredient.kind`/`family` -- `docs/ingredient-gap.md` measured why, and `docs/proposal-recipes-and-packs.md`
    // §3 asked for the shape -- and what is left is the three groupings, whose names are not a spelling of any
    // substance.
    test('**the enum is the three groupings and nothing else**', () {
      expect(IngredientCategory.values, hasLength(3));
      expect(
        IngredientCategory.values.map((c) => c.name).toSet(),
        {'itemsYouCanMake', 'theModernBar', 'top25MostUsed'},
      );
      // Every remaining member is a way of finding an ingredient, so the question "is this a substance" has one
      // answer and a caller no longer has to remember to filter.
      for (final grouping in IngredientCategory.values) {
        expect(grouping.isBrowseGrouping, isTrue, reason: grouping.name);
      }
    });

    test('**every name section 4.2 writes is either held or on the list of what is not**', () {
      // **The honest version of this test, and the first one was not.** It asserted that every shape section 4.2
      // names had at least one ingredient classified as it -- and `Mock Spirits` does not, and never did: no
      // ingredient in the library is one, and the older test had quietly left that name out of its list rather
      // than admitting it. **A test that drops the name it cannot satisfy reports coverage it does not have.**
      //
      // So both sets are written down: what the library holds, and what the section names that it does not. The
      // second is not a failure -- it is step 3 of `docs/ingredient-gap.md`, and recording it here means the next
      // person is handed the list rather than rediscovering it.
      const held = {
        'Whisk(e)y': 'whiskey', 'Gin': 'gin', 'R(h)um': 'rum', 'Tequila & Mezcal': 'agave',
        'Vodka & Similar': 'vodka', 'Brandy': 'brandy', 'Vermouth': 'vermouth',
        'Port & Sherry': 'fortified', 'Aperitifs': 'aperitif', 'Common Amaro': 'amaro',
        'Citrus': 'citrus', 'Jams & Preserves': 'preserve', 'Herbs & Spices': 'herb',
      };

      // Named, with the reason -- and **the eleven are the shape of step 3**.
      const notYetHeld = {
        'Beer & Cider': 'held as the kind `beer`; the family is not used',
        'Wine': 'held as the kind `wine`',
        'Common Liqueurs': 'held as the kind `liqueur`',
        'Common Bitters': 'held as the kind `bitter`',
        'Juices': 'held as the kind `juice`',
        'Fruit & Veg': 'held as the kind `fruit`',
        'Syrups': 'held as the kind `syrup`',
        'Sodas': 'held as the kind `mixer`',
        'Pantry Items': 'held as the kind `pantry`',
        'Grocery Items': 'held as the kind `pantry`',
        'Mock Spirits': '**no ingredient in the library is one, and never was**',
      };

      final file = File(artifactPath);
      if (!file.existsSync()) {
        markTestSkipped('$artifactPath is absent; it is tracked, so this means the checkout is partial');
        return;
      }
      final decoded = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      final rows = [
        for (final raw in decoded['ingredients']! as List<Object?>) (raw! as Map<String, Object?>),
      ];
      final families = {for (final r in rows) r['family'] as String?};
      final kinds = {for (final r in rows) r['kind'] as String?};

      for (final entry in held.entries) {
        final needle = entry.value;
        expect(
          kinds.contains(needle) || families.contains(needle),
          isTrue,
          reason: 'section 4.2 names "${entry.key}" and nothing in the library is classified `$needle`',
        );
      }

      // The ones answered by a kind directly rather than a family.
      for (final kind in ['beer', 'wine', 'liqueur', 'bitter', 'juice', 'spice', 'mixer', 'pantry', 'syrup']) {
        expect(kinds, contains(kind), reason: 'nothing in the library has kind `$kind`');
      }

      // **The two sets together are the whole section**, so a name cannot be moved out of `held` without being put
      // into `notYetHeld` -- which is the discipline the older test did not have.
      expect(
        {...held.keys, ...notYetHeld.keys},
        hasLength(24),
        reason: 'section 4.2 names 24 shapes; every one is either held or explicitly not',
      );
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

    test('**is provenance, and cannot be a browse grouping**', () {
      // one source files vermouth under `Beers & Wines` and Angostura under `Mixers & Soft Drinks`. Both are
      // defensible and neither is section 4.2 -- which is why the bucket is kept as provenance rather than mapped
      // onto anything.
      //
      // **The second assertion used to read `IngredientCategory.fromSource('Beers & Wines')` is null**, which it
      // was: the old enum had a `beersAndWines` member that `fromSource` declined to match, and the test was
      // really saying "a bucket name is not one of the section's names". That claim outlived the enum, so it is
      // restated against what is there now -- **the three browse groupings are the only members, and no bucket is
      // one of them.**
      expect(SourceBucket.fromSource('Beers & Wines'), SourceBucket.beersAndWines);
      expect(
        IngredientCategory.values.map((c) => c.name),
        isNot(contains('beersAndWines')),
        reason: 'a source bucket is not a way of finding an ingredient',
      );
    });
  });
}
