import 'dart:math' as math;
import 'dart:ui' show PictureRecorder;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/ui/display_providers.dart';
import 'package:hollow_court/ui/ornament.dart';
import 'package:hollow_court/ui/theme.dart';

/// Four themes, and the things about them a test can hold.
///
/// **A theme is not decoration and it is not taste-only.** Two of its properties are checkable and
/// both matter: the text has to be readable, and the theme a reader chose has to be the theme the next
/// screen is drawn in. Everything else -- whether 羊皮纸 is pleasant -- is a judgement no test can make
/// and none of these pretend to.
void main() {
  tearDown(() => HollowPalette.use(HollowPaletteValue.honeyed));

  /// WCAG relative luminance, the definition the ratio is computed from.
  double luminance(Color colour) {
    double channel(int value) {
      final v = value / 255;
      return v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    }

    return 0.2126 * channel((colour.r * 255).round()) +
        0.7152 * channel((colour.g * 255).round()) +
        0.0722 * channel((colour.b * 255).round());
  }

  double contrast(Color a, Color b) {
    final la = luminance(a);
    final lb = luminance(b);
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  group('every theme is readable', () {
    test('body text clears 4.5:1 on every surface it is drawn on', () {
      // **The floor the palette has always claimed and never asserted.** Section 20.3 asks for soft,
      // under-contrasted surfaces and the accessibility rule asks for readable text, and those two
      // pull in opposite directions -- so the claim is only worth having if a machine checks it. A
      // fifth theme added by somebody in a hurry is exactly the change that would break it.
      for (final value in HollowPaletteValue.all) {
        for (final (name, surface) in [
          ('ground', value.ground),
          ('surface', value.surface),
          ('surfaceRaised', value.surfaceRaised),
        ]) {
          expect(
            contrast(value.ink, surface),
            greaterThanOrEqualTo(4.5),
            reason: '${value.name}: ink on $name',
          );
          expect(
            contrast(value.inkSoft, surface),
            greaterThanOrEqualTo(4.5),
            reason: '${value.name}: secondary text on $name',
          );
          // **`inkFaint` and `absent` are held to the same floor as body text, and that is a change.**
          // They used to be exempt on the reasoning that they are for a placeholder and a disabled
          // control -- both of which WCAG exempts. A reader then reported that the text and the interface
          // were the same colour, and measuring showed they were right: `inkFaint` sat at 3.0-3.5:1 on the
          // surfaces it was actually used on, in captions and units and counts that are not placeholders
          // at all. The exemption was correct about the theory and wrong about this interface, so the two
          // values were raised until they clear the floor on every surface they are drawn on.
          expect(
            contrast(value.inkFaint, surface),
            greaterThanOrEqualTo(4.5),
            reason: '${value.name}: caption and unit text on $name',
          );
          expect(
            contrast(value.absent, surface),
            greaterThanOrEqualTo(4.5),
            reason: '${value.name}: the cannot-be-made label on $name',
          );
        }
      }
    });

    test('the three weights of text are still three weights', () {
      // The floor above must not have flattened the hierarchy: a caption that reads as loudly as body
      // text is a different way of being unreadable on a screen that uses weight to say what matters.
      for (final value in HollowPaletteValue.all) {
        final ink = contrast(value.ink, value.ground);
        final soft = contrast(value.inkSoft, value.ground);
        final faint = contrast(value.inkFaint, value.ground);
        expect(soft, lessThan(ink), reason: '${value.name}: secondary is quieter than body');
        expect(faint, lessThan(soft), reason: '${value.name}: a caption is quieter than secondary');
      }
    });

    test('**a separator can be seen, and decoration cannot compete with text**', () {
      // One colour could not do both jobs, which is what this pair of assertions now says. A rule between
      // two options is a functional boundary and clears the 3:1 non-text floor; the background's strokes
      // stay below 1.8:1 so that they never fight the words for attention. They used to be the same colour
      // at 1.4-1.7:1, which is why the reader's complaint was that the separation between options was not
      // obvious -- the rules were drawn and could not be seen.
      for (final value in HollowPaletteValue.all) {
        for (final (name, surface) in [
          ('ground', value.ground),
          ('surface', value.surface),
          ('surfaceRaised', value.surfaceRaised),
        ]) {
          expect(
            contrast(value.line, surface),
            greaterThanOrEqualTo(3.0),
            reason: '${value.name}: a separator on $name has to be visible',
          );
        }
        expect(
          contrast(value.hairline, value.ground),
          lessThan(1.8),
          reason: '${value.name}: decoration stays out of the way',
        );
      }
    });

    test('**text on an accent fill is readable, which is what a selected chip is**',
        () {
      // The pairing rule, asserted for every accent and every palette: `onAccent` and never `ink`. Before
      // it existed, a selected `ChoiceChip` drew `ink` on `gold` -- 1.5:1 in three palettes, 2.7 in the
      // fourth -- and a rose fill was no better. The disabled button is included because its fill is
      // `absent`, which is the third surface a label is drawn on.
      for (final value in HollowPaletteValue.all) {
        expect(contrast(value.onAccent, value.gold), greaterThanOrEqualTo(4.5),
            reason: '${value.name}: onAccent on gold');
        expect(contrast(value.onAccent, value.rose), greaterThanOrEqualTo(4.5),
            reason: '${value.name}: onAccent on rose');
        expect(contrast(value.onAccent, value.absent), greaterThanOrEqualTo(4.5),
            reason: '${value.name}: onAccent on the disabled fill');
        // And the reason the rule is worth having rather than trusting to taste: ink is not an option.
        expect(contrast(value.ink, value.gold), lessThan(4.5),
            reason: '${value.name}: ink on gold is the fault this rule exists for');
      }
    });

    test('the accents are visible against their own page', () {
      // An accent that cannot be seen on its background is not an accent. 3:1 is the large-text and
      // non-text floor, which is what a badge or a button outline has to clear.
      for (final value in HollowPaletteValue.all) {
        expect(contrast(value.rose, value.ground), greaterThanOrEqualTo(3.0), reason: value.name);
        expect(contrast(value.gold, value.ground), greaterThanOrEqualTo(3.0), reason: value.name);
      }
    });

    test('three worlds, three distinct names, one of them light', () {
      // **Four themes became three worlds on 2026-09-25.** The owner scrapped the old set and asked for new ones
      // designed from scratch, each with its own interface and its own art rather than a recolour; the count
      // followed the decision.
      expect(HollowPaletteValue.all, hasLength(3));
      expect(
        HollowPaletteValue.all.map((v) => v.name).toSet(),
        hasLength(3),
        reason: 'a name is the wire format, so two themes sharing one is a stored setting that opens '
            'the wrong theme',
      );
      expect(HollowPaletteValue.whiteCourt.brightness, Brightness.light);
      expect(HollowPaletteValue.honeyed.brightness, Brightness.dark);
    });

    test('each world draws its ground out of a different material', () {
      // **A world is not a palette.** Two of the three are dark and use the same motif; what tells them apart on
      // a screen with no words on it is what the ground is *made of*. Sharing a texture would mean two worlds
      // differing only in hue, which is the recolour this set replaced.
      expect(
        HollowPaletteValue.all.map((v) => v.texture).toSet(),
        hasLength(HollowPaletteValue.all.length),
        reason: 'two worlds are drawing the same ground',
      );
    });

    test('each world draws a different instrument behind its pages', () {
      // The third axis, after the palette and the ground: two dark worlds sharing an ornament would still be one
      // world twice. The grammar is shared -- a hairline drawing at a third strength, off-centre -- and the
      // drawing is the world's, so this asserts the drawing.
      expect(
        HollowPaletteValue.all.map((v) => v.ornament).toSet(),
        hasLength(HollowPaletteValue.all.length),
        reason: 'two worlds are drawing the same instrument',
      );
    });

    test('an unknown name falls back rather than failing', () {
      // A settings file written by a build that carried a theme this one does not.
      // The fallback is the world the application was designed around -- and `ivy` is now one of the names a
      // stored setting may still hold, because it belonged to a theme this build no longer carries. That is
      // exactly the case the rule exists for.
      expect(HollowPaletteValue.byName('a-theme-from-the-future').name, 'honeyed');
      expect(HollowPaletteValue.byName(null).name, 'honeyed');
      expect(HollowPaletteValue.byName('ivy').name, 'honeyed');
    });
  });

  group('switching a theme actually changes what is drawn', () {
    test('every theme builds a Material theme without complaining', () {
      // **The test that was missing, and the bug it would have caught.** `HollowTheme.build()` had a
      // hardcoded `ColorScheme.dark`, and `ThemeData` asserts that its own brightness agrees with the
      // scheme's -- so the light theme threw on the first frame of a real application while every test
      // passed, because the tests read colours out of the palette and never built the Material theme
      // at all. Building all four is three lines and closes that gap permanently.
      for (final value in HollowPaletteValue.all) {
        HollowPalette.use(value);
        final theme = HollowTheme.build();
        expect(theme.brightness, value.brightness, reason: value.name);
        expect(theme.colorScheme.brightness, value.brightness, reason: value.name);
        expect(theme.scaffoldBackgroundColor, value.ground, reason: value.name);
        expect(theme.colorScheme.primary, value.rose, reason: value.name);
      }
    });

    testWidgets('the palette the widgets read follows the setting', (tester) async {
      // **The assertion that the refactor was for.** The palette used to be ten `static const`s, which
      // no setting could change; it is now a value every call site reads through getters. This checks
      // the chain end to end: change the setting, and the colour the interface would paint with is the
      // new theme's.
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: Scaffold(body: SizedBox()))),
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(SizedBox)),
      );
      expect(container.read(displaySettingsProvider).theme.name, 'honeyed');
      expect(HollowPalette.ground, HollowPaletteValue.honeyed.ground);

      await container
          .read(displaySettingsProvider.notifier)
          .setTheme(HollowPaletteValue.whiteCourt);

      expect(container.read(displaySettingsProvider).theme.name, 'whiteCourt');
      expect(
        HollowPalette.ground,
        HollowPaletteValue.whiteCourt.ground,
        reason: 'the whole interface reads this getter, so it is what a repaint would use',
      );
      expect(HollowPalette.ink, HollowPaletteValue.whiteCourt.ink);
    });

    testWidgets('a text style carries the colour of the theme in force', (tester) async {
      // The subtler half of the same property: the seven text styles used to be `const`, which baked
      // in the colour they were compiled with -- so a theme switch would have left every word in the
      // old one. They are getters now, and this is what says so.
      HollowPalette.use(HollowPaletteValue.honeyed);
      expect(HollowType.body.color, HollowPaletteValue.honeyed.ink);

      HollowPalette.use(HollowPaletteValue.winter);
      expect(HollowType.body.color, HollowPaletteValue.winter.ink);
      expect(HollowType.caption.color, HollowPaletteValue.winter.inkSoft);
      expect(HollowType.numeric.color, HollowPaletteValue.winter.inkSoft);
    });

    testWidgets('the settings file keeps the choice', (tester) async {
      // Stored by name, so a round trip is a round trip.
      const chosen = DisplaySettings(theme: HollowPaletteValue.winter);
      final back = DisplaySettings.fromJson(chosen.toJson());
      expect(back.theme.name, 'winter');
      expect(back.textSize, TextSize.standard);

      // And a file with no theme at all -- written before this feature existed -- reads as the
      // default rather than as a failure.
      expect(DisplaySettings.fromJson(<String, Object?>{'textSize': 'large'}).theme.name, 'honeyed');
    });
  });

  group('the ornament is a background and behaves like one', () {
    testWidgets('it paints inside its bounds on any shape of window', (tester) async {
      // **The geometry is a function of the viewport, so the interesting cases are the extremes.** A
      // phone held upright, a desktop window, and a square: radii taken from the width alone would put
      // the plate off-screen on one of them, which is why the diagonal is used. A painter that threw,
      // or that drew outside the canvas, is what this catches.
      for (final size in const [Size(400, 900), Size(1400, 800), Size(700, 700)]) {
        final recorder = PictureRecorder();
        final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size.width, size.height));
        const HollowOrnamentPainter().paint(canvas, size);
        recorder.endRecording().dispose();
      }
      // And through the widget, which is how it is actually mounted.
      // **Inside a ProviderScope, because the backdrop watches the world.** It became a `ConsumerWidget` when
      // the const-mount bug was fixed: a background that has to be told which world it is in is one that will
      // eventually be told the wrong one, so it reads the setting itself -- and reading a provider needs a scope.
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: Scaffold(body: Stack(children: [OrnamentBackdrop()]))),
        ),
      );
      expect(find.byType(OrnamentBackdrop), findsOneWidget);
    });

    testWidgets('it does not swallow taps', (tester) async {
      // A `CustomPaint` filling a `Stack` takes part in hit testing by default, so a background that
      // covers the screen would eat every tap that missed a button by a pixel. It is wrapped in an
      // `IgnorePointer`, and this is the assertion that keeps it that way.
      var tapped = 0;
      await tester.pumpWidget(
        // As above: the backdrop reads the world, and reading a provider needs a scope around it.
        ProviderScope(
          child: MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                const OrnamentBackdrop(),
                Center(
                  child: GestureDetector(
                    onTap: () => tapped++,
                    child: const SizedBox(width: 100, height: 40, child: Text('tap me')),
                  ),
                ),
              ],
            ),
          ),
        ),
        ),
      );

      await tester.tap(find.text('tap me'));
      expect(tapped, 1);

      // And a tap on the background itself reaches the scaffold rather than the painter.
      await tester.tapAt(const Offset(10, 10));
      expect(tapped, 1, reason: 'the background is not a control');
    });

    testWidgets('the ornament can never be the highest contrast thing on the screen', (tester) async {
      // The claim in the painter's own comment, made checkable: its strokes are the palette's `hairline`,
      // which every palette keeps close to the page, so a background cannot compete with text for
      // attention. **This assertion used to be about `line`, and moving it is the point of this round:**
      // one colour was doing two jobs -- a decorative stroke that must be invisible and a separator that
      // must be seen -- and the test that kept decoration quiet was also what kept the rules between
      // options invisible. `line` is now the separator (3:1, asserted above) and `hairline` is this.
      for (final value in HollowPaletteValue.all) {
        expect(
          contrast(value.hairline, value.ground),
          lessThan(1.8),
          reason: '${value.name}: the background is meant to be nearly invisible',
        );
      }
    });
  });
}
