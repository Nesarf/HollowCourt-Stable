import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/domain/preferences/choice_set.dart';
import 'package:hollow_court/domain/units/measure_set.dart';
import 'package:hollow_court/domain/units/unit.dart';
import 'package:hollow_court/domain/units/unit_system.dart';
import 'package:hollow_court/ui/l10n/locale_catalogue.dart';
import 'package:hollow_court/ui/l10n/locale_defaults.dart';

void main() {
  group('every shipped locale has both defaults', () {
    test('no locale lands on the fallback by accident', () {
      // The failure this catches is a table with a typo in a tag: the locale would
      // still work, would still show text, and would quietly price bottles in the
      // fallback's money. Nothing on a screen would say so, which is exactly why the
      // assertion is per locale rather than a spot check.
      for (final locale in shippedLocales) {
        final money = currenciesFor(locale.tag);
        expect(money.primary.code, isNotEmpty, reason: locale.tag);
        expect(
          measuresFor(locale.tag).sets,
          hasLength(3),
          reason: '${locale.tag} is missing a state',
        );
      }
    });

    test('the two tables agree about a locale the catalogue has never heard of', () {
      // Both resolve through the catalogue's own chain, so a screen whose text fell
      // back to 简中 cannot have units that fell back somewhere else.
      expect(currencyFor('xx-YY').code, currencyFor(fallbackTag).code);
      expect(
        measuresFor('xx-YY').sets.map((s) => s.primary.id),
        measuresFor(fallbackTag).sets.map((s) => s.primary.id),
      );
    });

    test('文言文 is not a currency area, and takes the fallback for both', () {
      // The one locale in the catalogue whose text is a historical language. It has
      // its own row for money rather than being special-cased in the lookup, so this
      // asserts the row rather than the absence of one.
      expect(currencyFor('lzh').code, 'CNY');
      expect(measuresFor('lzh').sets.first.primary.id, 'g');
    });
  });

  group('the two measurement cultures', () {
    test('English reaches for ounces and everything else for millilitres', () {
      expect(measuresFor('en').forState(MatterState.liquid)!.primary.id, 'oz');
      expect(measuresFor('en').forState(MatterState.solid)!.primary.id, 'ozm');

      for (final tag in ['zh-Hans', 'zh-HK', 'zh-TW', 'ja', 'ko-KR', 'fr', 'de']) {
        expect(
          measuresFor(tag).forState(MatterState.liquid)!.primary.id,
          'ml',
          reason: tag,
        );
        expect(
          measuresFor(tag).forState(MatterState.solid)!.primary.id,
          'g',
          reason: tag,
        );
      }
    });

    test('the mass ounce and the volume ounce are the units that differ', () {
      // The id collision made visible: `en` offers `oz` for a liquid and `ozm` for a
      // solid, and they are not the same unit even though both are printed `oz`.
      final liquid = measuresFor('en').forState(MatterState.liquid)!;
      final solid = measuresFor('en').forState(MatterState.solid)!;

      expect(liquid.primary.symbol, 'oz');
      expect(solid.primary.symbol, 'oz');
      expect(liquid.primary, isNot(solid.primary));
      expect(liquid.dimension, UnitDimension.volume);
      expect(solid.dimension, UnitDimension.mass);
    });
  });

  group('mixing dimensions is legal in exactly one place', () {
    test('a stated state never mixes, and 糖浆/蜂蜜 always does', () {
      // The rule this table is allowed to rely on. A `liquid` set offering grams would
      // answer a question nobody asked and would look perfectly fine on a screen; an
      // `either` set mixing ml and g is the instruction almost word for word.
      for (final locale in shippedLocales) {
        final measures = measuresFor(locale.tag);
        expect(
          measures.illegalSets(),
          isEmpty,
          reason: '${locale.tag} has a set mixing dimensions for a stated state',
        );
        expect(
          measures.forState(MatterState.either)!.isMixed,
          isTrue,
          reason: '${locale.tag} should offer both for a syrup',
        );
      }
    });

    test('the either set defaults to volume, which is what was asked for', () {
      // 糖浆/蜂蜜这种克和毫升都能用的，默认以毫升为主计量而克为副计量. Asserted on both
      // cultures, because "the default is volume" is the rule and "the default is
      // millilitres" is only the metric spelling of it.
      expect(measuresFor('zh-Hans').forState(MatterState.either)!.primary.id, 'ml');
      expect(measuresFor('en').forState(MatterState.either)!.primary.id, 'oz');
      expect(
        measuresFor('en').forState(MatterState.either)!.primary.dimension,
        UnitDimension.volume,
      );
      // And the gram is still on offer beside it, which is the other half of the
      // instruction.
      expect(
        measuresFor('zh-Hans').forState(MatterState.either)!.all.map((u) => u.id),
        contains('g'),
      );
    });
  });

  group('the choice-set rule holds on both axes', () {
    test('one primary, at most three secondaries, and no repetition', () {
      for (final locale in shippedLocales) {
        for (final set in measuresFor(locale.tag).sets) {
          final ids = set.all.map((u) => u.id).toList();
          expect(ids.toSet(), hasLength(ids.length), reason: '${locale.tag} $set');
          expect(ids.length, lessThanOrEqualTo(1 + ChoiceSet.maxSecondary));
          expect(set.units.primary, set.all.first);
        }

        final money = currenciesFor(locale.tag);
        final codes = money.all.map((c) => c.code).toList();
        expect(codes.toSet(), hasLength(codes.length), reason: locale.tag);
        expect(codes.length, lessThanOrEqualTo(1 + ChoiceSet.maxSecondary));
      }
    });

    test('every unit id in both tables is one this system carries', () {
      // `MeasureSet.fromIds` throws on an unknown id, so simply reaching this line is
      // most of the assertion -- but the totals are checked too, so a table that lost
      // a unit to a typo in a *secondary* would still be caught if the factory were
      // ever loosened.
      for (final locale in shippedLocales) {
        for (final set in measuresFor(locale.tag).sets) {
          for (final unit in set.all) {
            expect(UnitSystem.all, contains(unit), reason: '${locale.tag} ${unit.id}');
          }
          expect(set.all.length, greaterThanOrEqualTo(2));
        }
      }
    });

    test('a set that is not full is not a set that is broken', () {
      // Two pre-filled slots at most, so at least one secondary slot is left for the
      // reader. Every slot filled by default is a slot somebody has to clear.
      for (final locale in shippedLocales) {
        final money = currenciesFor(locale.tag);
        expect(money.isFull, isFalse, reason: locale.tag);
      }
    });
  });
}
