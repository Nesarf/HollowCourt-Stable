import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/domain/model/recipe.dart';
import 'package:hollow_court/domain/pricing/price.dart';
import 'package:hollow_court/domain/pricing/recipe_cost.dart';
import 'package:hollow_court/domain/units/quantity.dart';

/// Costing a recipe from what the reader actually paid.
///
/// The tests are in the shop's own numbers: a 700 ml bottle for ¥120, a 60 ml pour of it, and the totals a bar
/// would recognise. Any arithmetic that loses the pour -- or that quietly treats a missing price as free -- fails
/// here rather than at the till.
void main() {
  const cny = Currency('CNY', 2);
  const usd = Currency('USD', 2);
  Money yuan(int whole, [int fen = 0]) => Money.fromMinorUnits(whole * 100 + fen, cny);
  Volume ml(int value) => Volume.fromMillilitres(value);

  RecipeItem item(String id, int millilitres) => RecipeItem(ingredientId: id, amount: millilitres * 1000);

  Recipe recipeOf(List<RecipeItem> items) => Recipe(
    id: 'test',
    name: 'Test',
    items: items,
  );

  group('the cost basis', () {
    test('**a pour of a bottle costs its share of the bottle, to the fen**', () {
      final bottle = BottlePrice(paid: yuan(120), volume: ml(700));
      // 12000 fen over 700 ml, times 60 ml = 1028.57 fen, rounded once -- 10.29 yuan.
      expect(bottle.costOf(ml(60)).minorUnits, 1029);
      expect(bottle.costOf(ml(700)).minorUnits, 12000, reason: 'a whole bottle is its whole price');
      expect(bottle.costOf(ml(0)).minorUnits, 0);
    });

    test('several bottles of the same thing blend by volume, not by count', () {
      final handle = BottlePrice(paid: yuan(200), volume: ml(1750));
      final mini = BottlePrice(paid: yuan(30), volume: ml(50));
      final blend = BottlePrice.blendOf([handle, mini])!;
      expect(blend.volume.microlitres, 1800000);
      expect(blend.paid.minorUnits, 23000);
      // The miniature must not shout as loudly as the handle: a plain mean would put this near 95 yuan a litre.
      final perLitre = blend.costOf(ml(1000)).minorUnits;
      expect(perLitre, greaterThan(12000), reason: 'still cheap gin, but not miniature-priced');
      expect(perLitre, lessThan(13000));
    });

    test('two currencies do not blend, and the answer is null rather than a guess', () {
      expect(
        BottlePrice.blendOf([
          BottlePrice(paid: yuan(120), volume: ml(700)),
          BottlePrice(paid: Money.fromMinorUnits(999, usd), volume: ml(700)),
        ]),
        isNull,
      );
    });
  });

  group('a recipe', () {
    test('sums its lines at each ingredient\'s own price', () {
      final cost = costOfRecipe(
        recipe: recipeOf([item('gin', 60), item('vermouth', 30)]),
        prices: {
          'gin': BottlePrice(paid: yuan(120), volume: ml(700)),
          'vermouth': BottlePrice(paid: yuan(80), volume: ml(750)),
        },
      );
      expect(cost.isComplete, isTrue);
      expect(cost.currency!.code, 'CNY');
      // 60/700 of 120 plus 30/750 of 80 = 10.2857 + 3.2 = 13.4857 -> 13.49
      expect(cost.total!.minorUnits, 1349);
    });

    test('**an ingredient with no price is a named gap, not a free one**', () {
      final cost = costOfRecipe(
        recipe: recipeOf([item('gin', 60), item('absinthe', 5), item('olive', 0)]),
        prices: {'gin': BottlePrice(paid: yuan(120), volume: ml(700))},
      );
      expect(cost.total, isNotNull, reason: 'the part that can be costed is still costed');
      expect(cost.total!.minorUnits, 1029, reason: 'and it is not lowered by the missing lines');
      expect(cost.uncostedKeys, ['absinthe', 'olive'], reason: 'named, so the reader can act on it');
      expect(cost.isPartial, isTrue);
      expect(cost.coverage, closeTo(1 / 3, 1e-9));
    });

    test('nothing priced means no number at all, rather than zero', () {
      final cost = costOfRecipe(recipe: recipeOf([item('gin', 60)]), prices: const {});
      expect(cost.total, isNull);
      expect(cost.isComplete, isFalse);
      expect(cost.isPartial, isFalse, reason: 'unknown is not the same as partial');
      expect(cost.uncostedKeys, ['gin']);
    });

    test('a currency that does not match the line is a gap, because no rate is invented here', () {
      final cost = costOfRecipe(
        recipe: recipeOf([item('gin', 60), item('whiskey', 60)]),
        prices: {
          'gin': BottlePrice(paid: yuan(120), volume: ml(700)),
          'whiskey': BottlePrice(paid: Money.fromMinorUnits(5000, usd), volume: ml(700)),
        },
      );
      expect(cost.currency!.code, 'CNY');
      expect(cost.uncostedKeys, ['whiskey']);
      expect(cost.isPartial, isTrue);
    });
  });

  group('what a drink earns', () {
    test('profit and margin, from the price charged', () {
      final cost = costOfRecipe(
        recipe: recipeOf([item('gin', 60)]),
        prices: {'gin': BottlePrice(paid: yuan(120), volume: ml(700))},
      );
      final margin = RecipeMargin(price: yuan(48), cost: cost);
      expect(margin.profit!.minorUnits, 4800 - 1029);
      expect(margin.margin!.toDouble(), closeTo((4800 - 1029) / 4800, 1e-9));
      expect(margin.isPartial, isFalse);
    });

    test('**an uncosted recipe reports no profit rather than pure profit**', () {
      final cost = costOfRecipe(recipe: recipeOf([item('gin', 60)]), prices: const {});
      final margin = RecipeMargin(price: yuan(48), cost: cost);
      expect(margin.profit, isNull, reason: 'the price is not profit when the cost is unknown');
      expect(margin.margin, isNull);
    });

    test('a partial cost still reports a partial profit, and says so', () {
      final cost = costOfRecipe(
        recipe: recipeOf([item('gin', 60), item('absinthe', 5)]),
        prices: {'gin': BottlePrice(paid: yuan(120), volume: ml(700))},
      );
      final margin = RecipeMargin(price: yuan(48), cost: cost);
      expect(margin.profit!.minorUnits, 4800 - 1029);
      expect(margin.isPartial, isTrue, reason: 'the screen must be able to say the number is a floor');
    });

    test('a price in another currency gives no profit rather than a wrong one', () {
      final cost = costOfRecipe(
        recipe: recipeOf([item('gin', 60)]),
        prices: {'gin': BottlePrice(paid: yuan(120), volume: ml(700))},
      );
      final margin = RecipeMargin(
        price: Money.fromMinorUnits(4800, usd),
        cost: cost,
      );
      expect(margin.profit, isNull);
    });
  });
}
