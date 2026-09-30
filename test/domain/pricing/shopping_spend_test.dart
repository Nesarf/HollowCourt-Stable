import 'package:hollow_court/domain/events/hlc.dart';
import 'package:hollow_court/domain/model/glass.dart';
import 'package:hollow_court/domain/model/ice.dart';
import 'package:hollow_court/domain/model/item_role.dart';
import 'package:hollow_court/domain/model/liquid_visual.dart';
import 'package:hollow_court/domain/model/recipe.dart';
import 'package:hollow_court/domain/pricing/price.dart';
import 'package:hollow_court/domain/pricing/shopping_spend.dart';
import 'package:hollow_court/domain/stats/shopping_list.dart';
import 'package:hollow_court/domain/units/quantity.dart';
import 'package:test/test.dart';

/// **Where section 7's open question ended.** For months the record said this project had not decided which price
/// sources it may query, and waited on the owner. Measured on 2026-09-30 it was not a decision: the only open,
/// anonymously-readable price database has no coverage in China. What does have an answer is what the reader
/// already paid, and that is what these cover.
///
/// The arithmetic is small on purpose. What is worth testing is the two places where a total could be *confidently
/// wrong* rather than merely absent: mixing two currencies into one figure, and presenting a sum over priced
/// ingredients as if it were the whole cost.
void main() {
  const cny = Currency('CNY', 2);
  final now = DateTime(2026, 9, 30, 12);

  RecipeItem item(String ingredientId) =>
      RecipeItem(ingredientId: ingredientId, amount: 30000, role: ItemRole.base);

  Recipe recipe(String id, List<String> ingredients) => Recipe(
    id: id,
    name: id,
    glass: Glass.cocktail,
    ice: IceKind.none,
    method: Method.stirred,
    liquid: const LiquidVisual(colour: LiquidColour.orangeDark, opacityPercent: 75),
    items: [for (final ingredient in ingredients) item(ingredient)],
  );

  /// One observation: [minor] for a 700 ml bottle, recorded now.
  PricePoint paid(int minor, {Currency currency = cny, int millilitres = 700}) => PricePoint(
    hlc: Hlc(physicalMillis: now.millisecondsSinceEpoch, counter: minor, nodeId: 'test'),
    paid: Money.fromMinorUnits(minor, currency),
    volume: Volume.fromMillilitres(millilitres),
    source: PriceSource.manual,
  );

  ShoppingList listOf(List<Recipe> recipes, List<String> planned) => ShoppingList.of(
    recipes: recipes,
    plannedRecipeIds: planned.toSet(),
    have: (_) => false,
  );

  test('an ingredient the reader has paid for is priced from that payment', () {
    final list = listOf([recipe('gimlet', ['gin', 'lime'])], ['gimlet']);

    final spend = ShoppingSpend.of(list, lastPaid: (id) => id == 'gin' ? paid(12800) : null);

    expect(spend.lines, hasLength(1));
    expect(spend.lines.single.ingredientId, 'gin');
    expect(spend.lines.single.point.paid.minorUnits, 12800);
    // **The volume comes with it**, because a price without one is not an answer: ¥128 says nothing about gin
    // until it is ¥128 for 700 ml.
    expect(spend.lines.single.point.volume.microlitres, 700000);
    expect(spend.total.minorUnits, 12800);
    expect(spend.currency, cny);
  });

  test('**an ingredient with no price is counted, not silently dropped**', () {
    // The failure this guards is a total that reads as the whole cost while a line of the list is missing from it.
    final list = listOf([recipe('gimlet', ['gin', 'lime'])], ['gimlet']);

    final spend = ShoppingSpend.of(list, lastPaid: (id) => id == 'gin' ? paid(12800) : null);

    expect(spend.unpriced, 1, reason: 'lime has never been priced');
    expect(spend.total.minorUnits, 12800, reason: 'the total is what has a price');
  });

  test('**two currencies produce no total rather than a meaningless one**', () {
    // ¥128 and $9 add up as numbers and mean nothing by it -- the rule `PriceSeries.isSingleCurrency` states for
    // the chart. The mistake would be invisible: the axis would draw and the figure would look like a figure.
    final list = listOf([recipe('gimlet', ['gin', 'lime'])], ['gimlet']);
    const usd = Currency('USD', 2);

    final spend = ShoppingSpend.of(
      list,
      lastPaid: (id) => id == 'gin' ? paid(12800) : paid(900, currency: usd),
    );

    expect(spend.lines, hasLength(2), reason: 'both lines are still shown');
    expect(spend.currency, isNull, reason: 'and the total is withheld');
  });

  test('a list with nothing priced has nothing to show', () {
    final list = listOf([recipe('gimlet', ['gin'])], ['gimlet']);
    final spend = ShoppingSpend.of(list, lastPaid: (_) => null);

    expect(spend.isEmpty, isTrue);
    expect(spend.unpriced, 1);
  });

  test('**the count is recipes, and the model says so rather than implying otherwise**', () {
    // `neededBy` counts the planned recipes that name an ingredient -- not bottles, and not the volume the
    // recipes call for. This test exists so that the name cannot quietly become a quantity later: a figure
    // derived from it and presented as "how many bottles" would be invented.
    final list = listOf(
      [recipe('gimlet', ['gin']), recipe('martini', ['gin', 'vermouth'])],
      ['gimlet', 'martini'],
    );

    final spend = ShoppingSpend.of(list, lastPaid: (id) => id == 'gin' ? paid(12800) : null);

    expect(spend.lines.single.neededBy, 2, reason: 'two recipes name gin');
    expect(
      spend.total.minorUnits,
      12800,
      reason: 'one payment, counted once -- the count of recipes does not multiply the price',
    );
  });
}
