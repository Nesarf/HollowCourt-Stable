// The P1 acceptance criterion, as a test.
//
// Section 14 states it as a capability rather than as a screen: *can enter a
// bottle, compute a match score, mix a drink and decrement stock*. So this walks
// that sentence in order, on the real seed, through the real event log, and
// asserts what each step produced -- which is the only way to know the pieces
// are wired to each other rather than merely all present.
//
// A screen is a later deliverable. If this test passes and no screen exists
// yet, the capability is real and the interface is not, and those are different
// facts worth keeping apart.
import 'dart:io';

import 'package:hollow_court/data/event_log.dart';
import 'package:hollow_court/data/seed/seed_repository.dart';
import 'package:hollow_court/domain/dosing/scaling.dart';
import 'package:hollow_court/domain/events/stock.dart';
import 'package:hollow_court/domain/matching/match_score.dart';
import 'package:hollow_court/domain/model/drink.dart';
import 'package:hollow_court/domain/model/recipe.dart';
import 'package:hollow_court/domain/units/quantity.dart';
import 'package:test/test.dart';

// Our own library, not the harvested seed: that artifact and its sources were deleted on 2026-09-22.
const artifactPath = 'data/drinks/library.json';

/// The drink this walkthrough uses, and **it is one of ours**.
///
/// It was a harvested recipe until 2026-09-22, when the owner had the another source and one source data deleted. The
/// Boulevardier replaces it because it has the same shape the acceptance sentence needs: three measured
/// ingredients across two roles -- a base and two modifiers -- a method, a glass, and no garnish that
/// anybody would keep in a bottle.
const walkthroughRecipeId = 'ibaBoulevardier';

SeedRepository? _repository;
SeedRepository get repository => _repository!;

