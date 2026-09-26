import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/domain/preferences/choice_set.dart';
import 'package:hollow_court/domain/pricing/price.dart';
import 'package:hollow_court/ui/choice_set_editor.dart';

/// A set to edit, and a record of what the editor asked for.
late ChoiceSet<Currency> _value;
late List<ChoiceSet<Currency>> _asked;

Future<void> pumpEditor(
  WidgetTester tester, {
  required ChoiceSet<Currency> start,
}) async {
  _value = start;
  _asked = [];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => ChoiceSetEditor<Currency>(
            value: _value,
            options: Currency.all,
            labelOf: (currency) => currency.code,
            keyOf: (currency) => currency.code,
            addPrompt: 'Add',
            onChanged: (next) {
              _asked.add(next);
              setState(() => _value = next);
            },
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  /// The bug the owner reported, as a number.
  ///
  /// **A `DropdownButton` sizes its menu to its items**, and the measure editors offer every unit of
  /// a dimension: eleven for a liquid, sixteen for `either`. Sixteen rows at the default 48 pixels is
  /// 768 tall, which is taller than a phone's usable height and taller than a 720-pixel desktop
  /// window -- so the expanded list covered the very setting it was changing, on all three
  /// platforms. This asserts the ceiling rather than the look, because the look needs eyes and the
  /// ceiling is what makes the look acceptable.
  group('an expanded menu is bounded instead of covering the screen', () {
    testWidgets('the primary menu is at most half the window tall', (tester) async {
      tester.view.physicalSize = const Size(400, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pumpEditor(
        tester,
        start: ChoiceSet<Currency>(primary: Currency.cny, secondary: [Currency.usd]),
      );

      // Four currencies in this fixture, so the menu is short; the check that matters is against the
      // bound rather than against the item count, because the item count is what varies.
      expect(
        tester.widget<DropdownButton<String>>(find.byType(DropdownButton<String>)).menuMaxHeight,
        lessThanOrEqualTo(350),
      );
      expect(
        tester.widget<DropdownButton<String>>(find.byType(DropdownButton<String>)).menuMaxHeight,
        lessThanOrEqualTo(700 * 0.5 + 1),
        reason: 'and never more than half of a short window',
      );
    });

    testWidgets('the add-a-secondary menu carries the same ceiling', (tester) async {
      // The second door onto the same list. It is at its longest when nothing has been chosen yet,
      // which is exactly when a reader is hunting for one unit among sixteen.
      await pumpEditor(
        tester,
        start: ChoiceSet<Currency>(primary: Currency.cny),
      );

      final popup = tester.widget<PopupMenuButton<Currency>>(
        find.byType(PopupMenuButton<Currency>),
      );
      expect(popup.constraints?.maxHeight, lessThanOrEqualTo(350));
    });
  });

  testWidgets('the primary and every secondary are on screen', (tester) async {
    await pumpEditor(
      tester,
      start: ChoiceSet<Currency>(
        primary: Currency.cny,
        secondary: [Currency.usd, Currency.eur],
      ),
    );

    expect(find.text('CNY'), findsWidgets);
    expect(find.byKey(const ValueKey('secondary-USD')), findsOneWidget);
    expect(find.byKey(const ValueKey('secondary-EUR')), findsOneWidget);
  });

  testWidgets('adding a secondary asks for a set that contains it',
      (tester) async {
    await pumpEditor(tester, start: ChoiceSet<Currency>(primary: Currency.cny));

    await tester.tap(find.byKey(const ValueKey('add-secondary')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('JPY').last);
    await tester.pumpAndSettle();

    expect(_asked, hasLength(1));
    expect(_asked.single.all.map((c) => c.code), ['CNY', 'JPY']);
  });

  testWidgets('an option already in the set is not offered again',
      (tester) async {
    // 都不可重复, as the reader meets it: the second copy of a currency is not in the
    // menu, so it cannot be chosen twice. `ChoiceSet` would refuse it anyway, which is
    // why this is presentation and not enforcement -- but a menu that offered it and
    // then did nothing would be the worse screen.
    await pumpEditor(
      tester,
      start: ChoiceSet<Currency>(
        primary: Currency.cny,
        secondary: [Currency.usd],
      ),
    );

    await tester.tap(find.byKey(const ValueKey('add-secondary')));
    await tester.pumpAndSettle();

    // Counted inside the menu rather than on the whole screen: the secondary chip for
    // USD is also a `Text` with that word, so a bare `find.text('USD')` found the chip
    // and the first version of this test failed for that reason and not because the
    // menu offered a duplicate.
    Finder inMenu(String code) => find.descendant(
      of: find.byType(PopupMenuItem<Currency>),
      matching: find.text(code),
    );
    expect(inMenu('JPY'), findsOneWidget, reason: 'not in the set, so offered');
    expect(inMenu('USD'), findsNothing, reason: 'already a secondary, so not offered');
  });

  testWidgets('removing a secondary asks for a set without it', (tester) async {
    await pumpEditor(
      tester,
      start: ChoiceSet<Currency>(
        primary: Currency.cny,
        secondary: [Currency.usd, Currency.eur],
      ),
    );

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('secondary-EUR')),
        matching: find.byIcon(Icons.close),
      ),
    );
    await tester.pumpAndSettle();

    expect(_asked.single.all.map((c) => c.code), ['CNY', 'USD']);
  });

  testWidgets('promoting a secondary swaps it to the front and keeps it',
      (tester) async {
    // `ChoiceSet.promote`'s rule, seen from the screen: a reader who puts euro first
    // has not asked to lose it from the second slot. Nothing is dropped.
    // HKD and not EUR: a `DropdownButton` lays its menu out lazily, so an item below
    // the fold is never built and cannot be tapped -- the first version reached for EUR
    // (sixth in the list) and hit HKD instead, which is a test hitting the wrong widget
    // and not the editor doing the wrong thing.
    await pumpEditor(
      tester,
      start: ChoiceSet<Currency>(
        primary: Currency.cny,
        secondary: [Currency.hkd],
      ),
    );

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('HKD').last);
    await tester.pumpAndSettle();

    // The old primary leaves rather than being dropped silently into a second slot: it
    // was the reader's first choice and the set holds what they chose.
    expect(_asked.single.all.map((c) => c.code), ['HKD', 'CNY']);
  });

  testWidgets('a full set offers no add control with anything in it',
      (tester) async {
    // Three secondaries is the cap. The chip stays on screen so the row does not
    // reflow, and it opens nothing -- an empty menu would be worse than a flat one.
    await pumpEditor(
      tester,
      start: ChoiceSet<Currency>(
        primary: Currency.cny,
        secondary: [Currency.usd, Currency.eur, Currency.gbp],
      ),
    );

    final add = tester.widget<PopupMenuButton<Currency>>(
      find.byKey(const ValueKey('add-secondary')),
    );
    expect(add.enabled, isFalse);
  });
}
