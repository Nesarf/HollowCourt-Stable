import 'package:flutter/material.dart';
import 'package:hollow_court/ui/app.dart';
import 'package:hollow_court/ui/prism.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/ui/display_providers.dart';
import 'package:hollow_court/ui/ornament.dart';
import 'package:hollow_court/ui/theme.dart';

/// **The bug a screenshot found and no test could, and the test that would have.**
///
/// The three worlds were given different palettes, different grounds and different instruments, and three tests
/// asserted that each of those differs. All three passed -- and then a capture of the white world came back
/// carrying **Amber Court's lattice**, because the backdrop was mounted `const`: built once, with the default
/// world, because the stored setting arrives asynchronously, and never built again. The colours followed the
/// theme; the art did not.
///
/// **The lesson stated as a test.** Asserting that two *values* differ is not asserting that the screen *uses*
/// them. So this walks the widgets a reader actually sees, asks what they are drawing, changes the world the way
/// the settings screen changes it, and asks again.
///
/// It lives in its own file rather than beside the palette tests because it is about a different question: those
/// check the table, this checks the wiring from the table to the screen.
void main() {
  /// The instrument the backdrop is currently painting.
  HollowOrnamentPainter instrument(WidgetTester tester) => tester
      .widgetList<CustomPaint>(
        find.descendant(of: find.byType(OrnamentBackdrop), matching: find.byType(CustomPaint)),
      )
      .map((paint) => paint.painter)
      .whereType<HollowOrnamentPainter>()
      .first;

  /// The texture the wash beneath it is currently painting.
  GroundTexture ground(WidgetTester tester) => tester
      .widgetList<CustomPaint>(
        find.descendant(of: find.byType(OrnamentBackdrop), matching: find.byType(CustomPaint)),
      )
      .map((paint) => paint.painter)
      .whereType<PrismWashPainter>()
      .first
      .texture;

  testWidgets('the ground and the instrument follow the world when it changes', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: HollowCourtApp()));
    await tester.pump();

    // What the application opens in.
    expect(instrument(tester).ornament, HollowPaletteValue.honeyed.ornament,
        reason: 'the application opens in the world it was designed around');
    expect(ground(tester), HollowPaletteValue.honeyed.texture);

    // **Switched the way the settings screen switches it.** Not by rebuilding the app around a new value: the
    // fault was in the wiring between the setting and the screen, so a test that skipped the wiring would have
    // passed with the bug still in place -- which is exactly what the first version of this test did.
    final container = ProviderScope.containerOf(tester.element(find.byType(HollowCourtApp)));
    await container.read(displaySettingsProvider.notifier).setTheme(HollowPaletteValue.winter);
    await tester.pump();

    expect(HollowPalette.current.name, 'winter', reason: 'the palette itself must have followed');
    expect(
      instrument(tester).ornament,
      Ornament.snowCrystal,
      reason: 'the instrument kept the old world -- the backdrop is not rebuilding',
    );
    expect(
      ground(tester),
      GroundTexture.frost,
      reason: 'the ground kept the old world -- the wash is not rebuilding',
    );
  });
}
