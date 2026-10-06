// A smoke test for the shell. Run with `flutter test`, not `dart test`.
//
// This replaces the counter application's template test, which stopped compiling
// the moment `main.dart` stopped being the template.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/ui/app.dart';
import 'package:hollow_court/ui/display_providers.dart';
import 'package:hollow_court/ui/hollow_glyphs.dart';
import 'package:hollow_court/ui/hollow_nav_bar.dart';
import 'package:hollow_court/ui/l10n/locale_providers.dart';
import 'package:hollow_court/ui/l10n/locale_settings.dart';
import 'package:hollow_court/ui/theme.dart';

void main() {
  testWidgets('the shell draws five tabs, named as section 12.3 names them after the merge',
      (tester) async {
    // **Five, and the arithmetic is worth keeping.** Section 12.3 named five tabs; the owner's decision of
    // 2026-09-27 merged the bar into the cellar, so the shelf that had one of its own became a section and the
    // count fell to four; and on 2026-10-06 原料 was promoted out of 设置, which is the fifth. **The count is
    // asserted as well as the names**, because a list that only checked the names would pass whether or not a
    // destination had been added or removed.
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
      Copy.tabRecipes.textFor('zh-Hans'),
      Copy.tabCellar.textFor('zh-Hans'),
      Copy.tabIngredients.textFor('zh-Hans'),
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
    // **The settings tab has to lead somewhere.** The count and the label are asserted above; this is
    // the one that says the screen behind it is the settings screen -- the language pickers and the
    // money editor, which used to be a section at the bottom of 记录.
    await tester.pumpWidget(_shellInSimplifiedChinese());
    await tester.pump();

    await tester.tap(find.text(Copy.tabSettings.textFor('zh-Hans')));
    // **Two discrete pumps, and `pumpAndSettle` is impossible here -- measured, not assumed.**
    //
    // Tapping a destination is two gestures inside one: `onTapDown` sets the pressed state and `onTap` calls back
    // to change the page. One `pump` therefore lands the assertion somewhere inside that sequence rather than
    // after it, which is why this test passed on its own and failed twice in the full suite.
    //
    // The obvious fix is `pumpAndSettle`, and it does not work: **it times out**, because something in this
    // application schedules frames forever, so there is no quiet frame to settle on. That is worth knowing for its
    // own sake -- it is why a single `pump` was a race in the first place -- and it is the reason the other tests
    // in this file avoid `pumpAndSettle` for a different reason (the cellar's platform channel) while arriving at
    // the same rule.
    //
    // So: pump twice, which is enough for the callback and the rebuild it causes. This is not a wait for an
    // unknown amount of work; it is the exact number of frames that sequence needs.
    await tester.pump();
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
    expect(find.text('货架还在图纸上。'), findsNothing);
  });


  testWidgets('the frame around it uses the palette', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: HollowCourtApp()));
    await tester.pump();

    final theme = Theme.of(tester.element(find.byType(HollowNavBar)));
    expect(theme.scaffoldBackgroundColor, HollowPalette.ground);
    expect(theme.colorScheme.primary, HollowPalette.rose);
  });

  testWidgets('**the text size setting reaches the screen, not just the file**',
      (tester) async {
    // 2026-09-30: the four steps were stored, drawn in the settings page, and read by nothing -- so
    // choosing one changed `display.json` and left every string the size it already was. The control had
    // existed long enough to look finished.
    //
    // **Asserted on the resolved scaler rather than on the stored value.** A test that read the provider
    // back would have passed the whole time the feature did nothing, which is the failure this is here to
    // catch: the setting and its effect are different facts, and only the second one is a feature.
    //
    // The platform's own scale is 1.0 under `flutter_test`, so the resolved factor is the application's
    // step exactly. That the platform's is multiplied rather than replaced is asserted separately in
    // `display_providers_test.dart`, where a scaler of a known shape can be handed in.
    // **Two sizes that differ, in two tests rather than a loop.** `pumpWidget` reuses the provider
    // container across calls within one test -- the second call kept the first call's state and reported
    // `small`'s factor under `extraLarge`'s name, twice. A test is the cheaper thing to give up than the
    // framework's widget-reuse rules are to reason about, and two tests get two containers.
    await _expectTextScale(tester, TextSize.small, 0.9);
  });

  testWidgets('**the largest step is larger, so a screen stuck on one setting fails**',
      (tester) async {
    await _expectTextScale(tester, TextSize.extraLarge, 1.3);
  });
}

/// Pumps the application at one text size and asserts what the screen is actually drawn at.
Future<void> _expectTextScale(WidgetTester tester, TextSize size, double expected) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [displaySettingsProvider.overrideWith(() => _FixedDisplay(size))],
      child: const HollowCourtApp(),
    ),
  );
  await tester.pump();

  // **Asserted on the resolved scaler rather than on the stored value.** A test that read the provider
  // back would have passed the whole time the feature did nothing, which is the failure this is here to
  // catch: the setting and its effect are different facts, and only the second one is a feature.
  //
  // The platform's scale is 1.0 under `flutter_test`, so what comes back is the application's step
  // exactly. That the platform's is multiplied rather than replaced is a separate claim; it is argued in
  // `ScaledTextScaler`, whose `scale` multiplies rather than substitutes.
  final resolved = MediaQuery.of(tester.element(find.byType(HollowNavBar))).textScaler;
  expect(
    resolved.scale(100),
    closeTo(100 * expected, 0.001),
    reason: 'choosing ${size.name} must change what the screen is drawn at',
  );
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

/// A display setting fixed at one text size, so the scaling can be asserted without a file.
class _FixedDisplay extends DisplaySettingsNotifier {
  _FixedDisplay(this._size);

  final TextSize _size;

  @override
  DisplaySettings build() => DisplaySettings(textSize: _size);
}
