import 'package:hollow_court/domain/dosing/density.dart';
import 'package:hollow_court/domain/units/quantity.dart';
import 'package:hollow_court/domain/units/rational.dart';
import 'package:hollow_court/domain/units/unit_system.dart';
import 'package:test/test.dart';

void main() {
  final system = UnitSystem.standard();

  // One fluid ounce, exactly, as the recipe would write it.
  final oneOunce = system.volumeOf(
    Rational.one,
    UnitSystem.fluidOunceUnit,
  );

  group('the bridge between volume and mass', () {
    test('water weighs what it measures', () {
      // A microlitre of water is a milligram, which is what makes the density
      // arithmetic so tidy: ul * g/ml = mg with no constant in between.
      expect(Densities.water.massOf(Volume.fromMillilitres(30)).milligrams, 30000);
      expect(Densities.water.massOf(Volume.fromMillilitres(750)).milligrams, 750000);
    });

    test('an ounce of simple syrup is the figure the design document gives', () {
      // Section 5.4 works this example: one ounce of syrup at 1.30 g/ml is
      // about 38.4 grams.
      final mass = Densities.simpleSyrup.massOf(oneOunce);
      expect(mass.milligrams, 38446);
      expect(mass.milligrams / 1000, closeTo(38.4, 0.05));
    });

    test('a spirit is lighter than the water it is mostly made of', () {
      final spiritMass = Densities.spirit.massOf(oneOunce);
      final waterMass = Densities.water.massOf(oneOunce);

      expect(spiritMass < waterMass, isTrue);

      // 29574 ul -- the ounce rounded to whole microlitres, which is what
      // [oneOunce] is -- times 0.94 is 27799.56 mg, rounding to 27800. The
      // bridge takes a whole volume in and gives a whole mass back, so the
      // only rounding in the chain is the one already in the volume.
      expect(spiritMass.milligrams, 27800);
    });

    test('syrup is heavier than water by about a third', () {
      final syrup = Densities.simpleSyrup.massOf(oneOunce);
      final water = Densities.water.massOf(oneOunce);

      expect(syrup.milligrams / water.milligrams, closeTo(1.30, 0.001));
    });
  });

  group('going back the other way', () {
    test('a mass divides back into the volume it came from', () {
      final volume = Volume.fromMillilitres(30);
      final mass = Densities.simpleSyrup.massOf(volume);
      final returned = Densities.simpleSyrup.volumeOf(mass);

      // Within a microlitre: the bridge rounds to whole milligrams on the way
      // out and to whole microlitres on the way back, and nothing else.
      expect((returned.microlitres - volume.microlitres).abs(), lessThanOrEqualTo(1));
    });

    test('water round trips exactly, because its density is one', () {
      for (final millilitres in [1, 30, 50, 750]) {
        final volume = Volume.fromMillilitres(millilitres);
        expect(
          Densities.water.volumeOf(Densities.water.massOf(volume)),
          volume,
          reason: '$millilitres ml',
        );
      }
    });

    test('a heavier liquid takes less room for the same mass', () {
      final mass = Mass.fromGrams(100);
      final asSyrup = Densities.simpleSyrup.volumeOf(mass);
      final asWater = Densities.water.volumeOf(mass);

      expect(asSyrup < asWater, isTrue);
    });
  });

  group('what the bridge refuses', () {
    test('a density cannot be negative', () {
      expect(
        () => Rational.of(-1, 2).massOf(oneOunce),
        throwsArgumentError,
      );
      expect(
        () => Rational.of(-1, 2).volumeOf(Mass.fromGrams(1)),
        throwsArgumentError,
      );
    });

    test('a substance with no density has no volume for a given mass', () {
      // Not the same as a density of zero meaning "weightless": a mass that
      // displaces nothing is a division by zero, and saying so is better than
      // returning infinity or zero.
      expect(() => Rational.zero.volumeOf(Mass.fromGrams(1)), throwsArgumentError);
    });

    test('zero volume weighs nothing whatever the density', () {
      expect(Densities.simpleSyrup.massOf(Volume.zero).milligrams, 0);
      expect(Densities.water.massOf(Volume.zero).milligrams, 0);
    });
  });
}