void main() {
  setUpAll(() {
    if (File(artifactPath).existsSync()) {
      _repository = SeedRepository.fromJson(File(artifactPath).readAsStringSync());
    }
  });

  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('hollow-court-p1');
  });
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<EventLog> cellar() {
    var now = 1000;
    return EventLog.open(
      file: File('${dir.path}${Platform.pathSeparator}cellar.ndjson'),
      nodeId: 'test',
      nowMillis: () => now++,
    );
  }

  /// **Step one: enter a bottle.**
  Future<void> enterBottle(
    EventLog log, {
    required String sku,
    required int millilitres,
  }) => log.record(
    (hlc) => StockEvents.bottleAdded(
      hlc: hlc,
      bottleId: 'bottle-$sku',
      sku: sku,
      volume: Volume.fromMillilitres(millilitres),
    ),
  );

  /// **Step two: what can this bar make?**
  ///
  /// The bridge between the seed and section 9 is one line: a recipe item names
  /// an ingredient id, and the shelf answers whether a bottle of that sku is
  /// open. Nothing else about the two layers has to agree.
  MatchScore scoreOf(EventLog log, Recipe recipe) {
    final ledger = log.stock;
    return MatchScore.of([
      for (final item in recipe.items)
        Requirement(
          id: item.ingredientId,
          role: item.role,
          available: ledger.bottles.any(
            (bottle) =>
                bottle.sku == item.ingredientId &&
                bottle.remaining.microlitres > 0,
          ),
        ),
    ]);
  }

  /// A recipe as the dosing arithmetic sees it.
  ///
  /// Throws when the recipe has no method, and that is not a shortcut: section
  /// 5.5 reads the method to work out how much ice melts, so a drink whose
  /// method is unknown has no computable dilution. The consequence was written
  /// down when `Recipe.method` was made nullable, and this is it happening.
  Drink drinkOf(Recipe recipe) {
    final method = recipe.method;
    if (method == null) {
      throw StateError('${recipe.id} has no method, so its dilution is unknown');
    }
    return Drink(
      components: [
        for (final item in recipe.items)
          Component(
            volume: Volume.fromMicrolitres(item.amount),
            role: item.role,
          ),
      ],
      method: method,
    );
  }

  group('the P1 acceptance criterion', () {
    test('is reachable on the real seed, in the order it is written', () async {
      if (_repository == null) {
        markTestSkipped('data/drinks/library.json is absent; it is tracked, so this means the checkout is partial');
        return;
      }

      final recipe = repository.recipeById(walkthroughRecipeId);
      expect(recipe, isNotNull, reason: walkthroughRecipeId);
      final log = await cellar();

      // ---------------------------------------------------------------- enter
      // A bottle of each measured ingredient. Garnishes are left out on
      // purpose, because a bar recording a twist of peel as stock would be
      // recording something nobody buys in bottles.
      final liquids = [
        for (final item in recipe!.items) if (item.amount > 0) item,
      ];
      expect(liquids, hasLength(3));
      for (final item in liquids) {
        await enterBottle(log, sku: item.ingredientId, millilitres: 700);
      }

      expect(log.stock.bottleCount, 3);
      final bourbon = log.stock.bottles.firstWhere((b) => b.sku == 'bourbonWhiskey');
      expect(bourbon.remaining, Volume.fromMillilitres(700));

      // ----------------------------------------------------------------- score
      final complete = scoreOf(log, recipe);
      expect(complete.verdict, MatchVerdict.makeable);
      expect(complete.mainPercent, 100);

      // And a bar missing its base is not nearly makeable, which is section 9's
      // whole point: the base weighs one and a modifier weighs eight tenths.
      final withoutBase = MatchScore.of([
        for (final item in recipe.items)
          Requirement(
            id: item.ingredientId,
            role: item.role,
            // bourbonWhiskey is the base of a Boulevardier, and section 9 weighs a base heavier than
            // anything beside it -- which is the point this assertion exists to make.
            available: item.ingredientId != 'bourbonWhiskey',
          ),
      ]);
      expect(withoutBase.verdict, MatchVerdict.insufficient);
      expect(withoutBase.missing.map((m) => m.id), ['bourbonWhiskey']);

      // ------------------------------------------------------------------ mix
      // Resized to fill a coupe, which is what section 5.6 is for.
      final drink = drinkOf(recipe);
      // 45 + 30 + 30 millilitres: the Boulevardier's own arithmetic.
      expect(drink.undilutedVolume.microlitres, 105000);

      final doubled = Scaling.toUndilutedVolume(
        drink,
        Volume.fromMillilitres(190),
      );
      // **Scaled to the target, and the rounding is visible.** `toUndilutedVolume` fills a 190 ml measure,
      // so the total lands on 190 ml up to a microlitre. The harvested Adonis divided evenly -- 95 ml into
      // 190 ml exactly -- while the Boulevardier's 105 ml does not, and a bare literal would have been an
      // assertion about one drink's arithmetic rather than about scaling.
      expect(doubled.undilutedVolume.microlitres, closeTo(190000, 2));

      // And a component keeps its share of the whole: the base is 45 of 105 millilitres.
      final baseComponent = doubled.components.first;
      expect(
        baseComponent.volume.microlitres,
        closeTo(45000 * doubled.undilutedVolume.microlitres / 105000, 2),
      );

      // ----------------------------------------------------------- decrement
      // Each poured line comes off the bottle that supplied it, matched by sku.
      for (var i = 0; i < recipe.items.length; i++) {
        final poured = doubled.components[i].volume.microlitres;
        if (poured == 0) continue;
        final sku = recipe.items[i].ingredientId;
        await log.record(
          (hlc) => StockEvents.bottleConsumed(
            hlc: hlc,
            bottleId: 'bottle-$sku',
            volume: Volume.fromMicrolitres(poured),
          ),
        );
      }

      final after = log.stock;
      expect(after.bottleCount, 3);
      // **Seven hundred millilitres in, and the scaled drink's own share out** -- computed from what was
      // poured rather than from a number copied out of the old walkthrough. The harvested Adonis took 90 ml
      // of its base; the Boulevardier takes 45 of 105, and the two are different drinks.
      final pouredBase = after.bottles.firstWhere((b) => b.sku == 'bourbonWhiskey');
      expect(
        pouredBase.remaining.microlitres,
        700000 - baseComponent.volume.microlitres,
        reason: 'the bottle lost exactly the share the drink took',
      );
      expect(pouredBase.remaining, isA<Volume>());
      // **Every bottle lost exactly its own share, and the shares are the drink's proportions.** The old
      // walkthrough asserted three literals (610, 610, 690) that came from the Adonis's own arithmetic; the
      // Boulevardier has three measured ingredients of 45, 30 and 30 millilitres, so each bottle's remaining
      // volume is computed here from the amount actually poured.
      for (final item in recipe.items.where((i) => i.amount > 0)) {
        final share = item.amount * doubled.undilutedVolume.microlitres ~/ 105000;
        expect(
          after.bottles.firstWhere((b) => b.sku == item.ingredientId).remaining.microlitres,
          700000 - share,
          reason: '${item.ingredientId} kept more or less than it should',
        );
      }
      expect(after.bottles.any((b) => b.isOverdrawn), isFalse, reason: 'no bottle went negative');

      // ------------------------------------------------- and it survived disk
      // The log is a file, so the state above is what a second launch reads.
      final reopened = await EventLog.open(
        file: File('${dir.path}${Platform.pathSeparator}cellar.ndjson'),
        nodeId: 'test',
        nowMillis: () => 99999,
      );
      expect(reopened.stock.bottleCount, 3);
      expect(
        reopened.stock.bottles
            .firstWhere((b) => b.sku == 'bourbonWhiskey')
            .remaining
            .microlitres,
        700000 - baseComponent.volume.microlitres,
      );
      expect(scoreOf(reopened, recipe).verdict, MatchVerdict.makeable);
    });

    test('and a recipe with no method cannot be mixed, which is the cost',
        () async {
      if (_repository == null) {
        markTestSkipped('artifact absent');
        return;
      }
      // **The cost of a drink with no method, and the recipe is built here rather than found.**
      //
      // This used to search the harvested library, where some of another source's recipes had no method at all (the
      // method lived in a hashtag inside the steps). That data was deleted on 2026-09-22 at the owner's
      // instruction, and our own list gives every drink a method -- so a test that looked for one would now
      // fail for the wrong reason. Constructing it is better anyway: the rule under test is "a drink with no
      // method cannot be mixed", and that rule does not depend on somebody's library having a hole in it.
      final withMethod = repository.recipeById(walkthroughRecipeId)!;
      final methodless = Recipe(
        id: 'noMethodAtAll',
        name: 'No method at all',
        items: withMethod.items,
        glass: withMethod.glass,
        ice: withMethod.ice,
        method: null,
      );
      expect(methodless.method, isNull);
      expect(() => drinkOf(methodless), throwsA(isA<StateError>()));
    });

    test('the two layers agree about every ingredient a recipe names', () {
      if (_repository == null) {
        markTestSkipped('artifact absent');
        return;
      }
      // The join between the seed and the shelf is a string, so it is worth
      // asserting that every string on one side has a counterpart that could
      // exist on the other. A recipe naming an ingredient the seed does not
      // carry would be a bottle the shelf can never offer.
      expect(repository.danglingIngredientIds, isEmpty);

      final known = {for (final i in repository.ingredients) i.id};
      for (final recipe in repository.recipes) {
        for (final item in recipe.items) {
          expect(known, contains(item.ingredientId),
              reason: '${recipe.id} names ${item.ingredientId}');
        }
      }
    });
  });
}
