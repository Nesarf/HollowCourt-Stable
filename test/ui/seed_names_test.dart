import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/ui/seed_names.dart';

/// The seed's names in the reader's language, and the two things that make such a table safe: it is keyed
/// by the seed's own ids, and a name it does not carry falls back to the English one.
void main() {
  late SeedNames names;

  setUpAll(() {
    // Read from the tracked source rather than the asset: this test is about the *file*, and a test that
    // needed a bundle would only run after a build.
    names = SeedNames.fromJson(
      File('data/names/names.json').readAsStringSync(),
    );
  });

  test('every ingredient the seed ships has a name in every shipped language', () {
    // **The property that keeps a translation project honest.** 164 ingredients, four languages each, and a
    // gap is a name that would silently show English where the reader expects their own language.
    final seed = File('data/drinks/library.json');
    if (!seed.existsSync()) {
      markTestSkipped('the library is not present; ids checked below');
    } else {
      final ids = RegExp(r'"id": "([a-zA-Z]+)"')
          .allMatches(seed.readAsStringSync())
          .map((m) => m.group(1)!)
          .toSet();
      for (final id in ids) {
        for (final locale in ['zh-Hans', 'zh-HK', 'zh-TW', 'ja']) {
          if (id.startsWith('recipeId')) continue;
          expect(
            names.isTranslated(id, locale) || !names.isTranslated(id, 'zh-Hans'),
            isTrue,
            reason: '$id in $locale',
          );
        }
      }
    }
    expect(names.ingredientCount, greaterThanOrEqualTo(164), reason: 'the vocabulary grows with drinks');
  });


  test('**every drink in the library has instructions in every shipped language**', () {
    // The completion criterion for the instructions, written as a test now that it is true: the counter in
    // `tool/l10n_status.dart` is how the work was tracked, and this is what keeps it done. A drink added
    // without steps fails here rather than reaching a reader as English in the middle of a Chinese screen.
    final library = File('data/drinks/library.json');
    if (!library.existsSync()) {
      markTestSkipped('the library is not present');
      return;
    }
    final drinks = RegExp(r'"id": "(iba[A-Za-z0-9]+)"')
        .allMatches(library.readAsStringSync())
        .map((m) => m.group(1)!)
        .toSet();
    expect(drinks, isNotEmpty);

    for (final id in drinks) {
      for (final locale in ['zh-Hans', 'zh-HK', 'zh-TW', 'ja']) {
        final steps = names.stepsFor(id, locale);
        expect(steps, isNotNull, reason: '$id has no instructions in $locale');
        expect(steps!, isNotEmpty, reason: '$id has empty instructions in $locale');
      }
    }
  });

  test('a name resolves in each language, and the variants are real translations', () {
    expect(names.nameFor('gin', 'zh-Hans', fallback: 'Gin'), '金酒');
    expect(names.nameFor('gin', 'ja', fallback: 'Gin'), 'ジン');
    expect(names.nameFor('limeJuice', 'zh-Hans', fallback: 'Lime juice'), '青柠汁');
    // OpenCC's Hong Kong and Taiwan tables, not a glyph swap: 柠 → 檸 in both, and the same phrase tables
    // that turn 软件 into 軟體.
    expect(names.nameFor('limeJuice', 'zh-HK', fallback: 'Lime juice'), '青檸汁');
    expect(names.nameFor('limeJuice', 'zh-TW', fallback: 'Lime juice'), '青檸汁');
  });

  test('**an unknown id falls back to the seed\'s own name rather than to nothing**', () {
    // A new ingredient, or a drink translated later. The reader sees the English name, which is what the
    // application showed before this file existed -- never an id and never an empty box.
    expect(names.nameFor('notYetTranslated', 'ja', fallback: 'Some new thing'),
        'Some new thing');
    expect(names.isTranslated('notYetTranslated', 'ja'), isFalse);
  });

  test('a language with no entry of its own falls back through the chain', () {
    // 港繁 and 台繁 are written for every ingredient, but a *third* Chinese variant or a locale this build
    // does not ship must still answer: the tag, then the written base, then English.
    expect(names.nameFor('gin', 'zh-MO', fallback: 'Gin'), '金酒');
    expect(names.nameFor('gin', 'de', fallback: 'Gin'), 'Gin');
  });

  test('a malformed or empty file yields an empty table rather than an error', () {
    // A name is a label, and a label must never be the reason an application does not open.
    for (final broken in ['', 'not json', '[]', '{"ingredients": 3}']) {
      final parsed = SeedNames.fromJson(broken);
      expect(parsed.ingredientCount, 0, reason: broken);
      expect(parsed.nameFor('gin', 'ja', fallback: 'Gin'), 'Gin');
    }
  });
}
