import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/domain/pricing/cashflow.dart';
import 'package:hollow_court/domain/pricing/price.dart';
import 'package:hollow_court/domain/pricing/recipe_judgement.dart';

/// What a recipe's own history says about it.
///
/// The tests are about the two mistakes this feature could make and must not: reporting a success rate for a drink
/// nobody has tried, and reporting a development cost that silently treats an unpriced attempt as free.
void main() {
  const cny = Currency('CNY', 2);
  final now = DateTime(2026, 9, 25, 22);

  IngredientUse use(
    ConsumptionPurpose purpose, {
    required int day,
    int? costFen,
    String recipe = 'margarita',
  }) => IngredientUse(
    purpose: purpose,
    at: DateTime(2026, 9, day, 20),
    currency: cny,
    costMinorUnits: costFen,
    recipeId: recipe,
  );

  test('**a drink nobody has tried has no success rate, rather than 0%**', () {
    // 0% would say it had been tried and failed every time, which is the opposite of the truth.
    final judgement = judgeRecipe(
      recipeId: 'margarita',
      uses: const [],
      window: CashflowWindow.month,
      now: now,
    );
    expect(judgement.successRate, isNull);
    expect(judgement.hasBeenTried, isFalse);
    expect(judgement.attempts, 0);
  });

  test('a rate that is a fraction, and a drink that has never worked', () {
    final judgement = judgeRecipe(
      recipeId: 'margarita',
      uses: [
        use(ConsumptionPurpose.developed, day: 20, costFen: 1029),
        use(ConsumptionPurpose.developed, day: 21, costFen: 1029),
        use(ConsumptionPurpose.failed, day: 22, costFen: 1180),
        use(ConsumptionPurpose.failed, day: 23, costFen: 1180),
      ],
      window: CashflowWindow.month,
      now: now,
    );
    expect(judgement.successes, 2);
    expect(judgement.failures, 2);
    expect(judgement.successRate!.toDouble(), closeTo(0.5, 1e-9));
    expect(judgement.isUnsuccessful, isFalse);

    final doomed = judgeRecipe(
      recipeId: 'margarita',
      uses: [use(ConsumptionPurpose.failed, day: 22, costFen: 1180)],
      window: CashflowWindow.month,
      now: now,
    );
    expect(doomed.successRate!.toDouble(), 0);
    expect(doomed.isUnsuccessful, isTrue, reason: 'tried, and never worked: a different thing from untried');
  });

  test('**sales are not development**: a hit drink is not a successful experiment', () {
    final judgement = judgeRecipe(
      recipeId: 'margarita',
      uses: [
        use(ConsumptionPurpose.developed, day: 20, costFen: 1000),
        use(ConsumptionPurpose.sold, day: 24),
        use(ConsumptionPurpose.sold, day: 25),
      ],
      window: CashflowWindow.month,
      now: now,
    );
    expect(judgement.attempts, 3);
    expect(judgement.sales, 2);
    expect(judgement.successRate!.toDouble(), 1, reason: 'one experiment, and it worked');
    expect(judgement.developmentCost.minorUnits, 1000, reason: 'a sale is revenue, not development spend');
  });

  test('**an unpriced attempt is counted, not costed**', () {
    final judgement = judgeRecipe(
      recipeId: 'margarita',
      uses: [
        use(ConsumptionPurpose.developed, day: 20, costFen: 1000),
        use(ConsumptionPurpose.failed, day: 21), // an ingredient had no price
      ],
      window: CashflowWindow.month,
      now: now,
    );
    expect(judgement.developmentCost.minorUnits, 1000);
    expect(judgement.unpricedAttempts, 1, reason: 'the screen must be able to say the figure is a floor');
    expect(judgement.failures, 1, reason: 'it still counts as an attempt -- only its cost is unknown');
  });

  test('spoilage and hospitality are kept apart from experiments', () {
    // Averaged together a busy developer looks like a careless one, which is why they are separate purposes.
    final judgement = judgeRecipe(
      recipeId: 'margarita',
      uses: [
        use(ConsumptionPurpose.developed, day: 20, costFen: 1000),
        use(ConsumptionPurpose.spoiled, day: 21, costFen: 2000),
        use(ConsumptionPurpose.personal, day: 22, costFen: 900),
      ],
      window: CashflowWindow.month,
      now: now,
    );
    expect(judgement.spoiled, 1);
    expect(judgement.personal, 1);
    expect(judgement.developmentCost.minorUnits, 1000, reason: 'neither is development spend');
  });

  test('the window is the same four spans the cashflow uses, and excludes the rest', () {
    final uses = [
      use(ConsumptionPurpose.sold, day: 25),
      use(ConsumptionPurpose.sold, day: 20),
      use(ConsumptionPurpose.sold, day: 10), // thirteen days ago: inside the month, outside the week
    ];
    final today = judgeRecipe(recipeId: 'margarita', uses: uses, window: CashflowWindow.today, now: now);
    final week = judgeRecipe(recipeId: 'margarita', uses: uses, window: CashflowWindow.week, now: now);
    final month = judgeRecipe(recipeId: 'margarita', uses: uses, window: CashflowWindow.month, now: now);

    expect(today.sales, 1);
    expect(week.sales, 2, reason: 'the 20th is inside seven days of the 25th');
    expect(month.sales, 3);
  });

  test('frequency is per week over the window that was judged', () {
    final week = judgeRecipe(
      recipeId: 'margarita',
      uses: [for (var day = 19; day <= 25; day++) use(ConsumptionPurpose.sold, day: day)],
      window: CashflowWindow.week,
      now: now,
    );
    expect(week.frequencyPerWeek(7)!.toDouble(), closeTo(7, 1e-9), reason: 'seven pours in seven days');

    final month = judgeRecipe(
      recipeId: 'margarita',
      uses: [for (var day = 19; day <= 25; day++) use(ConsumptionPurpose.sold, day: day)],
      window: CashflowWindow.month,
      now: now,
    );
    expect(month.frequencyPerWeek(30)!.toDouble(), closeTo(7 * 7 / 30, 1e-9));
  });

  test('a use belonging to another recipe is not this recipe\'s history', () {
    final judgement = judgeRecipe(
      recipeId: 'margarita',
      uses: [
        use(ConsumptionPurpose.sold, day: 25),
        use(ConsumptionPurpose.sold, day: 25, recipe: 'daiquiri'),
      ],
      window: CashflowWindow.month,
      now: now,
    );
    expect(judgement.attempts, 1);
  });
}
