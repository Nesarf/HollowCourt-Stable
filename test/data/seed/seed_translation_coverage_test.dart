import 'dart:convert';
import 'dart:io';

import 'package:hollow_court/ui/seed_names.dart';
import 'package:test/test.dart';

/// **The shipped library and the shipped translations cover each other, and that is a maintained fact.**
///
/// The names file is ours and the library is ours, and they are keyed by the same ids -- which is what makes a
/// missing translation a *silent* English name on a screen rather than an error anywhere. This test is the thing
/// that is allowed to fail when somebody adds a drink.
///
/// **Why it is worth having when the display defects are already fixed**: the reported fault was not a missing
/// translation, it was code that never asked for one, and the two look identical from a screen. A coverage test
/// cannot tell them apart either -- but a screen test can only check the screens somebody thought of, and this
/// checks all 88 and all 187.
void main() {
  late Map<String, Object?> library;
  late SeedNames names;

  /// The names file as data as well as through [SeedNames], because two of these tests ask what a *locale
  /// column* says and the table only answers through its fallback chain -- which is the chain that hid the
  /// missing 港繁 and 台繁 labels in the first place.
  late Map<String, Object?> namesRaw;

  setUpAll(() {
    final libraryFile = File('data/drinks/library.json');
    final namesFile = File('data/names/names.json');
    expect(libraryFile.existsSync(), isTrue, reason: 'run this from the repository root');
    expect(namesFile.existsSync(), isTrue, reason: 'run this from the repository root');
    library = jsonDecode(libraryFile.readAsStringSync()) as Map<String, Object?>;
    names = SeedNames.fromJson(namesFile.readAsStringSync());
    namesRaw = jsonDecode(namesFile.readAsStringSync()) as Map<String, Object?>;
  });

  /// The languages Section 12.4 ships, and the ones a reader can select today.
  const locales = ['zh-Hans', 'zh-HK', 'zh-TW', 'ja'];

  test('**every drink in the library is named in every shipped language**', () {
    final recipes = (library['recipes']! as List).cast<Map<String, Object?>>();
    expect(recipes, isNotEmpty, reason: 'the library is the thing being covered');

    final missing = <String>[];
    for (final recipe in recipes) {
      final id = recipe['id']! as String;
      for (final locale in locales) {
        if (!names.isTranslated(id, locale)) missing.add('$id/$locale');
      }
    }
    expect(
      missing,
      isEmpty,
      reason: 'these drinks would show their harvested English name: ${missing.take(12).join(", ")}',
    );
  });

  test('**and so is every ingredient**', () {
    final ingredients = (library['ingredients']! as List).cast<Map<String, Object?>>();

    final missing = <String>[];
    for (final ingredient in ingredients) {
      final id = ingredient['id']! as String;
      for (final locale in locales) {
        if (!names.isTranslated(id, locale)) missing.add('$id/$locale');
      }
    }
    expect(
      missing,
      isEmpty,
      reason: 'these ingredients would show their harvested English name: ${missing.take(12).join(", ")}',
    );
  });

  test('**a translation is a different string from the English, not a copy of it**', () {
    // A table that answered every locale with the English name would pass a coverage test and fix nothing -- and
    // that is not hypothetical: the fallback chain ends at English by design, so the two are one step apart.
    final recipes = (library['recipes']! as List).cast<Map<String, Object?>>();
    final untranslated = <String>[];
    for (final recipe in recipes) {
      final english = recipe['name']! as String;
      final chinese = names.nameFor(recipe['id']! as String, 'zh-Hans', fallback: english);
      if (chinese == english) untranslated.add(english);
    }
    expect(untranslated, isEmpty, reason: 'these would read as English in a Chinese interface');
  });

  test('**no traditional column carries a machine-conversion trap**', () {
    // OpenCC cannot tell 干 (dry) from 幹 (to do), or a transliteration's 里 from 裡/裏. That produced
    // 幹馬天尼 for a *dry* martini and 蒂珀雷裏 for Tipperary, both of which are wrong in any context -- which
    // is what makes them worth a test rather than a note: they were not choices, they were accidents.
    //
    // Found by `tool/seed_name_audit.py`, which asks Wikipedia's own conversion table and reports the rest.
    final traps = {'幹': '乾 (dry)', '裏': '裡, or the 里 of a transliteration'};
    final found = <String>[];
    for (final section in ['recipes', 'ingredients']) {
      final entries = (namesRaw[section] ?? const {}) as Map<String, Object?>;
      entries.forEach((id, value) {
        final byLocale = value as Map<String, Object?>;
        for (final locale in ['zh-HK', 'zh-TW']) {
          final text = (byLocale[locale] ?? '') as String;
          traps.forEach((bad, right) {
            if (text.contains(bad)) found.add('$id/$locale: $text ($bad should be $right)');
          });
        }
      });
    }
    expect(found, isEmpty, reason: found.join('; '));
  });

  test('**the regional words Wikipedia settles are the ones the file uses**', () {
    // `Module:CGroup/Food` is the table Chinese Wikipedia converts 餐饮 articles with, so it is the nearest
    // thing to an authority on 大陆／臺灣／香港 vocabulary -- and every one of these was a machine conversion of
    // the 简中 form before it was checked against it. A regression here means somebody regenerated the file.
    const settled = {
      'cherry': {'zh-HK': '車厘子'},
      'chocolate': {'zh-HK': '朱古力'},
      'gin': {'zh-HK': '氈酒', 'zh-TW': '琴酒'},
      'iceCream': {'zh-HK': '雪糕'},
      'orangeJuice': {'zh-TW': '柳橙汁'},
      'pineapple': {'zh-TW': '鳳梨'},
      'tonicWater': {'zh-TW': '通寧水'},
      'lime': {'zh-TW': '萊姆'},
      'cream': {'zh-HK': '忌廉', 'zh-TW': '鮮奶油'},
      'eggWhite': {'zh-HK': '蛋白', 'zh-TW': '蛋白'},
    };
    final ingredients = (namesRaw['ingredients'] ?? const {}) as Map<String, Object?>;
    for (final entry in settled.entries) {
      final byLocale = ingredients[entry.key] as Map<String, Object?>?;
      expect(byLocale, isNotNull, reason: '${entry.key} left the library');
      entry.value.forEach((locale, want) {
        expect(byLocale![locale], want, reason: '${entry.key} in $locale');
      });
    }
  });

  test('the instructions travel too, for every drink', () {
    // Steps were the first thing this table was extended for, and a drink whose steps fall back is a drink whose
    // instruction list is English under a Chinese title.
    final recipes = (library['recipes']! as List).cast<Map<String, Object?>>();
    expect(names.stepsTranslatedIn('zh-Hans'), recipes.length);
    expect(names.stepsTranslatedIn('ja'), recipes.length);
  });
}
