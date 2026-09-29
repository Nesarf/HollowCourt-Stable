/// The shipped locales of section 12.4, and how a system tag resolves to one.
///
/// **The list is the document's; two things here are decisions and are marked as
/// such.** Section 12.4 says of its own table: *"The list is settled; the default
/// and the fallback chain are not, and nothing is implemented."* This file
/// implements it, which means it has to answer those two questions. They are
/// marked [decision] rather than quoted as rules, because a reader must be able to
/// tell the document's word from this file's.
///
/// **The display name is UTF-8 and the tag is ASCII, on purpose.** Section 12.4's
/// first rule is that everything a person reads is real UTF-8 -- *"the actual micro
/// sign, the actual Chinese, the actual accents"* -- while keys and tags stay ASCII
/// for the machine. [ShippedLocale] therefore carries both, and the test asserts each
/// half stays in its own alphabet.
///
/// **A tension in the document, followed rather than resolved.** The table's column is
/// headed *Display name (native)* and the prose beside it says a picker *"shows every
/// language in its own script"* -- but the column itself is written in Chinese:
/// `简体中文`, `文言文`, `港繁`, `台繁`, `朝鲜语`, `韩语`. The two cannot both be
/// literal. This file follows the **column**, because the column is the part section
/// 12.4 calls settled and the prose is a general rule about encoding. So `日本語` would
/// sit under `日语` only if the document said so, and it does not.
///
/// That is recorded here rather than fixed quietly: renaming a settled list is the
/// reader's decision, not an implementer's, and a picker that shows every language in
/// its own script is a different product from one that shows them in Chinese. **Asked,
/// not assumed.**
///
/// **自定义中文 is deliberately absent.** Section 12.4 is explicit that it is not a
/// fifteenth locale: it is section 8's overlay layer applied to terms, the user's own
/// words *on top of* the shipped data, so they survive an update and are never
/// something this project redistributes. Listing it here would duplicate machinery the
/// project already has, and would put a user's words into the seed.
///
/// **Nothing in this file imports anything.** That is the same discipline
/// `dual_copy.dart` states for itself: the domain layer may not reach for Flutter,
/// and a type layer with no imports is the only kind that can be tested on the plain
/// Dart VM, where a single Flutter import would stop the suite from running.
library;

/// One language this application can be read in.
///
/// Both fields are load-bearing and they are not redundant: [nativeName] is what a
/// person reads and [tag] is what a machine matches on. Section 12.4's two released
/// cases bracket what happens when only one is present -- eight directories for six
/// languages, with `English(Alpha ver)` as an identity, against a content bundle
/// named `<display name>(<bcp-47 tag>)` where the tag is what disambiguates.
final class ShippedLocale {
  const ShippedLocale(this.tag, this.nativeName);

  /// The BCP-47 tag, spelled as section 12.4 spells it. ASCII.
  final String tag;

  /// The language's name in its own script. Real UTF-8.
  final String nativeName;

  @override
  String toString() => '$nativeName ($tag)';
}

/// [decision] The language a string falls back to when nothing else matches.
///
/// Section 12.4 leaves this open. It is `zh-Hans` because the copy inventory is
/// authored with Chinese as the primary line -- `Copy.appName` has rendered as
/// `空庭 · Hollow Court` since section 0.1, for the task switcher, which shows one
/// string and this is the one string. A fallback that disagreed with the line every
/// pair is already written around would make the fallback a second primary.
const String fallbackTag = 'zh-Hans';

/// The revision language: the second line of a pair, when a reader wants two.
///
/// Section 12.4 settles this one itself -- *"One reference language, defaulting to
/// English, itself a setting."* It is a constant here and a setting on
/// [LocaleSettings], which is what "itself a setting" means.
const String referenceTag = 'en';

