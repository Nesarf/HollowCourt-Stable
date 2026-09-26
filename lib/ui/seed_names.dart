import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'l10n/locale_providers.dart';

/// **What the seed's ingredients and drinks are called in the reader's language.**
///
/// The seed names are English -- `Absinthe`, `Lime juice`, `Adonis` -- because they were harvested from
/// English-language sources, and the owner asked for them to be translated on 2026-09-22, in the same
/// message as the Chinese variants: *"酒名也要翻译"*.
///
/// WHERE THE TRANSLATIONS LIVE, and why not in the seed. Section 15 is explicit that the seed is a **build
/// artifact of third-party data**: the sources are not redistributed, the artifact is git-ignored, and a
/// fresh clone has no library until the pipeline runs. A translation is *our* work, so it belongs in git --
/// `data/names/names.json`, keyed by the library's own ids so the two can be versions of each other without
/// the names file carrying any of somebody else's data.
///
/// WHY A FILE AND NOT CODE. 164 ingredient names and 502 drink names, in four languages each, is data by
/// any measure; a Dart file would be a very large Dart file, and the people who can review a translation
/// are not always the people who can review a diff.
///
/// **A missing name is the English one, which is why nothing here can fail.** A seed entry the file does
/// not cover -- a new ingredient, a drink translated later -- shows its own English name rather than an id
/// or an empty box, exactly as the copy layer falls back rather than showing nothing.
final class SeedNames {
  const SeedNames(this._byId, [this._steps = const {}]);

  /// id -> locale tag -> name.
  final Map<String, Map<String, String>> _byId;

  /// id -> locale tag -> the drink's instructions, sentence by sentence.
  ///
  /// **Steps are sentences rather than names, and that is why they needed their own section.** A name is a
  /// noun that two languages often share and a converter can sometimes carry; an instruction is a sentence
  /// somebody wrote, and there is no table that turns "Shake everything with ice" into 加冰摇匀. The owner's
  /// instruction on 2026-09-22 was to finish the translations, and this is the part of the library that was
  /// still English while every name was already in four forms.
  final Map<String, Map<String, List<String>>> _steps;

  static const String assetPath = 'assets/names/names.json';

  /// The name for [id] in [locale], or [fallback] when this build has no translation for it.
  ///
  /// The fallback chain is the same shape as everywhere else in this application: the tag, the language's
  /// written base (a Hong Kong reader gets the simplified line rather than English when 港繁 has not been
  /// written for that entry), then English, then the seed's own name.
  String nameFor(String id, String locale, {required String fallback}) {
    final byLocale = _byId[id];
    if (byLocale == null) return fallback;
    for (final candidate in _chain(locale)) {
      final name = byLocale[candidate];
      if (name != null && name.isNotEmpty) return name;
    }
    return fallback;
  }

  /// True when the translation file itself names this id in [locale].
  bool isTranslated(String id, String locale) =>
      (_byId[id]?[locale] ?? '').isNotEmpty;

  int get ingredientCount => _byId.length;

  /// The instructions for [id] in [locale], or null when this build has not translated them.
  ///
  /// Null rather than the English steps, so the caller decides what a missing translation means: the recipes
  /// page falls back to the drink's own English instructions, and a counter can tell the difference between
  /// "translated" and "fell back" -- which a method that quietly returned English could not.
  List<String>? stepsFor(String id, String locale) {
    final byLocale = _steps[id];
    if (byLocale == null) return null;
    for (final candidate in _chain(locale)) {
      final steps = byLocale[candidate];
      if (steps != null && steps.isNotEmpty) return steps;
    }
    return null;
  }

  /// How many drinks have instructions in [locale], for the progress counter.
  int stepsTranslatedIn(String locale) =>
      _steps.values.where((byLocale) => (byLocale[locale] ?? const []).isNotEmpty).length;

  int get stepCount => _steps.length;

  static List<String> _chain(String tag) {
    final chain = <String>[tag];
    final dash = tag.indexOf('-');
    final language = dash > 0 ? tag.substring(0, dash).toLowerCase() : tag.toLowerCase();
    // **The written base, and only for Chinese.** 港繁 and 台繁 are written for every ingredient here, but a
    // Chinese variant that has not been written for one entry should fall back to 简中 rather than to
    // English -- they are the same language, and the simplified line is a translation the reader can read.
    if (language == 'zh' && tag != 'zh-Hans') chain.add('zh-Hans');
    // **And then English, which is not a translation here: it is the seed's own language.** The names in
    // `seed.json` are English because the sources are, so an entry this file does not carry is best served
    // by the source name. A German reader getting Chinese because the chain ended at 'zh-Hans' was the
    // first version of this, and it was wrong for exactly that reason.
    chain.add('en');
    return chain;
  }

  /// Reads the file. A malformed or absent file yields an **empty** table rather than an error: a name is a
  /// label, and a label must never be the reason an application does not open (the same rule the display
  /// settings and the identity store follow).
  factory SeedNames.fromJson(String source) {
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map<String, Object?>) return const SeedNames({});
      final byId = <String, Map<String, String>>{};
      final steps = <String, Map<String, List<String>>>{};
      for (final section in const ['ingredients', 'recipes']) {
        final entries = decoded[section];
        if (entries is! Map<String, Object?>) continue;
        entries.forEach((id, names) {
          if (names is! Map<String, Object?>) return;
          byId[id] = {
            for (final entry in names.entries)
              if (entry.value is String && (entry.value! as String).isNotEmpty)
                entry.key: entry.value! as String,
          };
        });
      }
      // The steps section, read the same forgiving way: a drink the file does not carry, or a locale it does
      // not carry, simply has no steps and the caller falls back.
      final stepSection = decoded['steps'];
      if (stepSection is Map<String, Object?>) {
        stepSection.forEach((id, byLocale) {
          if (byLocale is! Map<String, Object?>) return;
          final forId = <String, List<String>>{};
          byLocale.forEach((locale, list) {
            if (list is! List) return;
            final steps = [
              for (final step in list)
                if (step is String && step.trim().isNotEmpty) step,
            ];
            if (steps.isNotEmpty) forId[locale] = steps;
          });
          if (forId.isNotEmpty) steps[id] = forId;
        });
      }
      return SeedNames(byId, steps);
    } on Object {
      return const SeedNames({});
    }
  }
}

/// The translation table, loaded once.
final seedNamesProvider = FutureProvider<SeedNames>((ref) async {
  try {
    return SeedNames.fromJson(await rootBundle.loadString(SeedNames.assetPath));
  } on Object {
    // No asset, or an unreadable one: every name falls back to the seed's own, which is what the
    // application showed before this file existed.
    return const SeedNames({});
  }
});

/// The reader's language, as a name lookup needs it.
final seedNameLocaleProvider = Provider<String>(
  (ref) => ref.watch(localeSettingsProvider).primaryTag,
);
