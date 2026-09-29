import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/domain/units/unit.dart';
import 'package:hollow_court/domain/units/unit_system.dart';
import 'package:hollow_court/ui/amount_row.dart';
import 'package:hollow_court/ui/l10n/locale_providers.dart';
import 'package:hollow_court/ui/l10n/locale_settings.dart';
import 'package:hollow_court/ui/measure_field.dart';

/// The number on the left, the unit on the right -- and what happens to the number when the
/// unit changes under it.
void main() {
  /// A field a test can drive: the caller owns the unit and the text, exactly as the form does.
  Future<TextEditingController> pumpField(
    WidgetTester tester, {
    required List<Unit> units,
    Unit? unit,
    String text = '700',
  }) async {
    final controller = TextEditingController(text: text);
    var chosen = unit ?? units.first;

    // **A scope, and the language pinned to 简中.** The field shows each unit's *name* in the reader's
    // language now (`unit_labels.dart`), so a test without a locale would assert against whatever
    // language the machine reports -- and the names would differ from the ones written below.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localeSettingsProvider.overrideWith(
            () => _FixedLocale(
              const LocaleSettings(
                primaryTag: 'zh-Hans',
                secondaryTag: 'en',
                dualCopy: false,
              ),
            ),
          ),
        ],
        child: MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => MeasureField(
              id: 'test-volume',
              label: '容量',
              unitLabel: '单位',
              controller: controller,
              units: units,
              unit: chosen,
              onUnitChanged: (picked) => setState(() => chosen = picked),
            ),
          ),
          ),
        ),
      ),
    );
    return controller;
  }

  const metric = [UnitSystem.millilitre, UnitSystem.centilitre, UnitSystem.litre];
  const american = [UnitSystem.fluidOunceUnit, UnitSystem.millilitre];

  group('a measurement is a number and a unit side by side', () {
    testWidgets('the number is in a box and the unit is a menu', (tester) async {
      await pumpField(tester, units: metric);

      expect(find.byKey(AmountRow.valueKeyFor('test-volume')), findsOneWidget);
      expect(find.byKey(AmountRow.menuKeyFor('test-volume')), findsOneWidget);
      expect(find.text('容量'), findsOneWidget);
      expect(find.text('单位'), findsOneWidget);
      // **The label no longer names a unit**, which is the whole change: 容量（毫升） was a millilitre
      // bottle and nothing else. `毫升` *does* appear now -- as the millilitre's name in the unit menu,
      // which is where a reader choosing a unit should meet the word -- so the assertion is that the
      // *label* does not contain it rather than that the screen does not.
      expect(
        find.descendant(
          of: find.byKey(AmountRow.valueKeyFor('test-volume')),
          matching: find.textContaining('毫升'),
        ),
        findsNothing,
      );
      expect(find.text('毫升'), findsWidgets,
          reason: 'the menu names the unit in the language the reader chose');
    });

    testWidgets('the first unit offered is the one it opens on', (tester) async {
      // The reader's primary comes first in their own measure set, so a metric reader opens
      // on millilitres and an American one on ounces without touching anything.
      await pumpField(tester, units: american);
      expect(
        find.descendant(
          of: find.byKey(AmountRow.menuKeyFor('test-volume')),
          matching: find.text('液量盎司'),
        ),
        findsOneWidget,
      );

      await pumpField(tester, units: metric);
      expect(
        find.descendant(
          of: find.byKey(AmountRow.menuKeyFor('test-volume')),
          matching: find.text('毫升'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the menu offers exactly the units it was given', (tester) async {
      // **Not every unit this system carries.** A shelf set is the reader's own four, and a
      // menu that offered a dash for a bottle of gin would be a menu nobody could use.
      await pumpField(tester, units: american);

      await tester.tap(find.byKey(AmountRow.menuKeyFor('test-volume')));
      await tester.pumpAndSettle();

      // **The menu shows names, not symbols.** A reader choosing between a teaspoon and a tablespoon is
      // choosing between two words, and `ml / cl / oz` is a menu of abbreviations; the *symbol* is what
      // follows a number on the shelf, and the number here is unaccompanied.
      expect(find.text('毫升'), findsOneWidget, reason: 'the second one is offered');
      expect(find.text('厘升'), findsNothing);
      expect(find.text('升'), findsNothing);
      expect(find.text('dash'), findsNothing);
    });

    testWidgets('the two boxes are one line, not two heights', (tester) async {
      // **A layout check, because nothing else in this file can see it.** The number box is a
      // `TextField` and the menu is an `InputDecorator` around a `DropdownButton`; two controls
      // built from different widgets are the usual way a form ends up with one box taller than
      // the other along the same row, and that is a thing you only find by looking. The
      // `TextField` builds an `InputDecorator` of its own, so there are two in the tree and they
      // are the two being compared.
      await pumpField(tester, units: metric);

      final decorators = find.byType(InputDecorator);
      expect(decorators, findsNWidgets(2));

      final number = tester.getRect(decorators.at(0));
      final unit = tester.getRect(decorators.at(1));
      expect(unit.top, moreOrLessEquals(number.top, epsilon: 1));
      expect(unit.height, moreOrLessEquals(number.height, epsilon: 1));
    });
  });

  group('changing the unit keeps the amount rather than the digits', () {
    testWidgets('700 ml becomes 70 cl when the menu changes', (tester) async {
      // **The judgement this widget makes.** The number is a statement about a bottle and the
      // unit is only how it is said, so switching the menu re-says it -- the same reason a
      // changed preference redraws every bottle instead of relabelling it. Reinterpreting
      // instead would turn `700` into 700 cl under the reader's hands.
      final controller = await pumpField(
        tester,
        units: metric,
        unit: UnitSystem.millilitre,
        text: '700',
      );

      await tester.tap(find.byKey(AmountRow.menuKeyFor('test-volume')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('厘升').last);
      await tester.pumpAndSettle();

      expect(controller.text, '70');
    });

    testWidgets('700 ml becomes 23.7 oz, rounded the way a shelf rounds', (tester) async {
      // One decimal and a trailing `.0` dropped, through the same formatter the shelf uses:
      // `volumeNumber`. A box that rounded differently from the label beside it would be a
      // box a person could not check.
      final controller = await pumpField(
        tester,
        units: american,
        unit: UnitSystem.millilitre,
        text: '700',
      );

      await tester.tap(find.byKey(AmountRow.menuKeyFor('test-volume')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('液量盎司').last);
      await tester.pumpAndSettle();

      expect(controller.text, '23.7');
    });

    testWidgets('a box that holds no number is left exactly as it was', (tester) async {
      // **A unit switch is not a reason to delete what somebody was saying.** An empty box and
      // a half-typed one have no amount to keep, and rewriting either would be the form
      // arguing with the reader.
      final controller = await pumpField(
        tester,
        units: metric,
        unit: UnitSystem.millilitre,
        text: '',
      );

      await tester.tap(find.byKey(AmountRow.menuKeyFor('test-volume')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('厘升').last);
      await tester.pumpAndSettle();

      expect(controller.text, '');
    });

    testWidgets('a typed comma survives a unit change, read the way it is parsed', (tester) async {
      // `Rational.parse` accepts a comma as a decimal separator, so `0,5` is half a litre --
      // and the conversion has to read it through that same door rather than through
      // `double.parse`, which would refuse it and leave the box holding a number the form
      // would later reject.
      final controller = await pumpField(
        tester,
        units: metric,
        unit: UnitSystem.litre,
        text: '0,5',
      );

      await tester.tap(find.byKey(AmountRow.menuKeyFor('test-volume')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('毫升').last);
      await tester.pumpAndSettle();

      expect(controller.text, '500');
    });
  });
}

/// A locale that answers 简中 rather than whatever this machine reports.
class _FixedLocale extends LocaleSettingsNotifier {
  _FixedLocale(this._initial);

  final LocaleSettings _initial;

  @override
  LocaleSettings build() => _initial;
}
