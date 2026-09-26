// A smoke test for the shell. Run with `flutter test`, not `dart test`.
//
// This replaces the counter application's template test, which stopped compiling
// the moment `main.dart` stopped being the template.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/ui/app.dart';
import 'package:hollow_court/ui/hollow_glyphs.dart';
import 'package:hollow_court/ui/hollow_nav_bar.dart';
import 'package:hollow_court/ui/l10n/locale_providers.dart';
import 'package:hollow_court/ui/l10n/locale_settings.dart';
import 'package:hollow_court/ui/bar_page.dart';
import 'package:hollow_court/ui/theme.dart';

void main() {
  testWidgets('the shell draws five tabs, named as section 12.3 names them',
      (tester) async {
    // **Five, and it was four.** The owner asked for a settings tab, so 12.3 names five now and the
    // settings that used to sit at the bottom of 记录 have a screen of their own. The count is
    // asserted as well as the names: four of the five were already here, and a list that only
    // checked the names would pass whether or not the fifth was added.
    // **The language is pinned, and that is the change of 2026-09-22 showing up in a test.** The tab labels
    // are resolved from the reader's locale now, and a test machine reports `en_US` -- so the labels here
    // would be English and an assertion about 简中 names would fail while the application was correct. Pinning
    // the locale is what makes the assertion about *the application's naming* rather than about the machine
    // the suite happens to run on.
    await tester.pumpWidget(_shellInSimplifiedChinese());
    // One pump, not pumpAndSettle: the cellar opens a file through a platform
    // channel that a widget test does not have, so the app is left in its
    // loading state rather than waited on. That is the honest state to assert
    // the shell in.
    await tester.pump();

    // **The bar is ours now, and the assertion moved with it.** It used to be Material's `NavigationBar` with
    // Material's icon font in every destination; on 2026-09-25 the owner's instruction was that the interface
    // itself has to be made here, so this checks the application's own bar rather than the toolkit's.
    expect(find.byType(HollowNavBar), findsOneWidget);
    expect(find.byType(HollowGlyphMark), findsNWidgets(5));
    for (final label in [
      Copy.tabStock.textFor('zh-Hans'),
      Copy.tabBar.textFor('zh-Hans'),
      Copy.tabRecipes.textFor('zh-Hans'),
      Copy.tabCellar.textFor('zh-Hans'),
      Copy.tabSettings.textFor('zh-Hans'),
    ]) {
      expect(find.text(label), findsWidgets, reason: label);
    }

    expect(
      tester.widget<HollowNavBar>(find.byType(HollowNavBar)).destinations.length,
      5,
    );
  });

  testWidgets("the Settings tab reaches the application's own settings",
      (tester) async {
    // **The fifth tab has to lead somewhere.** The count and the label are asserted above; this is
    // the one that says the screen behind it is the settings screen -- the language pickers and the
    // money editor, which used to be a section at the bottom of 记录.
    await tester.pumpWidget(_shellInSimplifiedChinese());
    await tester.pump();

    await tester.tap(find.text(Copy.tabSettings.textFor('zh-Hans')));
    await tester.pump();

    expect(find.byKey(const ValueKey('primary-locale-picker')), findsOneWidget);
    expect(find.byKey(const ValueKey('currencies')), findsOneWidget);
    expect(find.text(Copy.settingsPageTitle.primary.text), findsWidgets);
  });

  testWidgets('the Bar tab is the page now, not the apology for it',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(child: HollowCourtApp()));
    await tester.pump();

    // The Bar tab is the second destination. Until P2 it was a placeholder whose
    // text said the shelves were still on paper, and this test asserted that text
    // -- so the test encoded "the shelves do not exist yet". They do now, and the
    // assertion has to move with the fact rather than the fact with the assertion.
    //
    // Asserted by widget type rather than by content, because the page's content
    // depends on the event log loading, which a widget test has no directory for.
    // What is being checked here is that the tab is wired to the built page.
    // **Tapped by position in the bar, because there is no icon font to look up any more.** The five marks are
    // this project's own glyphs; naming one of them in a test would be asserting the drawing rather than the
    // wiring, and the wiring is what this test is for.
    final bar = find.byType(HollowNavBar);
    final box = tester.getRect(bar);
    await tester.tapAt(Offset(box.left + box.width * 0.3, box.center.dy));
    await tester.pump();
    expect(find.byType(BarPage), findsOneWidget);
    expect(find.text('货架还在图纸上。'), findsNothing);
  });


  testWidgets('the frame around it uses the palette', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: HollowCourtApp()));
    await tester.pump();

    final theme = Theme.of(tester.element(find.byType(HollowNavBar)));
    expect(theme.scaffoldBackgroundColor, HollowPalette.ground);
    expect(theme.colorScheme.primary, HollowPalette.rose);
  });
}

/// The application with its language pinned to 简中.
///
/// **A test machine reports `en_US`, and the tab labels are resolved from the reader's locale now**, so an
/// assertion about the Chinese names would fail while the application was correct. Pinning it is what makes
/// these assertions about *the application's naming* rather than about the machine the suite runs on.
Widget _shellInSimplifiedChinese() => ProviderScope(
  overrides: [
    localeSettingsProvider.overrideWith(
      () => _FixedLocale(
        const LocaleSettings(
          primaryTag: 'zh-Hans',
          secondaryTag: 'en',
          dualCopy: true,
        ),
      ),
    ),
  ],
  child: const HollowCourtApp(),
);

/// A locale that answers 简中 instead of whatever this machine reports.
class _FixedLocale extends LocaleSettingsNotifier {
  _FixedLocale(this._initial);

  final LocaleSettings _initial;

  @override
  LocaleSettings build() => _initial;
}
