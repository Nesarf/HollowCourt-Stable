import '../units/rational.dart';
import 'cashflow.dart';
import 'price.dart';

/// **Why an ingredient was used up.** The owner's instruction of 2026-09-25:
///
/// > 用掉酒的时候需要允许注明是收入还是研发等，也可以注明为失败等，提供更细化的收支情况记录
/// > 还可以建立对某种配方的成功率、研发频次等，提供更细致的判断
///
/// **A purpose is not a note.** Recording *why* something was poured is what turns a cellar into a business: the
/// same 60 ml of gin is revenue if a customer drank it, an experiment if the maker was testing a new recipe, and
/// waste if it went down the sink -- and a log that cannot tell those apart can only report that stock went down.
///
/// **[decision] Success and failure are separate purposes rather than one "development" plus a flag.** A bar that
/// developed four drinks and got one of them is telling itself something quite different from a bar that developed
/// four and got four, and the difference has to be recordable in one tap at the moment of pouring. A flag would be
/// a second thing to remember, and the second thing is the one that gets skipped.
enum ConsumptionPurpose {
  /// A customer drank it: **income**, at the recipe's own menu price.
  sold,

  /// The maker was developing a recipe and it worked: a cost, and a success.
  developed,

  /// The maker was developing a recipe and it did not: a cost, and a failure.
  ///
  /// Poured away, and that is not the same as [spoiled] -- a failed attempt is the ordinary price of finding a
  /// drink, while spoilage is stock lost to time. Averaged together, a busy developer looks like a careless one.
  failed,

  /// Stock lost to time, a broken bottle, a spill: a loss with nobody's name on it.
  spoiled,

  /// Poured for the maker or a guest: a cost, and a choice rather than an accident.
  personal,

  /// Anything else, recorded as what it is rather than forced into a category that would be a guess.
  other;

  bool get isIncome => this == ConsumptionPurpose.sold;

  bool get isDevelopment =>
      this == ConsumptionPurpose.developed || this == ConsumptionPurpose.failed;

  /// Costs the bar money without being an experiment: spoilage and hospitality, which are different problems.
  bool get isLoss => this == ConsumptionPurpose.spoiled;

  String get name => switch (this) {
    ConsumptionPurpose.sold => 'sold',
    ConsumptionPurpose.developed => 'developed',
    ConsumptionPurpose.failed => 'failed',
    ConsumptionPurpose.spoiled => 'spoiled',
    ConsumptionPurpose.personal => 'personal',
    ConsumptionPurpose.other => 'other',
  };

  static ConsumptionPurpose? byName(String? name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }
}

/// One use of an ingredient, as a judgement needs to see it.
///
/// [costMinorUnits] arrives already computed -- by `costOfRecipe` for a whole drink, or by `BottlePrice.costOf`
/// for a single pour. Keeping it out of this type means the judgement can be tested, and later moved, without an
/// event log or a price store anywhere near it.
///
/// **[decision] A cost of null is carried, not zeroed.** An attempt whose ingredients are not all priced is an
/// attempt whose cost is *unknown*, and a success rate computed over invented costs would be a confident answer to
/// a question nobody can answer yet.
final class IngredientUse {
  const IngredientUse({
    required this.purpose,
    required this.at,
    required this.currency,
    this.costMinorUnits,
    this.recipeId,
    this.label,
  });

  final ConsumptionPurpose purpose;
  final DateTime at;
  final Currency currency;

  /// What it cost, when every ingredient in it had a price.
  final int? costMinorUnits;

  /// Which recipe this belongs to, when it was a drink rather than a splash. Null for a use that is about an
  /// ingredient rather than a menu item.
  final String? recipeId;

  /// What was used, for a gap that has to be named.
  final String? label;
}

/// What a recipe's own history says about it: how often it was tried, how often it worked, and what that cost.
final class RecipeJudgement {
  const RecipeJudgement({
    required this.attempts,
    required this.sales,
    required this.successes,
    required this.failures,
    required this.spoiled,
    required this.personal,
    required this.developmentCost,
    required this.unpricedAttempts,
    required this.currency,
  });

  /// Every use of this recipe, in any purpose.
  final int attempts;

  final int sales;
  final int successes;
  final int failures;
  final int spoiled;
  final int personal;

  /// What the development attempts cost, from the ones that could be costed.
  final Money developmentCost;

  /// Development attempts whose cost is unknown, so [developmentCost] can be reported as the floor it is.
  final int unpricedAttempts;

  final Currency? currency;

  /// **The success rate, as a fraction rather than a percentage.** Ratios are not doubled into floats until a
  /// screen has to draw them, and the domain has a `Rational` for exactly this reason.
  ///
  /// **Null when nothing has been developed**, which is not the same as zero. A drink nobody has tried has no
  /// success rate; reporting 0% would say it had been tried and failed every time.
  Rational? get successRate => successes + failures == 0
      ? null
      : Rational.of(successes, successes + failures);

  /// How often this recipe has been poured per week within the window that was judged.
  ///
  /// Null for a window of no days, because "per week" of nothing is not a number.
  Rational? frequencyPerWeek(int days) => days <= 0 ? null : Rational.of(attempts * 7, days);

  /// True when the recipe has been developed and never worked, which is a different thing from never tried.
  bool get isUnsuccessful => successes == 0 && failures > 0;

  bool get hasBeenTried => successes + failures > 0;
}

/// Judges one recipe from the uses recorded against it.
///
/// The window is the caller's -- the same four spans the cashflow uses, so a reader comparing "this week" across
/// the two screens is comparing the same days. Uses outside it are ignored entirely rather than weighted.
RecipeJudgement judgeRecipe({
  required String recipeId,
  required Iterable<IngredientUse> uses,
  required CashflowWindow window,
  required DateTime now,
}) {
  final from = window.startFrom(now);

  var attempts = 0;
  var sales = 0;
  var successes = 0;
  var failures = 0;
  var spoiled = 0;
  var personal = 0;
  var developmentMinor = 0;
  var unpriced = 0;
  Currency? currency;

  for (final use in uses) {
    if (use.recipeId != recipeId) continue;
    if (use.at.isBefore(from) || use.at.isAfter(now)) continue;
    attempts++;

    switch (use.purpose) {
      case ConsumptionPurpose.sold:
        sales++;
      case ConsumptionPurpose.developed:
        successes++;
      case ConsumptionPurpose.failed:
        failures++;
      case ConsumptionPurpose.spoiled:
        spoiled++;
      case ConsumptionPurpose.personal:
        personal++;
      case ConsumptionPurpose.other:
        break;
    }

    if (!use.purpose.isDevelopment) continue;
    final cost = use.costMinorUnits;
    if (cost == null) {
      unpriced++;
      continue;
    }
    // A currency the window has already left behind would be added to a total that means nothing.
    if (currency != null && use.currency != currency) {
      unpriced++;
      continue;
    }
    currency = use.currency;
    developmentMinor += cost;
  }

  return RecipeJudgement(
    attempts: attempts,
    sales: sales,
    successes: successes,
    failures: failures,
    spoiled: spoiled,
    personal: personal,
    developmentCost: Money.fromMinorUnits(developmentMinor, currency ?? const Currency('XXX', 2)),
    unpricedAttempts: unpriced,
    currency: currency,
  );
}
