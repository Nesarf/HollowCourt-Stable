import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/ui/l10n/locale_catalogue.dart';
import 'package:hollow_court/ui/l10n/locale_providers.dart';
import 'package:hollow_court/ui/l10n/locale_settings.dart';
import 'package:hollow_court/ui/settings_section.dart';
import 'package:hollow_court/ui/theme.dart';

/// Records the calls instead of writing them.
///
/// The persistence is the notifier's job and is tested where it is built; what this
/// screen owes is that a choice reaches the notifier at all, and inside a widget
/// test a real settings-file write would not complete -- the same FakeAsync trap
/// that `bar_page_test` records from the other side.
class _RecordingSettings extends LocaleSettingsNotifier {
  _RecordingSettings(this._initial);

  final LocaleSettings _initial;
  final List<String> calls = [];

  @override
  LocaleSettings build() => _initial;

  @override
  Future<void> setPrimary(String tag) async => calls.add('primary:$tag');

  @override
  Future<void> setSecondary(String tag) async => calls.add('secondary:$tag');

  @override
  Future<void> setDualCopy(bool value) async => calls.add('dual:$value');
}

late _RecordingSettings _notifier;

Future<void> pumpSettings(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localeSettingsProvider.overrideWith(() {
          _notifier = _RecordingSettings(
            const LocaleSettings(
              primaryTag: 'zh-Hans',
              secondaryTag: 'en',
              dualCopy: true,
            ),
          );
          return _notifier;
        }),
      ],
      // Scrollable, because that is how the Cellar page hosts it -- a `ListView` with
      // the section as one child. Standing it in a bare `Scaffold` body made it
      // overflow by 448 px once the unit and money editors were added, which is a
      // property of the test's host and not of the section.
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: SettingsSection()),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('the section shows the three settings section 12.4 defines',
      (tester) async {
    await pumpSettings(tester);

    expect(find.text(Copy.settingsTitle.primary.text), findsOneWidget);
    expect(find.byKey(const ValueKey('primary-locale-picker')), findsOneWidget);
    expect(find.byKey(const ValueKey('secondary-locale-picker')), findsOneWidget);
    expect(find.byKey(const ValueKey('dual-copy-switch')), findsOneWidget);
    expect(find.text(Copy.settingsPrimary.primary.text), findsOneWidget);
    expect(find.text(Copy.settingsSecondary.primary.text), findsOneWidget);
  });

  testWidgets('the picker shows the locale name and its tag together',
      (tester) async {
    // Section 12.4's two rules in one widget: the name is UTF-8 because a person
    // reads it, the tag is ASCII because a machine matches on it.
    await pumpSettings(tester);

    final zh = shippedLocales.firstWhere((l) => l.tag == 'zh-Hans');
    expect(find.text(zh.toString()), findsWidgets);
    expect(zh.toString(), contains('zh-Hans'));
  });

  testWidgets('picking a primary language reaches the notifier', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.byKey(const ValueKey('primary-locale-picker')));
    await tester.pumpAndSettle();
    // The overlay lists every shipped locale; pick one that is not the current one.
    final target = shippedLocales.firstWhere((l) => l.tag == 'ja');
    await tester.tap(find.text(target.toString()).last);
    await tester.pumpAndSettle();

    expect(_notifier.calls, ['primary:ja']);
  });

  testWidgets('the switch reaches the notifier rather than flipping locally',
      (tester) async {
    // The switch's value comes from the provider, so a tap that only changed the
    // widget would spring back on the next build -- and the screen would have lied.
    await pumpSettings(tester);

    await tester.tap(find.byKey(const ValueKey('dual-copy-switch')));
    await tester.pump();

    expect(_notifier.calls, ['dual:false']);
  });

  testWidgets('both pickers offer everything shipped, including the same tag',
      (tester) async {
    // Offering a tag in both pickers is deliberate: `LocaleSettings.guarded` moves
    // the secondary when they collide, and the screen says so underneath. A picker
    // that quietly omitted the other one's language would look broken, and one that
    // accepted the collision silently would leave the reader guessing which of the
    // two choices took.
    await pumpSettings(tester);

    // Read from the control rather than from the opened menu. A `DropdownButton`
    // lays its menu out in a lazy list, so with thirteen locales the ones below the
    // fold are never built and `find.text` cannot see them -- the first version of
    // this test failed on 文言文 (lzh) for that reason and not because the item was
    // missing. The button's own `items` is the list, and it is the thing being
    // asserted about.
    final dropdown = tester.widget<DropdownButton<String>>(
      find.descendant(
        of: find.byKey(const ValueKey('secondary-locale-picker')),
        matching: find.byType(DropdownButton<String>),
      ),
    );
    expect(
      dropdown.items!.map((item) => item.value),
      containsAll(shippedLocales.map((locale) => locale.tag)),
    );
    expect(dropdown.items, hasLength(shippedLocales.length));

    // And the collision is explained on screen rather than resolved in silence.
    expect(find.text(Copy.settingsSameTagNote.primary.text), findsOneWidget);
  });
}
