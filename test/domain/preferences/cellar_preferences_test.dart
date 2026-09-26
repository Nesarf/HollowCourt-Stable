import 'package:hollow_court/domain/preferences/cellar_preferences.dart';
import 'package:hollow_court/domain/preferences/choice_set.dart';
import 'package:hollow_court/domain/pricing/price.dart';
import 'package:hollow_court/domain/units/measure_set.dart';
import 'package:hollow_court/domain/units/unit.dart';
import 'package:hollow_court/domain/units/unit_system.dart';
import 'package:test/test.dart';

/// A seed shaped like the metric locale table, so a fallback is visible as metric.
Map<MatterState, ChoiceSet<Unit>> get metricSeed => {
  MatterState.liquid: ChoiceSet<Unit>(
    primary: UnitSystem.millilitre,
    secondary: [UnitSystem.centilitre],
  ),
  MatterState.solid: ChoiceSet<Unit>(
    primary: UnitSystem.gram,
    secondary: [UnitSystem.kilogram],
  ),
};

ChoiceSet<Currency> get cnySeed =>
    ChoiceSet<Currency>(primary: Currency.cny, secondary: [Currency.usd]);

CellarPreferences read(Object? json) => CellarPreferences.fromJson(
  json,
  seedMeasures: metricSeed,
  seedCurrencies: cnySeed,
);

void main() {
  group('the round trip keeps what the reader chose', () {
    test('units and money survive a write and a read', () {
      final chosen = CellarPreferences(
        measures: {
          MatterState.liquid: ChoiceSet<Unit>(
            primary: UnitSystem.fluidOunceUnit,
            secondary: [UnitSystem.millilitre, UnitSystem.teaspoon],
          ),
          MatterState.solid: ChoiceSet<Unit>(
            primary: UnitSystem.ounceMass,
            secondary: [UnitSystem.gram],
          ),
        },
        currencies: ChoiceSet<Currency>(
          primary: Currency.eur,
          secondary: [Currency.gbp, Currency.usd],
        ),
      );

      final back = read(chosen.toJson());

      expect(
        back.measuresFor(MatterState.liquid)!.all.map((u) => u.id),
        ['oz', 'ml', 'tsp'],
      );
      expect(
        back.measuresFor(MatterState.solid)!.all.map((u) => u.id),
        ['ozm', 'g'],
      );
      expect(
        back.currencies.all.map((c) => c.code),
        ['EUR', 'GBP', 'USD'],
      );
    });

    test('it is written by id and code, never by symbol', () {
      // A file written with symbols would break the first time a symbol was corrected,
      // and `oz` is the case that proves it: two different units print the same symbol
      // and only the id tells them apart.
      final preferences = CellarPreferences(
        measures: {
          MatterState.solid: ChoiceSet<Unit>(primary: UnitSystem.ounceMass),
        },
        currencies: ChoiceSet<Currency>(primary: Currency.cny),
      );

      final json = preferences.toJson();

      expect(json['currencies'], {'primary': 'CNY', 'secondary': <String>[]});
      final measures = json['measures']! as Map<String, Object?>;
      expect((measures['solid']! as Map<String, Object?>)['primary'], 'ozm');
      expect(jsonEncodeSymbols(json), isNot(contains('"oz"')));
    });
  });

  group('what cannot be read falls back per axis', () {
    test('a unit this build no longer ships does not cost the reader their money', () {
      // The whole reason the fallback is per axis. The two choices have nothing to do
      // with each other, and a file written by a build that shipped a unit this one does
      // not would otherwise take the money with it.
      final back = read({
        'measures': {
          'liquid': {'primary': 'floz_old', 'secondary': <String>[]},
        },
        'currencies': {
          'primary': 'JPY',
          'secondary': <String>[],
        },
      });

      expect(
        back.measuresFor(MatterState.liquid)!.primary.id,
        'ml',
        reason: 'the seed stands, because the stored unit is not one this build knows',
      );
      expect(back.currencies.primary.code, 'JPY');
    });

    test('a currency this build no longer ships leaves the seeded money', () {
      final back = read({
        'currencies': {'primary': 'XYZ', 'secondary': <String>[]},
      });

      expect(back.currencies.primary.code, 'CNY');
    });

    test('a state this build does not have is ignored rather than fatal', () {
      final back = read({
        'measures': {
          'plasma': {'primary': 'ml', 'secondary': <String>[]},
          'solid': {'primary': 'kg', 'secondary': <String>[]},
        },
      });

      expect(back.measures.keys, containsAll([MatterState.liquid, MatterState.solid]));
      expect(back.measuresFor(MatterState.solid)!.primary.id, 'kg');
    });

    test('a secondary that does not resolve is dropped and the primary kept', () {
      // Asymmetry with the primary, and deliberate: the primary is what a number is
      // read in and cannot be guessed, while a secondary is an offer beside it. Losing
      // one offer beats losing the whole set over a unit this build stopped shipping.
      final back = read({
        'measures': {
          'liquid': {
            'primary': 'l',
            'secondary': ['gallon_old', 'cl'],
          },
        },
      });

      expect(back.measuresFor(MatterState.liquid)!.primary.id, 'l');
      expect(back.measuresFor(MatterState.liquid)!.all.map((u) => u.id), ['l', 'cl']);
    });

    test('a set with more secondaries than the rule allows falls back whole', () {
      // Truncating would silently drop what the reader chose; the seed is the safer
      // answer, and the count is the thing that was wrong.
      final back = read({
        'measures': {
          'liquid': {
            'primary': 'ml',
            'secondary': ['cl', 'l', 'oz', 'tsp', 'tbsp'],
          },
        },
      });

      expect(back.measuresFor(MatterState.liquid)!.all.map((u) => u.id), ['ml', 'cl']);
    });

    test('nothing stored at all gives the seeds', () {
      expect(read(null).currencies.primary.code, 'CNY');
      expect(read('not a map').measuresFor(MatterState.liquid)!.primary.id, 'ml');
      expect(read(const <String, Object?>{}).currencies.primary.code, 'CNY');
    });
  });

  group('changing one axis leaves the other alone', () {
    test('a new unit set keeps the money and a new money keeps the units', () {
      final start = CellarPreferences(
        measures: metricSeed,
        currencies: cnySeed,
      );

      final moneyChanged = start.withCurrencies(
        ChoiceSet<Currency>(primary: Currency.jpy),
      );
      expect(moneyChanged.currencies.primary.code, 'JPY');
      expect(moneyChanged.measuresFor(MatterState.liquid)!.primary.id, 'ml');

      final unitsChanged = start.withMeasures(
        MatterState.either,
        ChoiceSet<Unit>(primary: UnitSystem.fluidOunceUnit),
      );
      expect(unitsChanged.currencies.primary.code, 'CNY');
      expect(unitsChanged.measuresFor(MatterState.either)!.primary.id, 'oz');
      expect(
        unitsChanged.measuresFor(MatterState.liquid)!.primary.id,
        'ml',
        reason: 'changing one state does not change the others',
      );
    });
  });
}

/// The JSON as a string, so a test can assert on what is literally in the file.
String jsonEncodeSymbols(Map<String, Object?> json) => json.toString();
