import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/units/unit.dart';
import 'l10n/locale_providers.dart';

/// **What a unit is called in the reader's language.**
///
/// The owner asked for this on 2026-09-22: *"计量单位也要翻译"*. Until then a unit was shown as its own
/// `symbol` everywhere -- `ml`, `oz`, `dash`, `leaf` -- which is right for the international symbols and
/// wrong for the ones that are English **words**.
///
/// THE LINE THIS FILE DRAWS, because it is the whole design:
///
/// - **A measured unit keeps its international symbol in every language.** `ml` is `ml` in Tokyo and in
///   São Paulo; section 5 says a unit is a measurement rather than a word, and translating `ml` into
///   毫升 for the number itself would make a recipe incomparable with the bottle in the reader's hand.
///   What *is* localised for these is the [name] -- 毫升 / millilitre / ミリリットル -- which is what a
///   picker shows when a reader is choosing.
/// - **A counted or cultural unit is a word and is translated as one.** `leaf`, `slice`, `dash` and
///   `part` name things, not scales, and a Chinese interface printing `2 leaf` is the wrong language in
///   the one place this application promised a reader would never see one.
///
/// **[decision] Five bar words keep their English form in Chinese, with a Chinese gloss in the name.** A
/// dash is a dash; Chinese bartending says "dash" and "barspoon" the way it says "gin", and inventing
/// 抖振 or 吧勺 for a number somebody reads before pouring is worse than the term they already use. The
/// gloss lives on the name, which is what a picker and a tooltip show. Japanese does have its own words
/// for all five -- ダッシュ, バースプーン, ひとつまみ, ショット, パート -- and uses them, so it gets them:
/// a term is translated when the language has one and borrowed when it does not.
///
/// Nothing here touches the domain. `Unit` keeps its `id` and `symbol` and learns no language: section 3
/// keeps display text out of a layer that has to be testable without a UI, and the same rule is why the
/// wording lives here.
final class UnitLabel {
  // The lint wants `this._symbol`, which cannot be a named parameter: a private name is not part of the
  // public API, so `UnitLabel('x', {this._symbol})` does not compile. Answered rather than followed,
  // because following it here is not possible.
  // ignore: prefer_initializing_formals
  const UnitLabel(this.name, {String? symbol}) : _symbol = symbol;

  /// The full name, for a picker or a menu: 毫升, millilitre, ミリリットル.
  final String name;

  /// The form that follows a number, when the unit's own symbol is a word rather than a scale.
  ///
  /// Null means "use the unit's own symbol": `ml`, `g` and `kg` are already the right answer in every
  /// language, and a table that repeated them 26 times would be a table with 26 chances to disagree.
  final String? _symbol;

  String symbolFor(Unit unit) => _symbol ?? unit.symbol;
}

