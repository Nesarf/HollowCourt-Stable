import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hollow_court/ui/l10n/locale_settings.dart';
import 'package:hollow_court/ui/l10n/locale_providers.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hollow_court/adapters/declared.dart';
import 'package:hollow_court/adapters/registry.dart';
import 'package:hollow_court/ui/adapters_providers.dart';
import 'package:hollow_court/ui/adapters_section.dart';
import 'package:hollow_court/ui/theme.dart';

/// The adapters section, in the state this build is actually in: no door opens.
///
/// **This file has now asserted three different things, and each was true when it was written.** It began by
/// asserting that every switch was disabled, with the reasoning the section's own comment preserves: the
/// registry refuses to enable an unavailable adapter, so a control that moved and then threw would be worse
/// than one that plainly would not move. Then the bartender was built, and it asserted that exactly one switch
/// was offered and that the three that were not still said why.
///
/// **The bartender is gone again, and the reason is worth keeping.** It answered by asking a model served on
/// the reader's own machine -- a deployment rather than a feature of the application -- so it is not basic
/// content and does not belong in Stable. That returns the screen to its first state, and the owner's rule of
/// 2026-09-25 asks for the same thing it always did: 每一项功能必须要可以实现并使用，无法做到的就不显示. So the
/// assertion is that nothing appears, and it will keep being the right assertion until something is built that
/// can be used.
Future<void> pumpSection(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localeSettingsProvider.overrideWith(() => _FixedLocale(
          const LocaleSettings(primaryTag: 'zh-Hans', secondaryTag: 'en', dualCopy: true),
        )),
      ],
      child: MaterialApp(home: Scaffold(body: AdaptersSection())),
    ),
  );
}

void main() {
  testWidgets('**no seam this build cannot run is offered**', (tester) async {
    await pumpSection(tester);

    expect(tester.takeException(), isNull);
    for (final held in <String>[
      Copy.adapterPriceComparison.primary.text,
      Copy.adapterBarcode.primary.text,
      Copy.adapterMeasurement.primary.text,
    ]) {
      expect(find.text(held), findsNothing, reason: '$held is held back until it can be used');
    }
    expect(find.byType(Switch), findsNothing,
        reason: 'a switch is offered when a seam can be used, and none of them can be yet');
  });

  testWidgets('**and the registry agrees with the screen: nothing is available**', (tester) async {
    await pumpSection(tester);

    final container = ProviderScope.containerOf(tester.element(find.byType(AdaptersSection)));
    final registry = container.read(adapterRegistryProvider);
    expect(registry.enabled, isEmpty, reason: 'off by default is the initial state');
    for (final kind in AdapterKind.values) {
      expect(registry.isAvailable(kind), isFalse, reason: '${kind.name} is not built in this build');
    }
  });

  test('an unavailable adapter still refuses to be enabled', () {
    final registry = AdapterRegistry(declaredAdapters);
    expect(
      () => registry.enable(AdapterKind.barcode),
      throwsA(isA<StateError>()),
      reason: 'the registry is what makes a shut door shut, not the screen',
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
