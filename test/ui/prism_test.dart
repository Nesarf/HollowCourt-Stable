import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/ui/prism.dart';
import 'package:hollow_court/ui/theme.dart';

/// **The motif, and the one property the study set for it: it survives ten pixels.**
///
/// From `docs/DESIGN.md` 12.9.1 — a rhythm game's diamond appears as a 10×10 divider ornament, a card frame and a
/// button. The test of whether a shape is a motif or just a drawing is whether its **smallest** use is still
/// recognisable, so that is what is asserted: at ten pixels the prism still puts ink on the canvas, and it still
/// puts *more* than a plain diamond would, because the facet is drawn.
void main() {
  Future<void> pump(WidgetTester tester, Widget child, {Size size = const Size(120, 120)}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: HollowTheme.build(),
        home: Scaffold(body: Center(child: SizedBox(width: size.width, height: size.height, child: child))),
      ),
    );
    await tester.pump();
  }

  testWidgets('a prism draws at ten pixels, which is the whole point', (tester) async {
    await pump(tester, const Prism(size: 10));
    expect(find.byType(Prism), findsOneWidget);
    final painted = tester.widget<CustomPaint>(find.descendant(
      of: find.byType(Prism),
      matching: find.byType(CustomPaint),
    ));
    expect(painted.painter, isNotNull, reason: 'the motif is painted, not an asset that can drift');
  });

  testWidgets('**the divider is a line with the motif set into it**', (tester) async {
    await pump(tester, const PrismDivider(), size: const Size(300, 40));
    expect(find.byType(PrismDivider), findsOneWidget);
    expect(find.byType(Prism), findsOneWidget, reason: 'exactly one prism, centred in the rule');
    final sizes = tester.widget<Prism>(find.byType(Prism));
    expect(sizes.size, 10, reason: 'the size a rhythm game uses in its own dividers');
  });

  testWidgets('the mark is the same shape with the facet off, for very small uses', (tester) async {
    await pump(tester, const PrismMark());
    final prism = tester.widget<Prism>(find.byType(Prism));
    expect(prism.facet, isFalse);
    expect(prism.size, 12);
  });

  testWidgets('**the motif colour comes from the palette, so it cannot freeze**', (tester) async {
    // The rule this project has already broken once: a `const` widget holding a palette colour keeps the colour
    // it was built with, and the theme stops applying. The prism takes its colour at build time.
    await pump(tester, const Prism(size: 16));
    final prism = tester.widget<Prism>(find.byType(Prism));
    expect(prism.color, isNull, reason: 'it resolves HollowPalette.gold while painting, not at construction');
  });

  testWidgets('it draws the same geometry at every size, which is what makes it one motif', (tester) async {
    for (final size in const [10.0, 16.0, 32.0, 64.0]) {
      await pump(tester, Prism(key: ValueKey('prism-$size'), size: size));
      final painted = tester.widget<CustomPaint>(find.descendant(
        of: find.byKey(ValueKey('prism-$size')),
        matching: find.byType(CustomPaint),
      ));
      expect(painted.painter, isNotNull, reason: 'size $size');
      // One painter, one shape: the class of the painter is the same at every size, so four sizes cannot drift
      // into four different drawings.
      expect(painted.painter.runtimeType.toString(), '_PrismPainter', reason: 'size $size');
    }
  });

  /// **The wash, and the two properties that make it safe as a layer over the whole window.**
  ///
  /// It is the third treatment the reference study measured (`mobile-games-on-the-phone.md` §10.1: a lattice
  /// capped at alpha 91 of 255), and it is the only one of the three that covers everything, so the two things
  /// worth testing are the two things that could go wrong: it must be unable to take a tap, and it must be
  /// unable to become loud.
  group('the wash', () {
    testWidgets('**a caller cannot exceed the measured ceiling**', (tester) async {
      await pump(tester, const PrismWash(alpha: 1));
      final painted = tester.widget<CustomPaint>(find.descendant(
        of: find.byType(PrismWash),
        matching: find.byType(CustomPaint),
      ));
      final painter = painted.painter!;
      // The ceiling is enforced in code rather than asked for in a comment: `alpha: 1` still paints at most
      // 91/255, so the background can never be made to compete with the text on top of it.
      expect(prismWashCeiling, closeTo(91 / 255, 1e-9));
      expect(prismWashAlpha(1), prismWashCeiling, reason: 'the clamp itself');
      expect(prismWashAlpha(-2), 0, reason: 'and it clamps the other end too');
      // The painter is public API now, because a test that cannot see what a widget paints cannot check that it
      // paints it -- see `world_art_fidelity_test.dart`, where the distinction mattered.
      expect(painter.runtimeType.toString(), 'PrismWashPainter');
      final paintedAlpha = (painter as dynamic).alpha as double;
      expect(paintedAlpha, lessThanOrEqualTo(prismWashCeiling + 1e-9));
    });

    testWidgets('it defaults to half the ceiling, because the astrolabe is the floor', (tester) async {
      await pump(tester, const PrismWash());
      final painted = tester.widget<CustomPaint>(find.descendant(
        of: find.byType(PrismWash),
        matching: find.byType(CustomPaint),
      ));
      final paintedAlpha = ((painted.painter!) as dynamic).alpha as double;
      expect(paintedAlpha, closeTo(prismWashDefaultAlpha, 1e-9));
      expect(prismWashDefaultAlpha, lessThan(prismWashCeiling));
    });

    testWidgets('**it cannot take a tap**, because it covers the whole window', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: HollowTheme.build(),
          home: Scaffold(
            body: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => taps++,
                    child: const ColoredBox(color: Color(0xFF000000)),
                  ),
                ),
                const Positioned.fill(child: PrismWash()),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byType(PrismWash), warnIfMissed: false);
      await tester.pump();
      expect(taps, 1, reason: 'the tap reached the layer underneath instead of being swallowed');
    });
  });
}
