import 'package:hollow_court/domain/parsing/ingredient_phrase.dart';
import 'package:hollow_court/domain/units/quantity.dart';
import 'package:hollow_court/domain/units/rational.dart';
import 'package:hollow_court/domain/units/unit.dart';
import 'package:hollow_court/domain/units/unit_system.dart';
import 'package:test/test.dart';

/// Convenience: parse and assert the outcome type in one step.
MeasuredIngredient measured(String raw, {UnitSystem? units}) {
  final parsed = IngredientPhrase.parse(raw, units: units);
  expect(parsed, isA<MeasuredIngredient>(), reason: 'parsing "$raw"');
  return parsed as MeasuredIngredient;
}

CountedIngredient counted(String raw) {
  final parsed = IngredientPhrase.parse(raw);
  expect(parsed, isA<CountedIngredient>(), reason: 'parsing "$raw"');
  return parsed as CountedIngredient;
}

UnmeasuredIngredient unmeasured(String raw) {
  final parsed = IngredientPhrase.parse(raw);
  expect(parsed, isA<UnmeasuredIngredient>(), reason: 'parsing "$raw"');
  return parsed as UnmeasuredIngredient;
}

UnparsedIngredient unparsed(String raw) {
  final parsed = IngredientPhrase.parse(raw);
  expect(parsed, isA<UnparsedIngredient>(), reason: 'parsing "$raw"');
  return parsed as UnparsedIngredient;
}

