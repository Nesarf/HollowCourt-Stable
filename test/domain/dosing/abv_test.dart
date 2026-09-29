import 'package:hollow_court/domain/dosing/abv.dart';
import 'package:hollow_court/domain/dosing/dilution.dart';
import 'package:hollow_court/domain/model/drink.dart';
import 'package:hollow_court/domain/model/item_role.dart';
import 'package:hollow_court/domain/units/quantity.dart';
import 'package:hollow_court/domain/units/rational.dart';
import 'package:test/test.dart';

Drink negroni() => Drink(
  method: Method.stirred,
  components: [
    Component(
      volume: Volume.fromMillilitres(30),
      abvPercent: Rational.fromInt(40),
    ),
    Component(
      volume: Volume.fromMillilitres(30),
      abvPercent: Rational.fromInt(24),
      role: ItemRole.modifier,
    ),
    Component(
      volume: Volume.fromMillilitres(30),
      abvPercent: Rational.fromInt(16),
      role: ItemRole.modifier,
    ),
  ],
);

void main() {
  group('strength before the ice', () {
    test('a Negroni is a little over twenty-six percent as written', () {
      // 12 ml + 7.2 ml + 4.8 ml of alcohol in 90 ml.
      final drink = negroni();
      expect(drink.alcoholMicrolitres(), Rational.fromInt(24000));
      expect(drink.abvPercentUndiluted().toDouble(), closeTo(26.667, 0.001));
    });

    test('the figure is exact, not a floating point approximation of one', () {
      final drink = negroni();
      // 24000 / 90000 * 100 = 80 / 3, exactly.
      expect(drink.abvPercentUndiluted(), Rational.of(80, 3));
    });

    test('a drink with nothing in it is not strong', () {
      const empty = Drink(components: [], method: Method.stirred);
      expect(empty.abvPercentUndiluted(), Rational.zero);
      expect(empty.abvPercentServed(Dilution.stirred), Rational.zero);
    });
  });

  group('strength in the glass', () {
    test('the ice makes it weaker, and by a lot', () {
      final drink = negroni();
      final before = drink.abvPercentUndiluted().toDouble();
      final after = drink.abvPercentServed(Dilution.stirred).toDouble();

      expect(after, closeTo(22.695, 0.001));
      // Nearly four points, which is the difference section 5.5 is warning
      // about when it says an ABV that ignores dilution is simply wrong.
      expect(before - after, greaterThan(3.9));
    });

    test('shaking leaves it weaker than stirring', () {
      final drink = negroni();
      expect(
        drink.abvPercentServed(Dilution.shaken) <
            drink.abvPercentServed(Dilution.stirred),
        isTrue,
      );
    });

    test('a drink built in the glass keeps its written strength', () {
      final drink = Drink(
        components: negroni().components,
        method: Method.built,
      );
      expect(
        drink.abvPercentServed(Dilution.forMethod(Method.built)),
        drink.abvPercentUndiluted(),
      );
    });
  });

  group('reaching a ceiling', () {
    test('none is needed when the drink is already under it', () {
      final drink = negroni();
      // Twenty-five percent is above the 22.7 the ice leaves, so nothing has
      // to be added.
      expect(
        drink.volumeToAddForAbvCeiling(Rational.fromInt(25), Dilution.stirred),
        Rational.zero,
      );
    });

    test('the amount to add is what the arithmetic says', () {
      final drink = negroni();
      // 24 ml of alcohol at 20 percent needs 120 ml of drink; the ice leaves
      // 105.75 ml; so 14.25 ml of something without alcohol.
      final needed = drink.volumeToAddForAbvCeiling(
        Rational.fromInt(20),
        Dilution.stirred,
      );
      expect(needed, Rational.of(14250, 1));
      expect(needed.toDouble() / 1000, closeTo(14.25, 0.001));
    });

    test('adding it actually lands on the ceiling', () {
      final drink = negroni();
      final needed = drink.volumeToAddForAbvCeiling(
        Rational.fromInt(20),
        Dilution.stirred,
      );

      final served = Dilution.stirred.dilutedVolumeOf(drink).toRational();
      final total = served + needed;
      final abv = drink.alcoholMicrolitres() / total * Rational.fromInt(100);

      expect(abv, Rational.fromInt(20));
    });

    test('a drink with no alcohol needs nothing added', () {
      const juice = Drink(
        components: [Component(volume: Volume.fromMillilitres(100))],
        method: Method.built,
      );
      expect(
        juice.volumeToAddForAbvCeiling(Rational.fromInt(5), Dilution.none),
        Rational.zero,
      );
    });

    test('a ceiling of zero is refused rather than answered with infinity', () {
      expect(
        () => negroni().volumeToAddForAbvCeiling(Rational.zero, Dilution.stirred),
        throwsArgumentError,
      );
      expect(
        () => negroni().volumeToAddForAbvCeiling(
          Rational.fromInt(-1),
          Dilution.stirred,
        ),
        throwsArgumentError,
      );
    });
  });
}
