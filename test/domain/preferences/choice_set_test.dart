import 'package:test/test.dart';

import 'package:hollow_court/domain/preferences/choice_set.dart';

/// The one structure both preferences are built from, and the invariants the instruction
/// states: one primary, at most three secondary, and no repetition among the four.
///
/// Written against `package:test` and run on the plain Dart VM, which is also the evidence
/// that this layer imports no Flutter -- it can be reasoned about with nothing loaded.
void main() {
  group('the shape the instruction asks for', () {
    test('a primary alone is a valid set', () {
      final set = ChoiceSet<String>(primary: 'CNY');
      expect(set.primary, 'CNY');
      expect(set.secondary, isEmpty);
      expect(set.all, <String>['CNY']);
      expect(set.isFull, isFalse);
    });

    test('four choices in total is the ceiling, and it is enforced', () {
      final full = ChoiceSet<String>(
        primary: 'CNY',
        secondary: <String>['USD', 'EUR', 'JPY'],
      );
      expect(full.isFull, isTrue);
      expect(full.all.length, 4);
      expect(() => full.addSecondary('HKD'), throwsStateError);
    });

    test('a repetition is refused at construction', () {
      // Both directions, because a caller can arrive at either: the primary listed again
      // among the alternates, or the alternates repeating one another.
      expect(
        () => ChoiceSet<String>(primary: 'CNY', secondary: <String>['CNY']),
        throwsArgumentError,
      );
      expect(
        () => ChoiceSet<String>(primary: 'CNY', secondary: <String>['USD', 'USD']),
        throwsArgumentError,
      );
      expect(
        () => ChoiceSet<String>(
          primary: 'CNY',
          secondary: <String>['USD', 'EUR', 'JPY', 'HKD'],
        ),
        throwsArgumentError,
      );
    });

    test('the list of choices cannot be edited from outside', () {
      final set = ChoiceSet<String>(primary: 'CNY', secondary: <String>['USD']);
      expect(() => set.secondary.add('EUR'), throwsUnsupportedError);
    });
  });

  group('promoting is the operation with two behaviours', () {
    test('promoting a secondary swaps, so nothing is lost', () {
      // A reader who makes 欧元 primary must not thereby lose the currency they had.
      final set = ChoiceSet<String>(primary: 'CNY', secondary: <String>['USD', 'EUR'])
          .promote('EUR');
      expect(set.primary, 'EUR');
      expect(set.secondary, <String>['USD', 'CNY']);
      expect(set.all.length, 3);
    });

    test('promoting something absent lets the old primary leave', () {
      final set = ChoiceSet<String>(primary: 'CNY', secondary: <String>['USD'])
          .promote('HKD');
      expect(set.primary, 'HKD');
      expect(set.secondary, <String>['USD']);
      expect(set.contains('CNY'), isFalse,
          reason: 'the reader replaced it; keeping it would exceed nothing but surprise');
    });

    test('promoting the primary is not a change', () {
      final set = ChoiceSet<String>(primary: 'CNY', secondary: <String>['USD']);
      expect(set.promote('CNY').primary, 'CNY');
      expect(set.promote('CNY').secondary, <String>['USD']);
    });
  });

  group('replacing a secondary in place', () {
    test('is what a picker offers, and keeps the order', () {
      final set = ChoiceSet<String>(primary: 'CNY', secondary: <String>['USD', 'EUR'])
          .withSecondaryAt(1, 'JPY');
      expect(set.secondary, <String>['USD', 'JPY']);
      expect(set.primary, 'CNY');
    });

    test('refuses a value that is already in another slot', () {
      // Not a replacement: a duplicate arriving through the back door.
      final set = ChoiceSet<String>(primary: 'CNY', secondary: <String>['USD', 'EUR']);
      expect(() => set.withSecondaryAt(1, 'USD'), throwsArgumentError);
      expect(() => set.withSecondaryAt(1, 'CNY'), throwsArgumentError);
    });

    test('re-setting a slot to what it already holds is allowed', () {
      final set = ChoiceSet<String>(primary: 'CNY', secondary: <String>['USD']);
      expect(set.withSecondaryAt(0, 'USD').secondary, <String>['USD']);
    });

    test('refuses a slot that does not exist', () {
      final set = ChoiceSet<String>(primary: 'CNY', secondary: <String>['USD']);
      expect(() => set.withSecondaryAt(1, 'EUR'), throwsRangeError);
      expect(() => set.withSecondaryAt(-1, 'EUR'), throwsRangeError);
    });
  });

  group('adding and removing', () {
    test('adding refuses a duplicate', () {
      final set = ChoiceSet<String>(primary: 'CNY', secondary: <String>['USD']);
      expect(() => set.addSecondary('USD'), throwsArgumentError);
      expect(() => set.addSecondary('CNY'), throwsArgumentError);
    });

    test('adding appends, so the reader\'s order survives', () {
      final set = ChoiceSet<String>(primary: 'CNY', secondary: <String>['USD'])
          .addSecondary('EUR')
          .addSecondary('JPY');
      expect(set.secondary, <String>['USD', 'EUR', 'JPY']);
      expect(set.isFull, isTrue);
    });

    test('removing something absent is not an error', () {
      // A screen may ask twice, and a preference that threw would make the second tap a
      // crash rather than a no-op.
      final set = ChoiceSet<String>(primary: 'CNY', secondary: <String>['USD']);
      expect(set.removeSecondary('EUR').secondary, <String>['USD']);
      expect(set.removeSecondary('USD').secondary, isEmpty);
      expect(set.removeSecondary('USD').primary, 'CNY');
    });
  });

  group('it is generic, because both axes use it', () {
    test('a measure set is the same shape as a currency set', () {
      // The instruction gave the same rule twice with a different noun, so it is one type.
      final measures = ChoiceSet<String>(
        primary: 'ml',
        secondary: <String>['cl', 'fl oz'],
      );
      final money = ChoiceSet<String>(
        primary: 'CNY',
        secondary: <String>['USD', 'JPY'],
      );
      expect(measures.isFull, isFalse);
      expect(money.isFull, isFalse);
      expect(measures.promote('cl').primary, 'cl');
      expect(money.promote('USD').secondary, <String>['CNY', 'JPY']);
    });
  });
}