/// Every unit this build can display, in the three languages it ships, keyed by `Unit.id`.
///
/// A test asserts that **every unit in the catalogue has an entry for every shipped language**, so a
/// unit added to the domain cannot be displayed as a bare English word because somebody forgot this file.
const Map<String, Map<String, UnitLabel>> _labels = {
  // ---- volume, international symbols -------------------------------------------------------
  'ml': {
    'zh-Hans': UnitLabel('毫升'),
    'zh-HK': UnitLabel('毫升'),
    'zh-TW': UnitLabel('毫升'),
    'en': UnitLabel('millilitre'),
    'ja': UnitLabel('ミリリットル'),
  },
  'cl': {
    'zh-Hans': UnitLabel('厘升'),
    'zh-HK': UnitLabel('釐升'),
    'zh-TW': UnitLabel('釐升'),
    'en': UnitLabel('centilitre'),
    'ja': UnitLabel('センチリットル'),
  },
  'l': {
    'zh-Hans': UnitLabel('升'),
    'zh-HK': UnitLabel('升'),
    'zh-TW': UnitLabel('升'),
    'en': UnitLabel('litre'),
    'ja': UnitLabel('リットル'),
  },
  'oz': {
    'zh-Hans': UnitLabel('液量盎司'),
    'zh-HK': UnitLabel('液量安士'),
    'zh-TW': UnitLabel('液量盎司'),
    'en': UnitLabel('fluid ounce'),
    'ja': UnitLabel('液量オンス'),
  },
  'tsp': {
    'zh-Hans': UnitLabel('茶匙', symbol: '小匙'),
    'zh-HK': UnitLabel('茶匙', symbol: '小匙'),
    'zh-TW': UnitLabel('茶匙', symbol: '小匙'),
    'en': UnitLabel('teaspoon', symbol: 'teaspoon'),
    'ja': UnitLabel('小さじ', symbol: '小さじ'),
  },

  'tbsp': {
    'zh-Hans': UnitLabel('汤匙', symbol: '大匙'),
    'zh-HK': UnitLabel('湯匙', symbol: '大匙'),
    'zh-TW': UnitLabel('湯匙', symbol: '大匙'),
    'en': UnitLabel('tablespoon', symbol: 'tablespoon'),
    'ja': UnitLabel('大さじ', symbol: '大さじ'),
  },

  'drop': {
    'zh-Hans': UnitLabel('滴', symbol: '滴'),
    'zh-HK': UnitLabel('滴', symbol: '滴'),
    'zh-TW': UnitLabel('滴', symbol: '滴'),
    'en': UnitLabel('drop', symbol: 'drop'),
    'ja': UnitLabel('滴', symbol: '滴'),
  },

  // ---- mass, international symbols ---------------------------------------------------------
  'mg': {
    'zh-Hans': UnitLabel('毫克'),
    'zh-HK': UnitLabel('毫克'),
    'zh-TW': UnitLabel('毫克'),
    'en': UnitLabel('milligram'),
    'ja': UnitLabel('ミリグラム'),
  },
  'g': {
    'zh-Hans': UnitLabel('克'),
    'zh-HK': UnitLabel('克'),
    'zh-TW': UnitLabel('公克'),
    'en': UnitLabel('gram'),
    'ja': UnitLabel('グラム'),
  },
  'kg': {
    'zh-Hans': UnitLabel('千克'),
    'zh-HK': UnitLabel('公斤'),
    'zh-TW': UnitLabel('公斤'),
    'en': UnitLabel('kilogram'),
    'ja': UnitLabel('キログラム'),
  },
  'ozm': {
    'zh-Hans': UnitLabel('盎司'),
    'zh-HK': UnitLabel('安士'),
    'zh-TW': UnitLabel('盎司'),
    'en': UnitLabel('ounce'),
    'ja': UnitLabel('オンス'),
  },
  'lb': {
    'zh-Hans': UnitLabel('磅'),
    'zh-HK': UnitLabel('磅'),
    'zh-TW': UnitLabel('磅'),
    'en': UnitLabel('pound'),
    'ja': UnitLabel('ポンド'),
  },
  // ---- the bar's own measures --------------------------------------------------------------
  'dash': {
    'zh-Hans': UnitLabel('少许（dash）', symbol: 'dash'),
    'zh-HK': UnitLabel('少許（dash）', symbol: 'dash'),
    'zh-TW': UnitLabel('少許（dash）', symbol: 'dash'),
    'en': UnitLabel('dash', symbol: 'dash'),
    'ja': UnitLabel('ダッシュ', symbol: 'ダッシュ'),
  },

  'barspoon': {
    // **吧勺, as the owner corrected**: it is the widely used Chinese term for the tool and for the
    // measure, and the earlier decision to borrow the English word was wrong for this one -- a barspoon
    // has a Chinese name and Chinese bartenders use it.
    'zh-Hans': UnitLabel('吧勺', symbol: '吧勺'),
    // 吧匙 is the traditional form (匙, not 勺) and both regions use it; the term itself is the same word.
    'zh-HK': UnitLabel('吧匙', symbol: '吧匙'),
    'zh-TW': UnitLabel('吧匙', symbol: '吧匙'),
    'en': UnitLabel('barspoon', symbol: 'barspoon'),
    'ja': UnitLabel('バースプーン', symbol: 'バースプーン'),
  },

  'pinch': {
    'zh-Hans': UnitLabel('撮', symbol: '撮'),
    'zh-HK': UnitLabel('撮', symbol: '撮'),
    'zh-TW': UnitLabel('撮', symbol: '撮'),
    'en': UnitLabel('pinch', symbol: 'pinch'),
    'ja': UnitLabel('ひとつまみ', symbol: 'ひとつまみ'),
  },

  'shot': {
    'zh-Hans': UnitLabel('一份（shot）', symbol: 'shot'),
    'zh-HK': UnitLabel('一份（shot）', symbol: 'shot'),
    'zh-TW': UnitLabel('一份（shot）', symbol: 'shot'),
    'en': UnitLabel('shot', symbol: 'shot'),
    'ja': UnitLabel('ショット', symbol: 'ショット'),
  },

  'part': {
    'zh-Hans': UnitLabel('份（part）', symbol: 'part'),
    'zh-HK': UnitLabel('份（part）', symbol: 'part'),
    'zh-TW': UnitLabel('份（part）', symbol: 'part'),
    'en': UnitLabel('part', symbol: 'part'),
    'ja': UnitLabel('パート', symbol: 'パート'),
  },

  // ---- counted: whole things, never scaled --------------------------------------------------
  'leaf': {
    'zh-Hans': UnitLabel('叶', symbol: '片'),
    'zh-HK': UnitLabel('葉', symbol: '片'),
    'zh-TW': UnitLabel('葉', symbol: '片'),
    'en': UnitLabel('leaf', symbol: 'leaf'),
    'ja': UnitLabel('葉', symbol: '葉'),
  },

  'sprig': {
    'zh-Hans': UnitLabel('小枝', symbol: '枝'),
    'zh-HK': UnitLabel('小枝', symbol: '枝'),
    'zh-TW': UnitLabel('小枝', symbol: '枝'),
    'en': UnitLabel('sprig', symbol: 'sprig'),
    'ja': UnitLabel('小枝', symbol: '小枝'),
  },

  'wheel': {
    'zh-Hans': UnitLabel('圆片', symbol: '圆片'),
    'zh-HK': UnitLabel('圓片', symbol: '圓片'),
    'zh-TW': UnitLabel('圓片', symbol: '圓片'),
    'en': UnitLabel('wheel', symbol: 'wheel'),
    'ja': UnitLabel('輪切り', symbol: '輪切り'),
  },

  'twist': {
    'zh-Hans': UnitLabel('皮卷', symbol: '皮卷'),
    'zh-HK': UnitLabel('皮捲', symbol: '皮捲'),
    'zh-TW': UnitLabel('皮捲', symbol: '皮捲'),
    'en': UnitLabel('twist', symbol: 'twist'),
    'ja': UnitLabel('ツイスト', symbol: 'ツイスト'),
  },

  'peel': {
    'zh-Hans': UnitLabel('果皮', symbol: '果皮'),
    'zh-HK': UnitLabel('果皮', symbol: '果皮'),
    'zh-TW': UnitLabel('果皮', symbol: '果皮'),
    'en': UnitLabel('peel', symbol: 'peel'),
    'ja': UnitLabel('ピール', symbol: 'ピール'),
  },

  'cube': {
    'zh-Hans': UnitLabel('块', symbol: '角'),
    'zh-HK': UnitLabel('塊', symbol: '角'),
    'zh-TW': UnitLabel('塊', symbol: '角'),
    'en': UnitLabel('cube', symbol: 'cube'),
    'ja': UnitLabel('キューブ', symbol: 'キューブ'),
  },

  'wedge': {
    'zh-Hans': UnitLabel('角块', symbol: '角'),
    'zh-HK': UnitLabel('角塊', symbol: '角'),
    'zh-TW': UnitLabel('角塊', symbol: '角'),
    'en': UnitLabel('wedge', symbol: 'wedge'),
    'ja': UnitLabel('くし形', symbol: 'くし形'),
  },

  'slice': {
    'zh-Hans': UnitLabel('片', symbol: '片'),
    'zh-HK': UnitLabel('片', symbol: '片'),
    'zh-TW': UnitLabel('片', symbol: '片'),
    'en': UnitLabel('slice', symbol: 'slice'),
    'ja': UnitLabel('スライス', symbol: 'スライス'),
  },

  'each': {
    'zh-Hans': UnitLabel('个', symbol: '个'),
    'zh-HK': UnitLabel('個', symbol: '個'),
    'zh-TW': UnitLabel('個', symbol: '個'),
    'en': UnitLabel('each', symbol: 'each'),
    'ja': UnitLabel('個', symbol: '個'),
  },

};

