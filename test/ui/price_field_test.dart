import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/domain/pricing/price.dart';
import 'package:hollow_court/ui/amount_row.dart';
import 'package:hollow_court/ui/money_text.dart';
import 'package:hollow_court/ui/price_field.dart';

/// A price is a number and a currency, and **the currency menu reinterprets the number rather
/// than converting it** -- the one place this differs from `MeasureField`, and the reason this
/// file exists separately.
void main() {
  const slots = [Currency.cny, Currency.usd, Currency.jpy];

  Future<TextEditingController> pumpField(
    WidgetTester tester, {
    List<Currency> currencies = slots,
    Currency? currency,
    String text = '45.50',
  }) async {
    final controller = TextEditingController(text: text);
    var chosen = currency ?? currencies.first;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => PriceField(
              id: 'test-price',
              label: '价格',
              currencyLabel: '币种',
              controller: controller,
              currencies: currencies,
              currency: chosen,
              onCurrencyChanged: (picked) => setState(() => chosen = picked),
            ),
          ),
        ),
      ),
    );
    return controller;
  }

  group('a price is a number and a currency side by side', () {
    testWidgets('the number is in a box and the currency is a menu', (tester) async {
      await pumpField(tester);

      expect(find.byKey(AmountRow.valueKeyFor('test-price')), findsOneWidget);
      expect(find.byKey(AmountRow.menuKeyFor('test-price')), findsOneWidget);
      expect(find.text('价格'), findsOneWidget);
      expect(find.text('币种'), findsOneWidget);
      // **The label no longer names a minor unit.** It read 价格（分）, which is one currency's
      // hundredth written into a label and wrong for a yen.
      expect(find.textContaining('分'), findsNothing);
    });

    testWidgets('the menu opens on the reader primary slot', (tester) async {
      await pumpField(tester);
      expect(
        find.descendant(
          of: find.byKey(AmountRow.menuKeyFor('test-price')),
          matching: find.text('CNY'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the menu shows codes, not symbols, because ¥ is two currencies', (tester) async {
      // A picker offering `¥` twice would be a picker nobody could choose from. Section 12.4's
      // rule that a person never reads the code is about what travels on the wire; this is the
      // one place the ambiguity has to be on screen.
      await pumpField(tester);

      await tester.tap(find.byKey(AmountRow.menuKeyFor('test-price')));
      await tester.pumpAndSettle();

      expect(find.text('USD'), findsOneWidget);
      expect(find.text('JPY'), findsOneWidget);
      expect(find.text('¥'), findsNothing);
    });

    testWidgets('the two boxes are one line, not two heights', (tester) async {
      // The layout defect that was found in the measurement field, checked here too: the row
      // is shared, so the fix is shared, and this is the assertion that says the sharing
      // actually happened rather than a second copy of the row growing back.
      await pumpField(tester);

      final decorators = find.byType(InputDecorator);
      expect(decorators, findsNWidgets(2));
      final number = tester.getRect(decorators.at(0));
      final currency = tester.getRect(decorators.at(1));
      expect(currency.top, moreOrLessEquals(number.top, epsilon: 1));
      expect(currency.height, moreOrLessEquals(number.height, epsilon: 1));
    });
  });

  group('changing the currency keeps the digits and changes the meaning', () {
    testWidgets('45.50 stays 45.50 when the menu moves to JPY', (tester) async {
      // **The opposite of the measurement field, and deliberately so.** 700 ml switched to cl
      // becomes 70 because the two are names for one quantity; 45.50 CNY switched to JPY stays
      // 45.50 because a yuan and a yen have no ratio this program knows -- it has no exchange
      // rates and section 7's series is denominated per currency. Converting would need a rate
      // nobody has, and inventing one would move a number by an amount no screen could show.
      final controller = await pumpField(tester, text: '45.50');

      await tester.tap(find.byKey(AmountRow.menuKeyFor('test-price')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('JPY').last);
      await tester.pumpAndSettle();

      expect(controller.text, '45.50');
    });

    testWidgets('and the same digits are read as a different amount', (tester) async {
      // What "reinterpret" means for the stored value, which is where it matters: the digits did
      // not move and the amount did. 45.50 in a CNY slot is 4550 minor units; in a JPY slot it is
      // forty-five and a half yen, which does not exist -- so the form refuses it and says so
      // rather than rounding to 46 behind the reader's back.
      expect(minorUnitsTyped('45.50', Currency.cny), 4550);
      expect(minorUnitsTyped('45.50', Currency.jpy), isNull);
      expect(minorUnitsTyped('46', Currency.jpy), 46);
    });
  });
}
