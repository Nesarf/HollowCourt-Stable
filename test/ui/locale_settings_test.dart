import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/ui/l10n/locale_catalogue.dart';
import 'package:hollow_court/ui/l10n/locale_providers.dart';
import 'package:hollow_court/ui/l10n/locale_settings.dart';

/// Section 12.4's localization layer, as far as the settings key and locale
/// resolution -- the two things that section names as missing.
///
/// **The tests are split by what they can prove.** The catalogue and the settings
/// model are asserted the ordinary way; then one test proves the *claim* those two
/// files make about themselves, by reading their own source and finding no import in
/// it. A comment saying "testable without Flutter" is worth nothing; a test that
/// fails the moment somebody adds an import is worth something.
void main() {
  group('the shipped locale catalogue', () {
    test('is section 12.4\'s thirteen, in its order, with its display names', () {
      // **The set the owner narrowed it to on 2026-09-22**: *"把语言选项中除了中英日的语言全部剔除（中文保留
      // 各种类型）"*. Korean, French, German, Italian, Russian, Spanish and Portuguese came out, and every
      // Chinese variant stayed -- so this list is six entries now and the eight that went are named in the
      // commit that removed them, which is where the record belongs rather than in a test that would fail
      // for a reader who never knew they existed.
      const expected = <String, String>{
        'zh-Hans': '简中',
        'zh-HK': '港繁',
        'zh-TW': '台繁',
        'ja': '日语',
      };

      expect(shippedLocales.length, 5,
          reason: 'four translations and the reference language -- 文言文 is deferred, not shipped');

      final shipped = shippedLocales.take(4).toList();
      expect(shipped.map((l) => l.tag).toList(), expected.keys.toList(),
          reason: 'the document\'s order is the picker\'s order');
      for (final locale in shipped) {
        expect(locale.nativeName, expected[locale.tag]);
      }
    });

    test('keeps the tag ASCII and the name not', () {
      final ascii = RegExp(r'^[A-Za-z][A-Za-z-]*$');
      for (final locale in shippedLocales) {
        expect(ascii.hasMatch(locale.tag), isTrue,
            reason: '${locale.tag} is a key the machine matches on');
        expect(locale.nativeName.trim(), isNotEmpty);
      }

      // Section 12.4's first rule is "real UTF-8, the actual Chinese". `English` is
      // the one honest exception -- it is already in its own alphabet.
      final nonAscii = shippedLocales
          .where((l) => l.nativeName.runes.any((r) => r > 0x7F))
          .length;
      expect(nonAscii, 4);
    });

    test('has no duplicate tag, whatever the case', () {
      final seen = <String>{};
      for (final locale in shippedLocales) {
        expect(seen.add(locale.tag.toLowerCase()), isTrue,
            reason: '${locale.tag} appears twice');
      }
    });

    test('does not carry 自定义中文 as a locale', () {
      // Section 12.4: it is section 8's overlay layer, not a fifteenth locale.
      expect(shippedLocales.any((l) => l.nativeName.contains('自定义')), isFalse);
      expect(byTag('zh-Custom'), isNull);
    });

    test('carries the reference language, or the fallback hands English readers '
        'Chinese', () {
      expect(byTag(referenceTag), isNotNull);
      expect(resolveLocaleTag('en-US'), referenceTag);
    });
  });

  group('languageOf', () {
    test('takes the subtag before the first hyphen', () {
      expect(languageOf('zh-Hans'), 'zh');
      expect(languageOf('zh'), 'zh');
      expect(languageOf('ZH-HANS'), 'zh');
      // `lzh` is no longer shipped (see the catalogue), but the *subtag* still parses: a system that
      // reports it must resolve to something this build has rather than to nothing.
      expect(languageOf('lzh'), 'lzh');
      expect(resolveLocaleTag('lzh'), fallbackTag);
    });
  });

  group('byTag', () {
    test('matches without regard to case, and refuses what it does not ship', () {
      expect(byTag('zh-Hans')?.nativeName, '简中');
      expect(byTag('ZH-HANS')?.nativeName, '简中');
      expect(byTag('zh-hans')?.nativeName, '简中');
      expect(byTag('ar'), isNull);
      expect(byTag(''), isNull);
      expect(byTag(null), isNull);
    });
  });

  group('resolveLocaleTag', () {
    test('rule 1: an exact tag wins', () {
      expect(resolveLocaleTag('zh-HK'), 'zh-HK');
      expect(resolveLocaleTag('ja'), 'ja');
    });

    test('rule 2: a bare language takes its named variant', () {
      expect(resolveLocaleTag('zh'), 'zh-Hans');
    });

    test('rule 3: a language with one variant takes it, region and all', () {
      expect(resolveLocaleTag('ja-JP'), 'ja');
      expect(resolveLocaleTag('en-GB'), 'en');
      expect(resolveLocaleTag('zh-TW'), 'zh-TW');
    });

    test('**and a language this build no longer ships is the fallback, not itself**', () {
      // The owner narrowed the set to Chinese, English and Japanese on 2026-09-22, so a system set to
      // Korean or German gets the fallback rather than a language the build cannot draw. The first version
      // of this test asserted `pt → pt` and `ko → ko-KR`, which was right while eight more locales shipped
      // and became a claim about a language nobody can select.
      for (final gone in ['ko', 'ko-KR', 'fr', 'de', 'de-AT', 'it', 'ru', 'es', 'pt', 'pt-BR']) {
        expect(resolveLocaleTag(gone), fallbackTag, reason: gone);
      }
    });

    test('rule 4: anything else is the fallback', () {
      expect(resolveLocaleTag('ar'), fallbackTag);
      expect(resolveLocaleTag('th-TH'), fallbackTag);
      expect(resolveLocaleTag(null), fallbackTag);
      expect(resolveLocaleTag(''), fallbackTag);
    });

    test('never walks sideways to a neighbouring region', () {
      // The one rule worth stating twice: a reader in Macau gets simplified Chinese
      // by the fallback, not 港繁 by a guess about geography.
      expect(resolveLocaleTag('zh-MO'), fallbackTag);
      expect(resolveLocaleTag('zh-MO'), isNot('zh-HK'));
    });

    test('always returns a tag this build actually ships', () {
      const inputs = <String?>[
        'zh-Hans', 'zh', 'zh-MO', 'zh-TW', 'ja', 'ja-JP', 'en', 'en-US',
        'pt-BR', 'fr-CA', 'ar', '', null, 'xx-YY',
      ];
      for (final input in inputs) {
        final resolved = resolveLocaleTag(input);
        expect(byTag(resolved), isNotNull,
            reason: '$input resolved to $resolved, which is not shipped');
      }
    });
  });

  group('LocaleSettings', () {
    test('a first run takes the primary from the system and pairs it', () {
      final settings = LocaleSettings.initial('ja-JP');
      expect(settings.primaryTag, 'ja');
      expect(settings.secondaryTag, referenceTag);
      expect(settings.dualCopy, isTrue,
          reason: 'section 2.7 is served by the switch, not by the default');
    });

    test('a run in the reference language does not pair it with itself', () {
      final settings = LocaleSettings.initial('en-US');
      expect(settings.primaryTag, referenceTag);
      expect(settings.secondaryTag, isNot(settings.primaryTag));
      expect(settings.secondaryTag, fallbackTag);
    });

    test('the guard is one check in one place, and it moves the secondary', () {
      // Pointing the primary at the language the secondary already holds.
      final clash = const LocaleSettings(
        primaryTag: 'ja',
        secondaryTag: 'en',
        dualCopy: true,
      ).guarded();
      expect(clash.primaryTag, 'ja', reason: 'the primary is what is read');
      expect(clash.secondaryTag, referenceTag);
    });

    test('every mutator ends in the guard, so no caller has to remember it', () {
      final settings = LocaleSettings.initial('zh-Hans')
          .withSecondary('ja')
          .withPrimary('ja');
      expect(settings.primaryTag, 'ja');
      expect(settings.secondaryTag, isNot('ja'));
    });

    test('refuses a tag this build does not ship', () {
      final base = LocaleSettings.initial('zh-Hans');
      expect(base.withPrimary('ar'), base);
      expect(base.withSecondary('klingon'), base);
    });

    test('the second line is absent when the reader turned it off', () {
      final paired = LocaleSettings.initial('zh-Hans');
      expect(paired.secondaryOrNull, referenceTag);
      expect(paired.withDualCopy(false).secondaryOrNull, isNull);
      expect(paired.withDualCopy(false).secondaryTag, referenceTag,
          reason: 'switching it off must not forget the choice');
    });

    test('compares by value, so an identical settings object is not a change', () {
      expect(LocaleSettings.initial('zh-Hans'), LocaleSettings.initial('zh-Hans'));
      expect(LocaleSettings.initial('zh-Hans').hashCode,
          LocaleSettings.initial('zh-Hans').hashCode);
      expect(LocaleSettings.initial('zh-Hans'),
          isNot(LocaleSettings.initial('ja')));
    });
  });

  group('LocaleSettingsStore', () {
    late Directory directory;

    setUp(() => directory = Directory.systemTemp.createTempSync('hollow_locale'));
    tearDown(() => directory.deleteSync(recursive: true));

    File file() => File('${directory.path}${Platform.pathSeparator}locale.json');

    test('round-trips the three settings', () async {
      final store = LocaleSettingsStore(file());
      // Two *different* shipped languages, because the store re-resolves what it reads and a pair pointing
      // at one language is rewritten to satisfy the guard -- which is correct behaviour and was making this
      // test assert the round trip of a state that cannot exist.
      const written = LocaleSettings(
        primaryTag: 'ja',
        secondaryTag: 'en',
        dualCopy: false,
      );

      await store.write(written);
      expect(await store.read(), written);
    });

    test('an absent file is a first run, not a failure', () async {
      expect(await LocaleSettingsStore(file()).read(), isNull);
    });

    test('an unreadable file is a first run, not a crash', () async {
      final store = LocaleSettingsStore(file());
      await file().writeAsString('{ this is not json');
      expect(await store.read(), isNull);

      await file().writeAsString('');
      expect(await store.read(), isNull);

      await file().writeAsString('["not", "an", "object"]');
      expect(await store.read(), isNull);
    });

    test('re-resolves a stored tag rather than trusting it', () async {
      // A tag this build no longer ships must not become the primary.
      await file().writeAsString(jsonEncode(<String, Object?>{
        'primary': 'ar',
        'secondary': 'klingon',
        'dualCopy': true,
      }));

      final read = await LocaleSettingsStore(file()).read();
      expect(read, isNotNull);
      expect(byTag(read!.primaryTag), isNotNull);
      expect(byTag(read.secondaryTag), isNotNull);
    });

    test('applies the guard to what it read, so a hand-edited file cannot '
        'produce a pair with itself', () async {
      await file().writeAsString(jsonEncode(<String, Object?>{
        'primary': 'ja',
        'secondary': 'ja',
        'dualCopy': true,
      }));

      final read = await LocaleSettingsStore(file()).read();
      expect(read!.primaryTag, isNot(read.secondaryTag));
    });

    test('writes ASCII keys and English names for them', () async {
      await LocaleSettingsStore(file())
          .write(const LocaleSettings(primaryTag: 'zh-Hans', secondaryTag: 'en', dualCopy: true));

      final raw = await file().readAsString();
      expect(raw, contains('"primary"'));
      expect(raw, contains('"secondary"'));
      expect(raw, contains('"dualCopy"'));
      expect(RegExp(r'^[\x00-\x7F]*$').hasMatch(raw), isTrue,
          reason: 'section 12.4: a key is something a person never reads');
    });
  });

  group('the claim the two pure files make about themselves', () {
    // Both files say they can be tested without Flutter, and that is what lets them
    // live in `lib/ui/` while staying outside the suite that needs a binding. A
    // comment cannot enforce that; this can -- the same move section 3 makes when it
    // lets the domain suite fail rather than trusting anybody to remember.
    //
    // The property is *no package import*, not *no import at all*: the settings model
    // imports the catalogue, and a relative import between two files that both stay
    // off `package:flutter` keeps the property intact.
    for (final path in <String>[
      'lib/ui/l10n/locale_catalogue.dart',
      'lib/ui/l10n/locale_settings.dart',
    ]) {
      test('$path imports no package', () {
        final source = File(path).readAsStringSync();
        final packageImports = RegExp(
          "import\\s+'(package:|dart:)",
        ).allMatches(source).map((m) => m.group(0)).toList();
        expect(packageImports, isEmpty,
            reason: '$path must stay usable without a Flutter binding');
      });
    }

    test('the catalogue has no import of any kind', () {
      final source = File('lib/ui/l10n/locale_catalogue.dart').readAsStringSync();
      final imports =
          RegExp(r'^\s*import\s', multiLine: true).allMatches(source).length;
      expect(imports, 0);
    });
  });
}
