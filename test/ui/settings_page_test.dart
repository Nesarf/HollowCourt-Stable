import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hollow_court/ui/l10n/locale_settings.dart';
import 'package:hollow_court/ui/l10n/locale_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/ui/display_providers.dart';
import 'package:hollow_court/ui/settings_page.dart';
import 'package:hollow_court/ui/theme.dart';

/// The Settings tab's five sections, and the one control that changes anything on this screen.
///
/// **A section that renders nothing is the failure this guards.** Every one of these was added by
/// name -- 关于空庭, 界面样式, 开发者工具, 检查完整性 -- and the way a settings screen goes wrong is
/// not that a heading is misspelled: it is that a section is added to the page, compiles, and shows
/// an empty box because the widget it wraps returned nothing in the state it was built in.
void main() {
  /// Pumps the page into a viewport tall enough to hold all of it.
  ///
  /// **The page is a `ListView`, and a `ListView` builds only what is visible** -- so `find.text` for
  /// the About heading, which sits sixth on the page, finds nothing in the default 800x600 test
  /// window. That is not a missing section, it is an unbuilt one; scrolling in each test would test
  /// the scroller rather than the sections.
  Future<void> pumpSettings(WidgetTester tester) async {
    // Tall enough for the whole page, and it has grown twice: the four adapters moved here, and then the
    // sections gained a visible divider instead of a 32-pixel gap. A viewport that is only just tall enough
    // fails as "the text is missing", which is the least informative way to learn that a page got taller.
    tester.view.physicalSize = const Size(900, 3400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
      overrides: [
        localeSettingsProvider.overrideWith(() => _FixedLocale(
          const LocaleSettings(primaryTag: 'zh-Hans', secondaryTag: 'en', dualCopy: true),
        )),
      ],
      child: MaterialApp(home: Scaffold(body: SettingsPage())),
      ),
    );
    await tester.pump();
  }

  testWidgets('**every row of the language section carries its reason**', (tester) async {
    // The convention borrowed from a study of a rhythm game (DESIGN.md 12.9.1): a settings row is a label, **a
    // description**, a value and a control, and the description states what the choice does or costs. Three rows
    // here had only a label -- and the dual-copy switch's subtitle was the label's own English line, which is a
    // translation rather than an explanation, so it read as documented while saying nothing.
    //
    // Asserted by rendering, because the failure mode is a line being dropped in an edit, and a test on the copy
    // constants alone would not notice that the screen stopped drawing them.
    await pumpSettings(tester);
    for (final line in [Copy.settingsPrimaryNote, Copy.settingsSecondaryNote]) {
      await tester.scrollUntilVisible(
        find.text(line.primary.text),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(line.primary.text), findsOneWidget, reason: line.primary.text);
    }
    await tester.scrollUntilVisible(
      find.text(Copy.settingsDualCopyNote.primary.text),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(Copy.settingsDualCopyNote.primary.text), findsOneWidget);
  });

  testWidgets('all five sections are on the screen, and 关于空庭 is the last of them',
      (tester) async {
    await pumpSettings(tester);

    for (final heading in [
      Copy.settingsPageTitle,
      Copy.settingsTitle, // 语言与字幕
      Copy.displayHeading, // 界面样式
      Copy.integrityHeading, // 检查完整性
      Copy.developerHeading, // 开发者工具
      Copy.aboutHeading, // 关于空庭, and by the owner's instruction always the last section
    ]) {
      // **Scrolled to, not assumed visible.** A `ListView` builds only what is on screen, so a tall viewport
      // is a guess that gets more fragile every time a section grows a line -- and this test broke exactly
      // that way on 2026-09-22, when one sentence in 关于空庭 wrapped and pushed 开发者工具 past the edge.
      // Scrolling is also what a reader does, so the test now asserts the thing it means: the section is
      // reachable on this screen.
      await tester.scrollUntilVisible(
        find.text(heading.primary.text),
        300,
        // The page has nested scrollables of its own (the choice editors), and `scrollUntilVisible` insists on
        // exactly one unless told which; the page's own is the first.
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.text(heading.primary.text),
        findsWidgets,
        reason: 'missing section: ${heading.primary.text}',
      );
    }

    // **The order is asserted against the source rather than against the rendered list.** A `ListView` builds
    // only what is on screen, so a widget test can only ever see the part it has scrolled to -- an assertion
    // built on that is a guess dressed as a check, and this file's own comment above already records one test
    // that broke that way. `settings_page.dart` holds the order in one list, so that list is what is read.
    final page = File('lib/ui/settings_page.dart').readAsStringSync();
    final sections = RegExp(r'^\s+(\w+Section)\(\),', multiLine: true)
        .allMatches(page)
        .map((match) => match.group(1)!)
        .toList();
    expect(sections.last, 'AboutSection',
        reason: '关于空庭 is required to be the bottom-most section of the settings screen, '
            'and the owner asked for that to hold always rather than for now');
    for (final other in ['SettingsSection', 'NamesSection', 'DisplaySection', 'IntegritySection', 'DeveloperSection']) {
      expect(sections.indexOf(other), lessThan(sections.indexOf('AboutSection')),
          reason: '$other must come before 关于空庭');
    }
  });

  testWidgets('About says which version and which build this is', (tester) async {
    await pumpSettings(tester);

    expect(find.text(Copy.aboutVersion.primary.text), findsOneWidget);
    expect(find.text(Copy.aboutCommit.primary.text), findsOneWidget);
    // **Both rows read `unknown` in a test, and that is the assertion rather than an inconvenience.**
    // A test is a debug run with no `--dart-define`, so the honest value for both facts is the word that
    // says so. Until 2026-09-23 the version row's default was `1.0.0+1`, which let this test pass by
    // finding one `unknown` (the commit) beside a version number that no build had actually supplied --
    // no packaging script passed the define that would have replaced it. Two `unknown`s here means the
    // version row now reports a fact instead of a leftover.
    expect(find.text(Copy.aboutCommitUnknown), findsNWidgets(2),
        reason: 'the version row and the commit row both say they cannot name this build');
    expect(find.text('1.0.0+1'), findsNothing,
        reason: 'the old default claimed to be a version; a build that cannot say must say so');
  });

  testWidgets('the text size control changes the setting, and nothing else does',
      (tester) async {
    // **The one control on this screen that alters the application.** It is asserted through the
    // provider rather than through a rendered size: what is being checked is that the choice is
    // recorded, and the size it produces is the `MediaQuery`'s business, tested where that is wired.
    await pumpSettings(tester);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsPage)),
    );
    expect(container.read(displaySettingsProvider).textSize, TextSize.standard);

    await tester.tap(find.text(Copy.textSizeLarge.primary.text));
    await tester.pump();

    expect(container.read(displaySettingsProvider).textSize, TextSize.large);
  });

  testWidgets('the integrity check says there is no log rather than reporting clean',
      (tester) async {
    // **Two different sentences, and the difference matters.** With no cellar loaded there is
    // nothing to have checked; "clean" would be a claim about a file that was never read. The
    // button is still there, because the state a reader is in when they press it first is exactly
    // this one.
    await pumpSettings(tester);

    // **Twice, and deliberately.** Both this section and Developer tools need a loaded log before
    // they have anything to say, and the sentence for that is one fact with one wording rather than
    // two near-duplicates a translator would have to keep in step. `findsWidgets` records that;
    // `findsNothing` on "clean" is what actually guards the distinction being tested.
    expect(find.text(Copy.integrityNoLog.primary.text), findsWidgets);
    expect(find.text(Copy.integrityClean.primary.text), findsNothing);
    expect(find.byKey(const ValueKey('integrity-run')), findsOneWidget);
  });

  testWidgets('Developer tools lists the seams, which are not on the reader-facing tab',
      (tester) async {
    // The four adapters used to be on 记录 under 设备与同步, each saying it was not implemented in
    // this build. They are here now, and the wording is a state rather than an apology.
    await pumpSettings(tester);

    // The same reason as above: the developer section is the last on the page, so reaching it means scrolling
    // to it rather than trusting that the viewport happens to be tall enough this month.
    await tester.scrollUntilVisible(
      find.text(Copy.developerSeamsHeading.primary.text),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(Copy.developerSeamsHeading.primary.text), findsOneWidget);
    expect(find.text(Copy.developerSeamsNote.primary.text), findsOneWidget);
    // **The developer section lists the seams, and under the owner's rule of 2026-09-25 it lists only the ones
    // that can be used.** What is held back keeps its code and its disclosure; it is simply not on the screen,
    // which is what "暂时隐藏，等以后确认可用了再放出" means in practice. The bartender was the one that could be
    // used and it has since been withdrawn, so nothing is listed at all -- which is the same rule applied to a
    // different state rather than an exception to it.
    expect(find.text(Copy.adapterBarcode.primary.text), findsNothing,
        reason: 'the camera has no plugin, no permission and no implementation: held back');
    expect(find.text(Copy.adapterPriceComparison.primary.text), findsNothing,
        reason: 'no price source is built: held back');
    expect(
      find.text('这个构建里还没有实现，所以打不开。'),
      findsNothing,
      reason: 'the old apology must not be anywhere on this screen',
    );
  });
}


/// The copy language pinned to Chinese for this file, so that assertions written against the authored
/// sentences do not depend on the platform locale of the machine running the tests.
class _FixedLocale extends LocaleSettingsNotifier {
  _FixedLocale(this._initial);

  final LocaleSettings _initial;

  @override
  LocaleSettings build() => _initial;
}
