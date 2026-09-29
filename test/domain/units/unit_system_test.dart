import 'package:hollow_court/domain/units/quantity.dart';
import 'package:hollow_court/domain/units/rational.dart';
import 'package:hollow_court/domain/units/unit.dart';
import 'package:hollow_court/domain/units/unit_system.dart';
import 'package:test/test.dart';

/// Microlitres as a fraction, for readable expectations.
Rational ul(int value) => Rational.fromInt(value);

void main() {
  final us = UnitSystem.standard();

  group('the fluid ounce, which is where the ambiguity starts', () {
    // Section 5.3 leads with this because it is the largest difference hiding
    // behind a familiar symbol.
    test('a US fluid ounce is 29.5735295625 ml exactly', () {
      expect(
        us.microlitresPer(UnitSystem.fluidOunceUnit),
        Rational.of(295735295625, 10000000),
      );

      // The same number, read the way a person would: 29.5735295625 ml.
      final millilitres =
          us.microlitresPer(UnitSystem.fluidOunceUnit) /
          us.microlitresPer(UnitSystem.millilitre);
      expect(millilitres.toDouble(), closeTo(29.5735295625, 1e-10));
    });

    test('an imperial fluid ounce is 28.4131 ml exactly', () {
      final imperial = UnitSystem.standard(fluidOunce: FluidOunce.imperial);
      expect(
        imperial.microlitresPer(UnitSystem.fluidOunceUnit),
        Rational.of(284131, 10),
      );
    });

    test('the two differ by about four percent', () {
      final imperial = UnitSystem.standard(fluidOunce: FluidOunce.imperial);
      final usOz = us.microlitresPer(UnitSystem.fluidOunceUnit);
      final impOz = imperial.microlitresPer(UnitSystem.fluidOunceUnit);

      final ratio = usOz.toDouble() / impOz.toDouble();
      expect(ratio, closeTo(1.0408, 0.0001));

      // And in a drink: three ounces of the same recipe differ by more than
      // three millilitres, which is a visible pour.
      final difference =
          us.volumeOf(Rational.fromInt(3), UnitSystem.fluidOunceUnit) -
          imperial.volumeOf(Rational.fromInt(3), UnitSystem.fluidOunceUnit);
      expect(difference.microlitres, greaterThan(3400));
    });

    test('US is the default', () {
      expect(us.fluidOunce, FluidOunce.us);
    });
  });

  group('derived units are derived, not rounded', () {
    test('a teaspoon is exactly a sixth of an ounce', () {
      final ounce = us.microlitresPer(UnitSystem.fluidOunceUnit);
      expect(
        us.microlitresPer(UnitSystem.teaspoon),
        ounce / Rational.fromInt(6),
      );
    });

    test('a tablespoon is exactly half an ounce', () {
      final ounce = us.microlitresPer(UnitSystem.fluidOunceUnit);
      expect(
        us.microlitresPer(UnitSystem.tablespoon),
        ounce / Rational.fromInt(2),
      );
    });

    test('three teaspoons make a tablespoon', () {
      final tsp = us.microlitresPer(UnitSystem.teaspoon);
      final tbsp = us.microlitresPer(UnitSystem.tablespoon);
      expect(tsp * Rational.fromInt(3), tbsp);
    });

    test('the metric units are exact', () {
      expect(us.microlitresPer(UnitSystem.millilitre), ul(1000));
      expect(us.microlitresPer(UnitSystem.centilitre), ul(10000));
      expect(us.microlitresPer(UnitSystem.litre), ul(1000000));
    });
  });

  group('cultural units are guesses until somebody measures', () {
    test('dash and barspoon start as estimates', () {
      expect(us.isEstimate(UnitSystem.dash), isTrue);
      expect(us.isEstimate(UnitSystem.barspoon), isTrue);

      // Everything defined is not an estimate, and that has to include the
      // units that are merely unfamiliar.
      for (final unit in [
        UnitSystem.millilitre,
        UnitSystem.fluidOunceUnit,
        UnitSystem.teaspoon,
        UnitSystem.tablespoon,
        UnitSystem.drop,
      ]) {
        expect(us.isEstimate(unit), isFalse, reason: unit.id);
      }
    });

    test('the suggested dash is inside the range the design document quotes', () {
      final ml =
          us.microlitresPer(UnitSystem.dash) /
          us.microlitresPer(UnitSystem.millilitre);
      expect(ml.toDouble(), inInclusiveRange(0.6, 0.8));
    });

    test('the suggested barspoon starts at the smaller convention', () {
      final ml =
          us.microlitresPer(UnitSystem.barspoon) /
          us.microlitresPer(UnitSystem.millilitre);
      expect(ml.toDouble(), 2.5);
    });

    test('uncalibratedUnits lists exactly the guesses', () {
      final guesses = us.uncalibratedUnits();

      // Asserted against the unit table rather than against a literal count.
      // A count would have gone stale the moment pinch and shot were added, and
      // it would have gone stale *silently* -- which is the wrong failure mode
      // for a test whose whole job is to describe a list.
      final cultural = UnitSystem.all.where(
        (unit) => unit.kind == UnitKind.cultural && us.factorFor(unit) != null,
      );

      expect(guesses.keys.toSet(), cultural.toSet());
      expect(guesses, hasLength(cultural.length));
      expect(guesses.values.every((factor) => factor.isEstimate), isTrue);
      expect(
        guesses.keys,
        containsAll([UnitSystem.dash, UnitSystem.barspoon, UnitSystem.pinch, UnitSystem.shot]),
      );
    });

    test('calibrating replaces the guess and stops calling it one', () {
      final measured = us.withCalibration(UnitSystem.dash, ul(620));

      expect(measured.microlitresPer(UnitSystem.dash), ul(620));
      expect(measured.isEstimate(UnitSystem.dash), isFalse);

      // The system it came from is untouched: calibration is a new value, not
      // a mutation, so a screen can preview it before committing.
      expect(us.microlitresPer(UnitSystem.dash), ul(700));
      expect(us.isEstimate(UnitSystem.dash), isTrue);
    });

    test('calibrating one unit leaves the others alone', () {
      final measured = us.withCalibration(UnitSystem.dash, ul(620));
      expect(measured.microlitresPer(UnitSystem.barspoon), ul(2500));
      expect(measured.isEstimate(UnitSystem.barspoon), isTrue);
      expect(measured.microlitresPer(UnitSystem.fluidOunceUnit),
          us.microlitresPer(UnitSystem.fluidOunceUnit));
    });

    test('a calibration carries through to the drink', () {
      // Two dashes of bitters, before and after the user measures their bottle.
      final before = us.volumeOf(Rational.fromInt(2), UnitSystem.dash);
      final after =
          us.withCalibration(UnitSystem.dash, ul(620)).volumeOf(
                Rational.fromInt(2),
                UnitSystem.dash,
              );

      expect(before.microlitres, 1400);
      expect(after.microlitres, 1240);
    });

    test('what is defined cannot be recalibrated', () {
      expect(
        () => us.withCalibration(UnitSystem.millilitre, ul(999)),
        throwsArgumentError,
      );
      expect(
        () => us.withCalibration(UnitSystem.fluidOunceUnit, ul(30000)),
        throwsArgumentError,
      );
    });

    test('a measurement has to have a size', () {
      expect(() => us.withCalibration(UnitSystem.dash, Rational.zero),
          throwsArgumentError);
      expect(() => us.withCalibration(UnitSystem.dash, ul(-10)),
          throwsArgumentError);
    });
  });

  group('units that cannot become microlitres', () {
    test('a part has no size until the total is known', () {
      expect(
        () => us.microlitresPer(UnitSystem.part),
        throwsA(isA<UnitNotConvertible>()),
      );
      expect(us.isConvertible(UnitSystem.part), isFalse);
    });

    test('a count is not a volume', () {
      for (final unit in [
        UnitSystem.leaf,
        UnitSystem.sprig,
        UnitSystem.wheel,
        UnitSystem.twist,
        UnitSystem.peel,
        UnitSystem.cube,
      ]) {
        expect(
          () => us.microlitresPer(unit),
          throwsA(isA<UnitNotConvertible>()),
          reason: unit.id,
        );
        expect(us.isConvertible(unit), isFalse, reason: unit.id);
      }
    });

    test('a part says why it cannot be converted', () {
      try {
        us.microlitresPer(UnitSystem.part);
        fail('expected a UnitNotConvertible');
      } on UnitNotConvertible catch (error) {
        expect(error.unit, UnitSystem.part);
        expect(error.reason, contains('share'));
      }
    });
  });

  group('converting in and out', () {
    test('a whole ounce rounds to the nearest microlitre', () {
      // 29573.5295625 ul, and the half rounds away from zero.
      expect(
        us.volumeOf(Rational.one, UnitSystem.fluidOunceUnit).microlitres,
        29574,
      );
    });

    test('a recipe amount becomes a whole number of microlitres', () {
      // 1 1/2 oz, the way a recipe writes it.
      final amount = Rational.of(3, 2);
      expect(
        us.volumeOf(amount, UnitSystem.fluidOunceUnit).microlitres,
        44360,
      );

      // 50 ml is exact and needs no rounding at all.
      expect(
        us.volumeOf(Rational.fromInt(50), UnitSystem.millilitre).microlitres,
        50000,
      );
    });

    test('going back out is exact rather than rounded', () {
      final thirtyMl = Volume.fromMillilitres(30);
      final ounces = us.amountIn(thirtyMl, UnitSystem.fluidOunceUnit);

      // Deliberately not 1.01: a display layer rounds, this does not.
      expect(ounces * us.microlitresPer(UnitSystem.fluidOunceUnit), ul(30000));
      expect(ounces.isInteger, isFalse);
      expect(ounces.toDouble(), closeTo(1.01442, 0.00001));
    });

    test('a round trip through a defined unit loses nothing', () {
      for (final unit in [
        UnitSystem.millilitre,
        UnitSystem.centilitre,
        UnitSystem.teaspoon,
        UnitSystem.tablespoon,
        UnitSystem.drop,
      ]) {
        final original = Volume.fromMillilitres(750);
        final displayed = us.amountIn(original, unit);
        final returned = us.volumeOf(displayed, unit);
        expect(returned, original, reason: unit.id);
      }
    });

    test('a round trip through an ounce lands within half a microlitre', () {
      final original = Volume.fromMillilitres(750);
      final returned = us.volumeOf(
        us.amountIn(original, UnitSystem.fluidOunceUnit),
        UnitSystem.fluidOunceUnit,
      );

      final drift = (returned.microlitres - original.microlitres).abs();
      expect(drift, lessThanOrEqualTo(1));
    });

    test('scaling a recipe adds no drift beyond the final rounding', () {
      // A Negroni, three ounces, doubled by scaling the ratio rather than by
      // adding two rounded pours.
      final one = us.volumeOf(Rational.one, UnitSystem.fluidOunceUnit);
      final doubled = us.volumeOf(Rational.fromInt(2), UnitSystem.fluidOunceUnit);

      // The exact double is 59147.059125 ul and rounds to 59147; adding the
      // rounded single twice would have given 59148. One microlitre, and it
      // is the reason the ratio is carried rather than the volume.
      expect(one.microlitres * 2, 59148);
      expect(doubled.microlitres, 59147);
    });
  });

  group('quantities', () {
    test('volume arithmetic is whole and exact', () {
      final a = Volume.fromMillilitres(30);
      final b = Volume.fromMillilitres(45);

      expect((a + b).microlitres, 75000);
      expect((b - a).microlitres, 15000);
      expect(a.scaleBy(3).microlitres, 90000);
      expect(a < b, isTrue);
      expect(a, Volume.fromMicrolitres(30000));
      expect(Volume.zero.isZero, isTrue);
    });

    test('mass arithmetic is whole and exact', () {
      final a = Mass.fromGrams(30);
      final b = Mass.fromMilligrams(45000);

      expect((a + b).milligrams, 75000);
      expect(b.scaleBy(2).milligrams, 90000);
      expect(a < b, isTrue);
    });

    test('a volume and a mass are not the same kind of thing', () {
      // This is a compile-time property rather than a runtime one, which is
      // the point: there is no expression here that could be written to test
      // it. What can be tested is that they carry their units into any string
      // that escapes, so a log line cannot be misread.
      expect(Volume.fromMillilitres(1).toString(), '1000 ul');
      expect(Mass.fromGrams(1).toString(), '1000 mg');
    });
  });
}
