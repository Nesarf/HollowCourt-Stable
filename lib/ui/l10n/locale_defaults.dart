/// Which units and which money a locale reaches for, by default.
///
/// **A default is not a restriction.** Every unit and every currency here is
/// replaceable by the reader and the replacements are stored; this table only decides
/// what a fresh cellar offers before anybody has said. That is why it lives in the UI
/// layer beside the locale catalogue rather than in the domain: `g` and `CNY` are
/// domain types, but "a person who reads 简中 probably measures in grams" is a fact
/// about a person, and the domain has no business holding it.
///
/// The tags are resolved through the catalogue's own fallback chain, so a locale this
/// table has no row for lands on the same language the copy does -- a screen whose text
/// fell back to 简中 while its units fell back somewhere else would be a screen
/// disagreeing with itself.
library;

import '../../domain/pricing/price.dart';
import '../../domain/preferences/choice_set.dart';
import '../../domain/units/measure_set.dart';
import 'locale_catalogue.dart';

/// The measure sets for a locale tag.
///
/// Two shapes, and they are the two measurement cultures rather than two countries:
/// **metric**, which is every shipped locale including English-with-a-U, and
/// **US customary**, which is what plain `en` gets because that is the locale the
/// reference language resolves to and a fluid ounce is what an American bar reaches
/// for.
///
/// Every set is one dimension except `either`, which mixes them on purpose -- see
/// [MeasureSet.isLegal].
LocaleMeasures measuresFor(String? tag) =>
    _measuresByLocale[resolveLocaleTag(tag)] ?? _metric;

/// The sets a bare language gets, for a caller that has already resolved one.
LocaleMeasures measuresForLanguage(String language) =>
    _measuresByLocale[language] ?? _metric;

/// Built rather than declared `const`, and the reason is worth a line: a [ChoiceSet]
/// is created by a factory -- it checks the uniqueness rule -- and a factory cannot be
/// const. `fromIds` is also what refuses a unit id this system does not carry, so
/// building them is how a typo in this table becomes an exception rather than a locale
/// quietly offering one unit fewer.
final LocaleMeasures _metric = LocaleMeasures(
  sets: [
    // 固体用克. The kilogram is beside it because a sack of sugar is not measured in
    // thousands of grams, and the imperial pair comes last because a metric reader
    // occasionally has a recipe that is not.
    MeasureSet.fromIds(
      MatterState.solid,
      primary: 'g',
      secondary: ['kg', 'ozm', 'lb'],
    ),
    // 液体用毫升, with the litre for a bottle and the fluid ounce for a recipe
    // somebody else wrote.
    MeasureSet.fromIds(
      MatterState.liquid,
      primary: 'ml',
      secondary: ['cl', 'l', 'oz'],
    ),
    // 糖浆/蜂蜜: measured either way, defaulted to volume with the grams beside it,
    // which is the instruction almost word for word.
    MeasureSet.fromIds(
      MatterState.either,
      primary: 'ml',
      secondary: ['g', 'cl', 'oz'],
    ),
  ],
);

final LocaleMeasures _usCustomary = LocaleMeasures(
  sets: [
    MeasureSet.fromIds(
      MatterState.solid,
      primary: 'ozm',
      secondary: ['lb', 'g', 'kg'],
    ),
    MeasureSet.fromIds(
      MatterState.liquid,
      primary: 'oz',
      secondary: ['ml', 'l', 'tsp'],
    ),
    // The same admission as the metric one: a syrup is poured. The ounce is the
    // default here because that is the culture's pour, and the millilitre is offered
    // because a syringe is metric everywhere.
    MeasureSet.fromIds(
      MatterState.either,
      primary: 'oz',
      secondary: ['ml', 'g', 'tsp'],
    ),
  ],
);

final Map<String, LocaleMeasures> _measuresByLocale = <String, LocaleMeasures>{
  'zh-Hans': _metric,
  'lzh': _metric,
  'zh-HK': _metric,
  'zh-TW': _metric,
  'ko-KP': _metric,
  'ko-KR': _metric,
  'ja': _metric,
  'fr': _metric,
  'de': _metric,
  'it': _metric,
  'ru': _metric,
  'es': _metric,
  'pt': _metric,
  'en': _usCustomary,
};

/// The currency a locale prices its bottles in.
///
/// **A default, and one of up to four.** 钱默认跟语言区走（可换）: the primary is the
/// locale's own money and [currenciesFor] carries three more slots the reader can
/// fill. The table is deliberately one row per currency area rather than per locale --
/// 港繁 and 台繁 are different locales with different money, and that is worth a row
/// each; 文言文 is not a currency area, so it takes the fallback's money the way it
/// takes the fallback's units.
Currency currencyFor(String? tag) => currenciesFor(tag).primary;

/// The reader's currency slots for a locale, before they have changed anything.
///
/// Primary plus **two** secondaries rather than three, and that is a decision rather
/// than an oversight: the cap is three ([ChoiceSet.maxSecondary]), and every secondary
/// slot filled by default is a slot the reader has to clear before it holds what they
/// want. A second slot is pre-filled where a currency area genuinely runs on two --
/// Hong Kong beside CNY, and the euro beside the franc-and-mark neighbours -- and
/// otherwise the slots are left empty.
ChoiceSet<Currency> currenciesFor(String? tag) {
  final resolved = resolveLocaleTag(tag);
  return _currenciesByLocale[resolved] ?? _fallbackCurrencies;
}

final ChoiceSet<Currency> _fallbackCurrencies =
    ChoiceSet<Currency>(primary: Currency.cny, secondary: [Currency.usd]);

final Map<String, ChoiceSet<Currency>> _currenciesByLocale = {
  'zh-Hans': ChoiceSet<Currency>(primary: Currency.cny, secondary: [Currency.usd]),
  // 文言文 is not a currency area and not a measurement culture either, so both tables
  // send it to the fallback rather than inventing a historical currency.
  'lzh': ChoiceSet<Currency>(primary: Currency.cny, secondary: [Currency.usd]),
  'zh-HK': ChoiceSet<Currency>(primary: Currency.hkd, secondary: [Currency.cny]),
  'zh-TW': ChoiceSet<Currency>(primary: Currency.twd, secondary: [Currency.usd]),
  'ko-KP': ChoiceSet<Currency>(primary: Currency.krw, secondary: [Currency.usd]),
  'ko-KR': ChoiceSet<Currency>(primary: Currency.krw, secondary: [Currency.usd]),
  'ja': ChoiceSet<Currency>(primary: Currency.jpy, secondary: [Currency.usd]),
  'fr': ChoiceSet<Currency>(primary: Currency.eur, secondary: [Currency.gbp]),
  'de': ChoiceSet<Currency>(primary: Currency.eur, secondary: [Currency.usd]),
  'it': ChoiceSet<Currency>(primary: Currency.eur, secondary: [Currency.usd]),
  'ru': ChoiceSet<Currency>(primary: Currency.rub, secondary: [Currency.eur]),
  'es': ChoiceSet<Currency>(primary: Currency.eur, secondary: [Currency.usd]),
  'pt': ChoiceSet<Currency>(primary: Currency.eur, secondary: [Currency.usd]),
  'en': ChoiceSet<Currency>(primary: Currency.usd, secondary: [Currency.eur]),
};
