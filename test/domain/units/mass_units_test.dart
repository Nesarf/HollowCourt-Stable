import 'package:hollow_court/domain/units/rational.dart';
import 'package:hollow_court/domain/units/unit.dart';
import 'package:hollow_court/domain/units/unit_system.dart';
import 'package:test/test.dart';

void main() {
  final system = UnitSystem.standard();

  group('the mass base is the milligram, and the metric chain is exact', () {
    test('a kilogram is a thousand grams and a gram is a thousand milligrams', () {
      expect(
        system.milligramsPer(UnitSystem.kilogram),
        system.milligramsPer(UnitSystem.gram) * Rational.fromInt(1000),
      );
      expect(
        system.milligramsPer(UnitSystem.gram),
        system.milligramsPer(UnitSystem.milligram) * Rational.fromInt(1000),
      );
      expect(system.milligramsPer(UnitSystem.milligram), Rational.fromInt(1));
    });

    test('a mass unit scales exactly, because it is absolute and not cultural', () {
      // Section 5.2's reason for the three kinds: scaling a recipe multiplies an
      // absolute unit exactly, guesses at a cultural one, and leaves a count alone.
      // A gram is in the first group, and this is the assertion that says so.
      expect(UnitSystem.gram.kind, UnitKind.absolute);
      expect(UnitSystem.gram.isCultural, isFalse);
      expect(UnitSystem.gram.isDiscrete, isFalse);
      expect(system.isEstimate(UnitSystem.gram), isFalse);
    });
  });

  group('the imperial units are definitions, not measurements', () {
    test('an avoirdupois ounce is exactly 28.349523125 grams', () {
      // Written as the digits of the definition. A rounded 28.35 would make sixteen
      // of them miss a pound, and the miss would be invisible in any single unit.
      expect(
        system.milligramsPer(UnitSystem.ounceMass),
        Rational(BigInt.from(28349523125), BigInt.from(1000000)),
      );
    });

    test('a pound is exactly sixteen ounces, which is what makes it a pound', () {
      expect(
        system.milligramsPer(UnitSystem.pound),
        system.milligramsPer(UnitSystem.ounceMass) * Rational.fromInt(16),
      );
    });

    test('neither imperial unit is a guess', () {
      // Contrast the dash and the barspoon, which are estimates because they are set
      // by the bar. These two are set by treaty, and a screen that marked them
      // "approximate" would be inventing doubt about a definition.
      expect(system.isEstimate(UnitSystem.ounceMass), isFalse);
      expect(system.isEstimate(UnitSystem.pound), isFalse);
      expect(system.isEstimate(UnitSystem.dash), isTrue);
    });
  });

  group('a mass ounce and a volume ounce are different units', () {
    test('they share a symbol and not an identity', () {
      // The real world's problem, kept rather than papered over: `oz` means a fluid
      // ounce on one line and an ounce on another. What a person matches on is the
      // symbol, so both keep it; what a program matches on is the id, so the mass one
      // is `ozm`. Equality follows the id, which is the whole point.
      expect(UnitSystem.ounceMass.symbol, UnitSystem.fluidOunceUnit.symbol);
      expect(UnitSystem.ounceMass.id, isNot(UnitSystem.fluidOunceUnit.id));
      expect(UnitSystem.ounceMass, isNot(UnitSystem.fluidOunceUnit));
      expect(UnitSystem.ounceMass.dimension, UnitDimension.mass);
      expect(UnitSystem.fluidOunceUnit.dimension, UnitDimension.volume);
    });

    test('every unit id in the catalogue is unique, which is what caught this', () {
      // A duplicate id would make two units equal that are not, because `Unit`'s
      // equality is the id alone. Adding mass units is exactly the change that could
      // have introduced it.
      final ids = UnitSystem.all.map((u) => u.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
      expect(ids, contains(UnitSystem.ounceMass.id));
      expect(ids, contains(UnitSystem.fluidOunceUnit.id));
    });

    test('all five mass units are in the catalogue', () {
      for (final unit in [
        UnitSystem.milligram,
        UnitSystem.gram,
        UnitSystem.kilogram,
        UnitSystem.ounceMass,
        UnitSystem.pound,
      ]) {
        expect(UnitSystem.all, contains(unit), reason: unit.id);
      }
    });
  });

  group('the two doors stay separate', () {
    test('the volume door refuses a mass unit', () {
      // Deliberately: a `Mass` is not a `Volume` and the quantity family refuses to
      // add them, so a method that answered both would invite a caller to treat the
      // two bases as interchangeable.
      expect(
        () => system.microlitresPer(UnitSystem.gram),
        throwsA(isA<UnitNotConvertible>()),
      );
    });

    test('entering a mass goes through massOf, which rounds exactly once', () {
      // **The forward door that was missing.** The mass side had the factor
      // (`milligramsPer`) and the inverse (`milligramsOf`) and nothing that went in, so a
      // solid could be printed on a shelf and never weighed into one. This is the twin of
      // `volumeOf`, and the rounding sits in the same place for the same reason: everything
      // above it stays exact, so the only error is the single half-milligram it can add.
      expect(system.massOf(Rational.fromInt(500), UnitSystem.gram).milligrams, 500000);
      expect(system.massOf(Rational.one, UnitSystem.kilogram).milligrams, 1000000);
      expect(
        system.massOf(Rational.parse('1.5'), UnitSystem.ounceMass).milligrams,
        42524,
        reason: '1.5 x 28 349.523125 mg = 42 524.28..., rounded half up',
      );
    });

    test('massOf refuses a volume unit rather than answering with a mass', () {
      // The same refusal as the factor's, one level up: a caller that reached this with a
      // millilitre would otherwise get a number that reads as a weight.
      expect(
        () => system.massOf(Rational.one, UnitSystem.millilitre),
        throwsA(isA<UnitNotConvertible>()),
      );
    });

    test('the mass door refuses a volume unit and a count', () {
      expect(
        () => system.milligramsPer(UnitSystem.millilitre),
        throwsA(isA<UnitNotConvertible>()),
      );
      expect(
        () => system.milligramsPer(UnitSystem.each),
        throwsA(isA<UnitNotConvertible>()),
      );
    });

    test('isConvertible keeps answering the volume question', () {
      // The trap this avoids: once mass units exist, a caller that asked "can I pour
      // this" would start getting "yes" for grams if the old predicate had been
      // widened instead of twinned.
      expect(system.isConvertible(UnitSystem.millilitre), isTrue);
      expect(system.isConvertible(UnitSystem.gram), isFalse);
      expect(system.isMass(UnitSystem.gram), isTrue);
      expect(system.isMass(UnitSystem.millilitre), isFalse);
    });

    test('a ratio has no size in either dimension', () {
      expect(
        () => system.milligramsPer(UnitSystem.part),
        throwsA(isA<UnitNotConvertible>()),
      );
    });
  });
}
