import 'package:hollow_court/domain/dosing/dilution.dart';
import 'package:hollow_court/domain/model/drink.dart';
import 'package:hollow_court/domain/model/item_role.dart';
import 'package:hollow_court/domain/units/quantity.dart';
import 'package:hollow_court/domain/units/rational.dart';
import 'package:hollow_court/domain/units/unit_system.dart';
import 'package:test/test.dart';

/// A Negroni, the drink section 5.5 works its example with.
///
/// Equal parts, which is what makes it a good test: 30 ml of each, three
/// liquids, one of them strong.
Drink negroni() {
  Rational strength(int percent) => Rational.fromInt(percent);

  return Drink(
    method: Method.stirred,
    components: [
      Component(
        volume: Volume.fromMillilitres(30),
        abvPercent: strength(40),
        role: ItemRole.base,
      ),
      Component(
        volume: Volume.fromMillilitres(30),
        abvPercent: strength(24),
        role: ItemRole.modifier,
      ),
      Component(
        volume: Volume.fromMillilitres(30),
        abvPercent: strength(16),
        role: ItemRole.modifier,
      ),
    ],
  );
}

void main() {
  final system = UnitSystem.standard();

  group('the ranges section 5.5 gives', () {
    test('stirring adds a sixth to a fifth of the volume', () {
      expect(Dilution.stirred.low, Rational.of(15, 100));
      expect(Dilution.stirred.high, Rational.of(20, 100));
      expect(Dilution.stirred.typical, Rational.of(175, 1000));
    });

    test('shaking adds more than stirring, because it breaks the ice up', () {
      expect(Dilution.shaken.low, Rational.of(20, 100));
      expect(Dilution.shaken.high, Rational.of(25, 100));
      expect(Dilution.shaken.typical > Dilution.stirred.typical, isTrue);
    });

    test('something built in the glass picks up nothing', () {
      expect(Dilution.forMethod(Method.built).isNone, isTrue);
      expect(Dilution.forMethod(Method.poured).isNone, isTrue);
      expect(Dilution.none.typical, Rational.zero);
    });

    test('blending takes the shaken range, and that choice is recorded', () {
      // The design document gives ranges for the three methods a bar uses most
      // and none for blending. This is the one figure in the file that the
      // document does not state.
      expect(Dilution.forMethod(Method.blended).low, Dilution.shaken.low);
      expect(Dilution.forMethod(Method.blended).high, Dilution.shaken.high);
    });
  });

  group('the arithmetic', () {
    test('the document worked example: three ounces stirred to about three and a half', () {
      final threeOunces = system.volumeOf(
        Rational.fromInt(3),
        UnitSystem.fluidOunceUnit,
      );

      final served = Dilution.stirred.dilutedVolume(threeOunces);
      final inOunces = system.amountIn(served, UnitSystem.fluidOunceUnit);

      // Section 5.5 says "about three and a half ounces", and to one decimal
      // place it is exactly that: 3.525. The assertion says so directly rather
      // than hiding the reading in a tolerance chosen to fit.
      expect((inOunces.toDouble() * 10).round() / 10, 3.5);
      expect(inOunces.toDouble(), closeTo(3.525, 0.001));
    });

    test('dilution is a fraction of the original, not a fixed amount', () {
      final small = Dilution.stirred.dilutedVolume(Volume.fromMillilitres(90));
      final large = Dilution.stirred.dilutedVolume(Volume.fromMillilitres(180));

      expect(small.microlitres, 105750);
      // Twice the drink takes twice the water, which a fixed figure would miss.
      expect(large.microlitres, 211500);
      expect(large.microlitres, small.microlitres * 2);
    });

    test('the water itself is exact', () {
      final water = Dilution.stirred.waterFor(Volume.fromMillilitres(90));
      expect(water, Rational.of(15750, 1));
    });

    test('a whole drink dilutes by its total, not by its parts', () {
      final drink = negroni();
      expect(drink.undilutedVolume.microlitres, 90000);
      expect(
        Dilution.stirred.dilutedVolumeOf(drink).microlitres,
        105750,
      );
    });

    test('no dilution leaves the volume alone', () {
      final drink = negroni();
      expect(Dilution.none.dilutedVolumeOf(drink), drink.undilutedVolume);
      expect(Dilution.none.waterFor(drink.undilutedVolume), Rational.zero);
    });
  });

  group('what a drink is made of', () {
    test('the garnish is not part of the liquid', () {
      // A twist of peel sits on the rim, not in the glass. Counting its volume
      // would be harmless at zero and wrong the moment a garnish carries
      // anything -- a cherry in syrup, say.
      final drink = Drink(
        method: Method.stirred,
        components: [
          Component(
            volume: Volume.fromMillilitres(60),
            abvPercent: Rational.fromInt(40),
          ),
          Component(
            volume: Volume.fromMillilitres(20),
            role: ItemRole.garnish,
          ),
        ],
      );

      expect(drink.undilutedVolume.microlitres, 80000);
      expect(
        drink.liquidComponents.fold(
          Volume.zero,
          (sum, component) => sum + component.volume,
        ).microlitres,
        60000,
      );
    });

    test('a component with no alcohol contributes none', () {
      const juice = Component(volume: Volume.fromMicrolitres(30000));
      expect(juice.alcoholMicrolitres(), Rational.zero);
      expect(juice.isAlcoholic, isFalse);
    });

    test('alcohol is worked out exactly, with no rounding', () {
      // 30 ml at 40 percent is 12 ml of alcohol, and it has to stay 12 rather
      // than 12.000000001. Not const because Rational.fromInt is a factory:
      // its numerator is a BigInt, and BigInt has no constant constructor.
      final gin = Component(
        volume: Volume.fromMicrolitres(30000),
        abvPercent: Rational.fromInt(40),
      );
      expect(gin.alcoholMicrolitres(), Rational.fromInt(12000));
    });
  });
}