/// Every language this build carries, in the order a picker should show them.
///
/// The first thirteen are section 12.4's table verbatim, in its order, with its
/// display names. The variants are deliberate rather than excessive, as the document
/// says: 港繁 and 台繁 differ in vocabulary and not only in glyphs, and 朝鲜语 and
/// 韩语 are two orthographic standards of one language.
///
/// **`en` is the fourteenth entry and is not in the document's table.** [decision]
/// It is here because English is not a *planned* translation -- it is the language
/// 24 of the 47 constants in `Copy` are already written in, and the second line of
/// the other 23. A reader whose system is English and who could not select it would
/// be handed Chinese copy by the fallback above, which is the one outcome the
/// reference language exists to prevent. Flagged rather than assumed: if section
/// 12.4's table is meant to be exhaustive, this entry should come out and the
/// fallback should be revisited.
const List<ShippedLocale> shippedLocales = <ShippedLocale>[
  // **The set the owner narrowed it to on 2026-09-22**: Chinese in all its variants, English, and
  // Japanese. *"把语言选项中除了中英日的语言全部剔除（中文保留各种类型）"* -- so Korean, French, German,
  // Italian, Russian, Spanish and Portuguese came out, and every Chinese variant stayed.
  //
  // **The three Chinese variants share one written base on purpose.** [localeFallbacks] resolves `zh-HK`
  // and `zh-TW` to `zh-Hans` when a line has not been written for them, because 港繁 and 台繁 differ in
  // *vocabulary* rather than only in glyphs: the lines where they differ are worth writing and the lines
  // where they do not are not worth duplicating 158 times. 文言文 is a register rather than a variant and
  // is expected to be the sparsest of the three.
  ShippedLocale('zh-Hans', '简中'),
  ShippedLocale('zh-HK', '港繁'),
  ShippedLocale('zh-TW', '台繁'),
  // **`lzh` (文言文) is deferred rather than dropped, and it is not in the picker until it is translated.**
  // The owner's decision on 2026-09-22: *"文言文可以暂时先不弄（先设置为不可选）"*. 文言 is a register rather
  // than a script, no converter produces it, and an option that switches the interface to 简中 while calling
  // itself 文言文 would be a control that lies about what it did. Re-adding it is this one line plus 163
  // lines of classical Chinese -- and the resolution code already knows the tag, so nothing else changes.
  ShippedLocale('ja', '日语'),
  ShippedLocale(referenceTag, 'English'),
];
/// The language subtag of a tag, lowercased: `zh-Hans` and `zh-HK` are both `zh`.
String languageOf(String tag) {
  final cut = tag.indexOf('-');
  return (cut <= 0 ? tag : tag.substring(0, cut)).toLowerCase();
}

/// The language as a person should see it, or `null` if this build has no such
/// language.
ShippedLocale? byTag(String? tag) {
  if (tag == null || tag.isEmpty) return null;
  final wanted = tag.toLowerCase();
  for (final locale in shippedLocales) {
    if (locale.tag.toLowerCase() == wanted) return locale;
  }
  return null;
}

/// [decision] Which variant a bare language resolves to when the system gives none.
///
/// A system reports `zh-TW` or `ko-KR`, but it may also report a bare `zh`, and
/// section 12.4 ships three Chinese and two Korean variants. Leaving this to "the
/// first one in the list" would make 简体中文 and 朝鲜语 the accidental answers to a
/// question nobody asked. So the two ambiguous cases are named:
///
/// * `zh` -> `zh-Hans`, because the copy inventory is authored in simplified.
/// * `ko` -> `ko-KR`, because it is the standard with the larger population and
///   the one a bare `ko` is conventionally taken to mean.
///
/// Every other shipped language has exactly one variant, so it needs no entry and
/// [resolveLocaleTag] finds it by language alone.
/// **Only for languages this build still ships, and the narrowing of the set is what proved it matters.**
/// `'ko': 'ko-KR'` sat here after Korean came out of `shippedLocales` on 2026-09-22, so a phone set to
/// Korean resolved to a tag that is **not in the catalogue** -- a setting pointing at a language the
/// picker cannot show and the fallback chain cannot draw. A test now asserts that *every* answer this
/// function gives is a shipped tag, which is the property that was assumed and never checked.
const Map<String, String> _preferredVariant = <String, String>{
  'zh': 'zh-Hans',
};

/// [decision] The fallback chain, in one place and in one direction.
///
/// Section 12.4 leaves this open alongside the default. The chain, in order:
///
/// 1. the exact tag, case-insensitively -- `zh-Hans` matches `zh-Hans`, `ZH-HANS`;
/// 2. the named variant for the bare language, per [_preferredVariant];
/// 3. the language's only variant, when it has exactly one;
/// 4. [fallbackTag].
///
/// It never walks *up* to a parent region or *sideways* to a neighbour: a reader on
/// `zh-MO` gets 简体中文 by rule 4, not 港繁 by a guess about geography.
///
/// A null or empty system tag is a real case -- a platform may report neither -- and
/// it is answered by [fallbackTag] rather than by throwing, because a language is
/// not a thing an application is entitled to refuse to start over.
String resolveLocaleTag(String? systemTag) {
  final exact = byTag(systemTag);
  if (exact != null) return exact.tag;

  if (systemTag == null || systemTag.isEmpty) return fallbackTag;

  final language = languageOf(systemTag);

  // **Validated against the catalogue rather than trusted**, so a map entry for a language that has since
  // been removed degrades to the fallback instead of producing an unusable tag.
  final named = _preferredVariant[language];
  if (named != null && byTag(named) != null) return named;

  final sameLanguage = shippedLocales
      .where((ShippedLocale locale) => languageOf(locale.tag) == language)
      .toList(growable: false);
  if (sameLanguage.length == 1) return sameLanguage.single.tag;

  return fallbackTag;
}
