import 'package:hollow_court/domain/matching/match_score.dart';
import 'package:hollow_court/domain/model/item_role.dart';
import 'package:hollow_court/domain/units/rational.dart';
import 'package:test/test.dart';

/// A requirement that is on hand, or not.
Requirement has(String id, ItemRole role) =>
    Requirement(id: id, role: role, available: true);

Requirement missing(String id, ItemRole role) =>
    Requirement(id: id, role: role, available: false);

/// The Negroni again, this time as a shopping question rather than a drink.
List<Requirement> negroni({bool gin = true, bool campari = true, bool vermouth = true, bool peel = true}) => [
  gin ? has('gin', ItemRole.base) : missing('gin', ItemRole.base),
  campari ? has('campari', ItemRole.modifier) : missing('campari', ItemRole.modifier),
  vermouth ? has('vermouth', ItemRole.modifier) : missing('vermouth', ItemRole.modifier),
  peel ? has('orangePeel', ItemRole.garnish) : missing('orangePeel', ItemRole.garnish),
];

void main() {
  group('weights', () {
    test('a base counts for more than a modifier, which counts for more than an option', () {
      expect(MatchScore.weightOf(ItemRole.base), Rational.one);
      expect(MatchScore.weightOf(ItemRole.modifier), Rational.of(8, 10));
      expect(MatchScore.weightOf(ItemRole.optional), Rational.of(3, 10));
    });

    test('a garnish weighs nothing in the main score, because it scores apart', () {
      expect(MatchScore.weightOf(ItemRole.garnish), Rational.zero);
    });
  });

  group('the garnish is scored on its own', () {
    test('a missing twist does not make a Negroni impossible', () {
      // Section 9's worked argument, as a test. This is the whole reason the
      // two numbers are separate.
      final score = MatchScore.of(negroni(peel: false));

      expect(score.main, Rational.one);
      expect(score.verdict, MatchVerdict.makeable);
      expect(score.garnish, Rational.zero);
      expect(score.garnishComplete, isFalse);
    });

    test('a recipe needing no garnish has all of it', () {
      final score = MatchScore.of([
        has('gin', ItemRole.base),
        has('vermouth', ItemRole.modifier),
      ]);
      expect(score.garnish, Rational.one);
      expect(score.garnishComplete, isTrue);
    });

    test('a complete garnish reports complete', () {
      expect(MatchScore.of(negroni()).garnishComplete, isTrue);
    });
  });

  group('what the main score says', () {
    test('everything on hand is a hundred percent', () {
      final score = MatchScore.of(negroni());
      expect(score.main, Rational.one);
      expect(score.mainPercent, 100);
      expect(score.verdict, MatchVerdict.makeable);
      expect(score.missing, isEmpty);
    });

    test('missing a modifier drops it below the threshold', () {
      // Two modifiers at 0.8 against a base at 1.0: losing one leaves 1.8 of
      // 2.6, which is 69 percent -- under the 70 the document draws the line
      // at, and a good reminder that the bands are not generous.
      final score = MatchScore.of(negroni(vermouth: false));

      expect(score.main, Rational.of(9, 13));
      expect(score.mainPercent, 69);
      expect(score.verdict, MatchVerdict.insufficient);
      expect(score.missing.single.id, 'vermouth');
    });

    test('missing the base is worse than missing a modifier', () {
      final noBase = MatchScore.of(negroni(gin: false));
      final noModifier = MatchScore.of(negroni(vermouth: false));
      expect(noBase.main < noModifier.main, isTrue);
    });

    test('an optional ingredient is worth giving up', () {
      final score = MatchScore.of([
        has('gin', ItemRole.base),
        has('campari', ItemRole.modifier),
        has('vermouth', ItemRole.modifier),
        missing('olive', ItemRole.optional),
      ]);

      expect(score.mainPercent, 90);
      expect(score.verdict, MatchVerdict.close);
      expect(score.missing.single.id, 'olive');
    });
  });

  group('the bands, at their edges', () {
    // Twenty base ingredients, so the fractions land on the thresholds exactly
    // rather than near them.
    MatchScore withAvailable(int available) => MatchScore.of([
      for (var i = 0; i < 20; i++)
        i < available
            ? has('item$i', ItemRole.base)
            : missing('item$i', ItemRole.base),
    ]);

    test('ninety-five percent is makeable', () {
      expect(withAvailable(19).main, Rational.of(95, 100));
      expect(withAvailable(19).verdict, MatchVerdict.makeable);
    });

    test('ninety-four is close', () {
      final score = MatchScore.of([
        for (var i = 0; i < 100; i++)
          i < 94 ? has('item$i', ItemRole.base) : missing('item$i', ItemRole.base),
      ]);
      expect(score.verdict, MatchVerdict.close);
    });

    test('seventy is still close', () {
      expect(withAvailable(14).main, Rational.of(70, 100));
      expect(withAvailable(14).verdict, MatchVerdict.close);
    });

    test('sixty-five is not', () {
      expect(withAvailable(13).main, Rational.of(65, 100));
      expect(withAvailable(13).verdict, MatchVerdict.insufficient);
    });

    test('nothing at all is still a complete list of what is missing', () {
      expect(withAvailable(0).main, Rational.zero);
      expect(withAvailable(0).missing, hasLength(20));
      expect(withAvailable(0).verdict, MatchVerdict.insufficient);
    });
  });

  group('the missing list', () {
    test('keeps the order it was given, so a screen can show it as written', () {
      final score = MatchScore.of([
        missing('gin', ItemRole.base),
        has('campari', ItemRole.modifier),
        missing('vermouth', ItemRole.modifier),
      ]);

      expect(score.missing.map((requirement) => requirement.id), ['gin', 'vermouth']);
    });

    test('carries the roles, so a shopping list can be ordered by importance', () {
      final score = MatchScore.of(negroni(gin: false, peel: false));
      expect(
        score.missing.map((requirement) => requirement.role),
        [ItemRole.base, ItemRole.garnish],
      );
    });

    test('is not something a caller can scribble on', () {
      final score = MatchScore.of(negroni());
      expect(() => score.missing.add(has('x', ItemRole.base)), throwsUnsupportedError);
    });
  });

  group('degenerate inputs', () {
    test('a recipe with nothing in it is complete', () {
      // Nothing is missing from an empty list. Reporting zero would say the
      // opposite, and would make an empty recipe look impossible.
      final score = MatchScore.of([]);
      expect(score.main, Rational.one);
      expect(score.garnish, Rational.one);
      expect(score.verdict, MatchVerdict.makeable);
    });

    test('a garnish-only recipe is a complete drink with a complete garnish', () {
      final score = MatchScore.of([has('peel', ItemRole.garnish)]);
      expect(score.main, Rational.one);
      expect(score.garnish, Rational.one);
    });
  });
}
