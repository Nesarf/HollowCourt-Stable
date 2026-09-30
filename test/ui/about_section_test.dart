import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/ui/about_section.dart';
import 'package:hollow_court/ui/theme.dart';

/// The bottom of 关于空庭: where to find the source, and where to find the author.
///
/// **Two things here are load-bearing and neither is visible in a screenshot.** The rows have to lay out on a
/// narrow screen, and the author rows have to stay facts rather than requests -- the second is enforced by the
/// copy constants and the first by the layout, and this file is where both are held.
void main() {
  tearDown(() => HollowPalette.use(HollowPaletteValue.honeyed));

  /// Pumps the section and returns every overflow the layout reported.
  ///
  /// **Pumped, never settled.** `openInBrowser` goes through a platform channel a widget test does not have, so
  /// the future never completes and `pumpAndSettle` waits out its ten-minute timeout instead of failing. The
  /// first version of this probe did exactly that.
  Future<List<String>> pumpAt(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final errors = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) => errors.add(details.exceptionAsString());
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: const AboutSection(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    FlutterError.onError = previous;
    return errors.where((error) => error.contains('overflowed')).toList();
  }

  testWidgets('**the link rows fit on a narrow screen**', (tester) async {
    // 2026-09-30: at 200 px the label row overflowed by **115 px**, and 240 px was the narrowest width that fitted
    // -- by luck rather than by design. The cause is the one `_ShoppingRows` records from the other screen: a
    // `Text` in a `Row` with no flex takes its full intrinsic width instead of wrapping. The label is `Flexible`
    // now, and this is the assertion that keeps it that way.
    for (final width in [160.0, 200.0, 240.0, 320.0, 900.0]) {
      expect(
        await pumpAt(tester, width),
        isEmpty,
        reason: 'the about section overflowed at ${width}px',
      );
    }
  });

  testWidgets('**the credit PCL asks for is on the screen**', (tester) async {
    // `art/miku-wide.svg` and `art/miku-tall.svg` depict 初音ミク under the Piapro Character Licence, and
    // 第3条第3項 asks for a credit alongside the work. **Asserted by the character's own name in its own script**,
    // which is the part a well-meaning edit is most likely to "translate" -- and the character's name is not copy,
    // it is the name the rights holder uses.
    await pumpAt(tester, 900);
    expect(
      find.textContaining('初音ミク'),
      findsWidgets,
      reason: 'the character has to be named as the rights holder names her',
    );
    // And the licence is named, not merely alluded to.
    expect(find.textContaining('ピアプロ・キャラクター・ライセンス'), findsOneWidget);
  });

  // **The browser-failure path is deliberately not tested here.** `openInBrowser` shells out on Windows and
  // Linux (`explorer`, `xdg-open`) and only uses a platform channel on Android, so on the machine that runs
  // these tests the failure is unreachable -- it would return true and could even open a window. A test that
  // cannot reach its branch is a test that asserts nothing, and pretending otherwise would be worse than
  // leaving the gap named. `settings_page_test` covers the About screen as a whole.
}
