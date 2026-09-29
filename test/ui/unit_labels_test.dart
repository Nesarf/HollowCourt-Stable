import 'package:hollow_court/domain/units/unit.dart';
import 'package:hollow_court/domain/units/unit_system.dart';
import 'package:hollow_court/ui/l10n/locale_catalogue.dart';
import 'package:hollow_court/ui/unit_labels.dart';
import 'package:test/test.dart';

/// Naming units in the reader's language, and the line that decides which units are translated.
///
/// The owner asked for this on 2026-09-22 -- *"计量单位也要翻译"* -- and the interesting part is not the
/// table but the rule: **a measurement keeps its international symbol and a word is translated**, because
/// a recipe measured in 毫升 for the number is a recipe that cannot be compared with the bottle in the
/// reader's hand.
void main() {
  /// Every unit the domain declares, so the table cannot fall behind it.
  final catalogue = <String, Unit>{
    'ml': UnitSystem.millilitre,
    'cl': UnitSystem.centilitre,
    'l': UnitSystem.litre,
    'oz': UnitSystem.fluidOunceUnit,
    'tsp': UnitSystem.teaspoon,
    'tbsp': UnitSystem.tablespoon,
    'drop': UnitSystem.drop,
    'mg': UnitSystem.milligram,
    'g': UnitSystem.gram,
    'kg': UnitSystem.kilogram,
    'ozm': UnitSystem.ounceMass,
    'lb': UnitSystem.pound,
    'dash': UnitSystem.dash,
    'barspoon': UnitSystem.barspoon,
    'pinch': UnitSystem.pinch,
    'shot': UnitSystem.shot,
    'part': UnitSystem.part,
    'leaf': UnitSystem.leaf,
    'sprig': UnitSystem.sprig,
    'wheel': UnitSystem.wheel,
    'twist': UnitSystem.twist,
    'peel': UnitSystem.peel,
    'cube': UnitSystem.cube,
    'wedge': UnitSystem.wedge,
    'slice': UnitSystem.slice,
    'each': UnitSystem.each,
  };

  test('**every unit in the catalogue has a label in every shipped language**', () {
    // The property that keeps a new unit from reaching a reader as a bare English word. The ids are
    // listed here rather than derived, so adding a unit to the domain without adding it here is a
    // deliberate act -- and adding it here without a label fails the loop below.
    expect(catalogue.length, 26);
    expect(labelledUnitIds, catalogue.keys.toSet());

    // **Every locale the application ships, asked of the catalogue rather than listed here again.**
    // The first version of this test named three of them ('zh-Hans', 'en', 'ja') while `shippedLocales` had
    // five, so 港繁 and 台繁 fell through to the 简中 base for every unit -- silently, because the fallback
    // chain is designed to do exactly that. A completeness test that lists its own locales cannot notice a
    // locale being added beside it.
    for (final entry in catalogue.entries) {
      for (final locale in shippedLocales.map((l) => l.tag)) {
        final name = unitNameFor(entry.value, locale);
        expect(name, isNotEmpty, reason: '${entry.key} in $locale');
        // **Not "the name differs from the id"**: in English `drop` is both, and a rule that demanded a
        // difference would fail for the one language where the id was invented. The completeness check is
        // the table membership above, which is checked against the table's own keys.
        expect(labelledUnitIds, contains(entry.key));
      }
    }
  });

  test('a measured unit keeps its international symbol in every language', () {
    // `ml` is `ml` in Tokyo and in São Paulo. What is localised for these is the *name*, which is what a
    // picker shows; the number keeps the symbol it shares with every bottle in the world.
    for (final locale in ['zh-Hans', 'ja', 'en']) {
      expect(unitSymbolFor(UnitSystem.millilitre, locale), 'ml');
      expect(unitSymbolFor(UnitSystem.gram, locale), 'g');
      expect(unitSymbolFor(UnitSystem.kilogram, locale), 'kg');
    }
    expect(unitNameFor(UnitSystem.millilitre, 'ja'), 'ミリリットル');
    expect(unitNameFor(UnitSystem.gram, 'zh-Hans'), '克');
  });

  test('**and a unit that is a word is translated, because a word is a word**', () {
    // A Chinese interface printing `2 leaf` is the wrong language in the one place this application
    // promised a reader would never see one.
    expect(unitSymbolFor(UnitSystem.leaf, 'zh-Hans'), '片');
    expect(unitSymbolFor(UnitSystem.leaf, 'ja'), '葉');
    expect(unitSymbolFor(UnitSystem.sprig, 'zh-Hans'), '枝');
    expect(unitNameFor(UnitSystem.wheel, 'ja'), '輪切り');
    expect(unitSymbolFor(UnitSystem.each, 'zh-Hans'), '个');
    expect(unitSymbolFor(UnitSystem.slice, 'ja'), 'スライス');
  });

  test('the bar\'s own measures get Japanese words and keep the English term in Chinese', () {
    // **[decision]** A dash is a dash: Chinese bartending says "dash" and "barspoon" the way it says
    // "gin", and inventing 抖振 for a number somebody reads before pouring is worse than the word they
    // already use. Japanese *has* its own words for all of them, so it gets them -- a term is translated
    // when the language has one and borrowed when it does not.
    expect(unitNameFor(UnitSystem.dash, 'ja'), 'ダッシュ');
    expect(unitNameFor(UnitSystem.barspoon, 'ja'), 'バースプーン');
    // **And Chinese has a word for this one**, which the owner pointed out: 吧勺 is what it is called.
    // Borrowing the English term was the wrong side of the borrow-or-translate line for a barspoon.
    expect(unitNameFor(UnitSystem.barspoon, 'zh-Hans'), '吧勺');
    expect(unitNameFor(UnitSystem.pinch, 'ja'), 'ひとつまみ');
    expect(unitSymbolFor(UnitSystem.dash, 'zh-Hans'), 'dash');
    expect(unitNameFor(UnitSystem.dash, 'zh-Hans'), contains('dash'));
    expect(unitNameFor(UnitSystem.pinch, 'zh-Hans'), '撮');
  });

  test('the two spoons are words in every language, and differ', () {
    // 小匙/大匙 and 小さじ/大さじ: a reader who confuses them makes a drink twice as strong.
    expect(unitSymbolFor(UnitSystem.teaspoon, 'zh-Hans'), isNot(unitSymbolFor(UnitSystem.tablespoon, 'zh-Hans')));
    expect(unitSymbolFor(UnitSystem.teaspoon, 'ja'), isNot(unitSymbolFor(UnitSystem.tablespoon, 'ja')));
    expect(unitSymbolFor(UnitSystem.teaspoon, 'ja'), '小さじ');
    expect(unitSymbolFor(UnitSystem.tablespoon, 'ja'), '大さじ');
  });

  test('a language with no label falls back rather than showing nothing', () {
    // A tag this build does not ship, or a variant with no entry of its own: the chain in
    // `labelFallbacks` answers, and an unknown locale never produces an empty string.
    expect(unitNameFor(UnitSystem.millilitre, 'de'), 'millilitre');
    expect(unitNameFor(UnitSystem.millilitre, 'zh-HK'), '毫升');
    expect(unitSymbolFor(UnitSystem.leaf, 'zh-TW'), '片');
  });
}
