import '../model/recipe.dart';
import '../units/rational.dart';
import '../units/quantity.dart';
import 'price.dart';

/// What a bottle cost, and how much was in it.
///
/// **This is the whole of the cost basis, and the reader already types it.** The cellar's bottle sheet has asked
/// for a price, a currency and a purchase date since it was written, so nothing here needs new input -- it needs
/// the two numbers put together. A bar costs a pour by dividing the bottle's price by the bottle's volume, and so
/// does this.
final class BottlePrice {
  const BottlePrice({required this.paid, required this.volume});

  final Money paid;

  /// What was bought for [paid]. The sheet's own field, so a bottle entered in ounces works as well as one
  /// entered in millilitres.
  final Volume volume;

  /// **Several bottles of the same thing, as one figure, weighted by volume.**
  ///
  /// The average rather than the latest price, because "what does a millilitre of this gin cost me" is a question
  /// about the gin currently on the shelf: buying 1.75 L at a better rate should move the number, and buying a
  /// 50 ml miniature should barely move it. A plain mean would let the miniature shout as loudly as the handle.
  ///
  /// Currencies do not mix -- [Money] refuses to add two of them, and this returns null rather than picking one.
  static BottlePrice? blendOf(Iterable<BottlePrice> bottles) {
    var paidMinor = 0;
    var microlitres = 0;
    Currency? currency;
    for (final bottle in bottles) {
      if (currency != null && bottle.paid.currency != currency) return null;
      currency = bottle.paid.currency;
      paidMinor += bottle.paid.minorUnits;
      microlitres += bottle.volume.microlitres;
    }
    if (currency == null || microlitres == 0) return null;
    return BottlePrice(
      paid: Money.fromMinorUnits(paidMinor, currency),
      volume: Volume.fromMicrolitres(microlitres),
    );
  }

  /// What [used] of this bottle costs, rounded once at the end.
  ///
  /// **Rational arithmetic, not integer division.** ¥120 over 700 ml is 17 fen a millilitre, and a 60 ml pour of
  /// it costs ¥10.29 -- but doing that in minor units at any intermediate step loses the pour entirely. The
  /// fraction is carried exactly and rounded once, which is the rule `Volume` and `Money` were both built on.
  Money costOf(Volume used) => paid.times(
    Rational.of(used.microlitres, volume.microlitres),
  );
}

/// What a recipe costs to make, and **which parts of it could not be counted**.
///
/// The second half is the point. A costing feature that treats an unpriced ingredient as free produces a number
/// that looks complete and is wrong, and a reader who trusts it will price a drink below its cost. So the gaps are
/// named, counted, and carried all the way to the screen, where they read as *成本 12.40（3 种原料未标价）*.
final class RecipeCost {
  const RecipeCost({
    required this.currency,
    required this.total,
    required this.uncostedKeys,
    required this.costedLines,
    required this.totalLines,
  });

  /// Null when no line could be costed at all, or when the lines span currencies.
  final Currency? currency;

  /// The total for the lines that could be priced.
  final Money? total;

  /// The ingredient ids with no price on record. Named rather than counted, because the reader can act on a name.
  final List<String> uncostedKeys;

  final int costedLines;
  final int totalLines;

  bool get isComplete => total != null && uncostedKeys.isEmpty;

  /// True when the number exists but does not cover everything -- the state the screen has to say out loud.
  bool get isPartial => total != null && uncostedKeys.isNotEmpty;

  /// How much of the recipe the figure covers, for a screen that would rather show a proportion than a caveat.
  double get coverage => totalLines == 0 ? 0 : costedLines / totalLines;
}

/// Cost of [recipe] from the reader's own bottle prices, keyed by ingredient id.
///
/// **A missing price is a gap, not a zero.** An ingredient the reader has never bought through the cellar -- or
/// bought without recording what it cost -- lands in [RecipeCost.uncostedKeys]. That is why every ingredient line
/// is examined rather than only the ones with prices: the count of what is missing is the answer to "can I trust
/// this number", and it cannot be derived after the fact.
RecipeCost costOfRecipe({
  required Recipe recipe,
  required Map<String, BottlePrice> prices,
}) {
  // **Each line is costed on its own bottle, and the sum is rounded once at the end.**
  //
  // The first version of this accumulated prices and volumes into a single ratio, which is arithmetic nonsense:
  // 60 ml of a ¥120/700 ml gin and 30 ml of an ¥80/750 ml vermouth became one fraction over one volume, and the
  // test written from the shop's own numbers caught it -- ¥6.62 where the two lines cost ¥13.49.
  Rational exact = Rational.fromInt(0);
  Currency? currency;
  var costed = 0;
  final uncosted = <String>[];

  for (final item in recipe.items) {
    final bottle = prices[item.ingredientId];
    if (bottle == null || bottle.volume.microlitres == 0) {
      uncosted.add(item.ingredientId);
      continue;
    }
    if (currency != null && bottle.paid.currency != currency) {
      // Two currencies cannot be summed, and inventing a rate is worse than saying so. The line is a gap.
      uncosted.add(item.ingredientId);
      continue;
    }
    currency = bottle.paid.currency;
    exact = exact +
        bottle.paid.toRational() * Rational.of(item.amount, bottle.volume.microlitres);
    costed++;
  }

  if (currency == null || costed == 0) {
    return RecipeCost(
      currency: currency,
      total: null,
      uncostedKeys: uncosted,
      costedLines: costed,
      totalLines: recipe.items.length,
    );
  }

  // One rounding, here.
  final total = Money.fromMinorUnits(exact.roundHalfUpToBigInt().toInt(), currency);
  return RecipeCost(
    currency: currency,
    total: total,
    uncostedKeys: uncosted,
    costedLines: costed,
    totalLines: recipe.items.length,
  );
}

/// What a recipe earns: the price charged, the cost, and the two differences a reader actually decides on.
final class RecipeMargin {
  const RecipeMargin({required this.price, required this.cost});

  /// What the reader charges for one.
  final Money price;

  final RecipeCost cost;

  /// Price minus cost, or null when the cost is not known at all.
  ///
  /// **Null rather than the price itself.** An unpriced recipe reported as pure profit would be the most
  /// expensive lie this feature could tell, and the reader would only find out at the till.
  Money? get profit {
    final total = cost.total;
    if (total == null || total.currency != price.currency) return null;
    return price - total;
  }

  /// Profit as a fraction of the price, or null when either half is missing.
  Rational? get margin {
    final profitValue = profit;
    if (profitValue == null || price.isZero) return null;
    return Rational.of(profitValue.minorUnits, price.minorUnits);
  }

  /// True when the profit figure ignores at least one ingredient, which is a different warning from "unknown".
  bool get isPartial => profit != null && cost.isPartial;
}
