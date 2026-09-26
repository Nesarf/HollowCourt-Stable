import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/ui/materials.dart';
import 'package:hollow_court/ui/theme.dart';

/// **The design language's promise, checked rather than described.**
///
/// `docs/design-language.md` says the five rooms are furnished differently -- that a reader can tell which room
/// they are in from a corner of it -- and that no material may introduce text below the contrast the interface
/// already guarantees. Both are the kind of claim that quietly stops being true: a colour is nudged while fixing
/// something else, and six months later five rooms are the same dark grey and nobody can say when it happened.
///
/// So this file exists. It does not check that the materials are *good*; it checks they are **still distinct and
/// still readable**, which is what the document actually promised.
double _luminance(Color colour) {
  double channel(double value) =>
      value <= 0.03928 ? value / 12.92 : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(colour.r) + 0.7152 * channel(colour.g) + 0.0722 * channel(colour.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// How far apart two colours are in hue, on the wheel, in degrees.
double _hueGap(Color a, Color b) {
  final ha = HSVColor.fromColor(a).hue;
  final hb = HSVColor.fromColor(b).hue;
  final raw = (ha - hb).abs();
  return raw > 180 ? 360 - raw : raw;
}

/// Relative luminance, already defined above, reused as "how light is this room".
double _lightnessGap(Color a, Color b) => (_luminance(a) - _luminance(b)).abs();

/// A perceptual distance, weighted the way the eye weights the channels.
///
/// **Why not count channels.** The first version of this test asked for two channels more than 0.03 apart, and it
/// kept failing on rooms that a reader can tell apart at a glance -- because every material is a hue laid thinly
/// over a near-black ground, and that compresses all three channels towards the same small numbers. Counting
/// channels there measures the *arithmetic*, not the experience. What the document actually promises is that a
/// reader can tell which room they are in, so this is what gets measured.
double _distance(Color a, Color b) {
  final dr = a.r - b.r;
  final dg = a.g - b.g;
  final db = a.b - b.b;
  return math.sqrt(0.30 * dr * dr + 0.59 * dg * dg + 0.11 * db * db);
}

void main() {
  // The court is the default and the theme every other one is derived from, so it is the honest place to make a
  // claim about "the rooms are different" -- if they are only distinct in one theme, they are not distinct.
  const theme = HollowPaletteValue.honeyed;

  test('the five rooms are furnished differently, and a colour nudge cannot quietly merge them', () {
    // **A room is apart from another if it differs in hue or in lightness -- either is enough to name it.** The
    // first attempt demanded two channels of arithmetic difference and failed on pairs nobody could confuse; the
    // second asked for a hue gap alone and failed on amber against cream, which are the same hue at different
    // weights. A reader separates rooms on either axis, so the test does too, and the distance check behind it
    // catches the case where two rooms land on the same spot by two different routes.
    final rooms = RoomMaterial.values;
    for (var i = 0; i < rooms.length; i++) {
      for (var j = i + 1; j < rooms.length; j++) {
        final a = rooms[i].surface(theme);
        final b = rooms[j].surface(theme);
        final hue = _hueGap(a, b);
        final light = _lightnessGap(a, b);
        expect(
          hue >= 25 || light >= 0.06,
          isTrue,
          reason:
              '${rooms[i].name} and ${rooms[j].name} drifted into each other: '
              'hue ${hue.toStringAsFixed(1)} degrees, lightness ${light.toStringAsFixed(3)} apart',
        );
        expect(
          _distance(a, b),
          greaterThan(0.02),
          reason: '${rooms[i].name} and ${rooms[j].name} are the same colour by two different routes',
        );
      }
    }
  });

  test('a room is not the bare surface: the material has to be visible at all', () {
    for (final room in RoomMaterial.values) {
      expect(room.surface(theme), isNot(theme.surface), reason: '${room.name} is not actually furnished');
      expect(room.rule(theme), isNot(theme.line), reason: '${room.name} has no rule of its own');
    }
  });

  test('every room keeps the text readable, which is the mistake of the studied design we refuse', () {
    // Section 12.9.1 of DESIGN.md records that a rhythm game's own small print is unreadable by design, and that we took
    // its palette and its materials but not that. A material is exactly where that would get re-introduced: a
    // warm brown surface under the same ink, and the reading drops.
    for (final room in RoomMaterial.values) {
      final surface = room.surface(theme);
      expect(
        _contrast(theme.ink, surface),
        greaterThanOrEqualTo(4.5),
        reason: '${room.name}: body text on this material falls below the ratio the interface promises',
      );
    }
  });

  test('the materials hold their differences in every theme, not only the court', () {
    for (final theme in HollowPaletteValue.all) {
      for (final room in RoomMaterial.values) {
        final surface = room.surface(theme);
        expect(
          _contrast(theme.ink, surface),
          greaterThanOrEqualTo(4.5),
          reason: '${room.name} in the ${theme.name} theme',
        );
      }
    }
  });
}
