import 'package:flutter/widgets.dart';

import 'theme.dart';

/// The five rooms of the application, and the material each one is made of.
///
/// **The brief, and the tension inside it.** The owner asked on 2026-09-25 for the interface to stop being
/// monotonous *and* for each function to be visually independent, *各功能之间的视觉相互独立，不杂糅*. Those pull
/// against each other: variety alone gives five unrelated screens, separation alone gives one grey application
/// with different words on it. The way out is to put the variety in the **material** and the sameness in the
/// **grammar** -- one palette, one motif, one way of separating things, and five rooms furnished differently.
/// `docs/design-language.md` is the longer version.
///
/// **Why these are values and not a paragraph.** A design document that nothing checks is a wish. Every screen
/// takes its material from here rather than inventing a brown, and `test/ui/materials_test.dart` fails if two
/// rooms drift into the same colour -- so "we made them all the same dark grey" cannot pass quietly.
///
/// **Material is a *derivation*, not a colour.** Each room is a hue and a strength, and the surface is that hue
/// laid thinly over whatever the current theme's surface already is. That is what makes five materials work in
/// four themes without five times four hand-picked colours, and it is why nothing here is a literal hex value for
/// a background.
enum RoomMaterial {
  /// **Wood and glass.** A cellar: warm timber lines, and the glass is the point of the screen.
  cellar(Color(0xFF8A5A32), 0.34),

  /// **Stone and brass.** A bar top: cool, fine-grained, and deliberately the plainest of the five -- it is the
  /// room where a row of numbers has to stay readable. Its slate sits at 210 degrees, with the ledger's violet at
  /// 275 and the brass plate's verdigris at 145, so no two rooms are neighbours on the wheel.
  bar(Color(0xFF41566E), 0.34),

  /// **Paper.** Recipes are printed things -- and rose-sized paper is a real thing, which matters here for a
  /// reason the test forced: on a dark theme the ink has to stay light, so the *lightness* of a surface cannot be
  /// what tells two rooms apart. Hue is the only axis left, and warm paper sits 10 degrees from the cellar's
  /// amber. A rose-sized stock puts this room 45 degrees away and keeps the material honest.
  recipes(Color(0xFFC9889E), 0.30),

  /// **Ledger.** Ruled lines and a margin rule: the column is the interface. The ink is a leather
  /// ledger's violet rather than another blue -- the second try at keeping this room apart from the bar.
  journal(Color(0xFF4A2F6B), 0.38),

  /// **Brass plate.** The machine room, where plain geometry is the right answer.
  settings(Color(0xFF3F6B4F), 0.34);

  const RoomMaterial(this.hue, this.strength);

  /// The room's own colour, before it is thinned onto the theme's surface.
  final Color hue;

  /// How much of it shows. Enough to name the room, not enough to leave the palette.
  final double strength;

  /// The surface a panel of this material is made of, in [theme].
  ///
  /// [theme] is the theme rather than a colour because the same room has to exist in all four: the dark themes
  /// thin this hue onto a dark ground, the light ones onto a pale one, and both stay recognisably the room.
  Color surface(HollowPaletteValue theme) => Color.lerp(theme.surface, hue, strength)!;

  /// The hairline drawn on this material. A room's rule is its hue at a readable weight rather than the global
  /// line colour, which is what makes a glance at a corner enough to tell the rooms apart.
  Color rule(HollowPaletteValue theme) => Color.lerp(theme.line, hue, 0.55)!;

  /// The room's accent, for the one thing on a screen that matters. Never for large areas: the palette keeps
  /// exactly one saturated colour, and the rooms only tint it.
  Color accent(HollowPaletteValue theme) => Color.lerp(theme.gold, hue, 0.35)!;
}

/// The material in force, which is whatever the shell has told the palette the reader is looking at.
///
/// **A single mutable "current room" rather than an inherited widget**, because that is already how
/// [HollowPalette] works: the shell sets it when the tab changes, and every `HollowPalette.x` in the tree follows.
/// Adding a second mechanism for the same job would mean two places to keep in step, and the second one would be
/// the one that goes stale.
extension RoomMaterialContext on BuildContext {
  RoomMaterial get roomMaterial => currentRoom;
}

/// Which room the reader is in. Set by the shell when the tab changes.
///
/// **It lives here rather than on [HollowPalette] so that the two files do not have to import each other.** The
/// material needs the palette's values and the palette needs to know the room, which is a cycle; Dart tolerates
/// one, and leaving it in would mean that neither file can be read on its own. The state is small enough to keep
/// beside the thing it describes.
RoomMaterial _currentRoom = RoomMaterial.cellar;

RoomMaterial get currentRoom => _currentRoom;

set currentRoom(RoomMaterial value) => _currentRoom = value;
