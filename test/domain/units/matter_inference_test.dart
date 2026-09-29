import 'dart:convert';
import 'dart:io';

import 'package:hollow_court/domain/units/matter_inference.dart';
import 'package:hollow_court/domain/units/measure_set.dart';
import 'package:hollow_court/domain/units/unit.dart';
import 'package:hollow_court/domain/units/unit_system.dart';
import 'package:test/test.dart';

/// **Solid, liquid or either, worked out from how the drinks measure the thing.**
///
/// The owner asked for this on 2026-09-22: *"落实固体、液体、组合等对应默认计量单位的智能识别"*. The
/// principle the tests below hold to is that **the answer comes from the drinks and never from the name** --
/// so every case here is stated as evidence rather than as a substance.
void main() {
  MatterEvidence evidence({int volume = 0, int mass = 0, int counted = 0}) =>
      MatterEvidence(volume: volume, mass: mass, counted: counted);

  test('**what every drink pours is a liquid, and what every drink weighs is a solid**', () {
    final poured = inferMatter(evidence: evidence(volume: 30));
    expect(poured.state, MatterState.liquid);
    expect(poured.because, contains('pours it'));

    final weighed = inferMatter(evidence: evidence(mass: 12));
    expect(weighed.state, MatterState.solid);
    expect(weighed.because, contains('weighs it'));
  });

  test('**measured both ways is *either*, which is an answer rather than an abstention**', () {
    final both = inferMatter(evidence: evidence(volume: 6, mass: 4));
    expect(both.state, MatterState.either);
    expect(both.because, contains('both'));
  });

  test('**one unusual recipe does not make a liquid *either***', () {
    // A single drink that weighs the gin it is otherwise poured in is a drink doing something unusual. Calling
    // it *either* would put a scale on the entry form for a spirit -- the threshold exists for this case.
    final mostlyPoured = inferMatter(evidence: evidence(volume: 19, mass: 1));
    expect(mostlyPoured.state, MatterState.liquid);
  });

  test('a counted ingredient is neither state, and the reader keeps the library default', () {
    // A cherry and a mint leaf are not solid or liquid in any sense that helps somebody choose a unit;
    // `MatterState` has no member for them by design, so the honest answer is that this file has none.
    final counted = inferMatter(evidence: evidence(counted: 9));
    expect(counted.state, isNull);
    expect(counted.because, contains('count this ingredient'));
  });

  test('nothing measured is nothing known, and it says so', () {
    final silence = inferMatter(evidence: evidence());
    expect(silence.state, isNull);
    expect(silence.because, contains('nothing in the library'));
  });

  test('**a stated default outranks the statistics, because somebody wrote it down**', () {
    // The library's `defaultUnit` is a statement about the ingredient; the recipe lines are observations about
    // drinks. When both exist the statement wins, and the reading says which it used.
    final stated = inferMatter(
      evidence: evidence(volume: 20),
      statedDefault: UnitSystem.gram,
    );
    expect(stated.state, MatterState.solid);
    expect(stated.because, contains('the library states g'));

    final statedLiquid = inferMatter(
      evidence: evidence(mass: 20),
      statedDefault: UnitSystem.millilitre,
    );
    expect(statedLiquid.state, MatterState.liquid);
  });

  test('a stated *count* decides nothing, so the evidence gets its say', () {
    // `each` says the ingredient is not measured by substance -- which is not the same as saying it is a
    // liquid. The statistics answer if they can.
    final fallsThrough = inferMatter(
      evidence: evidence(volume: 5),
      statedDefault: unitById('each'),
    );
    expect(fallsThrough.state, MatterState.liquid);
    expect(fallsThrough.because, isNot(contains('the library states')));
  });


  test('**the category answers only when the drinks cannot, and never overrules them**', () {
    // The owner named three inputs -- category, defaultUnit, and what the recipes do -- and the order between
    // them is the part worth testing. A group judgement ("syrups are poured") must not overrule an observation
    // about a drink or a statement about this ingredient.
    final silent = inferMatter(evidence: evidence(), category: 'syrups');
    expect(silent.state, MatterState.liquid);
    expect(silent.because, contains('its category says liquid'));

    // But where the drinks *have* spoken, the category is not consulted at all.
    final weighed = inferMatter(evidence: evidence(mass: 4), category: 'syrups');
    expect(weighed.state, MatterState.solid, reason: 'the drinks outweigh the category');

    final stated = inferMatter(
      evidence: evidence(),
      statedDefault: UnitSystem.gram,
      category: 'syrups',
    );
    expect(stated.state, MatterState.solid, reason: 'a statement about this ingredient outweighs its group');

    // And a category that holds both a bag of sugar and a bottle of Worcestershire answers nothing.
    expect(stateFromCategory('pantryItems'), isNull);
    expect(stateFromCategory('groceryItems'), isNull);
    expect(stateFromCategory('citrus'), isNull);
    expect(stateFromCategory(null), isNull);
    expect(stateFromCategory('juices'), MatterState.liquid);
    expect(stateFromCategory('herbsAndSpices'), MatterState.solid);
  });

  test('the evidence is counted from the lines, by unit rather than by amount', () {
    // **The amount is irrelevant**: `5 ml` and `500 ml` are both a pour, and a rule that weighed amounts would
    // call a big measure a different substance from a small one.
    final gathered = gatherEvidence([
      (ingredientId: 'gin', unit: UnitSystem.millilitre),
      (ingredientId: 'gin', unit: UnitSystem.litre),
      (ingredientId: 'sugar', unit: UnitSystem.gram),
      (ingredientId: 'cherry', unit: unitById('each')!),
      (ingredientId: 'cherry', unit: unitById('dash')!),
    ]);
    expect(gathered['gin']!.volume, 2);
    expect(gathered['sugar']!.mass, 1);
    expect(gathered['cherry']!.counted, 2);
    expect(gathered['cherry']!.volume, 0);
  });

  test('an unknown unit id is null rather than a silent millilitre', () {
    // A library naming a unit this build cannot measure in is a fact the caller has to decide about; reading
    // it as millilitres would turn a data problem into wrong numbers on somebody's shelf.
    expect(unitById('furlong'), isNull);
    expect(unitById('ml'), isNotNull);
  });

  test('**the real library classifies the things a bar would expect**', () {
    final library = File('data/drinks/library.json');
    if (!library.existsSync()) {
      markTestSkipped('the library is not present');
      return;
    }
    // **Parsed rather than pattern-matched.** The first version of this test scraped the file with a regex
    // and found nothing, because the JSON is written with an indent and every field sits on its own line --
    // a test that reads a file by shape is a test that breaks when the shape is fine.
    final decoded = jsonDecode(library.readAsStringSync()) as Map<String, Object?>;
    final lines = <({String ingredientId, Unit unit})>[];
    for (final recipe in (decoded['recipes'] as List)) {
      for (final item in ((recipe as Map)['items'] as List)) {
        final map = item as Map;
        final unit = unitById(map['unit'] as String);
        if (unit != null) lines.add((ingredientId: map['ingredientId'] as String, unit: unit));
      }
    }
    expect(lines, isNotEmpty);

    final evidenceByIngredient = gatherEvidence(lines);
    expect(evidenceByIngredient.length, greaterThan(50));

    // Spirits and juices are poured; the few things this library weighs are solids.
    for (final id in const ['gin', 'vodka', 'limeJuice', 'sweetVermouth']) {
      final reading = inferMatter(evidence: evidenceByIngredient[id] ?? const MatterEvidence());
      expect(reading.state, MatterState.liquid, reason: '$id: ${reading.because}');
    }
    final sugar = inferMatter(evidence: evidenceByIngredient['sugar'] ?? const MatterEvidence());
    expect(sugar.state, MatterState.solid, reason: sugar.because);

    // And the counted things are recognised as counted rather than forced into a state.
    final cherry = inferMatter(evidence: evidenceByIngredient['cherry'] ?? const MatterEvidence());
    expect(cherry.state, isNull, reason: cherry.because);
  });
}
