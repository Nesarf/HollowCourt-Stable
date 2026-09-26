// The badge's second line, which was wrong on the phone on the first run.
//
// Run with `flutter test`, not `dart test`.
import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/domain/matching/match_score.dart';
import 'package:hollow_court/domain/model/item_role.dart';
import 'package:hollow_court/ui/recipes_page.dart';
import 'package:hollow_court/ui/theme.dart';

Requirement _req(String id, ItemRole role, bool available) =>
    Requirement(id: id, role: role, available: available);

void main() {
  group('a recipe badge cannot contradict its own verdict', () {
    test('a missing base is reported as missing from the drink', () {
      final score = MatchScore.of([
        _req('gin', ItemRole.base, false),
        _req('vermouth', ItemRole.modifier, true),
      ]);
      expect(score.verdict, MatchVerdict.insufficient);
      // The bug: this used to read "ingredients complete", because the garnish
      // was complete and the check looked only at the garnish.
      expect(verdictDetail(score), Copy.withCount(Copy.recipesMissingCount, 1));
      expect(verdictDetail(score), isNot(Copy.recipesNothingMissing));
    });

    test('and it counts the drink, not the garnish', () {
      // Two modifiers missing, and a garnish missing as well. The number the
      // badge shows is the drink's shortfall; the garnish is scored apart.
      final score = MatchScore.of([
        _req('gin', ItemRole.base, true),
        _req('vermouth', ItemRole.modifier, false),
        _req('bitters', ItemRole.modifier, false),
        _req('lemon', ItemRole.garnish, false),
      ]);
      expect(verdictDetail(score), Copy.withCount(Copy.recipesMissingCount, 2));
    });

    test('only the garnish missing says exactly that', () {
      // This is the honest case for the phrase, and the only one.
      final score = MatchScore.of([
        _req('gin', ItemRole.base, true),
        _req('vermouth', ItemRole.modifier, true),
        _req('lemon', ItemRole.garnish, false),
      ]);
      // Section 9: a missing twist of peel does not make the drink impossible.
      expect(score.verdict, MatchVerdict.makeable);
      expect(verdictDetail(score), Copy.recipesGarnishOnly);
    });

    test('nothing missing says nothing is missing', () {
      final score = MatchScore.of([
        _req('gin', ItemRole.base, true),
        _req('lemon', ItemRole.garnish, true),
      ]);
      expect(verdictDetail(score), Copy.recipesNothingMissing);
    });

    test('and a drink with no garnish at all is not asked about one', () {
      final score = MatchScore.of([_req('gin', ItemRole.base, true)]);
      expect(verdictDetail(score), Copy.recipesNothingMissing);
    });
  });
}
