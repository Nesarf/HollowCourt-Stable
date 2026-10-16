import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hollow_court/ui/display_providers.dart';
import 'package:hollow_court/ui/display_section.dart';
import 'package:hollow_court/ui/l10n/locale_providers.dart';
import 'package:hollow_court/ui/l10n/locale_settings.dart';
import 'package:hollow_court/ui/theme.dart';

/// **Every world, named, in every language this build speaks -- on the screen.**
///
/// ## Why a test and not a screenshot
///
/// The question "is the theme name drawn in each language" has twenty-five answers, and a screenshot shows one of
/// them at a time and needs somebody to click into 设置 first. **This is the instrument that matches the question**:
/// it asks all twenty-five, on the screen itself, and it says which one failed. The pictures are for *does it look
/// right*, which no assertion can answer.
///
/// ## What it holds
///
/// `theme_label_test.dart` asks the mapping directly: every world resolves to a name that is not its own key. **This
/// asks the drawing side**: that the picker puts that name on a chip, in the language in force. The two can fail
/// apart -- a mapping nobody calls is a name nobody reads, which is exactly what `Copy.themeWhiteCourt` was for ten
/// days after the world it named was deleted.
class _FixedLocale extends LocaleSettingsNotifier {
  _FixedLocale(this.tag);

  final String tag;

  @override
  LocaleSettings build() => LocaleSettings(primaryTag: tag, secondaryTag: 'en', dualCopy: false);
}

/// A display notifier that never reaches for the file system.
///
/// The real one restores from `display.json` through `path_provider`, which a widget test has no channel for -- so it
/// would sit in its default state and the test would be asserting about a theme the machine happened to store.
class _FixedDisplay extends DisplaySettingsNotifier {
  @override
  DisplaySettings build() => const DisplaySettings();
}

void main() {
  const languages = ['zh-Hans', 'zh-HK', 'zh-TW', 'ja', 'en'];

  Future<void> pump(WidgetTester tester, String tag) async {
    // **A fresh scope per language, and the key is the whole of it.**
    //
    // The first version pumped the same `ProviderScope` five times with different overrides, and **Riverpod kept the
    // container it already had**: the element tree matched, so the scope was not rebuilt, and every language got the
    // first one's locale. The symptom was a dump in which all five languages drew the same Chinese names -- which
    // read as *the picker ignores the language*, and was a test harness reusing state between iterations.
    //
    // **A `ValueKey` on the scope makes each pump a different widget**, so the old container is thrown away and the
    // override is built. Recorded because the failure mode is silent: nothing errors, the assertions simply describe
    // the first case five times.
    await tester.pumpWidget(
      ProviderScope(
        key: ValueKey('scope-$tag'),
        overrides: [
          localeSettingsProvider.overrideWith(() => _FixedLocale(tag)),
          displaySettingsProvider.overrideWith(_FixedDisplay.new),
        ],
        child: MaterialApp(
          theme: HollowTheme.build(),
          home: const Scaffold(body: SingleChildScrollView(child: DisplaySection())),
          // **Both, and the second one cost a run to learn.** `MaterialApp` resolves the requested locale against
          // `supportedLocales`, whose default is `en-US` alone, so `locale:` by itself is a request the app quietly
          // declines -- but the chips are drawn from the *settings* tag here rather than from `Localizations`, so
          // this test does not depend on either. Recorded because the next reader will wonder.
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('**every world has a chip, and every chip is named in the language in force**', (tester) async {
    for (final tag in languages) {
      await pump(tester, tag);

      for (final theme in HollowPalette.all) {
        final expected = Copy.themeLabelFor(theme).textFor(tag);
        expect(
          find.byKey(ValueKey('theme-${theme.name}')),
          findsOneWidget,
          reason: '${theme.name} has no chip in $tag',
        );
        expect(
          find.text(expected),
          findsWidgets,
          reason: '${theme.name} is not drawn as "$expected" in $tag',
        );
        // **And the id is never what is drawn.** The one assertion that would have caught the light world reading
        // `cosmicLatte` for ten days, asked of the screen rather than of the mapping.
        expect(
          find.text(theme.name),
          findsNothing,
          reason: '${theme.name} is drawn as its own key in $tag',
        );
      }
    }
  });

  testWidgets('**and the five names are five different names in every language**', (tester) async {
    // A language where two worlds collapsed to one string would pass the test above twice and leave a reader unable
    // to tell two chips apart. Cheap to ask, and it is the failure a translation table is most likely to have.
    for (final tag in languages) {
      final names = [for (final theme in HollowPalette.all) Copy.themeLabelFor(theme).textFor(tag)];
      expect(names.toSet(), hasLength(names.length), reason: 'two worlds share a name in $tag: $names');
    }
  });
}
