import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/domain/units/quantity.dart';
import 'package:hollow_court/domain/units/unit_system.dart';
import 'package:hollow_court/ui/measure_text.dart';

void main() {
  Mass mg(num milligrams) => Mass.fromMilligrams(milligrams.round());

  Volume ml(num millilitres) => Volume.fromMicrolitres((millilitres * 1000).round());

  group('a volume is written in the unit the reader measures in', () {
    test('the same bottle reads differently in three units', () {
      // The point of the whole preference: 700 ml, 70 cl and 0.7 l are one quantity,
      // and which one a reader sees is their choice rather than a literal in a string.
      final wine = ml(700);

      expect(volumeText(wine, UnitSystem.millilitre), '700 ml');
      expect(volumeText(wine, UnitSystem.centilitre), '70 cl');
      expect(volumeText(wine, UnitSystem.litre), '0.7 l');
    });

    test('four ounces read as 4 oz and not as 4.0 oz', () {
      // **The case that made the rule change.** An integer microlitre cannot represent
      // 29.5735295625 µl, so no count of fluid ounces is ever exactly whole -- and a
      // formatter that printed no decimals only for exact wholes printed `4.0 oz` here.
      // Round to one decimal and drop a trailing `.0` instead, which gives `4 oz` and
      // still gives `25.4 oz`.
      final fourOunces = Volume.fromMicrolitres(118294); // 4 US fluid ounces, to the µl
      expect(volumeText(fourOunces, UnitSystem.fluidOunceUnit), '4 oz');
    });

    test('one decimal, and a trailing .0 dropped', () {
      // A column of figures with mixed precision is harder to read than a column
      // rounded the same way, and a hundredth of a millilitre is below anything a bar
      // measures -- so one decimal is the ceiling. The `.0` is dropped because that is
      // what a person writes.
      expect(volumeText(ml(750), UnitSystem.fluidOunceUnit), '25.4 oz');
      expect(volumeText(ml(700), UnitSystem.millilitre), '700 ml');
      expect(volumeText(ml(0), UnitSystem.millilitre), '0 ml');
    });

    test('a mass unit is refused by the volume formatter, which has a mass twin', () {
      // Found by writing the case above and getting a volume in ounces out of a mass unit:
      // this function converts volumes, `amountIn` refuses anything else, and the refusal is
      // the correct answer -- it stays a refusal now that `massText` exists, because the two
      // bases are not interchangeable and a formatter that answered both would be the one
      // place a caller could treat microlitres and milligrams as the same kind of thing. The
      // mass formatter is `massText`, and the test above this one is its case.
      expect(
        () => volumeText(ml(100), UnitSystem.ounceMass),
        throwsA(anything),
        reason: 'a screen that printed a mass figure for a volume would be wrong by a '
            'density and would look entirely reasonable',
      );
    });

  });

  group('a typed number becomes the base the same way a printed one is written', () {
    // **The inverse of the formatter, and the reason it belongs in the same file.** A shelf
    // prints `700 ml`; a box that a person types into has to read `700` back as the same 700
    // ml, or the two ends of one screen would disagree about what a number means.
    test('the number is written without the symbol, for a box to hold', () {
      // What `MeasureField` puts in its box when the unit menu changes under a typed number:
      // same rounding as the shelf, no unit word, because the menu beside it says that.
      expect(volumeNumber(ml(700), UnitSystem.millilitre), '700');
      expect(volumeNumber(ml(700), UnitSystem.fluidOunceUnit), '23.7');
    });

    test('the unit decides what the number is worth', () {
      expect(microlitresTyped('700', UnitSystem.millilitre), 700000);
      expect(microlitresTyped('70', UnitSystem.centilitre), 700000);
      expect(microlitresTyped('0.7', UnitSystem.litre), 700000);
    });

    test('a fraction of a unit is an ordinary thing to type', () {
      // The whole reason the volume box stopped being a whole number: `l`, `cl` and `oz` all
      // make a decimal normal, and `int.tryParse` refused `0.7` outright.
      expect(microlitresTyped('4.5', UnitSystem.centilitre), 45000);
      expect(microlitresTyped('1,5', UnitSystem.centilitre), 15000, reason:
          '`Rational.parse` takes a comma, and a person typing a recipe should not have to '
          'know that the sources are American');
    });

    test('an ounce is exact rather than rounded to a millilitre', () {
      // **The case that made `addBottle` take a Volume instead of a count of millilitres.**
      // This system's fluid ounce is the exact 29.5735295625 ml, so 25.4 of them is
      // 751 167.65 µl -- a millilitre-shaped door would have stored 751 000, and nothing on
      // any screen would have said so. A half-ounce pour is the sharper version: 14 786.76 µl
      // becomes 14 000, which is a pour five per cent short.
      expect(microlitresTyped('25.4', UnitSystem.fluidOunceUnit), 751168);
      expect(microlitresTyped('0.5', UnitSystem.fluidOunceUnit), 14787);
      expect(
        volumeText(
          Volume.fromMicrolitres(microlitresTyped('25.4', UnitSystem.fluidOunceUnit)!),
          UnitSystem.fluidOunceUnit,
        ),
        '25.4 oz',
        reason: 'a typed number printed back is the number that was typed',
      );
    });

    test('text that is not a number is refused rather than guessed at', () {
      // Null rather than an exception, because typing is not a bug -- the form has a sentence
      // for this case, and a throw would be a crash where a refusal belongs.
      expect(microlitresTyped('', UnitSystem.millilitre), isNull);
      expect(microlitresTyped('   ', UnitSystem.millilitre), isNull);
      expect(microlitresTyped('700 ml', UnitSystem.millilitre), isNull,
          reason: 'the unit is a control on the screen, so a unit in the text is not a '
              'number this can read');
      expect(microlitresTyped('about 700', UnitSystem.millilitre), isNull);
    });

    test('zero and a negative are refused, because neither is a bottle', () {
      expect(microlitresTyped('0', UnitSystem.millilitre), isNull);
      expect(microlitresTyped('0.0', UnitSystem.litre), isNull);
      expect(microlitresTyped('-700', UnitSystem.millilitre), isNull);
    });

    test('a number too large for the base is refused rather than clamped', () {
      // `volumeOf` rounds exactly and then takes an `int`, and `BigInt.toInt` clamps: without
      // this check a typed `99999999999999999 l` would be stored as the largest int there is,
      // which is a bottle nobody has. The bound is applied to the exact product, so the
      // rounding rule stays inside `volumeOf`.
      expect(microlitresTyped('9223372036854775807', UnitSystem.millilitre), isNull);
      expect(microlitresTyped('99999999999999999', UnitSystem.litre), isNull);
      // One that fits still goes through, so the refusal is a range and not a blanket.
      expect(microlitresTyped('1000', UnitSystem.litre), 1000000000);
    });
  });

  group('a mass is written the same way, on the other base', () {
    test('the same sugar reads differently in three units', () {
      // 固体用克, and the twin of the volume cases above. Nothing is shared between the two
      // functions except the shape, which is the point: `UnitSystem` has two doors because
      // the two bases are not interchangeable.
      final sugar = mg(500000); // 500 g

      expect(massText(sugar, UnitSystem.gram), '500 g');
      expect(massText(sugar, UnitSystem.kilogram), '0.5 kg');
      expect(massText(sugar, UnitSystem.milligram), '500000 mg');
    });

    test('a pound rounds to 1 lb rather than printing 1.0', () {
      // The same decimal rule as volumes, and the same reason it had to change: an integer
      // milligram cannot represent 453592.37 mg exactly, so no count of pounds is ever
      // exactly whole and "no decimals for exact wholes" would print `1.0 lb`.
      expect(massText(mg(453592), UnitSystem.pound), '1 lb');
    });

    test('grams convert to the mass ounce, which is not the fluid ounce', () {
      // 100 g / 28.349523125 g per ounce = 3.527..., and the unit id is `ozm` while the
      // label is `oz` -- the same symbol as a fluid ounce and a different unit, which is
      // the real world's problem and not one a formatter can solve.
      expect(massText(mg(100000), UnitSystem.ounceMass), '3.5 oz');
    });

    test('a volume unit is refused rather than answered with a mass', () {
      // Mirrors the refusal in the other direction. A screen that printed a volume figure
      // for a mass would be wrong by a density and would look entirely reasonable.
      expect(
        () => massText(mg(100000), UnitSystem.millilitre),
        throwsA(anything),
      );
    });
  });

  group('a mass is entered the same way, on the other base', () {
    // **The pair the domain was missing a door for.** `UnitSystem.massOf` did not exist, so
    // the volume side could go in (`volumeOf`) while the mass side could only come out
    // (`milligramsOf`) -- which is why 固体用克 was half an instruction nobody could follow.
    test('the unit decides what the number is worth', () {
      expect(milligramsTyped('500', UnitSystem.gram), 500000);
      expect(milligramsTyped('0.5', UnitSystem.kilogram), 500000);
      expect(milligramsTyped('1', UnitSystem.pound), 453592,
          reason: '453 592.37 mg, rounded once, in the domain and nowhere else');
    });

    test('a mass ounce is not a fluid ounce', () {
      // The same symbol on two different units is the real world's problem, and the two entry
      // points must not become one function: `oz` beside a solid is `ozm` and means
      // 28.349523125 g, not 29.5735295625 ml.
      expect(milligramsTyped('1', UnitSystem.ounceMass), 28350);
      expect(microlitresTyped('1', UnitSystem.fluidOunceUnit), 29574);
      expect(UnitSystem.ounceMass.symbol, UnitSystem.fluidOunceUnit.symbol);
    });

    test('a typed mass prints back as the number that was typed', () {
      expect(
        massText(
          Mass.fromMilligrams(milligramsTyped('500', UnitSystem.gram)!),
          UnitSystem.gram,
        ),
        '500 g',
      );
      expect(massNumber(Mass.fromMilligrams(500000), UnitSystem.kilogram), '0.5');
    });

    test('the refusals are the volume ones, because the reading is shared', () {
      expect(milligramsTyped('', UnitSystem.gram), isNull);
      expect(milligramsTyped('500 g', UnitSystem.gram), isNull);
      expect(milligramsTyped('0', UnitSystem.gram), isNull);
      expect(milligramsTyped('-5', UnitSystem.gram), isNull);
      expect(milligramsTyped('99999999999999999', UnitSystem.kilogram), isNull,
          reason: 'past 2^63 milligrams, refused rather than clamped');
      expect(milligramsTyped('1,5', UnitSystem.kilogram), 1500000);
    });
  });
}