void main() {
  group('the four shapes the sources actually use', () {
    test('number, unit, ingredient -- the common case', () {
      // Verbatim from the another source harvest.
      final p = measured('2 oz of rye whiskey');

      expect(p.ingredient, 'rye whiskey');
      expect(p.amount, Rational.fromInt(2));
      expect(p.unit, UnitSystem.fluidOunceUnit);
      expect(p.volume, Volume.fromMicrolitres(59147));
      expect(p.isEstimate, isFalse);
    });

    test('a fractional amount stays exact rather than becoming a double', () {
      final p = measured('0.75 oz of sweet vermouth');
      expect(p.amount, Rational.of(3, 4));
      expect(p.volume, Volume.fromMicrolitres(22180));

      final q = measured('0.25 oz of Maraschino liqueur');
      expect(q.amount, Rational.of(1, 4));
    });

    test('number, ingredient -- a count with no unit word', () {
      final p = counted('1 of cherry');

      expect(p.ingredient, 'cherry');
      expect(p.count, Rational.fromInt(1));
      expect(p.unit, UnitSystem.each);
      expect(p.unit.kind, UnitKind.discrete);
    });

    test('number, unit, ingredient where the unit counts rather than measures', () {
      final p = counted('1 twist of lemon');

      expect(p.ingredient, 'lemon');
      expect(p.count, Rational.fromInt(1));
      expect(p.unit, UnitSystem.twist);
    });

    test('a use word instead of an amount', () {
      final rim = unmeasured('rim of bar sugar');
      expect(rim.ingredient, 'bar sugar');
      expect(rim.use, 'rim');

      final rinse = unmeasured('rinse of absinthe');
      expect(rinse.ingredient, 'absinthe');
      expect(rinse.use, 'rinse');

      final grated = unmeasured('grated of nutmeg');
      expect(grated.ingredient, 'nutmeg');
      expect(grated.use, 'grated');
    });

    test('nothing but an ingredient', () {
      final egg = unmeasured('of egg');
      expect(egg.ingredient, 'egg');
      expect(egg.use, isNull);

      final salt = unmeasured('of salt');
      expect(salt.ingredient, 'salt');
      expect(salt.use, isNull);
    });
  });

  group('the units that are guesses say so', () {
    test('a dash comes out marked as an estimate', () {
      final p = measured('2 dash of Angostura bitters');

      expect(p.unit, UnitSystem.dash);
      expect(p.volume, Volume.fromMicrolitres(1400));
      expect(
        p.isEstimate,
        isTrue,
        reason: 'section 5.3: a dash has no international standard',
      );
    });

    test('a pinch is a sixteenth of a teaspoon, derived from the ounce', () {
      final p = measured('1 pinch of salt');
      expect(p.volume, Volume.fromMicrolitres(308));
      expect(p.isEstimate, isTrue);
    });

    test('a shot is the US jigger and is also an estimate', () {
      final p = measured('1 shot of espresso');
      expect(p.volume, Volume.fromMicrolitres(44360));
      expect(p.isEstimate, isTrue);
    });

    test('a calibrated system changes what the same line measures', () {
      // Section 5.3's whole promise: measure your own dash once, and every
      // recipe in the library is right from then on.
      final calibrated = UnitSystem.standard().withCalibration(
        UnitSystem.dash,
        Rational.fromInt(500),
      );

      final before = measured('2 dash of Angostura bitters');
      final after = measured('2 dash of Angostura bitters', units: calibrated);

      expect(before.volume, Volume.fromMicrolitres(1400));
      expect(after.volume, Volume.fromMicrolitres(1000));
      expect(after.isEstimate, isFalse, reason: 'a measurement is not a guess');
    });

    test('the exact units are not marked', () {
      for (final line in [
        '30 ml of Cream of coconut (Lopez)',
        '1 cl of something',
        '0.5 tsp of Maraschino liqueur',
        '3 drop of Worcestershire sauce',
      ]) {
        expect(measured(line).isEstimate, isFalse, reason: line);
      }
    });
  });

  group('awkward lines from the real harvest', () {
    test('a parenthetical survives in the ingredient name', () {
      final p = measured('30 ml of Cream of coconut (Lopez)');
      expect(p.ingredient, 'Cream of coconut (Lopez)');
      expect(p.volume, Volume.fromMicrolitres(30000));
    });

    test('an apostrophe survives', () {
      final p = measured("0.5 oz of Galliano L'autentico");
      expect(p.ingredient, "Galliano L'autentico");
    });

    test('a whole line with runs of whitespace is tolerated', () {
      final p = measured('  2   oz   of   rye whiskey  ');
      expect(p.ingredient, 'rye whiskey');
      expect(p.volume, Volume.fromMicrolitres(59147));
    });

    test('a comma decimal separator is accepted', () {
      expect(measured('0,75 oz of sweet vermouth').amount, Rational.of(3, 4));
    });
  });

  group('it reports rather than guesses', () {
    test('a word that is not a unit is not treated as one', () {
      final p = unparsed('2 glugs of gin');
      expect(p.raw, '2 glugs of gin');
      expect(p.why, contains('glugs'));
    });

    test('a unit with no number in front of it is a broken line', () {
      final p = unparsed('oz of gin');
      expect(p.why, contains('no number'));
    });

    test('an empty line is reported, not thrown', () {
      final p = unparsed('   ');
      expect(p.why, contains('empty'));
    });

    test('a line matching no known shape is reported', () {
      final p = unparsed('rye whiskey, to taste');
      expect(p.why, contains('does not match'));
    });

    test('a number with nothing after "of" is reported', () {
      final p = unparsed('2 of ');
      expect(p.why, isNotEmpty);
    });

    test('every unparsed outcome carries the original text', () {
      for (final raw in ['2 glugs of gin', 'oz of gin', 'nonsense']) {
        expect(unparsed(raw).raw, raw);
      }
    });
  });

  group('counted ingredients do not become volumes', () {
    test('a discrete unit has no size and is not converted', () {
      for (final unit in [
        UnitSystem.leaf,
        UnitSystem.sprig,
        UnitSystem.wheel,
        UnitSystem.wedge,
        UnitSystem.slice,
        UnitSystem.each,
      ]) {
        expect(unit.kind, UnitKind.discrete, reason: unit.id);
        expect(unit.dimension, UnitDimension.count, reason: unit.id);
        expect(
          UnitSystem.standard().factorFor(unit),
          isNull,
          reason: '${unit.id} must have no factor, or it could be poured',
        );
      }
    });

    test('doubling a count is the spec, and the spec says so', () {
      // Section 5.2: a counted unit is carried through scaling unchanged, so
      // two drinks do not mean two wheels in one glass. The parser only has to
      // report the count; the scaling rule lives in the unit's kind.
      expect(counted('2 wheel of orange').count, Rational.fromInt(2));
    });
  });
}
