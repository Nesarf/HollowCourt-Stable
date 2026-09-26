import 'package:hollow_court/domain/dosing/abv.dart';
import 'package:hollow_court/domain/dosing/dilution.dart';
import 'package:hollow_court/domain/dosing/scaling.dart';
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
  group('by volume', () {
    test('doubling the liquid doubles every line in it', () {
      final doubled = Scaling.toUndilutedVolume(
        negroni(),
        Volume.fromMillilitres(180),
      );

      expect(doubled.undilutedVolume.microlitres, 180000);
      for (final component in doubled.components) {
        expect(component.volume.microlitres, 60000);
      }
    });

    test('halving it keeps the ratio and the strength', () {
      final half = Scaling.toUndilutedVolume(
        negroni(),
        Volume.fromMillilitres(45),
      );

      expect(half.undilutedVolume.microlitres, 45000);
      // A recipe is a ratio, so resizing leaves the strength exactly where it
      // was. This is the fact that makes the ceiling case below the odd one.
      expect(
        half.abvPercentUndiluted(),
        negroni().abvPercentUndiluted(),
      );
    });

    test('a drink with nothing in it cannot be scaled', () {
      const empty = Drink(components: [], method: Method.stirred);
      expect(
        () => Scaling.toUndilutedVolume(empty, Volume.fromMillilitres(100)),
        throwsArgumentError,
      );
    });
  });

  group('by what the glass holds', () {
    test('the room in a glass is its capacity less the ice', () {
      // Section 5.6's own arithmetic: a 200 ml glass with ice in it leaves
      // about 120 ml.
      expect(
        Scaling.workingVolumeOf(
          Volume.fromMillilitres(200),
          iceDisplacement: Volume.fromMillilitres(80),
        ).microlitres,
        120000,
      );
    });

    test('more ice than glass leaves no room rather than negative room', () {
      expect(
        Scaling.workingVolumeOf(
          Volume.fromMillilitres(200),
          iceDisplacement: Volume.fromMillilitres(250),
        ),
        Volume.zero,
      );
    });

    test('fitting a glass lands the served volume on the room available', () {
      final fitted = Scaling.toFit(
        negroni(),
        Volume.fromMillilitres(120),
        Dilution.stirred,
      );

      final served = Dilution.stirred.dilutedVolumeOf(fitted);
      expect((served.microlitres - 120000).abs(), lessThanOrEqualTo(2));
    });

    test('fitting a bigger glass makes more drink, not a stronger one', () {
      final small = Scaling.toFit(
        negroni(),
        Volume.fromMillilitres(120),
        Dilution.stirred,
      );
      final large = Scaling.toFit(
        negroni(),
        Volume.fromMillilitres(240),
        Dilution.stirred,
      );

      expect(large.undilutedVolume > small.undilutedVolume, isTrue);

      // The ratio is preserved exactly, but each component is a whole number
      // of microlitres, so the strength cannot come out identical to the last
      // decimal: a 34 ml pour is rounded proportionally harder than a 68 ml
      // one. The difference is in the fourth decimal place, and this test says
      // so rather than pretending otherwise.
      expect(
        large.abvPercentServed(Dilution.stirred).toDouble(),
        closeTo(small.abvPercentServed(Dilution.stirred).toDouble(), 0.001),
      );
    });
  });

  group('by parts', () {
    test('naming one line sizes the whole drink', () {
      // "Two ounces of gin" is how somebody with a jigger actually starts.
      final sized = Scaling.toComponentVolume(
        negroni(),
        0,
        Volume.fromMillilitres(60),
      );

      expect(sized.components[0].volume.microlitres, 60000);
      expect(sized.components[1].volume.microlitres, 60000);
      expect(sized.undilutedVolume.microlitres, 180000);
    });

    test('an index outside the drink is refused', () {
      expect(
        () => Scaling.toComponentVolume(negroni(), 3, Volume.fromMillilitres(30)),
        throwsRangeError,
      );
      expect(
        () => Scaling.toComponentVolume(negroni(), -1, Volume.fromMillilitres(30)),
        throwsRangeError,
      );
    });

    test('a line with nothing in it cannot be scaled to', () {
      final drink = Drink(
        method: Method.stirred,
        components: [
          Component(volume: Volume.zero, abvPercent: Rational.fromInt(40)),
          const Component(volume: Volume.fromMicrolitres(30000)),
        ],
      );
      expect(
        () => Scaling.toComponentVolume(drink, 0, Volume.fromMillilitres(30)),
        throwsArgumentError,
      );
    });
  });

  group('a strength ceiling is not a scale factor', () {
    test('scaling to a ceiling changes nothing, because it cannot', () {
      final drink = negroni();
      final attempted = Scaling.toAbvCeiling(drink, Rational.fromInt(10));

      // The method exists to make this explicit rather than to do something.
      // Resizing a ratio leaves the ratio alone, so a caller who reached for
      // scaling to weaken a drink would get a stronger one than they expected
      // and no warning.
      expect(attempted.undilutedVolume, drink.undilutedVolume);
      expect(attempted.abvPercentUndiluted(), drink.abvPercentUndiluted());
    });

    test('what actually works is adding something without alcohol', () {
      final drink = negroni();
      final needed = drink.volumeToAddForAbvCeiling(
        Rational.fromInt(15),
        Dilution.stirred,
      );

      expect(needed.isZero, isFalse);
      final served = Dilution.stirred.dilutedVolumeOf(drink).toRational();
      final abv = drink.alcoholMicrolitres() /
          (served + needed) *
          Rational.fromInt(100);
      expect(abv, Rational.fromInt(15));
    });

    test('asking whether a drink fits under a ceiling', () {
      final drink = negroni();
      expect(drink.fitsUnderAbv(Rational.fromInt(23), Dilution.stirred), isTrue);
      expect(drink.fitsUnderAbv(Rational.fromInt(22), Dilution.stirred), isFalse);
    });

    test('one more splash is visible in the number', () {
      final drink = negroni();
      final asServed = drink.abvPercentServed(Dilution.stirred);
      final withSplash = drink.abvPercentWithExtraDiluent(
        Rational.of(20, 100),
        Dilution.stirred,
      );

      expect(withSplash < asServed, isTrue);
      expect(withSplash.toDouble(), closeTo(18.912, 0.01));
    });

    test('adding nothing changes nothing', () {
      final drink = negroni();
      expect(
        drink.abvPercentWithExtraDiluent(Rational.zero, Dilution.stirred),
        drink.abvPercentServed(Dilution.stirred),
      );
      expect(
        () => drink.abvPercentWithExtraDiluent(
          Rational.fromInt(-1),
          Dilution.stirred,
        ),
        throwsArgumentError,
      );
    });
  });
}
