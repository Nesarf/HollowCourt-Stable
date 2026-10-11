import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hollow_court/ui/theme.dart';

/// **Every theme's text group, measured against the ground it is read on.**
///
/// `TextColours` names five roles per world, and the point of naming them is that they can be *checked*: a palette is
/// a taste argument except for the one part that is not -- **whether the words can be read on the surface they sit
/// on.** This file is that part, and it is what makes "tuned for each theme" a claim with evidence rather than a
/// statement of intent.
///
/// **The floors are the WCAG contrast ratios**, which are a borrowed standard and the right kind of borrowed thing:
/// 4.5:1 for body-sized text, 3:1 for text that is deliberately de-emphasised, and a higher one for the largest
/// type because a title in a colour that only just passes is a title that looks like a mistake.
///
/// **`faint` is allowed to be under 4.5 and nobody else is.** That is not a loophole: a hint or a placeholder is
/// meant to recede, and a palette that forced it to body contrast would make every one of them shout. What the floor
/// still refuses is faint text that has become unreadable, which is the failure mode this whole group exists to
/// catch.
void main() {
  /// Relative luminance, per WCAG 2.1.
  double luminance(Color c) {
    double channel(double v) =>
        v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
  }

  /// The contrast ratio between two colours, 1.0 (identical) to 21.0 (black on white).
  double contrast(Color a, Color b) {
    final la = luminance(a);
    final lb = luminance(b);
    final hi = math.max(la, lb);
    final lo = math.min(la, lb);
    return (hi + 0.05) / (lo + 0.05);
  }

  /// The floor each role has to clear, and the reason it is that number.
  const floors = <String, double>{
    'title': 7.0, // the largest type, and a title that only just passes looks like a mistake
    'body': 4.5, // running text, WCAG AA
    'caption': 4.5,
    'label': 4.5, // small and letter-spaced, so it needs this more than a caption does
    'faint': 3.0, // deliberately recessive, and still has to be readable
  };

  /// Every theme there is, taken from the palette itself rather than listed here.
  List<HollowPaletteValue> themes() {
    final before = HollowPalette.current;
    final out = <HollowPaletteValue>[];
    // The five are `static const` fields on the palette, and there is no enumerator -- so the test asks for the
    // ones the application ships by name, and the count is asserted below so a sixth cannot be added unnoticed.
    for (final name in const ['honeyed', 'cosmicLatte', 'winter', 'eternalDiva', 'wine']) {
      out.add(HollowPaletteValue.byName(name));
    }
    HollowPalette.use(before);
    return out;
  }

  test('**every theme names all five roles, and there are as many themes as this test knows**', () {
    final all = themes();

    // **The count is the guard, not the list.** A sixth world added to the palette without a line here would
    // otherwise be a theme whose text was never measured, and the failure would be a screen somebody cannot read.
    expect(all, hasLength(5), reason: 'a theme was added or removed; this test has to be told about it');
    for (final theme in all) {
      expect(theme.text.byRole.keys, containsAll(floors.keys), reason: theme.name);
    }
  });

  test('**every role clears its floor on every theme**', () {
    for (final theme in themes()) {
      for (final entry in theme.text.byRole.entries) {
        final floor = floors[entry.key]!;
        final measured = contrast(entry.value, theme.surface);
        expect(
          measured,
          greaterThanOrEqualTo(floor),
          reason: '${theme.name}/${entry.key} is ${measured.toStringAsFixed(2)}:1 against '
              '${theme.surface}, and its floor is $floor',
        );
      }
    }
  });

  test('**and against the ground too, because a page is not all surface**', () {
    // A caption on `surface` is the easy case; the same caption on `ground` -- a list row on a page rather than in a
    // raised card -- is where a group tuned only against one of them fails. The floor is the same, because the
    // reader does not know which of the two a given line happened to land on.
    for (final theme in themes()) {
      for (final role in ['title', 'body', 'caption', 'label']) {
        final measured = contrast(theme.text.byRole[role]!, theme.ground);
        expect(
          measured,
          greaterThanOrEqualTo(floors[role]!),
          reason: '${theme.name}/$role is ${measured.toStringAsFixed(2)}:1 against the ground',
        );
      }
    }
  });

  test('**the roles are a hierarchy rather than five names for one colour**', () {
    // Tuned per theme is only meaningful if the tones differ *within* a theme: a group whose five roles were the same
    // colour would clear every floor above and carry no hierarchy at all, which is the defect the group replaced.
    for (final theme in themes()) {
      final roles = theme.text.byRole;
      expect(roles['title'], isNot(roles['faint']), reason: theme.name);
      expect(roles['body'], isNot(roles['caption']), reason: theme.name);
      expect(roles['caption'], isNot(roles['label']), reason: theme.name);
      // **And they go one way, except for one pair that is deliberately out of order.**
      //
      // The run is title/body at the top and faint at the bottom. **`label` sits above `caption` in every dark
      // theme, and that is the point of giving it its own role**: it is the same size as a caption with less room
      // around it, so it needs more contrast rather than less. The first version of this test asserted a straight
      // five-step run, which failed on `honeyed` -- and the palette was right and the assertion was wrong, which is
      // what the failure message said once it printed the two numbers instead of just `false`.
      final ordered = ['title', 'body', 'caption', 'label', 'faint'];
      final l = {for (final r in ordered) r: luminance(roles[r]!)};
      final dark = theme.brightness == Brightness.dark;
      bool brighter(String a, String b) => dark ? l[a]! > l[b]! : l[a]! < l[b]!;

      expect(brighter('title', 'caption'), isTrue, reason: '${theme.name}: title vs caption');
      expect(brighter('body', 'caption'), isTrue, reason: '${theme.name}: body vs caption');
      expect(brighter('body', 'faint'), isTrue, reason: '${theme.name}: body vs faint');
      expect(brighter('label', 'faint'), isTrue, reason: '${theme.name}: label vs faint');
      expect(
        l['faint'] == l.values.reduce(dark ? math.min : math.max),
        isTrue,
        reason: '${theme.name}: faint is not the most recessive tone in the group: $l',
      );
    }
  });
}
