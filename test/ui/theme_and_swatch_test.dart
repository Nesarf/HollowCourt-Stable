// UI tests. Run with `flutter test`, not `dart test`: they need the Flutter
// framework, and the README says which runner covers which half.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/domain/model/glass.dart';
import 'package:hollow_court/domain/model/ice.dart';
import 'package:hollow_court/domain/model/liquid_visual.dart';
import 'package:hollow_court/ui/l10n/dual_copy.dart';
import 'package:hollow_court/ui/liquid_swatch.dart';
import 'package:hollow_court/ui/theme.dart';

/// WCAG relative luminance and contrast ratio, so that the claim in the theme's
/// own comment is checked rather than asserted.
double _luminance(Color colour) {
  double channel(double value) =>
      value <= 0.03928 ? value / 12.92 : _pow((value + 0.055) / 1.055, 2.4);
  return 0.2126 * channel(colour.r) +
      0.7152 * channel(colour.g) +
      0.0722 * channel(colour.b);
}

double _pow(double base, double exponent) {
  // `dart:math` in a test is fine; kept local so this file has one import fewer.
  var result = 1.0;
  var remaining = exponent;
  while (remaining >= 1) {
    result *= base;
    remaining -= 1;
  }
  return result * (1 + remaining * (base - 1));
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('the palette', () {
    test('body text on the page clears the accessibility floor', () {
      // The theme's own comment claims 4.5:1. A claim about contrast that is not
      // measured is a claim that will quietly stop being true the first time
      // somebody nudges a colour.
      expect(_contrast(HollowPalette.ink, HollowPalette.ground),
          greaterThanOrEqualTo(4.5));
    });

    test('secondary text clears the floor too', () {
      expect(_contrast(HollowPalette.inkSoft, HollowPalette.ground),
          greaterThanOrEqualTo(4.5));
      expect(_contrast(HollowPalette.inkSoft, HollowPalette.surface),
          greaterThanOrEqualTo(4.5));
    });

    test('the accent is legible on the surfaces it sits on', () {
      // The rose is used as a selected-tab colour and as a focus ring, so it is
      // read as a signal and has to be seen.
      expect(_contrast(HollowPalette.rose, HollowPalette.ground),
          greaterThanOrEqualTo(3.0));
      expect(_contrast(HollowPalette.gold, HollowPalette.ground),
          greaterThanOrEqualTo(3.0));
    });

    test('and the surfaces are close to each other, which is the point', () {
      // Section 20.3 asks for low contrast; the *surfaces* are deliberately
      // under-separated so a screen reads as one soft object. This asserts the
      // intent rather than a number, so that a future change to a hard-edged
      // palette breaks a test rather than a style.
      final separation =
          _contrast(HollowPalette.surface, HollowPalette.ground);
      expect(separation, lessThan(1.6));
    });

    test('**the faint ink clears the floor now, and the reason is a reader**', () {
      // This test used to assert the opposite -- that `inkFaint` fails 4.5:1, on the reasoning that it is
      // for placeholders and disabled controls, which WCAG exempts. A reader reported that the words and
      // the interface were the same colour, and measuring showed where: `inkFaint` is the colour of
      // captions, units and counts, which are content rather than placeholders, and on those surfaces it
      // sat at 3.0-3.5:1. The exemption was true about disabled controls and false about this interface,
      // so the value moved. What must stay true is the ordering -- see `theme_palette_test.dart`.
      expect(_contrast(HollowPalette.inkFaint, HollowPalette.ground),
          greaterThanOrEqualTo(4.5));
      expect(_contrast(HollowPalette.inkFaint, HollowPalette.ground),
          lessThan(_contrast(HollowPalette.inkSoft, HollowPalette.ground)));
    });
  });

  group('the theme', () {
    test('builds, and is dark, and carries the palette through', () {
      final theme = HollowTheme.build();
      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, HollowPalette.ground);
      expect(theme.colorScheme.primary, HollowPalette.rose);
      expect(theme.textTheme.displaySmall?.color, HollowPalette.ink);
    });

    test('every string a person reads is real UTF-8, not ASCII-fied', () {
      // Section 12.4's second rule, applied to the copy that exists so far. The
      // characters that would be tempting to strip are the whole point of it.
      expect(Copy.appTitle, contains('空'));
      expect(Copy.stockEmptyHint.primary.text, contains('瓶'));

      // **Two loops instead of one, because `Copy` is two types now.** The single
      // list this replaces mixed them and stopped compiling, which is the compiler
      // doing the job this very file is doing.
      //
      // And no string is empty, because an empty one renders as a gap nobody notices
      // until it ships.
      for (final line in [
        Copy.appTitle,
        Copy.appSubtitle,
        Copy.tabStock.textFor('zh-Hans'),
        Copy.tabBar.textFor('zh-Hans'),
        Copy.tabRecipes.textFor('zh-Hans'),
        Copy.tabCellar.textFor('zh-Hans'),
        Copy.tabSettings.textFor('zh-Hans'),
      ]) {
        expect(line.trim(), isNotEmpty);
      }

      // **Both languages of a pair.** The secondary is copy too, and a blank one is
      // the same defect one level down -- so this covers more than the list it
      // replaces rather than less. The pairs not named here have their own guard in
      // `dual_copy_test.dart`, which walks every one of them.
      for (final line in [
        Copy.stockTitle,
        Copy.stockEmpty,
        Copy.stockEmptyHint,
        Copy.stockAddBottle,
        Copy.recipesTitle,
        Copy.recipesEmpty,
        Copy.recipesEmptyHint,
        Copy.noLibrary,
        Copy.noLibraryHint,
      ]) {
        expect(line.primary.text.trim(), isNotEmpty);
        expect(
          line.secondary!.text.trim(),
          isNotEmpty,
          reason: line.primary.text,
        );
      }
    });

    test('the tab labels are the five section 12.3 asks for', () {
      // Five since the owner asked for a settings tab; 12.3 said four before that.
      expect(
        [
          Copy.tabStock.textFor('zh-Hans'),
          Copy.tabBar.textFor('zh-Hans'),
          Copy.tabRecipes.textFor('zh-Hans'),
          Copy.tabCellar.textFor('zh-Hans'),
          Copy.tabSettings.textFor('zh-Hans'),
        ],
        hasLength(5),
      );
    });

    test('the internal full name is in no string a person reads', () {
      // **Section 0's rule, asserted rather than remembered.** 空庭 /
      // Hollow Court is the public copy; the formal full name is an internal
      // identifier and an easter egg. The first version of the interface put the
      // full name on the title bar, and a test asserted it had to be there --
      // both wrong the same way, so neither caught the other. This asserts the
      // direction that cannot be got wrong twice.
      //
      // Checked as two-character sequences, not as characters: the full name and
      // the public name **share a character** (庭), so a single-character check
      // would either pass the full name or reject the public one.
      // Built from code points for the same reason the guard does it: this file is scanned too, and a literal
      // here would be rewritten by the sanitiser that prepares the public mirror.
      final onlyInTheFullName = [
        String.fromCharCodes(const [0x5E7D, 0x7A74]),
        String.fromCharCodes(const [0x871C, 0x5EAD]),
      ];

      // Every Copy string, **in both languages**. A new one has to be added here,
      // which is this guard's own weakness and worth naming rather than hiding.
      //
      // **The pairs are listed once and flattened, and the flattening is the point:**
      // the earlier version of this list held only the Chinese, so an internal name
      // reaching a reader through the English line would have passed it. A person
      // reads the second language too.
      final pairs = <CopyLine>[
        Copy.appName,
        Copy.stockTitle,
        Copy.stockEmpty,
        Copy.stockEmptyHint,
        Copy.stockAddBottle,
        Copy.stockName,
        Copy.stockNameHint,
        Copy.stockSaved,
        Copy.stockPickIngredient,
        Copy.stockVolumeProblem,
        Copy.stockNoVocabulary,
        Copy.stockPickHint,
        Copy.recipesTitle,
        Copy.recipesEmpty,
        Copy.recipesEmptyHint,
        Copy.barTitle,
        Copy.barShelfMain,
        Copy.barInTheBox,
        Copy.cellarTitle,
        Copy.noLibrary,
        Copy.noLibraryHint,
      ];

      final everything = <String>[
        Copy.appTitle,
        Copy.appSubtitle,
        Copy.tabStock.textFor('zh-Hans'),
        Copy.tabBar.textFor('zh-Hans'),
        Copy.tabRecipes.textFor('zh-Hans'),
        Copy.tabCellar.textFor('zh-Hans'),
        Copy.tabSettings.textFor('zh-Hans'),
        Copy.stockIngredient,
        Copy.stockIngredientHint,
        Copy.stockVolume,
        Copy.stockUnit,
        Copy.stockPrice,
        Copy.stockCurrency,
        Copy.stockBottles,
        Copy.stockSave,
        Copy.recipesMissing,
        Copy.recipesMissingCount,
        Copy.recipesNothingMissing,
        Copy.recipesGarnishOnly,
        Copy.recipesCount,
        Copy.filterAll,
        Copy.recipesMain,
        Copy.recipesGarnish,
        Copy.mixIt,
        Copy.garnish,
        Copy.recipeNote,
        Copy.recipeNoteHint,
        Copy.recipeNoteSave,
        Copy.recipeHasNote,
        Copy.verdictMakeable,
        Copy.verdictClose,
        Copy.verdictInsufficient,
        // The marker is read beside the reader's own language and is copy by intent,
        // so it is checked like any other string.
        Copy.machineMark,
        for (final line in pairs) ...[line.primary.text, line.secondary!.text],
      ];

      for (final line in everything) {
        for (final fragment in onlyInTheFullName) {
          expect(line.contains(fragment), isFalse,
              reason: '"$line" carries the internal full name');
        }
      }
    });

    test('and the public name is the pair section 0 asks for', () {
      expect(Copy.appTitle, '空庭');
      expect(Copy.appSubtitle, 'Hollow Court');
    });
  });

  group('the liquid swatch', () {
    Widget wrap(Widget child) => MaterialApp(
      theme: HollowTheme.build(),
      home: Scaffold(body: Center(child: child)),
    );

    testWidgets('draws a drink with a colour, a glass and ice', (tester) async {
      await tester.pumpWidget(wrap(const LiquidSwatch(
        liquid: LiquidVisual(colour: LiquidColour.orangeDark, opacityPercent: 75),
        glass: Glass.cocktail,
        ice: IceKind.cubes,
      )));
      expect(tester.takeException(), isNull);
      expect(find.byType(LiquidSwatch), findsOneWidget);
    });

    testWidgets('draws a drink with no colour at all, which is half the seed',
        (tester) async {
      // another source supplies no colour for any of its 88 recipes, so this is the
      // common case rather than an edge one, and it has to render as an empty
      // glass rather than as a guessed colour.
      await tester.pumpWidget(wrap(const LiquidSwatch(
        liquid: null,
        glass: Glass.highball,
        ice: IceKind.crushed,
      )));
      expect(tester.takeException(), isNull);
    });

    testWidgets('draws a layered drink with both colours', (tester) async {
      await tester.pumpWidget(wrap(const LiquidSwatch(
        liquid: LiquidVisual(
          colour: LiquidColour.red,
          colourSecondary: LiquidColour.yellowLight,
          opacityPercent: 50,
          opacitySecondary: 50,
          layered: true,
        ),
        glass: Glass.shot,
      )));
      expect(tester.takeException(), isNull);
    });

    testWidgets('draws every glass without throwing', (tester) async {
      for (final glass in Glass.values) {
        await tester.pumpWidget(wrap(LiquidSwatch(
          liquid: const LiquidVisual(
            colour: LiquidColour.neutralLight,
            opacityPercent: 40,
          ),
          glass: glass,
          ice: IceKind.none,
        )));
        expect(tester.takeException(), isNull, reason: glass.name);
      }
    });

    testWidgets('and a drink with no glass at all, which six recipes are',
        (tester) async {
      await tester.pumpWidget(wrap(const LiquidSwatch(
        liquid: LiquidVisual(colour: LiquidColour.blue, opacityPercent: 30),
        glass: null,
      )));
      expect(tester.takeException(), isNull);
    });
  });

  group('the colour mapping', () {
    test('every one of the 28 liquid colours maps to something', () {
      for (final colour in LiquidColour.values) {
        final mapped = liquidColour(colour);
        expect(mapped.a, 1.0, reason: colour.sourceName);
      }
    });

    test('families are distinguishable and tones are ordered', () {
      // A family is a hue, so two families must not come out the same, and the
      // tone has to move in one direction or the enum's whole design is moot.
      final families = <String, Color>{};
      for (final colour in LiquidColour.values) {
        families.putIfAbsent(colour.family, () => liquidColour(colour));
      }
      final distinct = families.values.map((c) => c.toARGB32()).toSet();
      expect(distinct, hasLength(families.length),
          reason: 'two families mapped to one colour');

      // Lightest must be lighter than light must be lighter than base, for the
      // families that have all three.
      expect(
        _luminance(liquidColour(LiquidColour.neutralLightest)),
        greaterThan(_luminance(liquidColour(LiquidColour.neutralLight))),
      );
      expect(
        _luminance(liquidColour(LiquidColour.neutralLight)),
        greaterThan(_luminance(liquidColour(LiquidColour.neutralDark))),
      );
      expect(
        _luminance(liquidColour(LiquidColour.neutralDark)),
        greaterThan(_luminance(liquidColour(LiquidColour.neutralDarkest))),
      );
    });

    test('and nothing in the list shouts', () {
      // Section 20.3: twenty of these are on screen at once and each is a
      // liquid rather than a signal. A fully saturated colour here would be the
      // palette's one mistake that no screenshot review would catch.
      for (final colour in LiquidColour.values) {
        final mapped = HSLColor.fromColor(liquidColour(colour));
        expect(mapped.saturation, lessThan(0.6),
            reason: '${colour.sourceName} is too saturated');
      }
    });
  });
}
