import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/domain/pricing/price.dart';
import 'package:hollow_court/ui/money_text.dart';

/// A price out, and a price in. **The two directions live in one file so they cannot disagree
/// about what a currency's digits are** -- which is the whole trap this pair exists to close.
void main() {
  group('a price is written in the currency it is denominated in', () {
    test('two digits for most, none for a yen, and the code after it', () {
      expect(moneyText(Money.fromMinorUnits(4550, Currency.cny)), '45.50 CNY');
      expect(moneyText(Money.fromMinorUnits(1200, Currency.jpy)), '1200 JPY');
      expect(moneyText(Money.fromMinorUnits(1200, Currency.krw)), '1200 KRW');
    });

    test('zero decimals does not mean zero precision', () {
      // The case a "divide by a hundred" formatter gets wrong, quietly and consistently: a
      // Japanese price shown at a hundredth of itself on exactly one screen.
      expect(moneyText(Money.fromMinorUnits(1, Currency.jpy)), '1 JPY');
      expect(moneyText(Money.fromMinorUnits(1, Currency.cny)), '0.01 CNY');
    });
  });

  group('a typed price becomes minor units, exactly', () {
    test('the currency decides how many digits the number has', () {
      expect(minorUnitsTyped('45.50', Currency.cny), 4550);
      expect(minorUnitsTyped('45,50', Currency.cny), 4550,
          reason: 'one number reader for the whole application, comma included');
      expect(minorUnitsTyped('45', Currency.cny), 4500);
      expect(minorUnitsTyped('1200', Currency.jpy), 1200,
          reason: 'a yen has no minor unit, so 1200 is twelve hundred of them');
    });

    test('the same digits in two currencies are two different amounts', () {
      // **The bug the currency menu closes.** `1200` in a JPY slot and `1200` in a CNY slot
      // used to be the same number of minor units with a label naming neither.
      expect(minorUnitsTyped('1200', Currency.jpy), 1200);
      expect(minorUnitsTyped('1200', Currency.cny), 120000);
    });

    test('rounding is not involved, because the parsing is exact', () {
      // 45.50 x 100 through a `double` is 4549.999999999999 on some inputs; through `Rational`
      // it is 4550 and nothing has to be rescued afterwards.
      expect(minorUnitsTyped('0.01', Currency.cny), 1);
      expect(minorUnitsTyped('0.07', Currency.cny), 7);
      expect(minorUnitsTyped('1234567.89', Currency.cny), 123456789);
    });

    test('what goes in comes back out as the same amount', () {
      // The property a form actually needs: printing a typed price and reading it again is a
      // no-op. Compared as **amounts and not as text**, because `7` in CNY is seven yuan and
      // prints as `7.00 CNY` -- the formatter shows a currency's digits whether or not the typist
      // did, and a round trip that demanded the same string would be testing the typist.
      //
      // The samples are per currency on purpose: `45.50` is a price in CNY and not one in JPY,
      // and the pair below is the whole rule. A single list of texts run through both currencies
      // would have to contain something one of them must refuse.
      // Not `const`: a `Currency` overrides `==`, and Dart refuses a const map whose keys do
      // that -- which is the language telling the truth, since two CNY slots are one key.
      final samples = <Currency, List<String>>{
        Currency.cny: ['45.50', '0.01', '1200', '7'],
        Currency.jpy: ['1200', '7', '0'],
      };

      for (final entry in samples.entries) {
        for (final text in entry.value) {
          final typed = minorUnitsTyped(text, entry.key)!;
          final printed = moneyText(Money.fromMinorUnits(typed, entry.key));
          final reread = minorUnitsTyped(printed.split(' ').first, entry.key);

          expect(printed.endsWith(entry.key.code), isTrue);
          expect(
            reread,
            typed,
            reason: '$text in ${entry.key.code} came back as $printed',
          );
        }
      }
    });

    test('an amount finer than the currency is refused rather than rounded', () {
      // **The refusal the first version of this function did not have.** `45.50` in a JPY slot is
      // forty-five and a half yen; `roundHalfUpToBigInt` would have stored 46 -- a number nobody
      // typed, silently, which is exactly what this file exists to prevent. `0.001` in CNY is a
      // tenth of a fen and refused for the same reason.
      expect(minorUnitsTyped('45.50', Currency.jpy), isNull);
      expect(minorUnitsTyped('0.001', Currency.cny), isNull);
      expect(minorUnitsTyped('0.01', Currency.cny), 1,
          reason: 'the smallest amount CNY can hold is fine');
      expect(minorUnitsTyped('45', Currency.jpy), 45);
    });

    test('text that is not a number is refused rather than guessed at', () {
      expect(minorUnitsTyped('', Currency.cny), isNull);
      expect(minorUnitsTyped('  ', Currency.cny), isNull);
      expect(minorUnitsTyped('45 yuan', Currency.cny), isNull,
          reason: 'the currency is a control on the screen, so one in the text is not a number');
      expect(minorUnitsTyped('about 45', Currency.cny), isNull);
    });

    test('a negative price is refused, because a refund is not a purchase', () {
      expect(minorUnitsTyped('-45', Currency.cny), isNull);
    });

    test('an amount too large for the base is refused rather than clamped', () {
      // `BigInt.toInt` clamps, so without the guard a typed number beyond 64 bits would become
      // the largest integer there is -- a price nobody paid, and nothing on screen to say so.
      //
      // **The bound is on the minor units, so it moves with the currency**, which is the part
      // worth writing down: the largest `int` is 9 223 372 036 854 775 807, so a quantity of
      // 10^17 fits in a JPY slot untouched and overflows a CNY one the moment it is multiplied
      // by a hundred. The first version of this test asserted null for both and the JPY case
      // failed, correctly.
      expect(minorUnitsTyped('99999999999999999', Currency.cny), isNull);
      expect(minorUnitsTyped('99999999999999999', Currency.jpy), 99999999999999999,
          reason: '10^17 minor units is inside an int when nothing scales it');
      expect(minorUnitsTyped('99999999999999999999', Currency.jpy), isNull,
          reason: '10^20 is past 2^63 before any currency gets a chance to scale it');
      expect(minorUnitsTyped('1000000', Currency.jpy), 1000000,
          reason: 'the refusal is a range rather than a blanket');
    });
  });
}
