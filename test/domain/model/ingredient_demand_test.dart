import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:hollow_court/data/seed/seed_codec.dart';
import 'package:hollow_court/domain/model/ingredient_demand.dart';

/// **How many recipes call for each ingredient** -- stage ② of `docs/catalogue-and-stock.md`, as arithmetic.
///
/// The numbers this exists for are in `docs/ingredient-gap.md` (33 / 31 / 57 / 68 over the library's 189). What is
/// asserted here is not those numbers -- they are a property of the shipped seed and belong to whoever changes the
/// seed -- but the four rules the classes are built from, because every one of them has a way of being wrong that
/// looks right on screen.
void main() {
  group('the four classes', () {
    test('**the boundary between rare and occasional, and between occasional and core**', () {
      // Named one at a time rather than as a range, because these are the two comparisons a `>=` written the wrong
      // way round gets wrong, and a loop over 0..10 would pass with either direction as long as one end held.
      expect(DemandClass.of(0), DemandClass.dead);
      expect(DemandClass.of(1), DemandClass.rare);
      expect(DemandClass.of(2), DemandClass.occasional);
      expect(DemandClass.of(3), DemandClass.occasional);
      expect(DemandClass.of(4), DemandClass.core, reason: 'four is core, not occasional');
      expect(DemandClass.of(40), DemandClass.core);
    });

    test('**nothing wants it is its own class, not the bottom of the scale**', () {
      // The whole point of stage ②: 68 of the library's 189 are records nothing calls for, and folding them in with
      // the 57 that exactly one recipe calls for would hide the number the stage exists to show.
      expect(DemandClass.of(0), isNot(DemandClass.of(1)));
      expect(DemandClass.values, hasLength(4));
    });

    test('the order is the order a reader meets them -- most wanted first', () {
      expect(DemandClass.values, [
        DemandClass.core,
        DemandClass.occasional,
        DemandClass.rare,
        DemandClass.dead,
      ]);
    });
  });

  group('counting', () {
    test('**a recipe that names the same thing twice counts once**', () {
      // The reader's own editor permits a duplicate line, so this is reachable from the interface rather than
      // theoretical: two lines of the same syrup is one drink that wants it, not a heavier piece of evidence.
      final demand = IngredientDemand.of([
        ['gin', 'gin', 'gin'],
      ]);
      expect(demand.countOf('gin'), 1);
      expect(demand.classOf('gin'), DemandClass.rare);
    });

    test('a count is the number of recipes, so four mentions across four recipes is core', () {
      final demand = IngredientDemand.of([
        ['gin'],
        ['gin', 'vermouth'],
        ['gin', 'campari'],
        ['gin', 'vermouth', 'campari'],
      ]);
      expect(demand.countOf('gin'), 4);
      expect(demand.classOf('gin'), DemandClass.core);
      expect(demand.countOf('vermouth'), 2);
      expect(demand.classOf('vermouth'), DemandClass.occasional);
      expect(demand.countOf('campari'), 2);
    });

    test('**an ingredient no recipe names is dead rather than absent**', () {
      // The ordinary case, not an error: 68 of the library's 189 are in exactly this position, and a lookup that
      // threw or returned null would make the screen that draws them the screen that breaks on them.
      final demand = IngredientDemand.of([
        ['gin'],
      ]);
      expect(demand.countOf('yuzu'), 0);
      expect(demand.classOf('yuzu'), DemandClass.dead);
    });

    test('nothing at all is a legal input, and everything in it is dead', () {
      expect(IngredientDemand.of(const []).classOf('gin'), DemandClass.dead);
      expect(IngredientDemand.none.classOf('gin'), DemandClass.dead);
      expect(IngredientDemand.none.histogramOf(['gin', 'yuzu'])[DemandClass.dead], 2);
    });
  });

  group('the histogram', () {
    test('**it counts the ids it is given, not the ids the counts know**', () {
      // A screen draws the ingredients it has, and a class it reports for something it does not draw is a number
      // the reader cannot check against anything. The two sets differ as soon as a screen filters.
      final demand = IngredientDemand.of([
        ['gin', 'vermouth'],
        ['gin'],
        ['gin'],
        ['gin'],
      ]);
      // `gin` is core and `vermouth` is rare -- but asking about only one of them must not report the other.
      expect(demand.histogramOf(['gin']), {DemandClass.core: 1});
      expect(demand.histogramOf(['vermouth']), {DemandClass.rare: 1});
      expect(demand.histogramOf(['gin', 'vermouth']), {DemandClass.core: 1, DemandClass.rare: 1});
    });

    test('an id nothing knows lands in dead, like every other unknown', () {
      final demand = IngredientDemand.of(const []);
      expect(demand.histogramOf(['gin', 'yuzu', 'campari']), {DemandClass.dead: 3});
    });
  });

  /// **The numbers the whole stage exists to show**, against the library that actually ships.
  ///
  /// They are `docs/ingredient-gap.md`'s, measured 2026-10-01, and this is the second measurement of them by a
  /// different route -- that one counted by hand over the artifact, this one folds the real seed through
  /// [IngredientDemand]. Two measurements agreeing is worth more than either, and the day they stop agreeing is a
  /// day somebody should look.
  ///
  /// **It is pinned exactly rather than bounded, and that is the point.** The numbers are a documented claim about
  /// the shipped data, so a seed change that moves them has made a document wrong, and a test that tolerated the
  /// move would be the same failure as the one `seed_vocabulary_test` records: a check that quietly redefines what
  /// it checks. Whoever adds ingredients or recipes updates this and the document together, deliberately.
  group('the library that ships', () {
    test('**33 / 31 / 57 / 68, over 189 ingredients and 103 recipes**', () {
      final seed = SeedCodec.decode(File('data/drinks/library.json').readAsStringSync());
      final demand = IngredientDemand.of([
        for (final recipe in seed.recipes)
          [for (final item in recipe.items) item.ingredientId],
      ]);
      final histogram = demand.histogramOf([for (final i in seed.ingredients) i.id]);

      expect(seed.ingredients, hasLength(189));
      expect(seed.recipes, hasLength(103));
      expect(histogram[DemandClass.core], 33);
      expect(histogram[DemandClass.occasional], 31);
      expect(histogram[DemandClass.rare], 57);
      expect(histogram[DemandClass.dead], 68);

      // **And the four add up to the catalogue**, which is the check that survives a wrong histogram: every
      // ingredient is in exactly one class, so a bucket lost to a bug shows up as a total that is short.
      final total = DemandClass.values.fold(0, (sum, c) => sum + (histogram[c] ?? 0));
      expect(total, seed.ingredients.length);
    });

    test('**dead stock is a third of the catalogue, and that is the finding**', () {
      // Said as a ratio rather than the raw 68, because the claim being guarded is the one a reader meets on the
      // screen -- "a third of these are not your responsibility" -- and 68 over 189 is what makes it true.
      final seed = SeedCodec.decode(File('data/drinks/library.json').readAsStringSync());
      final demand = IngredientDemand.of([
        for (final recipe in seed.recipes)
          [for (final item in recipe.items) item.ingredientId],
      ]);
      final dead = demand.histogramOf([for (final i in seed.ingredients) i.id])[DemandClass.dead]!;

      expect(dead / seed.ingredients.length, greaterThan(0.35));
      expect(dead / seed.ingredients.length, lessThan(0.37));
    });
  });
}