/// The unit's name in [locale], falling back through the same chain the strings use.
String unitNameFor(Unit unit, String locale) =>
    _pick(unit, locale)?.name ?? unit.symbol;

/// The form that follows a number in [locale]: `ml` stays `ml`, `leaf` becomes 片.
String unitSymbolFor(Unit unit, String locale) =>
    _pick(unit, locale)?.symbolFor(unit) ?? unit.symbol;

UnitLabel? _pick(Unit unit, String locale) {
  final byLocale = _labels[unit.id];
  if (byLocale == null) return null;
  for (final candidate in labelFallbacks(locale)) {
    final label = byLocale[candidate];
    if (label != null) return label;
  }
  return null;
}

/// The fallback chain for unit labels: the same shape as `localeFallbacks` in the copy layer, and named
/// separately because a unit is not a sentence -- if the two ever need to diverge, they can.
List<String> labelFallbacks(String tag) {
  final chain = <String>[tag];
  final dash = tag.indexOf('-');
  if (dash > 0 && tag.substring(0, dash).toLowerCase() == 'zh') {
    chain.add('zh-Hans');
  }
  for (final common in const ['en', 'zh-Hans']) {
    if (!chain.contains(common)) chain.add(common);
  }
  return chain;
}

/// The reader's language, as the unit helpers need it.
///
/// A provider rather than a parameter at every call site: a measurement is drawn deep inside lists and
/// rows, and threading a tag through forty widgets to reach one `Text` is how a codebase acquires a
/// parameter nobody can remove.
final unitLocaleProvider = Provider<String>(
  (ref) => ref.watch(localeSettingsProvider).primaryTag,
);

/// Every unit id this build can label, for the test that keeps the table complete.
///
/// Exposed as a getter rather than a constant so the test reads the table itself: a copy of the key list
/// beside the table would be a second thing to keep in step, which is the failure this exposes.
Set<String> get labelledUnitIds => _labels.keys.toSet();
