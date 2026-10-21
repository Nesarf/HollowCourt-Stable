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
    // **The barcode is offered and the other two are not**, which is the rule applied honestly rather than the rule
    // abandoned: on 2026-10-22 the camera and the catalogue became things this build can actually do.
    expect(find.text(Copy.adapterBarcode.primary.text), findsOneWidget,
        reason: 'the barcode can be scanned and looked up now, so its card is shown');
    for (final held in <String>[
      Copy.adapterPriceComparison.primary.text,
      Copy.adapterMeasurement.primary.text,
    ]) {
      expect(find.text(held), findsNothing, reason: '$held is held back until it can be used');
    }
    // And exactly one switch, beside the one seam that can be switched on.
    expect(find.byType(Switch), findsOneWidget,
        reason: 'a switch is offered for the seams that can be used, and there is one of those');
  });

  testWidgets('**and the registry agrees with the screen: only the barcode is built**', (tester) async {
    await pumpSection(tester);

    final container = ProviderScope.containerOf(tester.element(find.byType(AdaptersSection)));
    final registry = container.read(adapterRegistryProvider);
    expect(registry.enabled, isEmpty, reason: 'off by default is the initial state');
    // **The barcode is the one seam this build can actually run**, since the catalogue lookup landed on 2026-10-22.
    // Everything else is still a promise, and the discipline this file guards is that a promise is not a button.
    expect(registry.isAvailable(AdapterKind.barcode), isTrue);
    for (final kind in AdapterKind.values.where((k) => k != AdapterKind.barcode)) {
      expect(registry.isAvailable(kind), isFalse, reason: '${kind.name} is not built in this build');
    }
  });

  test('an unavailable adapter still refuses to be enabled', () {
    // The price comparison, which remains unimplemented; the barcode used to stand here as the example and no longer
    // can, because it is built.
    final registry = AdapterRegistry(declaredAdapters);
    expect(
      () => registry.enable(AdapterKind.priceComparison),
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
