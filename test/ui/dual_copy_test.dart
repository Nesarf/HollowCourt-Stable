import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/ui/l10n/dual_copy.dart';
import 'package:hollow_court/ui/l10n/dual_copy_text.dart';
import 'package:hollow_court/ui/theme.dart';

/// Dual copy: two languages in one place, and who is answerable for each.
///
/// The instruction is 中英文方面的相互影响可以采用双字幕的类型，也就是中英文同时实现，
/// 且根据需要进行机翻（用户可编辑）. The reader's locale is the primary line and the
/// secondary defaults to English.
///
/// **Two rules carry the weight here and both are about not lying to a reader.**
/// A machine translation must not be able to pass for a written one, and a line that
/// is not being drawn must say why it is not. The rest of the file is the plumbing
/// that makes those two sayable.
void main() {
  group('TextOrigin', () {
    test('a machine string needs a review mark and is not our own copy', () {
      const machine = Translated.machine('Hollow Court');
      expect(machine.needsReviewMark, isTrue);
      expect(machine.isOurOwnCopy, isFalse);
    });

    test('a written string needs no mark and is this project\'s copy', () {
      const written = Translated.authored('空庭');
      expect(written.needsReviewMark, isFalse);
      expect(written.isOurOwnCopy, isTrue);
    });

    test('a correction is edited and not authored', () {
      // The rule that matters most, and the reason it is a separate origin.
      //
      // Section 12.4 rejected 自定义中文 as a fifteenth locale because it would "put a
      // user's own words into the shipped seed data instead of on top of it". A
      // correction to a machine translation is that same thing, so collapsing it into
      // authored would quietly promote a user's words into this project's own copy.
      final corrected = const Translated.machine('Hollow Courrt').editedTo('Hollow Court');
      expect(corrected.text, 'Hollow Court');
      expect(corrected.origin, TextOrigin.edited);
      expect(corrected.origin, isNot(TextOrigin.authored));
    });

    test('a corrected string is settled for the reader and still not ours', () {
      // **The test that failed first, and it was right to.** This file originally
      // offered isGuest and isVouched, which read as complements and are not: an
      // edited string is both, because a machine wrote it and a person then read it.
      // Two questions were hiding in one pair, and `edited` is where they part.
      final corrected = const Translated.machine('x').editedTo('华沙');
      // Nobody needs to be told their own correction is a machine's.
      expect(corrected.needsReviewMark, isFalse);
      // And it is still not this project's to redistribute.
      expect(corrected.isOurOwnCopy, isFalse);
    });

    test('marking is asked for, never automatic', () {
      const written = Translated.authored('空庭');
      const machine = Translated.machine('Hollow Court');
      final corrected = const Translated.machine('x').editedTo('华沙');
      // A string that does not need the mark is returned unchanged even when a caller
      // asks, so no screen can decorate copy that does not need it.
      expect(written.asReviewMarked('*').text, '空庭');
      expect(corrected.asReviewMarked('*').text, '华沙');
      expect(machine.asReviewMarked('*').text, 'Hollow Court *');
      // And the marker does not change what the string is.
      expect(machine.asReviewMarked('*').origin, TextOrigin.machine);
    });

    test('the origin is part of identity, not decoration', () {
      // Two strings with the same text and different origins are different facts, so
      // they are not equal -- a cache keyed on the text alone would merge them.
      expect(
        const Translated.authored('x'),
        isNot(const Translated.machine('x')),
      );
      expect(const Translated.authored('x'), const Translated.authored('x'));
    });
  });

  group('CopyLine.present', () {
    const pair = CopyLine(
      Translated.authored('酒窖'),
      Translated.machine('Cellar'),
    );

    test('draws both when the mode is on and there is room', () {
      final shown = pair.present(dualCopy: true);
      expect(shown.primary, '酒窖');
      expect(shown.secondary, 'Cellar');
      expect(shown.isPaired, isTrue);
      expect(shown.omitted, isNull);
    });

    test('says the mode turned it off, rather than saying nothing', () {
      final shown = pair.present(dualCopy: false);
      expect(shown.isPaired, isFalse);
      expect(shown.omitted, SecondaryOmitted.bySetting);
    });

    test('separates a missing translation from a switched-off one', () {
      // The two have different fixes -- one is a preference, the other is a gap a
      // translator could fill -- so a caller that conflates them cannot report which.
      const single = CopyLine(Translated.authored('酒窖'));
      expect(single.present(dualCopy: true).omitted, SecondaryOmitted.notWritten);
      expect(single.present(dualCopy: false).omitted, SecondaryOmitted.bySetting);
    });

    test('a layout with no room is its own reason', () {
      // interaction-and-numbers.md 14: the lowest tier is named, reachable,
      // documented and tested, rather than an accident. A dropped second language is
      // that problem in typography.
      final shown = pair.present(dualCopy: true, roomForSecondary: false);
      expect(shown.isPaired, isFalse);
      expect(shown.omitted, SecondaryOmitted.noRoom);
      // The primary still draws. A narrow screen loses the subtitle, not the line.
      expect(shown.primary, '酒窖');
    });

    test('reports a secondary that still needs a review mark', () {
      expect(pair.secondaryNeedsReviewMark, isTrue);
      const writtenOnly = CopyLine(
        Translated.authored('酒窖'),
        Translated.authored('Cellar'),
      );
      expect(writtenOnly.secondaryNeedsReviewMark, isFalse);
    });
  });

  group('CopyPresentation.joined', () {
    test('joins both on one line, which is the task switcher case', () {
      final shown = Copy.appName.present(dualCopy: true);
      expect(shown.joined(' · '), '空庭 · Hollow Court');
    });

    test('falls back to the primary rather than to a bare separator', () {
      const single = CopyLine(Translated.authored('空庭'));
      expect(single.present(dualCopy: true).joined(' · '), '空庭');
    });
  });

  group('the character\'s copy', () {
    // Section 14.1 keeps the character in the stable release **as copy**, so a
    // machine line in her mouth is a different product decision from a machine line
    // on a button. The rule is asserted rather than trusted.
    //
    // The list grows as strings are converted to CopyLine; the check does not need to
    // change, which is the point of writing it against a collection now.
    // **The list is the check.** Section 4.2(c) says her copy is hand-written in both
    // languages and that the rule is asserted rather than trusted; this is that
    // assertion. It grows as strings are converted and the checks themselves do not
    // change, which is the reason to write them against a collection now.
    //
    // **Every `CopyLine` in `Copy` belongs here, and nothing else can.** The other
    // half of the split -- the strings that cannot be paired at all -- stays a
    // `String`, so the compiler is holding that half: a converted constant that
    // someone forgets to add here still fails the two tests below, and a constant
    // that could not be converted is not addable.
    final pairedCopy = <String, CopyLine>{
      'appName': Copy.appName,
      'stockTitle': Copy.stockTitle,
      'stockEmpty': Copy.stockEmpty,
      'stockEmptyHint': Copy.stockEmptyHint,
      'stockAddBottle': Copy.stockAddBottle,
      'stockName': Copy.stockName,
      'stockNameHint': Copy.stockNameHint,
      'stockSaved': Copy.stockSaved,
      'stockPickIngredient': Copy.stockPickIngredient,
      'stockVolumeProblem': Copy.stockVolumeProblem,
      'stockNoVocabulary': Copy.stockNoVocabulary,
      'stockPickHint': Copy.stockPickHint,
      'recipesTitle': Copy.recipesTitle,
      'recipesEmpty': Copy.recipesEmpty,
      'recipesEmptyHint': Copy.recipesEmptyHint,
      'barTitle': Copy.barTitle,
      'barShelfMain': Copy.barShelfMain,
      'barInTheBox': Copy.barInTheBox,
      'cellarTitle': Copy.cellarTitle,
      'noLibrary': Copy.noLibrary,
      'noLibraryHint': Copy.noLibraryHint,
    };

    test('is written by a person in both languages', () {
      for (final entry in pairedCopy.entries) {
        expect(
          entry.value.primary.origin,
          TextOrigin.authored,
          reason: '${entry.key} primary is ${entry.value.primary.origin.name}',
        );
        expect(
          entry.value.secondary?.origin,
          TextOrigin.authored,
          reason: '${entry.key} secondary is ${entry.value.secondary?.origin.name}',
        );
      }
    });

    test('and both languages are actually there', () {
      for (final entry in pairedCopy.entries) {
        expect(entry.value.primary.text, isNotEmpty, reason: entry.key);
        expect(
          entry.value.secondary,
          isNotNull,
          reason: '${entry.key} has no second language',
        );
        expect(entry.value.secondary!.text, isNotEmpty, reason: entry.key);
      }
    });

    test('and the second language is not the first one repeated', () {
      // A pair whose halves are identical is a string with a hyphen in it. It would
      // pass "written by a person in both languages" and mean nothing.
      for (final entry in pairedCopy.entries) {
        expect(
          entry.value.secondary!.text,
          isNot(entry.value.primary.text),
          reason: '${entry.key} says the same thing twice',
        );
      }
    });

    test('and the list is not empty, so the check is not vacuous', () {
      expect(pairedCopy, isNotEmpty);
    });
  });

  group('the subtitle is a second level of type', () {
    // Section 2.7: the secondary is smaller and dimmer. **Derived from the primary's
    // style rather than passed in**, so that a pair cannot be drawn at the primary's
    // size by accident -- which is the whole difference between a subtitle and a
    // repetition.
    test('is smaller and dimmer than the line above it', () {
      const base = TextStyle(fontSize: 20, color: Color(0xFFEDE4D8));
      final second = DualCopyText.secondary(base)!;
      expect(second.fontSize, lessThan(base.fontSize!));
      expect(second.color!.a, lessThan(1.0));
      // The same colour with less of it, so a rose error stays rose in both
      // languages and only loses emphasis.
      expect(second.color!.r, base.color!.r);
      expect(second.color!.g, base.color!.g);
      expect(second.color!.b, base.color!.b);
    });

    test('and a style that says nothing still yields a usable one', () {
      final second = DualCopyText.secondary(null)!;
      expect(second.fontSize, isNotNull);
      expect(second.color, isNotNull);
      expect(second.color!.a, lessThan(1.0));
    });
  });

  group('DualCopyText', () {
    Widget app({bool? dual}) => ProviderScope(
      overrides: [if (dual != null) dualCopyProvider.overrideWithValue(dual)],
      child: const MaterialApp(
        home: Scaffold(body: DualCopyText(Copy.stockTitle)),
      ),
    );

    testWidgets('draws both languages, which is the feature', (tester) async {
      // **Which language is first now depends on the reader**, which is the change of 2026-09-22: the
      // primary line used to be the authored Chinese regardless of settings. So the assertion is that two
      // *different* lines are drawn, one in each language, rather than that a particular one is first.
      await tester.pumpWidget(app());
      expect(find.text('酒窖'), findsOneWidget);
      expect(find.text('Cellar'), findsOneWidget);
    });

    testWidgets('and draws one when the reader turns the second off', (tester) async {
      await tester.pumpWidget(app(dual: false));
      // Exactly one line, in the reader's language. The earlier version of this asserted that Chinese was
      // the survivor, which was true only while the primary line ignored the locale.
      final chinese = find.text('酒窖');
      final english = find.text('Cellar');
      expect(chinese.evaluate().length + english.evaluate().length, 1);
      expect(english, findsOneWidget,
          reason: 'the test harness runs in an English locale, so English is the reader language');
    });

    testWidgets('a line nobody has translated draws one and is not an error', (
      tester,
    ) async {
      // Null is a real state and not a failure. The widget has to draw the line it
      // has rather than a placeholder, which is the whole reason `present` returns
      // the primary either way.
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: DualCopyText(CopyLine(Translated.authored('未译'))),
            ),
          ),
        ),
      );
      expect(find.text('未译'), findsOneWidget);
    });
  });

  group('NamePair', () {
    test('a name is not a translation', () {
      // 纯白交响曲 is a rendering of ましろ色シンフォニー and not a translation of it, and
      // the source records the original in its own body. Translating a proper noun
      // produces a different drink, so the original is carried beside the name and
      // the translation, if any, is a gloss.
      const name = NamePair(
        '纯白交响曲',
        original: 'ましろ色シンフォニー',
        gloss: Translated.machine('Pure White Symphony'),
      );
      expect(name.name, '纯白交响曲');
      expect(name.original, 'ましろ色シンフォニー');
      // A gloss may be a machine's, which is the whole reason it is a Translated and
      // the name is not.
      expect(name.gloss!.needsReviewMark, isTrue);
      expect(name.toString(), '纯白交响曲 (ましろ色シンフォニー)');
    });

    test('a name with no original is just a name', () {
      const name = NamePair('Trancing Time');
      expect(name.hasOriginal, isFalse);
      expect(name.toString(), 'Trancing Time');
    });

    test('an empty original counts as none', () {
      const name = NamePair('华沙', original: '');
      expect(name.hasOriginal, isFalse);
      expect(name.toString(), '华沙');
    });
  });
}
