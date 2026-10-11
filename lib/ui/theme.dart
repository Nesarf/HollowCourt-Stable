/// The palette, the typography and the voice.
///
/// Section 14.1 puts the aesthetic core in the stable release and defers only
/// what is measured in megabytes. So this file has to carry the look **without
/// an asset pack**, and that is a constraint rather than an apology: it means
/// colour, scale, spacing, letter case and the words themselves do the work, and
/// nothing here needs a font file or a texture to exist.
///
/// Section 20.3 asks for a specific register -- soft, rounded over chamfered,
/// low specular contrast, warm mid-tones, light that wraps rather than edges. A
/// palette is where most of that is won or lost, because contrast is a choice
/// before it is a rendering: [HollowPalette] is built out of warm near-blacks and
/// soft creams rather than #000 and #FFF, and nothing in it is fully saturated.
library;

import 'package:flutter/material.dart';

import 'l10n/dual_copy.dart';
import 'l10n/voice.dart';

/// The colours, as a value that can be one of several.
///
/// **Four themes, and the palette stopped being a table of constants to make them possible.** The
/// first version was `abstract final class HollowPalette` with ten `static const Color`s, read
/// directly by a hundred call sites. That is the cheapest thing that can work and it cannot be
/// switched: a theme is a *value* the whole interface reads, and a constant is a value that cannot
/// change.
///
/// WHY THE NAMES BELOW ARE STILL `HollowPalette.ground` AND NOT `context.palette.ground`.
///
/// The honest alternative was to thread a palette through every call site -- a hundred palette
/// references plus seventy-six text styles, in sixteen files, and every `const` widget holding a
/// colour would have had to stop being const. What that buys is *per-subtree* theming: one half of a
/// screen drawn in one palette and the other half in another. **This application has no use for
/// that.** Its appearance is one decision for the whole program, exactly like the language, and the
/// switch for it lives at the root for the same reason.
///
/// What it costs is one thing worth stating: these are getters rather than inherited values, so a
/// theme change is visible when the tree rebuilds. The root rebuilds when the setting changes, so
/// that is a property of the mechanism rather than a bug in it -- and it is why nothing may hold a
/// colour across builds. **A `const` widget holding a colour would freeze the theme it was compiled
/// under, which is why there are now no `const` widgets holding colours at all: the compiler refuses
/// to allow one, and that refusal is the guarantee.**
abstract final class HollowPalette {
  /// The theme in force. Set once at the root; read everywhere.
  ///
  /// **One mutable global, deliberately, and the only one in the interface.** See the note above for
  /// what it buys and what it costs. It is set before the first frame and changed only when the
  /// reader changes it, so nothing ever observes it half-applied.
  static HollowPaletteValue _current = HollowPaletteValue.honeyed;

  /// Switches the appearance. Called by the root, from the stored setting.
  static void use(HollowPaletteValue value) => _current = value;

  /// What is in force now, for a caller that needs the whole value -- a painter drawing an ornament,
  /// say -- rather than one colour out of it.
  static HollowPaletteValue get current => _current;

  /// The page. A warm near-black in `court`, aged paper in `parchment`.
  static Color get ground => _current.ground;

  /// A surface lifted off the page -- a card, a field, the navigation bar.
  static Color get surface => _current.surface;

  /// A surface standing slightly forward: a selected tab, a card under the finger.
  static Color get surfaceRaised => _current.surfaceRaised;

  /// **A separator: the hairline between one option and the next.**
  ///
  /// It is not the same colour as [hairline], and the difference is the whole of a reader's complaint. This one
  /// is *functional* -- a rule that says where one thing stops and the next begins -- so it has to clear the
  /// 3:1 non-text floor the same way a control's outline does. It used to be 1.4-1.7:1 against the page, which
  /// is why the reader's words were that the separation between options was not obvious: the rules were there
  /// and could not be seen.
  static Color get line => _current.line;

  /// **Decoration: a stroke in the background, a chart's gridline, a graduated cylinder's marks.**
  ///
  /// Held at 1.8:1 or below on purpose, and the reason is written in `ornament.dart`: the backdrop must never
  /// compete with text for attention. Splitting the two was necessary rather than tidy -- one colour cannot be
  /// both invisible-as-decoration and clearly-visible-as-separation, and the test that kept this one faint was
  /// also what kept the separators faint.
  static Color get hairline => _current.hairline;

  /// Body text.
  static Color get ink => _current.ink;

  /// Secondary text: a caption, a unit, a count.
  static Color get inkSoft => _current.inkSoft;

  /// Text that is barely there -- a placeholder, a disabled control.
  static Color get inkFaint => _current.inkFaint;

  /// The accent, and the one saturated colour in any of these palettes. Used sparingly, for the
  /// thing the screen is *for*.
  static Color get rose => _current.rose;

  /// A second accent, for a state that is good news rather than emphasis.
  static Color get gold => _current.gold;

  /// A drink that cannot be made. An absence rather than an error.
  static Color get absent => _current.absent;

  /// **The text and icon colour for anything drawn on an accent fill.**
  ///
  /// This exists because the accents are mid-tones and [ink] is not: measured on 2026-09-23, ink on a gold fill
  /// is **1.5:1** in three palettes and 2.7 in the fourth, and ink on a rose fill is 2.2-2.8. That is not a
  /// near miss, it is a word on a background of nearly the same lightness -- which is what a reader sees on a
  /// selected chip, and what "the text and the interface are the same colour" means in practice.
  ///
  /// The pairing rule is one line: **on an accent fill, the foreground is [onAccent] and never [ink].** It is
  /// asserted in `theme_palette_test.dart` against both accents in all four palettes, so a fifth palette
  /// cannot be added without answering it.
  static Color get onAccent => _current.onAccent;

  /// Every theme this build carries, in the order a picker should offer them.
  static const List<HollowPaletteValue> all = HollowPaletteValue.all;
}

/// One theme's ten colours.
///
/// Every value is warm-shifted and deliberately under-contrasted, in all four: the *surfaces* sit
/// close to each other on purpose, so a screen reads as one soft object rather than as a set of
/// panels. The accessibility floor is respected on text -- [ink] on [ground] clears 4.5:1, which is
/// asserted in `theme_palette_test.dart` rather than assumed -- and no colour anywhere is fully
/// saturated.
/// The instrument a world draws faintly behind its pages.
///
/// **The grammar is shared and the shape is not.** Every world's ornament is a hairline drawing at the same
/// strength -- a third of the hairline colour, chosen so that it is visible when looked at and absent when read
/// past -- because that restraint is what keeps the background a background. What differs is *what* is drawn
/// there, and it is the third axis on which two dark worlds can be told apart after their ground textures.
enum Ornament {
  /// **The halo itself**: rings, the prism ring, the graduations, on the character's own fifteen degrees.
  halo,

  /// **Engine-turning**: a guilloché rosette, the way a banknote or a watch case is decorated. White Court.
  guilloche,

  /// **A snow crystal** built out of the motif: six arms of nested rhombi. Winter Court.
  snowCrystal,

  /// **Sounding rings**: concentric rings with a radial burst across them, the ripple a note leaves.
  /// 永遠の歌姫, and the first ornament that is an event rather than an object.
  songRings,

  /// **Cooperage**: the arched bands and vertical staves of a barrel's head, seen face on. 酒红.
  ///
  /// The only ornament here whose subject is a *container* rather than a night sky, an instrument or a note -- the
  /// right subject for the room a cellar keeps its wine in, and the first one a reader could put a hand on rather
  /// than only look up at.
  cooperage,
}

/// The texture a world draws its ground with.
///
/// **A world is not a palette.** Two of these three worlds are dark and use the same motif; what tells them apart
/// on a screen with no words on it is the material the ground is made of. So the ground's texture is a property of
/// the world rather than a constant of the application, and `test/ui/theme_palette_test.dart` fails if two worlds
/// end up sharing one -- the same way it fails if two materials do.
///
/// Each is drawn rather than shipped as an image: a repeating texture as a PNG would need one per density and
/// would fight the theme's colours, while a painter takes the world's own ink and scales with the display.
enum GroundTexture {
  /// **The motif itself**, as a rhombic lattice: the halo's crystal, tiled. Amber Court.
  lattice,

  /// **Laid paper**: fine horizontal laid lines with a chain line every few centimetres, which is how paper was
  /// actually made and reads as *paper* rather than as a grid. White Court.
  laid,

  /// **Frost**: rhombi at two scales, sparse and uneven, the way ice grows on glass rather than the way a
  /// pattern is printed. Winter Court.
  frost,

  /// **A staff**: five fine horizontal lines with the motif scattered across them as notes. 永遠の歌姫.
  ///
  /// **Five lines and not a grid**, because a grid is what the lattice already is: the point of the four grounds
  /// is that they are four *materials*, and this one is ruled paper for music rather than ruled paper for prose --
  /// which is why the lines are close together and the marks on them are sparse.
  score,

  /// **Grain**: long wavering lines along one axis, with occasional darker bands across them.
  ///
  /// A material rather than a pattern, which is the rule every ground here follows. Where `laid` is the straight
  /// rule of a mould-made page, this one **wavers** -- the difference between paper and the grain of a stave, and
  /// the reason it is not simply `laid` at another angle. 酒红.
  grain,
}

/// The two shapes of one world's picture.
///
/// **Both live here and neither is chosen here.** Which one is drawn is a question about the screen -- a phone
/// held upright against a desktop window -- and the answer belongs to whoever is drawing, not to the theme that
/// owns the files. Putting a `Platform` check in this class would make a palette depend on the operating system,
/// which is the kind of coupling that turns a colour table into a device table.
final class WorldArtwork {
  const WorldArtwork({required this.tall, required this.wide});

  /// For a window taller than it is wide. `assets/art/diva-tall.png`, 1080x2160.
  final String tall;

  /// For a window wider than it is tall. `assets/art/diva-wide.png`, 1920x960.
  final String wide;
}

final class HollowPaletteValue {
  const HollowPaletteValue({
    required this.name,
    required this.ground,
    required this.surface,
    required this.surfaceRaised,
    required this.line,
    required this.ink,
    required this.inkSoft,
    required this.inkFaint,
    required this.rose,
    required this.gold,
    required this.absent,
    required this.onAccent,
    required this.hairline,
    this.texture = GroundTexture.lattice,
    this.ornament = Ornament.halo,
    this.brightness = Brightness.dark,
    this.artwork,
  });

  /// **A picture this world draws behind everything, or null.**
  ///
  /// Only 永遠の歌姫 has one, and it is deliberately a field rather than a branch on the theme's name: a world
  /// that carries art says so where the world is defined, and nothing elsewhere has to know which world that is.
  /// The owner's instruction on 2026-09-30 was that the two pieces 「只限定于 miku 主题里出现」 -- which is also
  /// what keeps the other three worlds honest: a full-colour illustration behind a page is the one thing the
  /// `hairline` rule exists to prevent, and a world without this field simply has none.
  ///
  /// **Two files, because the shape follows the screen.** The owner's split: 「竖版用于安卓，横版用于 windows 和
  /// linux」. `assets/art/diva-tall.png` is 1080x2160 for a phone held upright, `diva-wide.png` is 1920x960 for a
  /// desktop window -- one picture cropped two ways would be the wrong drawing on both.
  final WorldArtwork? artwork;

  /// The stored name: `honeyed`, `cosmicLatte`, `winter`. A wire format by identity, like a unit's id, so
  /// renaming one breaks a stored setting rather than a test -- which is why `byName` falls back instead of
  /// throwing, and why a name from an older build is a case the tests cover.
  final String name;

  /// Dark or light, for the parts of Material that have to be told: `ThemeData.brightness` decides
  /// what a default text colour and a system bar do where this application has not said.
  final Brightness brightness;

  final Color ground;
  final Color surface;
  final Color surfaceRaised;
  final Color line;
  final Color ink;
  final Color inkSoft;
  final Color inkFaint;
  final Color rose;
  final Color gold;
  final Color absent;

  /// The foreground for text and icons placed on [rose] or [gold]. See [HollowPalette.onAccent].
  final Color onAccent;

  /// A decorative stroke, kept below 1.8:1. See [HollowPalette.hairline].
  final Color hairline;

  /// What this world's ground is made of. See [GroundTexture].
  final GroundTexture texture;

  /// What this world draws behind its pages. See [Ornament].
  final Ornament ornament;

  /// The theme this application started with: a Renaissance medallion in a dark room.
  /// **琥珀庭 Amber Court: the court as it is.**
  ///
  /// The home world, and the one the name describes -- a honeyed court in a hollow. Its ground is nearly black so
  /// the amber reads as light *in* the room rather than paint on it, and the one saturated colour is the honey.
  static const HollowPaletteValue honeyed = HollowPaletteValue(
    name: 'honeyed',
    ornament: Ornament.halo,
    texture: GroundTexture.lattice,
    ground: Color(0xFF16110A),
    surface: Color(0xFF1F1810),
    surfaceRaised: Color(0xFF2B2116),
    line: Color(0xFF817158),
    ink: Color(0xFFF4E8CE),
    inkSoft: Color(0xFFC7B392),
    inkFaint: Color(0xFF9D8C6A),
    // **Raised by ten percent of the way to white on 2026-09-30 to clear the text floor.** It sat at 3.98:1 on
    // `surfaceRaised`, where it is drawn as caption text in warnings and totals across the interface -- just under
    // the 4.5:1 that `theme_palette_test.dart` now asserts for an accent used as text. The hue is unchanged.
    rose: Color(0xFFCA7279),
    gold: Color(0xFFE2A63E),
    absent: Color(0xFF988D7B),
    onAccent: Color(0xFF1A1208),
    hairline: Color(0xFF382C1D),
  );

  /// **宇宙拿铁 Cosmic Latte: the same court at noon, in the colour of the sky averaged over all light.**
  ///
  /// **This replaced 白庭 on 2026-10-01, and the replacement is the point.** The old world's `#F4F1E9` and this one's
  /// `#FFF8E7` are four points apart in red, seven in green and two in blue -- under one percent each. Side by side
  /// they can be told apart; **in two different builds, one after another, they cannot**, and a reader who chose the
  /// light world would have been handed what looked like the same light world under a new name and would reasonably
  /// have concluded that the theme switch does nothing. `docs/memo-themes.md` argues that at length, and the owner
  /// settled it: **delete 白庭 and add `CL`**, rather than shipping both or renaming one.
  ///
  /// **The rest of the palette is carried over unchanged, and that is a measurement rather than a shortcut.** The new
  /// ground is *lighter* than the old one in every channel, and the ink here is dark, so every contrast ratio this
  /// room had either holds or improves; the light-mode rules that section 12.9.1 argues for and
  /// `test/ui/theme_palette_test.dart` checks are exercised by this world exactly as they were by 白庭.
  ///
  /// The ornament and the texture stay too -- a guilloche on laid paper is what this room is made of, and the colour
  /// is what changed.
  static const HollowPaletteValue cosmicLatte = HollowPaletteValue(
    name: 'cosmicLatte',
    ornament: Ornament.guilloche,
    brightness: Brightness.light,
    texture: GroundTexture.laid,
    ground: Color(0xFFFFF8E7),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFFAF8F2),
    line: Color(0xFF898478),
    ink: Color(0xFF1B1813),
    inkSoft: Color(0xFF4C463C),
    inkFaint: Color(0xFF70695D),
    rose: Color(0xFFA83A58),
    gold: Color(0xFF876A29),
    absent: Color(0xFF6F685F),
    onAccent: Color(0xFFFFFDF8),
    hairline: Color(0xFFE3DCCC),
  );

  /// **冬庭 Winter Court: the court after frost.**
  ///
  /// The third world exists to prove the first two are choices rather than defaults: it is as dark as the honeyed
  /// court and shares none of its warmth, which is the test of whether a palette is a *world* or a shade.
  static const HollowPaletteValue winter = HollowPaletteValue(
    name: 'winter',
    ornament: Ornament.snowCrystal,
    texture: GroundTexture.frost,
    ground: Color(0xFF0D1418),
    surface: Color(0xFF141D22),
    surfaceRaised: Color(0xFF1D282E),
    line: Color(0xFF677981),
    ink: Color(0xFFE6F1F5),
    inkSoft: Color(0xFFA9C0C9),
    inkFaint: Color(0xFF80959E),
    // **Raised on the same day and for the same reason as the honeyed court's**: 4.02:1 on `surfaceRaised` is
    // under the floor for caption text, and this is the rose that clears it without leaving its hue.
    rose: Color(0xFFC47A8E),
    gold: Color(0xFF8FBAC6),
    absent: Color(0xFF84959C),
    onAccent: Color(0xFF0A1014),
    hairline: Color(0xFF24333A),
  );

  /// **永遠の歌姫: the fourth world, and the first one that is homage rather than a place.**
  ///
  /// **The colour is `#39C5BB` and the build is `3939`, and the two are one statement.** `39` reads ミク -- three
  /// is ミ, nine is ク -- so the number written twice is the reading written twice, and the hex carries `39` in its
  /// first two digits. The owner set the colour and the build number, and neither is a coincidence.
  ///
  /// **The first version of this comment got it wrong, and the mistake is worth keeping.** Reading the colour
  /// alone, I took it for copper patina, invented a plausible etymology, and wrote a paragraph about bronze and
  /// the Statue of Liberty. None of that was asked for and none of it was true to the request; the owner's
  /// question -- 「你应该知道 #39C5BB 的特殊含义吧?」 -- is the correction. The design record already held the clue
  /// that this is a reference: `J1407b` is a real designation and 宇宙拿鉄 is a real colour. What was invented was
  /// *which* reference, and a value somebody chose is not a value to interpret alone.
  ///
  /// **The name is the owner's, and it is a title rather than a name.** 永遠の歌姫 -- the eternal diva -- so the
  /// world is homage without borrowing anybody's mark, which is the line the rest of this project draws.
  ///
  /// **The storage name is permanent** (`A wire format by identity`, like a unit's id), so it is fixed now and
  /// cannot follow the display name if that is ever reworded.
  static const HollowPaletteValue eternalDiva = HollowPaletteValue(
    name: 'eternalDiva',
    ornament: Ornament.songRings,
    texture: GroundTexture.score,
    ground: Color(0xFF0A1414),
    surface: Color(0xFF101B1B),
    surfaceRaised: Color(0xFF182626),
    line: Color(0xFF5E7A78),
    ink: Color(0xFFEAF6F4),
    inkSoft: Color(0xFFB6CFCC),
    inkFaint: Color(0xFF8AA3A0),
    // **Not `#39C5BB` itself, and the reason is a rule rather than a preference.** That colour is the accent
    // below; `rose` is drawn as caption text on `surfaceRaised` across the interface, so it is held to the 4.5:1
    // text floor rather than the 3:1 a fill needs. This rose clears it with room.
    rose: Color(0xFFE0707F),
    gold: Color(0xFF39C5BB),
    absent: Color(0xFF8AA09E),
    onAccent: Color(0xFF06201E),
    hairline: Color(0xFF1F3130),
    // **The two pieces the owner traced, and this is the only world that draws them.** Traced from GPT
    // pictures into one ink (`#39C5BB`, the accent above) by `art/make_flat_svg.py`; the rasters here are
    // rendered from those SVGs because Flutter reads a bitmap and not a vector, and the shapes stay exact
    // because the SVG is the source rather than a snapshot of one.
    artwork: WorldArtwork(
      tall: 'assets/art/diva-tall.png',
      wide: 'assets/art/diva-wide.png',
    ),
  );

  /// **The owner's wine-red room, added 2026-10-01, and the palette that is not a near-black.**
  ///
  /// Every other world is a dark ground with a coloured accent, and the three dark grounds sit within five to
  /// seventeen RGB units of each other. **This one is a colour in its own right** — 79 units from 銅鳴, further than
  /// any two existing worlds are from each other — which is why it earns a place rather than being a fifth shade.
  ///
  /// **Every role was derived from the contrast rules rather than chosen and then tested.** The values below were
  /// solved backwards from `test/ui/theme_palette_test.dart`'s floors, and the two that failed a first attempt are
  /// worth naming because they are the two the rules bite hardest: `inkFaint` has to clear 4.5:1 against the
  /// *raised* surface rather than the ground (the lightest thing it can be drawn on), and `line` has to clear 3.0:1
  /// against all three, which makes the raised surface the binding case for both. `line` at the first attempt was
  /// 2.41:1 there.
  ///
  /// **`gold` here is a warm bronze rather than a gold**, for the reason 永遠の歌姫's accent is not its own rose: an
  /// accent that sat too close to the ground would make the interface's emphasis indistinguishable from its
  /// surfaces. It also clears 3:1 on the ground with room, and `ink` on it stays under 4.5:1 so that a label on an
  /// accent is still visibly a label.
  static const HollowPaletteValue wine = HollowPaletteValue(
    name: 'wine',
    ornament: Ornament.cooperage,
    texture: GroundTexture.grain,
    ground: Color(0xFF3A1219),
    surface: Color(0xFF4A1A22),
    surfaceRaised: Color(0xFF5C2430),
    line: Color(0xFFB0707C),
    ink: Color(0xFFF7ECEE),
    inkSoft: Color(0xFFCFB2B7),
    inkFaint: Color(0xFFBC9DA3),
    rose: Color(0xFFF0A6B2),
    gold: Color(0xFFD69B63),
    absent: Color(0xFFB79AA0),
    onAccent: Color(0xFF1E0A0E),
    hairline: Color(0xFF4E2129),
  );

  static const List<HollowPaletteValue> all = [honeyed, cosmicLatte, winter, wine, eternalDiva];

  /// The theme with [name], or the world the application was designed around when the name is one this build does not carry.
  ///
  /// **A missing theme is not an error**, the same rule a missing unit follows: a setting written by
  /// a build that carried a theme this one does not must not stop the application from opening, and
  /// the fallback is the theme the application was designed around.
  static HollowPaletteValue byName(String? name) {
    for (final value in all) {
      if (value.name == name) return value;
    }
    return honeyed;
  }
}

/// Type.
///
/// **No font is bundled**, and rather than pretend otherwise this expresses the register through
/// scale, spacing and case. A display size with generous letter spacing on a serif-capable platform
/// default reads as unhurried; the same string at 14 pt bold reads as a form. When a face is chosen
/// it slots in here and nothing else has to change.
///
/// The sizes are named for their job rather than their point size, because a screen should ask for
/// `display` and not for 34.
///
/// **These are getters now, because a text style carries a colour and a colour belongs to a theme.**
/// They were `static const TextStyle`s, which was cheaper and worked exactly as long as there was one
/// palette: a const style bakes in the colour it was compiled with, so a theme switch would have left
/// every word in this application in the old one. A getter rebuilds the style from the palette in
/// force. The cost is a `TextStyle` constructed per use rather than shared -- it is a handful of
/// fields, Flutter compares them by value, and a screen builds a few hundred of them.
abstract final class HollowType {
  /// A screen's title, and the only place text is large.
  static TextStyle get display => TextStyle(
    fontSize: 30,
    height: 1.15,
    letterSpacing: 0.4,
    fontWeight: FontWeight.w300,
    color: HollowPalette.ink,
  );

  /// A section heading inside a screen.
  static TextStyle get heading => TextStyle(
    fontSize: 19,
    height: 1.3,
    letterSpacing: 0.2,
    fontWeight: FontWeight.w400,
    color: HollowPalette.ink,
  );

  /// A recipe's name in a list.
  static TextStyle get title => TextStyle(
    fontSize: 16,
    height: 1.3,
    letterSpacing: 0.1,
    fontWeight: FontWeight.w400,
    color: HollowPalette.ink,
  );

  static TextStyle get body => TextStyle(
    fontSize: 14,
    height: 1.45,
    color: HollowPalette.ink,
  );

  /// A unit, a count, a percentage. Tabular so that a column of them lines up, which is the one place
  /// this application wants numbers to look like numbers.
  static TextStyle get numeric => TextStyle(
    fontSize: 14,
    height: 1.4,
    letterSpacing: 0.3,
    fontFeatures: const [FontFeature.tabularFigures()],
    color: HollowPalette.inkSoft,
  );

  static TextStyle get caption => TextStyle(
    fontSize: 12,
    height: 1.4,
    letterSpacing: 0.2,
    color: HollowPalette.inkSoft,
  );

  /// Small, spaced, and upper case. Used for a tab label and a field's name, which is the closest
  /// this palette gets to a rule and is enough.
  static TextStyle get label => TextStyle(
    fontSize: 11,
    height: 1.4,
    letterSpacing: 1.6,
    fontWeight: FontWeight.w500,
    color: HollowPalette.inkSoft,
  );
}

/// The Material theme, assembled from the two above.
abstract final class HollowTheme {
  static ThemeData build() {
    // **`ColorScheme.dark` and `ColorScheme.light` differ in more than a flag**, and the constructor
    // has to be chosen by the palette's own brightness rather than hardcoded. Hardcoding `dark` was
    // the first version of the four-theme change, and it did not fail until a light theme was built:
    // `ThemeData` asserts that its `brightness` and its `colorScheme.brightness` agree, so `parchment`
    // threw on the first frame while every widget test in the suite passed -- because none of them
    // built the *Material* theme, they only read colours out of the palette. `shop_themes_test` now
    // builds every theme for this reason.
    final light = HollowPalette.current.brightness == Brightness.light;
    final scheme = light
        ? ColorScheme.light(
            primary: HollowPalette.rose,
            onPrimary: HollowPalette.onAccent,
            secondary: HollowPalette.gold,
            onSecondary: HollowPalette.onAccent,
            surface: HollowPalette.surface,
            onSurface: HollowPalette.ink,
            error: HollowPalette.rose,
            onError: HollowPalette.onAccent,
            outline: HollowPalette.line,
          )
        : ColorScheme.dark(
            primary: HollowPalette.rose,
            onPrimary: HollowPalette.onAccent,
            secondary: HollowPalette.gold,
            onSecondary: HollowPalette.onAccent,
            surface: HollowPalette.surface,
            onSurface: HollowPalette.ink,
            error: HollowPalette.rose,
            onError: HollowPalette.onAccent,
            outline: HollowPalette.line,
          );

    return ThemeData(
      useMaterial3: true,
      // The palette's own, not a hardcoded dark: `parchment` is a light theme, and Material has to be
      // told so that the parts this application does not paint -- a default text colour, a system
      // bar, a text selection -- stop assuming a dark page.
      brightness: HollowPalette.current.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: HollowPalette.ground,
      canvasColor: HollowPalette.ground,
      dividerColor: HollowPalette.line,
      // Section 20.3: soft silhouettes, nothing that snaps. A radius is the
      // cheapest place to say so, and it is applied to everything at once.
      cardTheme: CardThemeData(
        color: HollowPalette.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          side: BorderSide(color: HollowPalette.line),
        ),
      ),
      // **The three button states, defined as a set** -- the second convention from a study of a rhythm game
      // (DESIGN.md 12.9.1). It drew every button in exactly three states (`Button_Normal`, `Button_Press`,
      // `Button_Disable`) in its layout data, its texture names *and* its default widget art, and showed
      // disabled **beside** enabled rather than on its own -- a grey chevron next to a white one.
      //
      // Nothing here was defined before this: the buttons were taking Material's defaults, which means the
      // pressed state was a ripple nobody chose and the disabled state was a grey nobody had looked at. So:
      //
      //   enabled   the action, in gold -- 金＝已选 (the colour decision from 12.9)
      //   pressed   the same shape, visibly darkened, because a press has to be felt and not only detected
      //   disabled  **the same shape in `absent`** -- the palette already has a colour for "not here", which is
      //             why the disabled state is a version of the enabled one rather than a separate look
      //
      // The text colour follows the same rule: a filled button is dark ink on gold, and when it is disabled the
      // ink fades to `inkFaint` -- still legible as a label, plainly not actionable.
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? HollowPalette.absent
                : HollowPalette.gold,
          ),
          // **Both states take `onAccent`, and the disabled one is why.** It used to be `inkFaint` on the
          // `absent` fill; when the two faint colours were raised to clear 4.5:1 against the *surfaces* they
          // became neighbours of each other (measured: 1.0-1.1:1), so a disabled button would have been a
          // label the colour of its own background. The fill is what changes with the state -- gold to grey --
          // and the foreground is the same rule either way.
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => HollowPalette.onAccent,
          ),
          // The pressed overlay is stated rather than inherited: 10% black over gold reads as a press in every
          // one of the four themes, and inheriting Material's would make the same button feel different
          // depending on which theme happened to be in force.
          overlayColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.pressed)
                ? const Color(0x1A000000)
                : Colors.transparent,
          ),
        ),
      ),
      // The secondary action (`不一致`, `返回`) -- the same three states, in the quieter register: rose for the
      // label because refusing is what the rose in this palette means, and `inkFaint` when it is disabled.
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? HollowPalette.inkFaint
                : HollowPalette.rose,
          ),
          overlayColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.pressed)
                ? const Color(0x14FFFFFF)
                : Colors.transparent,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: HollowPalette.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
          borderSide: BorderSide(color: HollowPalette.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
          borderSide: BorderSide(color: HollowPalette.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
          borderSide: BorderSide(color: HollowPalette.rose),
        ),
        labelStyle: HollowType.label,
        hintStyle: TextStyle(color: HollowPalette.inkFaint),
      ),
      textTheme: TextTheme(
        displaySmall: HollowType.display,
        headlineSmall: HollowType.heading,
        titleMedium: HollowType.title,
        bodyMedium: HollowType.body,
        bodySmall: HollowType.caption,
        labelSmall: HollowType.label,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: HollowPalette.surface,
        indicatorColor: HollowPalette.surfaceRaised,
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStateProperty.all(HollowType.label),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 21,
            color: states.contains(WidgetState.selected)
                ? HollowPalette.rose
                : HollowPalette.inkFaint,
          ),
        ),
      ),
      // **`ChipThemeData` is where the reader's complaint was**, and it was invisible in the source: no
      // `chipTheme` existed, so every `ChoiceChip` and `InputChip` in the interface took Material's defaults --
      // and their labels are drawn in `HollowType.body`, which is `ink`. On a *selected* chip, filled with an
      // accent, that put `ink` on `gold`: 1.5:1 in three palettes. The label style is set here rather than at
      // each call site so the rule holds for chips nobody has written yet.
      chipTheme: ChipThemeData(
        backgroundColor: HollowPalette.surfaceRaised,
        selectedColor: HollowPalette.gold,
        labelStyle: HollowType.body.copyWith(color: HollowPalette.ink),
        secondaryLabelStyle: HollowType.body.copyWith(color: HollowPalette.onAccent),
        side: BorderSide(color: HollowPalette.line),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? HollowPalette.onAccent
              : HollowPalette.inkSoft,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? HollowPalette.rose
              : HollowPalette.surfaceRaised,
        ),
        trackOutlineColor: WidgetStateProperty.all(HollowPalette.line),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: HollowPalette.rose,
        linearTrackColor: HollowPalette.line,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: HollowPalette.surfaceRaised,
        contentTextStyle: HollowType.body,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

/// Every string a person reads.
///
/// **One locale, and it is a placeholder.** Section 12.4 settles that display
/// copy is real UTF-8 in the reader's language and is a localization
/// *configuration* rather than a single translation -- and that the layer is
/// deliberately not built yet, because a localization layer written before there
/// are screens to localize is guessing at the strings it is supposed to hold.
/// These are those strings, gathered in one place so that the layer has somewhere
/// to land.
///
/// The voice is the character's, and it is the one thing here that is not
/// placeholder: **spare with words, precise in manner, warm once you are past the
/// surface.** Section 20.5 is explicit that a cheerful chatterbox would be a
/// different character wearing the same face, so the copy is short, it does not
/// exclaim, and it never congratulates anybody for pouring a drink.
abstract final class Copy {
  /// **The public name, and only this one.**
  ///
  /// Section 0 settles it: 空庭 / Hollow Court is what a person ever sees, and
  /// the formal full name is an internal identifier and an easter egg. The first
  /// version of this file put the full name here, which is the one place it must
  /// not be -- **and a test was written asserting the wrong thing too**, so both
  /// were wrong in the same direction and neither caught the other.
  ///
  /// The pair is the name in both scripts, because section 12.4's display rule
  /// wants the reader's language beside the machine-readable one.
  static const appTitle = '空庭';

  /// The name in 日本語, which is the same name rather than a translation of it: 虚ろな庭.
  ///
  /// Kept as a constant beside [appTitle] for the same reason that one exists -- a platform's chrome takes one
  /// string in one language, and Android's launcher label and the task switcher are the places this is read.
  static const appJaTitle = '虚ろな庭';

  static const appSubtitle = 'Hollow Court';

  /// The name as a pair, which is what this pair has always been.
  ///
  /// **The first [CopyLine], and it is not a conversion -- it is the recognition of
  /// something already here.** `app.dart` has built the task-switcher string as
  /// `'${appTitle} · ${appSubtitle}'` since the beginning, because section 0.1 settled
  /// that Android's task switcher shows one string and this is the one it shows. A
  /// pair of constants joined by hand is a dual line with the type missing.
  ///
  /// [appTitle] and [appSubtitle] stay, and they are not redundant: the Android
  /// launcher label is `空庭` alone and the Windows window title is `Hollow Court`
  /// alone, each in the language of the platform chrome around it, and section 0.1
  /// lists both. Those are the single-language forms; this is the paired one.
  ///
  /// Both halves are [TextOrigin.authored] and a test holds them there. Section 14.1
  /// keeps the character in the stable release **as copy**, so a machine line in her
  /// mouth is a different product decision from a machine line on a button -- and the
  /// only way to keep that a decision rather than a drift is to assert it.
  static const appName = CopyLine.withLanguages(
    Translated.authored(appTitle),
    Translated.authored(appSubtitle),
    // **The name follows the reader's script, and that is a correction the owner made on 2026-09-22**: *"根据
    // 语言区不同，空庭使用 Hollow Court 或虚ろな庭"*. It is one name in three writings -- 空庭 / Hollow Court /
    // 虚ろな庭 -- rather than one text repeated, which is what this declaration said an hour before it was
    // corrected. The two Chinese variants stay 空庭 because the characters are the same in traditional.
    also: {'zh-HK': appTitle, 'zh-TW': appTitle, 'ja': appJaTitle},
  );

  /// The mark appended to a machine translation nobody has reviewed.
  ///
  /// A marker rather than a line of copy: it is read *beside* the reader's own
  /// language, so it cannot itself be paired without recursing. It is the only
  /// `String` in this class that is display copy of its own accord rather than
  /// because something confined it to one line.
  static const machineMark = '·机器';

  // ---------------------------------------------------------------------------
  // Two groups, and the split between them is mechanical rather than a matter of
  // taste.
  //
  // **A [CopyLine] is a string displayed as itself, with room to be two lines.**
  // **A `String` is a string that the platform or a composition has already
  // confined to one line.** The second group is not a queue of pending work -- it
  // is the list of places where a pair cannot be drawn at all, and the reason is
  // written beside each one. Section 4.2(a) says the type is the decision; these
  // are the sites where the decision was taken out of this class's hands.
  // ---------------------------------------------------------------------------

  // Section 12.3's four tabs, and **the pair cannot be drawn here**:
  // `NavigationDestination.label` takes a `String`. A bilingual tab label is a
  // different navigation bar rather than a different string -- so section 2.7's
  // "the four tabs are the first place this shows up" turns out to be a finding
  // about the framework, and this is it.
  static const tabStock = CopyLine.withLanguages(
    Translated.authored('酒窖'),
    Translated.authored('Cellar'),
    also: {'zh-HK': '酒窖', 'zh-TW': '酒窖', 'ja': '酒蔵'},
  );
  static const tabBar = CopyLine.withLanguages(
    Translated.authored('吧台'),
    Translated.authored('Bar'),
    also: {'zh-HK': '吧枱', 'zh-TW': '吧檯', 'ja': 'バー'},
  );
  static const tabRecipes = CopyLine.withLanguages(
    Translated.authored('配方'),
    Translated.authored('Recipes'),
    also: {'zh-HK': '配方', 'zh-TW': '配方', 'ja': 'レシピ'},
  );
  static const tabCellar = CopyLine.withLanguages(
    Translated.authored('记录'),
    Translated.authored('Journal'),
    also: {'zh-HK': '記錄', 'zh-TW': '記錄', 'ja': '記録'},
  );

  /// **A fifth tab, and section 12.3 had four.** The reader's language, measuring system and money
  /// were a section at the bottom of 记录 -- the screen a person opens to look at their bottles,
  /// which is the wrong place to find the controls for the application itself. The owner asked for
  /// this tab by name, so 12.3 now names five and `SettingsPage` is the screen.
  ///
  /// A `String` like the other four: `NavigationDestination.label` takes one line, and the English
  /// belongs to section 12.4's `.arb` layer along with the rest.
  /// The fifth tab, added 2026-10-06.
  ///
  /// **A `String` like the other four**, and it says the plural in both languages because the tab lists many
  /// ingredients rather than describing a category -- 原料 is both singular and plural in Chinese, so the Japanese
  /// line is the one that has to choose.
  static const tabIngredients = CopyLine.withLanguages(
    Translated.authored('原料'),
    Translated.authored('Ingredients'),
    also: {'ja': '材料', 'zh-HK': '原料', 'zh-TW': '原料'},
  );

  static const tabSettings = CopyLine.withLanguages(
    Translated.authored('设置'),
    Translated.authored('Settings'),
    also: {'zh-HK': '設置', 'zh-TW': '設定', 'ja': '設定'},
  );

  // Stock.
  static const stockTitle = CopyLine.withLanguages(
    Translated.authored('酒窖'),
    Translated.authored('Cellar'),
    also: {'zh-HK': '酒窖', 'zh-TW': '酒窖', 'ja': '酒蔵'},
  );

  /// **"Still empty" and not "the cellar is empty".** What a person sees here is a
  /// shelf that has been bare since the app was installed, and that is not the same
  /// statement as a cellar somebody has drunk dry.
  static const stockEmpty = CopyLine.withLanguages(
    Translated.authored('这里还是空的。'),
    Translated.authored('Still empty here.'),
    also: {'zh-HK': '這裏還是空的。', 'zh-TW': '這裡還是空的。', 'ja': 'ここはまだ空です。'},
    voices: {
      Voice.heiress: '哼，这里空空如也呢。',
      Voice.heiressJa: 'ふん、ここはまだ空っぽよ。',
    
      Voice.minister:
          'The position at present is that nothing has been recorded here.',},
  );

  static const stockEmptyHint = CopyLine.withLanguages(
    Translated.authored('记下第一瓶酒，配方就知道能为你做什么。'),
    Translated.authored(
      'Record the first bottle, and the recipes will know what they can do for you.',
    ),
    voices: {
      Voice.heiress: '……才、才不是催你。只是记下第一瓶的话，配方就知道该怎么伺候你了。',
      Voice.heiressJa: '……べ、別に急かしてるわけじゃないわ。ただ最初の一本を記録すれば、レシピが何をできるか分かるのよ。',
    
      Voice.minister:
          'It would be a service to record the first bottle; the recipes are then in a position to establish what they may do for you.',},
    also: {'zh-HK': '記下第一瓶酒，配方就知道能為你做什麼。', 'zh-TW': '記下第一瓶酒，配方就知道能為你做什麼。', 'ja': '最初の一本を記録すると、レシピが何ができるかを教えてくれます。'},
  );

  /// Shown twice: as the sheet's heading, and as the button that opens it.
  ///
  /// **The button does not draw the second language, and it says which reason.**
  /// It passes `roomForSecondary: false`, which is [SecondaryOmitted.noRoom] and not
  /// [SecondaryOmitted.bySetting] -- a button is one line by construction, and a dual
  /// label on a button is the noise section 2.4 names. The heading has room, so it
  /// pairs. One string, two sites, two different honest answers.
  static const stockAddBottle = CopyLine.withLanguages(
    Translated.authored('记一瓶'),
    Translated.authored('Add a bottle'),
    also: {'zh-HK': '記一瓶', 'zh-TW': '記一瓶', 'ja': '一本記録する'},
  );

  static const stockName = CopyLine.withLanguages(
    Translated.authored('酒名'),
    Translated.authored('Bottle name'),
    also: {'zh-HK': '酒名', 'zh-TW': '酒名', 'ja': '名前'},
  );

  static const stockNameHint = CopyLine.withLanguages(
    Translated.authored('例如：坦奎瑞金酒'),
    Translated.authored('For example: Tanqueray gin'),
    also: {'zh-HK': '例如：坦奎瑞金酒', 'zh-TW': '例如：坦奎瑞金酒', 'ja': 'この瓶を何と呼ぶか'},
  );

  /// **Single-line, because `InputDecoration.labelText` and `hintText` are
  /// `String`s.** [stockIngredient], [stockIngredientHint] and [stockVolume] are the
  /// same wall as the tab bar one layer down, and their English belongs to section
  /// 12.4's `.arb` layer rather than here.
  static const stockIngredient = '对应配料';
  /// **Not \'leave empty to match by name\', which is what it said first.**
  /// The form requires a selection -- a bottle recorded under a name no recipe
  /// uses is one the shelf can never offer for anything -- so a hint inviting
  /// the field to be left empty contradicted the button beside it.
  static const stockIngredientHint = '搜酒库里的配料';

  /// **The unit left this label, which is the point of the change.** It used to read
  /// `容量（毫升）` -- a millilitre bottle and nothing else -- so a reader who measures in
  /// ounces had to do the conversion before typing. The number is now a box and the unit is
  /// a menu beside it, which is why this is 容量 alone and [stockUnit] is a label of its own.
  static const stockVolume = '容量';

  /// The unit menu's label, beside the number box.
  ///
  /// **A `String` for the same reason [stockVolume] is:** `InputDecoration.labelText` takes
  /// one line by construction. What goes *in* the menu is a unit symbol (`ml`, `oz`) and
  /// those are not translated -- a millilitre is a millilitre everywhere -- so the only
  /// thing here that needs a language is the word for "unit".
  static const stockUnit = '单位';

  /// The price field's label, and **a `String` for the same reason [stockVolume] is**.
  ///
  /// **The unit left this label too, and for a sharper reason than the volume's.** It read
  /// `价格（分）` -- a whole number of fen -- which is one currency's minor unit written into a
  /// label. The same box under JPY means yen and under KWD a thousandth of a dinar, and the
  /// label named neither, so `1200` meant twelve yuan in one slot and one thousand two hundred
  /// yen in another. Now the number is what a person reads (`45.50`) and [stockCurrency] is a
  /// menu beside it; the minor unit is computed from the chosen currency on the way in.
  static const stockPrice = '价格';

  /// The currency menu's label, beside the price box.
  ///
  /// **A `String` for the same reason, and what goes in it is a code**: `CNY`, `JPY`. A
  /// picker showing `¥` would show it twice for two different currencies and nobody could
  /// choose between them -- section 12.4's rule that a person never reads the code is about
  /// what is on the wire, and this is the one place the ambiguity has to be visible.
  static const stockCurrency = '币种';

  /// The purchase date's label.
  ///
  /// **A date is display copy and belongs to `intl`**, which is section 12.4's unbuilt half
  /// along with the `.arb` files. Until then the value beside this label is ISO 8601 --
  /// unambiguous, sortable, and honestly not localised rather than pretending to be. A
  /// hand-rolled `20/09/2026` would be a different day depending on who read it.
  static const stockPurchased = CopyLine.withLanguages(
    Translated.authored('购买日期'),
    Translated.authored('Purchase date'),
    also: {'zh-HK': '購買日期', 'zh-TW': '購買日期', 'ja': '購入日'},
  );

  /// The price history sheet's title.
  static const priceHistory = CopyLine.withLanguages(
    Translated.authored('价格走势'),
    Translated.authored('Price history'), also: {'ja': '価格の推移', 'zh-HK': '價格走勢', 'zh-TW': '價格走勢'});

  /// **States what is true rather than drawing an empty chart as if it were data.**
  /// A bottle entered without a price is one whose price nobody knows yet, and
  /// `PriceChart` draws a bare baseline for exactly this case.
  static const priceNone = CopyLine.withLanguages(
    Translated.authored('还没有记过价格。'),
    Translated.authored('No price recorded yet.'), also: {'ja': 'まだ価格を記録していません。', 'zh-HK': '還沒有記過價格。', 'zh-TW': '還沒有記過價格。'},
      voices: {
        Voice.heiress: '价钱嘛……你还没告诉过我，所以我也不打算瞎猜。',
        Voice.heiressJa: '値段？まだ教えてもらってないんだから、私だって当てずっぽうは言わないわ。',
        Voice.minister:
            'No figure has been supplied, and it would not be appropriate to conjecture one.',
      },);

  static const priceLatest = CopyLine.withLanguages(
    Translated.authored('最近价格'),
    Translated.authored('Latest price'), also: {'ja': '直近の価格', 'zh-HK': '最近價格', 'zh-TW': '最近價格'});

  /// **The pour is named in the number beside this label, not inside the string.** A
  /// translated sentence containing `45 毫升` would be wrong the day `standardPour`
  /// changes, and nothing would say so.
  static const pricePerGlass = CopyLine.withLanguages(
    Translated.authored('每杯成本'),
    Translated.authored('Cost per glass'), also: {'ja': '一杯あたりの原価', 'zh-HK': '每杯成本', 'zh-TW': '每杯成本'});

  /// Empty is allowed and means "not known yet"; anything else has to be a number the chosen
  /// currency can hold. Saying so is not a nicety -- the alternative is a form that silently
  /// drops what somebody typed.
  ///
  /// **It stopped saying 分 when the field stopped being minor units.** It read 「价格要是整数分，
  /// 或者留空。」, which was true of a box that stored what was typed; the box now stores a
  /// currency-scaled amount and accepts a decimal, so a sentence about whole fen would refuse
  /// `45.50` on screen while the form accepted it.
  ///
  /// **It also has to cover an amount the currency cannot hold**, which is a refusal the sentence
  /// above never had: `45.50` is fine in CNY and impossible in JPY, and `0.001` is impossible in
  /// both. One sentence for all of it, because the screen does not need to explain which of the
  /// three reasons applied -- what it needs is to not store a number nobody typed.
  static const stockPriceProblem = CopyLine.withLanguages(
    Translated.authored('价格要是一个正数，而且这个币种能表示出来。'),
    Translated.authored('The price has to be a positive amount this currency can hold.'), also: {'ja': '価格は正の数で、その通貨で表せる必要があります。', 'zh-HK': '價格要是一個正數，而且這個幣種能表示出來。', 'zh-TW': '價格要是一個正數，而且這個幣種能表示出來。'},
    voices: {
      Voice.heiress: '价格得是正数，而且这个币种得表示得出来。含糊的数，本小姐不收。',
      Voice.heiressJa: '価格は正の数であること、そしてその通貨で表せること。曖昧な数は、あたしは受け取らないわ。',
    
      Voice.minister:
          'The price is required to be a positive amount, and one that this currency is able to hold.',},
  );

  /// Section 7's `Total cellar value`, on section 12.3's Cellar tab.
  static const cellarValue = CopyLine.withLanguages(
    Translated.authored('酒窖价值'),
    Translated.authored('Cellar value'), also: {'ja': '酒蔵の評価額', 'zh-HK': '酒窖價值', 'zh-TW': '酒窖價值'});

  /// **Shown when nothing can be valued**, and it is not the same as a value of zero.
  static const cellarNoPrices = CopyLine.withLanguages(
    Translated.authored('还没有一瓶记过价格，所以这个数还算不出来。'),
    Translated.authored('No bottle has a price recorded, so this figure cannot be worked out yet.'), also: {'ja': '価格を記録した瓶がまだ無いので、この数字は出せません。', 'zh-HK': '還沒有一瓶記過價格，所以這個數還算不出來。', 'zh-TW': '還沒有一瓶記過價格，所以這個數還算不出來。'},
    voices: {
      Voice.heiress: '还没有一瓶记过价格——所以这个数还算不出来。先记一瓶，它自然就有了。',
      Voice.heiressJa: '価格を記録した瓶がまだ一本もないの——だからこの数字はまだ出せないわ。一本記録すれば、自然と出てくるのよ。',
    
      Voice.minister:
          'No bottle has had a price recorded against it, and this figure is therefore not one that can yet be arrived at.',},
  );

  /// **Single-line: it is interpolated into a count**, like [stockBottles]. The two
  /// halves are separate constants rather than one template because a `CopyLine` cannot
  /// go inside a string, which is section 12.4's composition wall.
  static const cellarUnpriced = '瓶还没有价格，所以上面的数偏低';

  static const cellarPriced = '瓶已计入';

  /// Section 11's adapter layer, as section 12.3's Cellar tab lists it under "devices".
  static const cellarAdapters = CopyLine.withLanguages(
    Translated.authored('网络适配器'),
    Translated.authored('Network adapters'), also: {'ja': 'ネットワーク連携', 'zh-HK': '網絡適配器', 'zh-TW': '網路介面卡'});

  // ---- Section 12.3's other half of "devices and sync": the sync itself. ----

  /// The heading for the half of this tab that is about two cellars rather than one.
  static const cellarSync = CopyLine.withLanguages(
    Translated.authored('设备同步'),
    Translated.authored('Sync between devices'), also: {'ja': '端末間の同期', 'zh-HK': '設備同步', 'zh-TW': '裝置同步'});

  /// **The instruction, and it names both directions because both are on this screen.** A reader
  /// holding two phones needs to know which one to press what on, and the two actions are
  /// asymmetric in a way the labels alone do not say.
  static const syncHint = CopyLine.withLanguages(
    Translated.authored('把下面这串码给对方看，或者输入对方屏幕上的码。'),
    Translated.authored('Show the code below to the other device, or type the one on its screen.'),
    also: {'zh-HK': '把下面這串碼給對方看，或者輸入對方螢幕上的碼。', 'zh-TW': '把下面這串碼給對方看，或者輸入對方螢幕上的碼。', 'ja': '下のコードを相手に見せるか、相手の画面のコードを入力します。'},
    voices: {
      Voice.heiress: '把下面这串码给对方看，或者输入对方屏幕上的码——两条路，随你。哼，就是别把码念错。',
      Voice.heiressJa: '下のコードを相手に見せるか、相手の画面のコードを入力するの——道は二つ、好きな方でいいわ。ふん、ただ読み間違えないことね。',
    
      Voice.minister:
          'The code below may be shown to the other device, or the one on its screen may be entered; either course will serve.',},
  
  );

  static const syncShowCode = CopyLine.withLanguages(
    Translated.authored('显示配对码'),
    Translated.authored('Show a pairing code'),
    also: {'zh-HK': '顯示配對碼', 'zh-TW': '顯示配對碼', 'ja': 'ペアリングコードを表示'},
  );

  /// **What the hosting side reads while it waits.** A screen that only said "waiting" would leave
  /// the reader wondering whether the other device had been told what to do, so it says what the
  /// other person is supposed to do with the code.
  static const syncWaiting = CopyLine.withLanguages(
    Translated.authored('正在等待对方输入这串码…'),
    Translated.authored('Waiting for the other device to enter this code…'),
    also: {'zh-HK': '正在等待對方輸入這串碼…', 'zh-TW': '正在等待對方輸入這串碼…', 'ja': '相手を待っています…'},
  
      voices: {
        Voice.heiress: '在等那边把码敲进去……你念，我看着。',
        Voice.heiressJa: 'あちらが打ち込むのを待っているわ……読んで、私が見ているから。',
        Voice.minister:
            'We are awaiting the entry of this code on the other device.',
      },);

  static const syncCodeLabel = CopyLine.withLanguages(
    Translated.authored('配对码'),
    Translated.authored('Pairing code'),
    also: {'zh-HK': '配對碼', 'zh-TW': '配對碼', 'ja': '相手のペアリングコード'},
  );

  // ---------------------------------------------------------------- comparing two screens

  /// The two ways of adding a device, as chips.
  static const compareModeCode = CopyLine.withLanguages(
    Translated.authored('用配对码'),
    Translated.authored('With a code'),
    also: {'zh-HK': '用配對碼', 'zh-TW': '用配對碼', 'ja': 'コードで追加'},
  );

  static const compareModeCompare = CopyLine.withLanguages(
    Translated.authored('对数字'),
    Translated.authored('By comparing'),
    also: {'zh-HK': '對數字', 'zh-TW': '對數字', 'ja': '数字を照合'},
  );

  static const compareModeCodeNote = CopyLine.withLanguages(
    Translated.authored('一台显示、另一台输入。只有一边看得见屏幕时，这是唯一可行的。'),
    Translated.authored(
      'One screen shows it, the other types it. The only way that works when you cannot see both screens.',
    ),
    also: {
      'zh-HK': '一台顯示、另一台輸入。只有一邊看得見螢幕時，這是唯一可行的。',
      'zh-TW': '一台顯示、另一台輸入。只有一邊看得見螢幕時，這是唯一可行的。',
      'ja': '一方が表示し、もう一方が入力します。両方の画面が見えないときは、これだけが使えます。',
    },
    voices: {
      Voice.heiress: '一台显示、另一台输入——只有一边看得见屏幕的时候，这是唯一走得通的办法。本小姐可没别的招给你。',
      Voice.heiressJa: '片方で表示、もう片方で入力——画面が一つしか見えないときは、これが唯一通る道よ。あたしに他の手はないんだから。',
    
      Voice.minister:
          'One screen displays it and the other enters it -- the only arrangement that commends itself when both screens cannot be seen at once.',},
  
  );

  static const compareModeCompareNote = CopyLine.withLanguages(
    Translated.authored('两台都显示同一串六位数字，你只要看一眼。两块屏幕要能同时看见。'),
    Translated.authored(
      'Both screens show the same six digits and you only have to look. Needs both screens in view at once.',
    ),
    also: {
      'zh-HK': '兩台都顯示同一串六位數字，你只要看一眼。兩塊螢幕要能同時看見。',
      'zh-TW': '兩台都顯示同一串六位數字，你只要看一眼。兩塊螢幕要能同時看見。',
      'ja': '両方の画面に同じ六桁が出ます。見比べるだけです。ただし二つの画面が同時に見える必要があります。',
    },
    voices: {
      Voice.heiress: '哼，两台各显示同一串六位数字——看一眼就行。不过话先说在前头：两块屏幕得同时看得见，本小姐可没法替你把它们并排放好。',
      Voice.heiressJa: 'ふん、二台とも同じ六桁が出るわ——見比べるだけよ。ただし先に言っておくの：二つの画面が同時に見えること。あたしが代わりに並べてあげるわけにはいかないんだから。',
    
      Voice.minister:
          'Both screens will show the same six digits, and no more than a glance is required of you. The two screens must, however, be in view at the same time.',},
  
  );

  static const compareTitle = CopyLine.withLanguages(
    Translated.authored('对一下两边的数字'),
    Translated.authored('Compare the two screens'),
    also: {'zh-HK': '對一下兩邊的數字', 'zh-TW': '對一下兩邊的數字', 'ja': '二つの画面の数字を照合してください'},
  );

  static const compareNote = CopyLine.withLanguages(
    Translated.authored('两台设备各自算出这串数字，只有这次握手相同才会一致。一边一样、一边不一样，就说明中间有别人在转接。'),
    Translated.authored(
      'Each device worked these digits out from this handshake, so they agree only if nobody is in the '
      'middle. If the two screens differ, somebody is relaying the connection.',
    ),
    also: {
      'zh-HK': '兩台裝置各自算出這串數字，只有這次握手相同才會一致。一邊一樣、一邊不一樣，就說明中間有別人在轉接。',
      'zh-TW': '兩台裝置各自算出這串數字，只有這次握手相同才會一致。一邊一樣、一邊不一樣，就說明中間有別人在轉接。',
      'ja': '二台が今回のハンドシェイクから同じ数字を導きます。間に誰もいなければ一致します。片方だけ違えば、誰かが中継しています。',
    },
    voices: {
      Voice.heiress: '两台各自算出这串数字——握手相同才会一致。一边一样、一边不一样？那就是中间有人插了手，别信。',
      Voice.heiressJa: '二台がそれぞれこの数字を出すの——同じ握手なら一致する。片方だけ違う？なら間に誰かが割り込んでるわ、信じないで。',
      Voice.minister:
          'Each machine derives the number from this handshake, and agreement is the evidence of '
          'an uninterrupted conversation. Should one side differ, the difference is itself the '
          'finding: somebody is relaying between you.',
    },
  );

  static const compareAgree = CopyLine.withLanguages(
    Translated.authored('一致'),
    Translated.authored('They match'),
    also: {'zh-HK': '一致', 'zh-TW': '一致', 'ja': '一致する'},
  );

  static const compareRefuse = CopyLine.withLanguages(
    Translated.authored('不一致'),
    Translated.authored('They differ'),
    also: {'zh-HK': '不一致', 'zh-TW': '不一致', 'ja': '一致しない'},
  );

  /// Said under the buttons, because the second one is final.
  static const compareRefuseNote = CopyLine.withLanguages(
    Translated.authored('不一致会直接放弃这次同步，不会重试——六位数字只够用一次。'),
    Translated.authored(
      'Differing gives the sync up rather than retrying: six digits is enough exactly once.',
    ),
    also: {
      'zh-HK': '不一致會直接放棄這次同步，不會重試——六位數字只夠用一次。',
      'zh-TW': '不一致會直接放棄這次同步，不會重試——六位數字只夠用一次。',
      'ja': '一致しなければこの同期はあきらめます。やり直しはしません——六桁は一度きりで足りる数字です。',
    },
    voices: {
      Voice.heiress: '两台指纹一样，握手却被拒了——这不是网络的事，是中间有人在转接。别继续。哼，本小姐说到这儿就够了。',
      Voice.heiressJa: '二台の指紋が同じなのに、ハンドシェイクは拒まれた——ネットワークの問題じゃないわ、間に誰かが割り込んでいるの。続けないで。ふん、あたしはここまで言えば十分よ。',
    
      Voice.minister:
          'A difference is taken as the sync being given up rather than retried; six digits serve exactly once, and no more.',},
  
  );

  // ---------------------------------------------------------------- the cable

  static const usbTitle = CopyLine.withLanguages(
    Translated.authored('通过 USB 直连（ADB 转发）'),
    Translated.authored('Direct over USB (ADB forwarding)'),
    also: {'zh-HK': '透過 USB 直連（ADB 轉發）', 'zh-TW': '透過 USB 直連（ADB 轉送）', 'ja': 'USBで直接つなぐ（ADBフォワード）'},
    voices: {
      Voice.heiress: '通过 USB 直连（ADB 转发）——线插好，本小姐替你把话说进去。',
      Voice.heiressJa: 'USB で直結（ADB 転送）——線をつないでおきなさい、あたしが代わりに話を通してあげる。',
    
      Voice.minister:
          'Direct connection by USB (ADB forwarding).',},
  
  );

  /// The first button: not "forward" but "look", because nothing about the cable is known yet.
  static const usbCheck = CopyLine.withLanguages(
    Translated.authored('检查 USB 连接'),
    Translated.authored('Check for a cable'),
    also: {'zh-HK': '檢查 USB 連接', 'zh-TW': '檢查 USB 連線', 'ja': 'ケーブルを確認'},
  
      voices: {
        Voice.heiress: 'USB 有没有接上，我看一眼。',
        Voice.heiressJa: 'USB が繋がっているか、見てくるわ。',
        Voice.minister:
            'Check the USB connection.',
      },);

  static const usbForward = CopyLine.withLanguages(
    Translated.authored('建立转发'),
    Translated.authored('Set up the forward'),
    also: {'zh-HK': '建立轉發', 'zh-TW': '建立轉送', 'ja': 'フォワードを設定'},
  );

  /// Shown after the forward exists: the address is what the other side needs.
  static const usbReady = CopyLine.withLanguages(
    Translated.authored('转发已建立。这串地址就是对方的连接地址，数据只在数据线上走：'),
    Translated.authored(
      'The forward is up. This is the address the other side connects to, and the datagrams stay on the '
      'cable:',
    ),
    also: {
      'zh-HK': '轉發已建立。這串地址就是對方的連接地址，資料只在資料線上走：',
      'zh-TW': '轉送已建立。這串地址就是對方的連接地址，資料只在資料線上走：',
      'ja': 'フォワードを設定しました。これが相手が接続するアドレスで、データはケーブル上だけを流れます：',
    },
    voices: {
      Voice.heiress: '转发已经架好了——这串地址就是对方的连接地址，数据从你这边转过去。地址别抄错，抄错了本小姐可不负责重来。',
      Voice.heiressJa: '転送はもう立っているわ——このアドレスが相手の接続先、データはあなたの側から転がっていくの。書き写し間違えないこと、間違えてもやり直しは手伝わないわよ。',
    
      Voice.minister:
          'The forward is established. This is the address to which the other side connects, and the datagrams are confined to the cable:',},
  
  );

  // ---------------------------------------------------------------- carrying a cellar on a stick

  static const packTitle = CopyLine.withLanguages(
    Translated.authored('U 盘搬运（.courtpack）'),
    Translated.authored('Carry it on a stick (.courtpack)'),
    also: {'zh-HK': 'U 盤搬運（.courtpack）', 'zh-TW': 'U 盤搬運（.courtpack）', 'ja': 'USBメモリで運ぶ（.courtpack）'},
    voices: {
      Voice.heiress: 'U 盘搬运（.courtpack）——没有网也行，这是那条走得通的路。',
      Voice.heiressJa: 'USB メモリでの運搬（.courtpack）——網が無くてもいいの、これが通る道よ。',
    
      Voice.minister:
          'Carriage by USB drive (`.courtpack`).',},
  
  );

  static const packNote = CopyLine.withLanguages(
    Translated.authored('导出成一个文件，拷到另一台设备再导入。没有网络也能用——这也是它在客户端隔离的网络里唯一可行的那条路。它不是备份，也不被信任：导入永远是并入你自己的日志，导两次不会多出东西。'),
    Translated.authored(
      'Export to a file, copy it to the other device, import it there. It needs no network at all -- which '
      'makes it the only carrier that works where client isolation does. It is not a backup and it is not '
      'trusted: an import always merges into your own log, so importing twice adds nothing.',
    ),
    also: {
      'zh-HK': '匯出成一個檔案，拷到另一台裝置再匯入。沒有網路也能用——這也是它在客戶端隔離的網路裡唯一可行的那條路。它不是備份，也不被信任：匯入永遠是併入你自己的日誌，匯兩次不會多出東西。',
      'zh-TW': '匯出成一個檔案，拷到另一台裝置再匯入。沒有網路也能用——這也是它在客戶端隔離的網路裡唯一可行的那條路。它不是備份，也不被信任：匯入永遠是併入你自己的日誌，匯兩次不會多出東西。',
      'ja': 'ファイルに書き出し、もう一方の端末にコピーして取り込みます。ネットワークは不要——クライアント分離のあるネットワークで唯一使える手段です。バックアップではなく、信頼もされません。取り込みは常に自分のログへの併合なので、二度取り込んでも増えません。',
    },
    voices: {
      Voice.heiress: '导出一个文件，拷到另一台再导进去——没有网也行，这也是客户端隔离的网里唯一走得通的路。但它不是备份，也不必信它：导入永远是并进你自己的日志，导两次也不会多出东西。',
      Voice.heiressJa:
          'ファイルに書き出して、もう一台にコピーして取り込むの——網がなくても使える。クライアント分離の網では、それが唯一通る道よ。でもバックアップではないし、信じる必要もないの。取り込みはいつも自分のログに併合されるだけだから、二度やっても増えないわ。',
      Voice.minister:
          'Written to a single file and carried to the other machine. It functions without a '
          'network, which is the only reason it works at all where clients are isolated. It is '
          'not a backup and is not to be trusted as one: an import is always merged into your '
          'own log, and performing it twice adds nothing.',
    },
  );

  static const packExport = CopyLine.withLanguages(
    Translated.authored('导出整个酒窖'),
    Translated.authored('Export the whole cellar'),
    also: {'zh-HK': '匯出整個酒窖', 'zh-TW': '匯出整個酒窖', 'ja': '酒蔵全体を書き出す'},
  );

  static const packWritten = CopyLine.withLanguages(
    Translated.authored('写在这里：'),
    Translated.authored('Written to: '),
    also: {'zh-HK': '寫在這裡：', 'zh-TW': '寫在這裡：', 'ja': '書き出し先：'},
  );

  static const packFound = CopyLine.withLanguages(
    Translated.authored('这个目录里的搬运包'),
    Translated.authored('Packs in this directory'),
    also: {'zh-HK': '這個目錄裡的搬運包', 'zh-TW': '這個目錄裡的搬運包', 'ja': 'このフォルダ内のパック'},
  );

  static const packNone = CopyLine.withLanguages(
    Translated.authored('还没有。把一个 .courtpack 拷进上面那个目录，它就会出现在这里。'),
    Translated.authored(
      'None yet. Copy a .courtpack into the directory above and it appears here.',
    ),
    also: {
      'zh-HK': '還沒有。把一個 .courtpack 拷進上面那個目錄，它就會出現在這裡。',
      'zh-TW': '還沒有。把一個 .courtpack 拷進上面那個目錄，它就會出現在這裡。',
      'ja': 'まだありません。上のフォルダに .courtpack をコピーすると、ここに現れます。',
    },
    voices: {
      Voice.heiress: '哼，还没有呢。把一个 .courtpack 拷进上面那个目录——它自己就会出现在这里，不用你催。',
      Voice.heiressJa: 'ふん、まだ何もないわ。上のフォルダに .courtpack をコピーして——あとは勝手にここへ現れるの。急かさなくていいわよ。',
      Voice.minister:
          'At present, nothing. Place a `.courtpack` in the directory above and it will present '
          'itself here; the arrangement requires no further instruction from you.',
    },
  );

  static const packImport = CopyLine.withLanguages(
    Translated.authored('导入'),
    Translated.authored('Import'),
    also: {'zh-HK': '匯入', 'zh-TW': '匯入', 'ja': '取り込む'},
  );

  /// The label before "applied / offered", which is the pair worth showing: they differ when the pack held
  /// events this log already had, and that is a success rather than a no-op.
  static const packApplied = CopyLine.withLanguages(
    Translated.authored('并入的新事件：'),
    Translated.authored('New events applied: '),
    also: {'zh-HK': '併入的新事件：', 'zh-TW': '併入的新事件：', 'ja': '新しく併合したイベント：'},
  );

  /// The four link modes, named on the screen so a reader knows what they are about to sync over.
  static const syncLinkWired = CopyLine.withLanguages(
    Translated.authored('有线网络'),
    Translated.authored('Wired'),
    also: {'zh-HK': '有線網路', 'zh-TW': '有線網路', 'ja': '有線LAN'},
  );

  static const syncLinkWireless = CopyLine.withLanguages(
    Translated.authored('无线网络'),
    Translated.authored('Wireless'),
    also: {'zh-HK': '無線網路', 'zh-TW': '無線網路', 'ja': '無線LAN'},
  );

  static const syncLinkUsb = CopyLine.withLanguages(
    Translated.authored('USB 连接'),
    Translated.authored('USB'),
    also: {'zh-HK': 'USB 連接', 'zh-TW': 'USB 連線', 'ja': 'USB接続'},
  );

  /// The mode worth naming: it works across two networks that cannot see each other.
  static const syncLinkTunnel = CopyLine.withLanguages(
    Translated.authored('隧道（VPN 网桥）'),
    Translated.authored('Tunnel (VPN bridge)'),
    also: {'zh-HK': '隧道（VPN 網橋）', 'zh-TW': '隧道（VPN 網橋）', 'ja': 'トンネル（VPNブリッジ）'},
  );

  static const syncLinkUnknown = CopyLine.withLanguages(
    Translated.authored('这条链路无法归类'),
    Translated.authored('Unclassified link'),
    also: {'zh-HK': '這條鏈路無法歸類', 'zh-TW': '這條鏈路無法歸類', 'ja': '分類できないリンク'},
  );

  /// **The unrestricted choice, which is a choice and not the absence of one.**
  ///
  /// Every build before this field existed behaved this way, so a reader who has never opened this section is on it --
  /// and naming it is what makes the three restrictions beside it read as three restrictions rather than as the only
  /// options.
  /// The heading and the note over the five choices.
  static const syncLinkModeTitle = CopyLine.withLanguages(
    Translated.authored('同步走哪条链路'),
    Translated.authored('Which link sync may use'),
    also: {'zh-HK': '同步走哪條鏈路', 'zh-TW': '同步走哪條鏈路', 'ja': '同期はどの回線を使うか'},
  );

  /// **What a mode is, in one sentence**, because it is not what a reader will assume.
  ///
  /// A reader who has met a "preferred network" setting expects the choice to be a preference: try this one, fall back to
  /// the others. This one does not fall back, and the difference is the whole reason it exists -- so it is said here rather
  /// than discovered on a laptop with the cable unplugged.
  static const syncLinkModeNote = CopyLine.withLanguages(
    Translated.authored('选了哪一条，就只走哪一条 —— 不会回落到别的链路。'),
    Translated.authored('The one you choose is the only one used; it does not fall back to another.'),
    also: {
      'zh-HK': '選了哪一條，就只走哪一條 —— 不會回落到別的鏈路。',
      'zh-TW': '選了哪一條，就只走哪一條 —— 不會回落到別的鏈路。',
      'ja': '選んだ回線だけを使います。ほかへは回りません。',
    },
  
      voices: {
        Voice.heiress: '你挑哪一条，我就只走那一条。别的链路我不会替你偷偷试。',
        Voice.heiressJa: '選んだ一本だけを使うのよ。他に落ちるなんてことはないわ。',
        Voice.minister:
            'The link selected is the only link used; there is no fallback to another.',
      },);

  /// **The one mode whose consequence is not obvious**, said only while it is chosen.
  ///
  /// A tunnel is the only kind of link that can reach a device which is not on this network, and the only one where
  /// discovery cannot be relied on: a broadcast does not cross a router, so two devices on a tunnel find each other by
  /// pairing code or by having met before. A reader who chooses it and sees an empty nearby list has to be told that,
  /// rather than concluding that nobody is there.
  static const syncLinkTunnelNote = CopyLine.withLanguages(
    Translated.authored('隧道里广播过不去，所以两边要靠配对码、或者以前见过面。附近的设备列表会是空的。'),
    Translated.authored('A broadcast does not cross a tunnel, so the two ends meet by pairing code or by having met before. The nearby list will be empty.'),
    also: {
      'zh-HK': '隧道裡廣播過不去，所以兩邊要靠配對碼、或者以前見過面。附近的裝置列表會是空的。',
      'zh-TW': '隧道裡廣播過不去，所以兩邊要靠配對碼、或者以前見過面。附近的裝置列表會是空的。',
      'ja': 'トンネルはブロードキャストが通りません。ペアリングコードか、以前に会った相手だけです。近くの端末一覧は空になります。',
    },
  
      voices: {
        Voice.heiress: '隧道挡得住广播。两边想见上，只能靠配对码，或者你我本来就认得。所以附近那栏，你不会看到任何东西。',
        Voice.heiressJa: 'トンネルはブロードキャストを通さないの。だから両端はペアリングコードか、以前に会ったという事実だけが頼りよ。近くの機器の一覧は空になるわ。',
        Voice.minister:
            'A broadcast will not cross a tunnel; the two ends must therefore rely on a pairing code or on a previous acquaintance. The list of nearby devices will be empty.',
      },);

  static const syncLinkAny = CopyLine.withLanguages(
    Translated.authored('不限，哪条链路都可以'),
    Translated.authored('Any link'),
    also: {'zh-HK': '不限，哪條鏈路都可以', 'zh-TW': '不限，哪條鏈路都可以', 'ja': 'どの回線でもよい'},
  
      voices: {
        Voice.heiress: '哪条链路都行，我不挑。',
        Voice.heiressJa: 'どの経路でも構わないわ。',
        Voice.minister:
            'No restriction; any link will serve.',
      },);

  /// **Said when the chosen mode has nothing to work with, and it names the mode.**
  ///
  /// `link_mode.dart`'s own comment says the consequence of a mode has to be said on screen rather than there: **a mode
  /// with nothing in it finds nothing and syncs nothing**, and a reader who chose 有线 on a laptop with no cable is told
  /// that instead of being quietly served by the radio. That is this line's whole job.
  ///
  /// A `String` rather than a `CopyLine` because it is interpolated, which is the same reason `cellarUnpriced` is one.
  static String syncLinkRestricted(String mode) => '这一版只走「$mode」，而现在没有可用的这条链路。';

  static const syncLinkNone = CopyLine.withLanguages(
    Translated.authored('这台机器现在没有局域网地址。'),
    Translated.authored('This machine has no LAN address right now.'),
    also: {'zh-HK': '這台機器現在沒有區域網地址。', 'zh-TW': '這台機器現在沒有區域網地址。', 'ja': 'この端末には今、LANアドレスがありません。'},
  
      voices: {
        Voice.heiress: '这台机器现在没有局域网地址。先接上网，我再替你找。',
        Voice.heiressJa: 'この機械、今は LAN の住所も持っていないわ。先に繋いでちょうだい。探すのは私がやるから。',
        Voice.minister:
            'This machine is not, at present, in possession of a LAN address.',
      },);

  /// The heading over the devices that can be heard right now.
  static const syncNearbyTitle = CopyLine.withLanguages(
    Translated.authored('附近的设备'),
    Translated.authored('Nearby devices'),
    also: {'zh-HK': '附近的裝置', 'zh-TW': '附近的裝置', 'ja': '近くの端末'},
  );

  /// What the list is, and what it is not: an announcement is a claim rather than an identity.
  static const syncNearbyNote = CopyLine.withLanguages(
    Translated.authored('在同一个局域网里、且此刻正在宣告自己的设备。名字只是自称，真正作数的是指纹与握手。'),
    Translated.authored(
      'Devices on this network that are announcing themselves right now. A name is only a claim; the '
      'fingerprint and the handshake are what count.',
    ),
    also: {
      'zh-HK': '在同一個區域網裡、且此刻正在宣告自己的裝置。名字只是自稱，真正作數的是指紋與握手。',
      'zh-TW': '在同一個區域網裡、且此刻正在宣告自己的裝置。名字只是自稱，真正作數的是指紋與握手。',
      'ja': '同じネットワーク上で、いま自分を名乗っている端末。名前は自称にすぎず、効くのは指紋とハンドシェイクです。',
    },
    voices: {
      Voice.heiress: '同一个网里、此刻正在报上名号的设备——名字只是自称，算数的是指纹与握手。名字看看就好。',
      Voice.heiressJa: '同じ網の中で、いま名乗っている端末——名前は自称にすぎないの。効くのは指紋とハンドシェイクよ。名前は眺めるだけにしておいて。',
      Voice.minister:
          'Machines on this network that are, at this moment, announcing themselves. A name is '
          'an assertion and nothing more; what counts is the fingerprint and the handshake that '
          'follows it.',
    },
  );

  /// The mark on a device this machine has never met.
  static const syncNearbyNew = CopyLine.withLanguages(
    Translated.authored('新设备'),
    Translated.authored('new'),
    also: {'zh-HK': '新裝置', 'zh-TW': '新裝置', 'ja': '新しい端末'},
  );

  // ---- §10.3.2: what a tap carries, and what a host says about its own door. ----

  /// **The one step between wanting that device and being connected to it** (the owner, 2026-09-23).
  ///
  /// The line below carries no apostrophe and no quotation mark on purpose: `translation_coverage_test.dart`
  /// finds the definitions by counting brackets and skipping quoted runs, so an odd quote in a comment shifts
  /// everything after it and the whole file stops being readable to that test.
  ///
  /// The box exists because a mis-tap costs somebody a dialog on *another* screen: the row in the list carries
  /// a name and six characters of fingerprint, and the confirmation carries everything the announcement knows,
  /// with the fingerprint as the one thing a device cannot simply claim about itself.
  static const syncConnectTitle = CopyLine.withLanguages(
    Translated.authored('连这台设备？'),
    Translated.authored('Connect to this device?'),
    also: {'zh-HK': '連這台裝置？', 'zh-TW': '連這台裝置？', 'ja': 'この端末に接続しますか？'},
  );

  static const syncConnectNote = CopyLine.withLanguages(
    Translated.authored('名字只是自称。指纹是它唯一没法随口说出来的东西——看清了再按。'),
    Translated.authored(
      'A name is only a claim. The fingerprint is the one thing the device cannot invent about itself, so '
      'read it before you press.',
    ),
    also: {
      'zh-HK': '名字只是自稱。指紋是它唯一沒法隨口說出來的東西——看清了再按。',
      'zh-TW': '名字只是自稱。指紋是它唯一沒法隨口說出來的東西——看清了再按。',
      'ja': '名前は自称にすぎません。指紋だけは勝手に名乗れないものです——確かめてから押してください。',
    },
    voices: {
      Voice.heiress: '名字只是自称——指纹才是它唯一没法随口说出来的东西。核对指纹，不是核对名字，别搞错了。',
      Voice.heiressJa: '名前は自称にすぎないの——指紋こそ、口から出任せにできない唯一のものよ。見るべきは指紋、名前じゃないわ。',
    
      Voice.minister:
          'A name is a claim and nothing more. The fingerprint is the one particular in which a device cannot be inventive about itself, and we would be grateful if you would read it before pressing.',},
  
  );

  static const syncConnectNameLabel = CopyLine.withLanguages(
    Translated.authored('名字'),
    Translated.authored('Name'),
    also: {'zh-HK': '名字', 'zh-TW': '名字', 'ja': '名前'},
  );

  static const syncConnectAddressLabel = CopyLine.withLanguages(
    Translated.authored('地址'),
    Translated.authored('Address'),
    also: {'zh-HK': '地址', 'zh-TW': '地址', 'ja': 'アドレス'},
  );

  static const syncConnectFingerprintLabel = CopyLine.withLanguages(
    Translated.authored('指纹'),
    Translated.authored('Fingerprint'),
    also: {'zh-HK': '指紋', 'zh-TW': '指紋', 'ja': '指紋'},
  );

  static const syncConnectRememberedLabel = CopyLine.withLanguages(
    Translated.authored('是否已记住'),
    Translated.authored('Already known'),
    also: {'zh-HK': '是否已記住', 'zh-TW': '是否已記住', 'ja': '記憶済みか'},
  );

  /// The value of the row above, when the fingerprint is one this machine has stored a key for.
  static const syncConnectRememberedYes = CopyLine.withLanguages(
    Translated.authored('已记住——上次见面学过它的密钥'),
    Translated.authored('yes -- its key was learned at an earlier meeting'),
    also: {
      'zh-HK': '已記住——上次見面學過它的密鑰',
      'zh-TW': '已記住——上次見面學過它的金鑰',
      'ja': '記憶済み——前回の対面で鍵を学習しています',
    },
    voices: {
      Voice.heiress: '已记住——上次见面学过它的密钥，这次不用再对码。',
      Voice.heiressJa: '記憶済みよ——前回会ったときに鍵を覚えたから、今度はコードを合わせなくていいの。',
    
      Voice.minister:
          'Remembered: the key was learned at the previous meeting.',},
  
  );

  static const syncConnectRememberedNo = CopyLine.withLanguages(
    Translated.authored('陌生——这台机器没见过它'),
    Translated.authored('no -- this machine has never met it'),
    also: {
      'zh-HK': '陌生——這台機器沒見過它',
      'zh-TW': '陌生——這台機器沒見過它',
      'ja': '初対面——この端末は会ったことがありません',
    },
  
      voices: {
        Voice.heiress: '没见过。这台机器不认识它。',
        Voice.heiressJa: '初対面よ。この機械は相手を知らないわ。',
        Voice.minister:
            'Unknown -- no prior acquaintance with this machine is recorded.',
      },);

  static const syncConnectNextLabel = CopyLine.withLanguages(
    Translated.authored('按下之后'),
    Translated.authored('What happens next'),
    also: {'zh-HK': '按下之後', 'zh-TW': '按下之後', 'ja': '押したあと'},
  );

  static const syncConnectNextStraight = CopyLine.withLanguages(
    Translated.authored('直接用上次学到的密钥同步，不用再对数字。'),
    Translated.authored('It syncs with the key learned last time; there are no digits to compare.'),
    also: {
      'zh-HK': '直接用上次學到的密鑰同步，不用再對數字。',
      'zh-TW': '直接用上次學到的金鑰同步，不用再對數字。',
      'ja': '前回学んだ鍵でそのまま同期します。数字の照合はありません。',
    },
    voices: {
      Voice.heiress: '直接用上次学到的密钥同步——不用再对数字。省下的那点功夫，你自己看着用。',
      Voice.heiressJa: '前回覚えた鍵でそのまま同期するの——数字を照合する必要はないわ。省いた手間は、好きに使いなさい。',
    
      Voice.minister:
          'The sync proceeds on the key learned on the previous occasion; there are no digits requiring comparison.',},
  
  );

  static const syncConnectNextCompare = CopyLine.withLanguages(
    Translated.authored('两台设备各显示六位数字，对上了才开始同步。'),
    Translated.authored('Both devices show six digits, and the sync starts only if they match.'),
    also: {
      'zh-HK': '兩台裝置各顯示六位數字，對上了才開始同步。',
      'zh-TW': '兩台裝置各顯示六位數字，對上了才開始同步。',
      'ja': '両方の端末が六桁の数字を出し、一致したときだけ同期が始まります。',
    },
    voices: {
      Voice.heiress: '两台各显示六位数字——对上了才开始同步。对不上就别往下走，没有例外。',
      Voice.heiressJa: '二台がそれぞれ六桁の数字を出すの——一致してはじめて同期が始まるわ。合わなければ先へ進まないこと、例外はないのよ。',
    
      Voice.minister:
          'Both devices will show six digits, and the sync commences only in the event that they agree.',},
  
  );

  static const syncConnectConfirm = CopyLine.withLanguages(
    Translated.authored('连接'),
    Translated.authored('Connect'),
    also: {'zh-HK': '連接', 'zh-TW': '連線', 'ja': '接続する'},
  );

  static const syncConnectCancel = CopyLine.withLanguages(
    Translated.authored('取消'),
    Translated.authored('Cancel'),
    also: {'zh-HK': '取消', 'zh-TW': '取消', 'ja': 'やめる'},
  );

  /// **The same promise as being discoverable, said in the other direction** (§10.3.2 ②).
  ///
  /// A device is announced *and* listening while this screen is open; a reader who can see that much can tell
  /// why a neighbour is or is not reaching them, which is the sentence the timing-out phone could never say.
  static const syncReachable = CopyLine.withLanguages(
    Translated.authored('附近的设备现在可以点到这台机器'),
    Translated.authored('Nearby devices can tap this machine right now'),
    also: {
      'zh-HK': '附近的裝置現在可以點到這台機器',
      'zh-TW': '附近的裝置現在可以點到這台機器',
      'ja': '近くの端末から今この端末を叩けます',
    },
    voices: {
      Voice.heiress: '附近的设备现在可以点到这台机器——想连就连，本小姐不拦。',
      Voice.heiressJa: '近くの端末から今この機械に届くわ——つなぎたければつなぎなさい、あたしは止めないの。',
    
      Voice.minister:
          'This machine is presently reachable from nearby devices.',},
  
  );

  static const firewallTitle = CopyLine.withLanguages(
    Translated.authored('入站自查'),
    Translated.authored("This machine's inbound door"),
    also: {'zh-HK': '入站自查', 'zh-TW': '入站自查', 'ja': '受信の自己点検'},
  );

  /// Why the host has to speak, in the words of the failure that put this row here.
  static const firewallNote = CopyLine.withLanguages(
    Translated.authored('真正被挡住的机器往往一言不发，对端只看到一次超时。所以这里由宿主把话说出来。'),
    Translated.authored(
      'The machine with the problem usually says nothing, and the other end only sees a timeout. So this is '
      'the host saying it.',
    ),
    also: {
      'zh-HK': '真正被擋住的機器往往一言不發，對端只看到一次超時。所以這裡由宿主把話說出來。',
      'zh-TW': '真正被擋住的機器往往一言不發，對端只看到一次逾時。所以這裡由主機把話說出來。',
      'ja': '本当に止められている側は何も言わないので、相手にはタイムアウトだけが見えます。だからここで宿主が言います。',
    },
    voices: {
      Voice.heiress: '真被挡住的机器往往一声不响——对面只看到一次超时，问也问不出来。所以这里由宿主替它开口。',
      Voice.heiressJa: '本当に止められている端末はたいてい何も言わないの——相手にはタイムアウトが一度見えるだけ。だからここはホストが代わりに口を開くのよ。',
      Voice.minister:
          'A machine that is genuinely being blocked tends to say nothing at all, and the other '
          'side observes only a timeout. It falls to the host, therefore, to speak on its behalf '
          '-- which is what this is.',
    },
  );

  static const firewallCheck = CopyLine.withLanguages(
    Translated.authored('检查这台机器能不能被连上'),
    Translated.authored('Check whether this machine can be reached'),
    also: {
      'zh-HK': '檢查這台機器能不能被連上',
      'zh-TW': '檢查這台機器能不能被連上',
      'ja': 'この端末に届くか確かめる',
    },
  
      voices: {
        Voice.heiress: '看看外面连不连得进这台机器。',
        Voice.heiressJa: 'この機械に外から届くかどうか、確かめてみるわ。',
        Voice.minister:
            'Establish whether this machine can be reached.',
      },);

  static const firewallChecking = CopyLine.withLanguages(
    Translated.authored('正在检查…'),
    Translated.authored('Checking…'),
    also: {'zh-HK': '正在檢查…', 'zh-TW': '正在檢查…', 'ja': '確認中…'},
  );

  static const firewallCopy = CopyLine.withLanguages(
    Translated.authored('复制放行命令'),
    Translated.authored('Copy the allow command'),
    also: {'zh-HK': '複製放行命令', 'zh-TW': '複製放行命令', 'ja': '許可コマンドをコピー'},
  );

  static const firewallCopied = CopyLine.withLanguages(
    Translated.authored('已复制'),
    Translated.authored('Copied'),
    also: {'zh-HK': '已複製', 'zh-TW': '已複製', 'ja': 'コピーしました'},
  );

  /// The one-sentence conclusions. **One sentence each, because that is the requirement** (§10.3.2 ②): a reader
  /// has to be able to act on the answer without reading a report.
  static const firewallVerdictOpen = CopyLine.withLanguages(
    Translated.authored('一句话结论：这台机器现在能被局域网里的设备连上。'),
    Translated.authored('In one sentence: this machine can be reached from the network right now.'),
    also: {
      'zh-HK': '一句話結論：這台機器現在能被區域網裡的裝置連上。',
      'zh-TW': '一句話結論：這台機器現在能被區域網裡的裝置連上。',
      'ja': '一言で：この端末には今、同じネットワークから届きます。',
    },
    voices: {
      Voice.heiress: '哼。门是开着的——本小姐可没把谁拦在外面。局域网里的谁，现在都连得上。',
      Voice.heiressJa: 'ふん。門は開いてるわ——あたしが誰かを締め出したりしてないもの。同じネットワークの誰でも、今なら届くわ。',
      Voice.minister:
          'The position is as follows. The machine may be reached from the network at this moment; no '
          'obstruction of ours stands in the way, and we would prefer it understood that none was intended.',
    },
  );

  static const firewallVerdictNoRule = CopyLine.withLanguages(
    Translated.authored('一句话结论：入站被防火墙挡住了——没有一条入站规则覆盖这个程序。'),
    Translated.authored(
      'In one sentence: inbound is blocked by the firewall -- no inbound rule covers this program.',
    ),
    also: {
      'zh-HK': '一句話結論：入站被防火牆擋住了——沒有一條入站規則覆蓋這個程式。',
      'zh-TW': '一句話結論：入站被防火牆擋住了——沒有一條入站規則覆蓋這個程式。',
      'ja': '一言で：受信はファイアウォールに止められています——このプログラムを覆う受信規則がありません。',
    },
    voices: {
      Voice.heiress: '哼，门房把人拦下了——不是本小姐吩咐的。这扇门压根就没给他开过。',
      Voice.heiressJa: 'ふん、門番が人を止めてるわ——あたしが言いつけたわけじゃないの。この門、あの人には一度も開いてないだけ。',
      Voice.minister:
          'We have, I am afraid, a difficulty of a structural nature: inbound traffic is stopped, because no '
          'inbound rule has been made to cover this program. That is not so much a decision as an omission.',
    },
  );

  static const firewallVerdictWrongProfile = CopyLine.withLanguages(
    Translated.authored('一句话结论：入站被挡住了——规则在，但没有覆盖这台机器现在的网络类别。'),
    Translated.authored(
      'In one sentence: inbound is blocked -- the rule exists but does not cover the category this network is '
      'in.',
    ),
    also: {
      'zh-HK': '一句話結論：入站被擋住了——規則在，但沒有覆蓋這台機器現在的網路類別。',
      'zh-TW': '一句話結論：入站被擋住了——規則在，但沒有覆蓋這台機器現在的網路類別。',
      'ja': '一言で：受信は止められています——規則はありますが、今のネットワーク種別を覆っていません。',
    },
    voices: {
      Voice.heiress: '门是有的，只是没给这一种客人开——规则在，可它管不着这台机器现在待的这种网络。',
      Voice.heiressJa: '門はあるの。ただ、今のこのお客さんには開いてないだけ——規則はあっても、この端末が今いる種別を覆ってないのよ。',
      Voice.minister:
          'The rule exists; the difficulty is one of scope. It does not extend to the category of network the '
          'machine currently finds itself in -- a distinction the firewall draws, and one we are obliged to report.',
    },
  );

  static const firewallVerdictLoopback = CopyLine.withLanguages(
    Translated.authored('一句话结论：监听只绑在本机回环上，局域网里的设备永远连不上。'),
    Translated.authored(
      'In one sentence: the listener is bound to loopback only, so nothing on the network can ever reach it.',
    ),
    also: {
      'zh-HK': '一句話結論：監聽只綁在本機回環上，區域網裡的裝置永遠連不上。',
      'zh-TW': '一句話結論：監聽只綁在本機回環上，區域網裡的裝置永遠連不上。',
      'ja': '一言で：待ち受けがループバックだけなので、同じネットワークからは永遠に届きません。',
    },
    voices: {
      Voice.heiress: '本小姐压根没往外应声——只在自家屋里听着呢。局域网里的人，等多久都等不到。',
      Voice.heiressJa: 'あたし、外には返事してないの——自分の部屋で聞いてるだけ。同じネットワークの人は、いつまでも待ちぼうけよ。',
      Voice.minister:
          'The listener is bound to loopback only. It is, if you will, answering a telephone in a room nobody '
          'else can enter -- and the network will wait for a reply that was never addressed to it.',
    },
  );

  static const firewallVerdictNoAddress = CopyLine.withLanguages(
    Translated.authored('一句话结论：这台机器现在没有局域网地址，附近的设备连地址都拿不到。'),
    Translated.authored(
      'In one sentence: this machine has no LAN address right now, so a neighbour has nothing to connect to.',
    ),
    also: {
      'zh-HK': '一句話結論：這台機器現在沒有區域網地址，附近的裝置連地址都拿不到。',
      'zh-TW': '一句話結論：這台機器現在沒有區域網地址，附近的裝置連地址都拿不到。',
      'ja': '一言で：今この端末には LAN アドレスがなく、近くの端末は接続先すら持てません。',
    },
    voices: {
      Voice.heiress: '连门牌号都没有，叫别人怎么找上门——这台机器现在没有局域网地址。',
      Voice.heiressJa: '表札もないのに、どうやって訪ねて来いと——この端末には今、ネットワークの住所がないの。',
      Voice.minister:
          'We are, at present, without an address on the local network. A neighbour seeking us would have '
          'nothing to seek; the difficulty precedes any question of permission.',
    },
  );

  static const firewallVerdictUnknown = CopyLine.withLanguages(
    Translated.authored('一句话结论：查不出来——这台机器不是 Windows，或者防火墙工具不可用。'),
    Translated.authored(
      'In one sentence: this could not be determined -- this is not Windows, or the firewall tool is not '
      'available.',
    ),
    also: {
      'zh-HK': '一句話結論：查不出來——這台機器不是 Windows，或者防火牆工具不可用。',
      'zh-TW': '一句話結論：查不出來——這台機器不是 Windows，或者防火牆工具不可用。',
      'ja': '一言で：判定できません——Windows ではないか、ファイアウォールの道具が使えません。',
    },
    voices: {
      Voice.heiress: '查不出来就是查不出来——本小姐不会为看不见的事编一个答案。这台机器不是 Windows，要么那工具根本不在。',
      Voice.heiressJa: '分からないものは分からないの——あたし、見えないことをでっち上げたりしないわ。Windows じゃないか、その道具がないかよ。',
      Voice.minister:
          'I am unable to give you a determination. This is not Windows, or the instrument in question is '
          'unavailable; either way, an answer would be a guess wearing the clothes of a finding.',
    },
  );

  static const firewallProfileLabel = CopyLine.withLanguages(
    Translated.authored('网络类别'),
    Translated.authored('Network category'),
    also: {'zh-HK': '網路類別', 'zh-TW': '網路類別', 'ja': 'ネットワーク種別'},
  );

  static const firewallRuleLabel = CopyLine.withLanguages(
    Translated.authored('覆盖这个程序的入站规则'),
    Translated.authored('Inbound rules covering this program'),
    also: {
      'zh-HK': '覆蓋這個程式的入站規則',
      'zh-TW': '覆蓋這個程式的入站規則',
      'ja': 'このプログラムを覆う受信規則',
    },
  
      voices: {
        Voice.heiress: '管着这个程序的入站规则。',
        Voice.heiressJa: 'このアプリに効いている受信の規則よ。',
        Voice.minister:
            'Inbound rules applying to this program.',
      },);

  static const firewallProgramLabel = CopyLine.withLanguages(
    Translated.authored('程序'),
    Translated.authored('Program'),
    also: {'zh-HK': '程式', 'zh-TW': '程式', 'ja': 'プログラム'},
  );

  static const firewallNone = CopyLine.withLanguages(
    Translated.authored('（没有）'),
    Translated.authored('(none)'),
    also: {'zh-HK': '（沒有）', 'zh-TW': '（沒有）', 'ja': '（なし）'},
  );

  /// Why the command is scoped to a program and not to a port -- the lesson from the ① run.
  static const firewallPortNote = CopyLine.withLanguages(
    Translated.authored('监听端口每次都不一样，所以命令是按程序放行，而不是按端口。'),
    Translated.authored(
      'The listening port is different every time, so this allows the program rather than a port.',
    ),
    also: {
      'zh-HK': '監聽埠每次都不一樣，所以命令是按程式放行，而不是按埠。',
      'zh-TW': '監聽埠每次都不一樣，所以命令是按程式放行，而不是按埠。',
      'ja': '待ち受けポートは毎回変わるので、ポートではなくプログラム単位で許可します。',
    },
    voices: {
      Voice.heiress: '监听端口每次都不一样——所以规矩是按程序放行，不是按端口。端口变来变去，本小姐可不想每次都替你改一遍。',
      Voice.heiressJa: '待ち受けポートは毎回変わるの——だからポート単位ではなく、プログラム単位で許可するのよ。ポートが変わるたびに、あたしが書き直してあげるわけにはいかないんだから。',
    
      Voice.minister:
          'The listening port differs on each occasion, which is why the permission is extended to the program rather than to a port.',},
  
  );

  static const syncEnterLabel = CopyLine.withLanguages(
    Translated.authored('对方的配对码'),
    Translated.authored("The other device's code"),
    also: {'zh-HK': '對方的配對碼', 'zh-TW': '對方的配對碼', 'ja': '相手のペアリングコード'});

  /// The token the reader may choose for the share code they are about to show.
  ///
  /// **[decision] 2026-09-23**, in the owner's words: *「把手动输入的东西改成可自定义的分享码，最长为 18 位」* --
  /// the token half of the code is the reader's to pick. The note under the field states the cost rather than
  /// only the rule, because the token is the only secret inside a code whose other half is an address.
  static const syncTokenLabel = CopyLine.withLanguages(
    Translated.authored('自己定令牌（可留空）'),
    Translated.authored('A token of your own (may be left empty)'),
    also: {
      'zh-HK': '自己定令牌（可留空）',
      'zh-TW': '自己定權杖（可留空）',
      'ja': '自分で決めるトークン（空欄でも可）',
    },
      voices: {
        Voice.heiress: '令牌自己写一个（留空也行）。',
        Voice.heiressJa: 'トークンは自分で決めていいの（空でも構わないわ）。',
        Voice.minister:
            'A token of your own choosing, which may be left empty.',
      },);

  static const syncTokenNote = CopyLine.withLanguages(
    Translated.authored('6–8 位，字符集里没有 I、O、0、1。令牌是这串码里唯一的秘密：太短就等于让别人也能完成第一次见面。'),
    Translated.authored(
        'Six to eight characters, from a set with no I, O, 0 or 1. The token is the only '
        'secret in this code: a short one lets somebody else finish the first meeting.'),
    also: {
      'zh-HK': '6–8 位，字符集裏沒有 I、O、0、1。令牌是這串碼裏唯一的祕密：太短就等於讓別人也能完成第一次見面。',
      'zh-TW': '6–8 位，字符集裡沒有 I、O、0、1。權杖是這串碼裡唯一的祕密：太短就等於讓別人也能完成第一次見面。',
      'ja': '6〜8 文字、I・O・0・1 を含まない文字だけ。トークンはこのコードで唯一の秘密です。短すぎると、初対面を他人に完了されてしまいます。',
    },
    // **The voice that was written for this line arrived at `syncJoin` instead.** The inserting tool guessed where a
    // definition ends and walked past this one, so the explanation spent a while attached to a button -- where rule
    // three forbids it, and where nobody reading the app would ever have seen it. Moved back here, where the note a
    // person actually reads lives.
    voices: {
      Voice.heiress: '6 到 8 位，字符里没有 I、O、0、1——省得你看错。令牌是这串码里唯一的秘密：太短，就等于把第一次见面白白让给别人。',
      Voice.heiressJa: '6〜8 文字で、I・O・0・1 は使わないの——見間違えないようにね。トークンはこのコードで唯一の秘密よ。短すぎたら、初対面を他人に譲るようなものよ。',
      Voice.minister:
          'Six to eight characters, from which I, O, zero and one have been excluded. The token '
          'is the only secret the code contains; a short one merely permits somebody else to '
          'complete the introduction on your behalf.',
    },
  );

  static const syncJoin = CopyLine.withLanguages(
    Translated.authored('连接并同步'),
    Translated.authored('Connect and sync'),
    // **No voice here, and that is rule three rather than an oversight.** This line is a button: a voice belongs on
    // the sentences a person reads, not on the control they press. A long line was attached to it by mistake -- the
    // token explanation, which belongs to `syncTokenNote` two definitions up -- and the mistake survived because the
    // tool that inserted it guessed where a definition ends. It was the only such misplacement in the file; a scan
    // for the shape (a short authored line carrying a long voiced one) is what found it.
    also: {'zh-HK': '連接並同步', 'zh-TW': '連線並同步', 'ja': '接続して同期'},
  );

  /// **Neutral, because this screen is used for both directions.** The hosting side's line names
  /// the code and what to do with it; this one is shown while a connection is being made, when
  /// there may be no code on screen at all.
  static const syncConnecting = CopyLine.withLanguages(
    Translated.authored('正在连接…'),
    Translated.authored('Connecting…'),
    also: {'zh-HK': '正在連接…', 'zh-TW': '正在連線…', 'ja': '接続しています…'},
  );

  static const syncStop = CopyLine.withLanguages(
    Translated.authored('停止等待'),
    Translated.authored('Stop waiting'),
    also: {'zh-HK': '停止等待', 'zh-TW': '停止等待', 'ja': '中止'},
  );

  /// **Produced by this screen, not by the transport.** A code the reader typed can fail to parse
  /// before any connection is attempted, and that is the one failure the reader caused and can fix,
  /// so it is the one failure this screen words for them.
  ///
  /// The failures that come back from an exchange are shown as they arrive, in the transport's own
  /// words. That is deliberate: they are a set that grows, they name sockets and timeouts rather
  /// than cellars, and matching on their English text to substitute a translation would be the
  /// kind of proxy that breaks the first time a message is reworded. A reader who sees one has
  /// something a bug report can use.
  static const syncBadCode = CopyLine.withLanguages(
    Translated.authored('这不像是一个空庭的配对码。请检查有没有漏字。'),
    Translated.authored("That does not look like a Hollow Court code. Check for missing characters."), also: {'ja': '空庭のペアリングコードではないようです。抜けがないか確認してください。', 'zh-HK': '這不像是一個空庭的配對碼。請檢查有沒有漏字。', 'zh-TW': '這不像是一個空庭的配對碼。請檢查有沒有漏字。'},
    voices: {
      Voice.heiress: '这不像是一个空庭的配对码——先检查有没有漏字。少一位都不算数。',
      Voice.heiressJa: 'これは空庭のペアリングコードには見えないわ——まず抜けがないか確認するの。一文字足りなくても駄目よ。',
    
      Voice.minister:
          'That does not present itself as a Hollow Court code. It would be advisable to establish whether any character has been omitted.',},
  );

  static const syncDone = CopyLine.withLanguages(
    Translated.authored('同步完成'),
    Translated.authored('Sync finished'),
    also: {'zh-HK': '同步完成', 'zh-TW': '同步完成', 'ja': '同期しました'},
  );

  static const syncFailed = CopyLine.withLanguages(
    Translated.authored('没能同步'),
    Translated.authored('Could not sync'),
    also: {'zh-HK': '沒能同步', 'zh-TW': '沒能同步', 'ja': '同期できませんでした'},
  );

  /// Shown when this device could not write its own identity down.
  ///
  /// **Its own line rather than folded into a sync failure, because the sync did not fail.** The pairing
  /// succeeded, the reader was told so, and what went wrong is that it will not survive a restart -- so a message
  /// about syncing would be describing the wrong event. Written after the review of 2026-10-01, where a silent
  /// write failure meant peers began refusing this device days later with nothing anywhere having said why.
  static const syncIdentityNotSaved = CopyLine.withLanguages(
    Translated.authored('这台设备没能把自己的身份存下来——刚才记住的设备，重启后不会记得。'),
    Translated.authored("This device could not save its own identity, so the device it just remembered "
        "will be forgotten when the application restarts."),
    also: {
      'zh-HK': '這台裝置沒能把自己的身分存下來——剛才記住的裝置，重啟後不會記得。',
      'zh-TW': '這台裝置沒能把自己的身分存下來——剛才記住的裝置，重啟後不會記得。',
      'ja': 'この端末は自分の身元を保存できませんでした。今覚えた端末は、再起動すると忘れます。',
    },
  );

  // ---------------------------------------------------------------- the reader's own dictionary

  /// Shown on the back row of an open folder.
  static const folderBack = CopyLine.withLanguages(
    Translated.authored('全部配方'),
    Translated.authored('All recipes'),
    also: {'zh-HK': '全部配方', 'zh-TW': '全部配方', 'ja': 'すべてのレシピ'},
  );

  static const synonymTitle = CopyLine.withLanguages(
    Translated.authored('批量自定义'),
    Translated.authored('Bulk customization'),
    also: {'zh-HK': '批量自訂', 'zh-TW': '批量自訂', 'ja': 'まとめて自分好みに'},
  );

  /// The sentence that says what the feature is for, using the owner's own examples.
  static const synonymNote = CopyLine.withLanguages(
    Translated.authored('同一个东西有几种叫法，写在这里，应用就当成一件事：利口酒＝力娇＝力娇酒，安高天娜＝安哥斯图拉，马天尼＝马提尼，菲士＝菲兹，金酒＝琴酒，蓝柑＝蓝橙。'),
    Translated.authored(
      'One thing, several names: write them here and the application treats them as one. Liqueur and 力娇 '
      'and 力娇酒, Angostura and 安哥斯图拉, Martini and 马提尼.',
    ),
    also: {
      'zh-HK': '同一個東西有幾種叫法，寫在這裡，應用就當成一件事：利口酒＝力嬌＝力嬌酒，安高天娜＝安哥斯圖拉，馬天尼＝馬提尼，菲士＝菲茲，金酒＝琴酒，藍柑＝藍橙。',
      'zh-TW': '同一個東西有幾種叫法，寫在這裡，應用就當成一件事：利口酒＝力嬌＝力嬌酒，安高天娜＝安哥斯圖拉，馬天尼＝馬提尼，菲士＝菲茲，金酒＝琴酒，藍柑＝藍橙。',
      'ja': '同じものでも呼び方がいくつもある。ここに書けば、アプリは同じものとして扱います。',
    },
    voices: {
      Voice.heiress: '同一个东西有几种叫法，写在这里，应用就当它们是一件事——利口酒＝力娇＝力娇酒，安高天娜＝安哥斯图拉，马天尼＝马提尼，菲士＝菲兹，金酒＝琴酒，蓝柑＝蓝橙。',
      Voice.heiressJa:
          '同じものがいくつもの名前で呼ばれるでしょう。ここに書けば、アプリは同じ一つのこととして扱うの——利口酒＝力娇＝力娇酒、安高天娜＝安哥斯图拉、马天尼＝马提尼、菲士＝菲兹、金酒＝琴酒、蓝柑＝蓝橙。この名前たちは、あなたが実際に見る綴りそのものよ。',
      Voice.minister:
          'Several names for one thing, set down here, are thereafter treated as one thing: 利口酒 '
          '= 力娇 = 力娇酒, and the rest of them. The application does not adjudicate which name is '
          'correct; it declines to care.',
    },
  );

  /// The grammar, shown where it is used rather than hidden in a help page.
  static const synonymExample = CopyLine.withLanguages(
    Translated.authored('一行一组：等号前是你要显示的名字，等号后是其它叫法，用逗号分开。以 # 开头的行是备注。'),
    Translated.authored(
      'One group per line: the name to show, then "=", then the other names separated by commas. A line '
      'starting with # is a note.',
    ),
    also: {
      'zh-HK': '一行一組：等號前是你要顯示的名字，等號後是其它叫法，用逗號分開。以 # 開頭的行是備註。',
      'zh-TW': '一行一組：等號前是你要顯示的名字，等號後是其它叫法，用逗號分開。以 # 開頭的行是備註。',
      'ja': '1行に1組：表示したい名前、「=」、そのあとに別の呼び方をカンマで区切って書きます。# で始まる行はメモです。',
    },
    voices: {
      Voice.heiress: '一行一组——等号前是你要显示的名字，等号后是别的叫法，逗号分开。以 # 开头的行是备注，别搞错了，那不是让你写注释的地方。',
      Voice.heiressJa: '1行に1組よ——「=」の前が表示したい名前、後ろが別の呼び方、カンマで区切るの。# で始まる行はメモよ。あたしに注釈を書けと言っているんじゃないわ。',
    
      Voice.minister:
          'One group occupies one line: the name to be shown, then "=", then the other names, separated by commas. A line beginning with # is a note and nothing further.',},
  
  );

  static const synonymUnderstood = CopyLine.withLanguages(
    Translated.authored('读懂了'),
    Translated.authored('Understood'),
    also: {'zh-HK': '讀懂了', 'zh-TW': '讀懂了', 'ja': '読み取れた組'},
  );

  static const synonymLineProblem = CopyLine.withLanguages(
    Translated.authored('第'),
    Translated.authored('Line'),
    also: {'zh-HK': '第', 'zh-TW': '第', 'ja': '行'},
  );

  static const synonymApply = CopyLine.withLanguages(
    Translated.authored('保存这张表'),
    Translated.authored('Save this table'),
    also: {'zh-HK': '儲存這張表', 'zh-TW': '儲存這張表', 'ja': 'この表を保存'},
  );

  /// Shown instead of the save button when a line could not be read.
  static const synonymFixFirst = CopyLine.withLanguages(
    Translated.authored('有一行读不懂，先改掉它——否则保存会悄悄丢掉那一行。'),
    Translated.authored(
      'A line could not be read. Fix it first: saving now would drop that line silently.',
    ),
    also: {
      'zh-HK': '有一行讀不懂，先改掉它——否則儲存會悄悄丟掉那一行。',
      'zh-TW': '有一行讀不懂，先改掉它——否則儲存會悄悄丟掉那一行。',
      'ja': '読めない行があります。先に直してください。このまま保存するとその行は黙って消えます。',
    },
    voices: {
      Voice.heiress: '有一行读不懂，先改掉它——否则保存会悄悄丢掉那一行。本小姐可不想替你收拾这个。',
      Voice.heiressJa: '読めない行が一行あるわ、先に直しなさい——そのまま保存すると、その行は黙って消えるのよ。あたしはその後始末を引き受ける気はないんだから。',
    
      Voice.minister:
          'A line has not been readable. It would be preferable to correct it first: a save at this juncture would drop that line without saying so.',},
  
  );

  static const synonymUnchanged = CopyLine.withLanguages(
    Translated.authored('与已保存的一致。'),
    Translated.authored('Nothing has changed since it was saved.'),
    also: {'zh-HK': '與已儲存的一致。', 'zh-TW': '與已儲存的一致。', 'ja': '保存された内容と同じです。'},
  );

  static const synonymInForce = CopyLine.withLanguages(
    Translated.authored('现在生效的叫法'),
    Translated.authored('Names in force now'),
    also: {'zh-HK': '現在生效的叫法', 'zh-TW': '現在生效的叫法', 'ja': '現在有効な呼び方'},
  );

  // ---------------------------------------------------------------- what this device is called

  static const namesTitle = CopyLine.withLanguages(
    Translated.authored('这台设备叫什么'),
    Translated.authored('What this device is called'),
    also: {'zh-HK': '這台設備叫什麼', 'zh-TW': '這臺裝置叫什麼', 'ja': 'この端末の名前'},
  );

  /// The sentence that has to be right, because it is the difference between a label and an identity.
  static const namesNote = CopyLine.withLanguages(
    Translated.authored(
      '名字是标签，指纹才是身份：改名字不会让两台设备混起来，别人冒用你的名字也拿不到你的指纹。',
    ),
    Translated.authored(
      'A name is a label; the fingerprint is the identity. Renaming this device cannot make two devices '
      'look alike, and copying a name gains a stranger nothing.',
    ),
    also: {'zh-HK': '名字是標籤，指紋才是身份：改名字不會讓兩台設備混起來，別人冒用你的名字也拿不到你的指紋。', 'zh-TW': '名字是標籤，指紋才是身份：改名字不會讓兩臺裝置混起來，別人冒用你的名字也拿不到你的指紋。', 'ja': '名前はラベル、指紋が身元です。名前を変えても二台が混ざることはなく、名前を真似ても指紋は手に入りません。'},
  );

  static const namesDevice = CopyLine.withLanguages(
    Translated.authored('设备名称'),
    Translated.authored('Device name'),
    also: {'zh-HK': '設備名稱', 'zh-TW': '裝置名稱', 'ja': '端末名'},
  );
  static const namesDeviceHint = CopyLine.withLanguages(
    Translated.authored('这台机器叫什么，例如 NesarfDX'),
    Translated.authored('The machine, e.g. NesarfDX'),
    also: {'zh-HK': '這台機器叫什麼，例如 NesarfDX', 'zh-TW': '這臺機器叫什麼，例如 NesarfDX', 'ja': 'この機械の名前、例：NesarfDX'},
    voices: {
      Voice.heiress: '这台机器叫什么——例如 NesarfDX。名字随你取，别太短就行。',
      Voice.heiressJa: 'この機械の名前よ——例：NesarfDX。名前は好きにつけていいけど、短すぎないこと。',
    
      Voice.minister:
          'The machine, for instance NesarfDX',},
  
  );
  static const namesCellar = CopyLine.withLanguages(
    Translated.authored('空庭名称'),
    Translated.authored('Cellar name'),
    also: {'zh-HK': '空庭名稱', 'zh-TW': '空庭名稱', 'ja': '酒蔵の名前'},
  );
  // **The example is the public name, and it used to be the internal one.** The design document states the
  // rule two pages in -- that no string a person reads carries the private name -- and this hint, which is a
  // string a person reads, carried it in all four languages. The rule had no test behind it, so it held
  // everywhere the copy had been written carefully and failed here, where somebody reached for an example.
  // `test/ui/private_name_test.dart` now enforces it.
  //
  // **And the two characters of the private name are not written here either.** The guard scans shipped
  // sources as text, so quoting the rule in a comment would fail it -- which is the right behaviour: a
  // comment travels into the artefact, into a screenshot of an editor, and into the public mirror.
  static const namesCellarHint = CopyLine.withLanguages(
    Translated.authored('你自己的酒窖叫什么，例如 空庭'),
    Translated.authored('Your cellar, e.g. Hollow Court'),
    also: {'zh-HK': '你自己的酒窖叫什麼，例如 空庭', 'zh-TW': '你自己的酒窖叫什麼，例如 空庭', 'ja': 'あなたの酒蔵の名前、例：空庭'},
    voices: {
      Voice.heiress: '你自己的酒窖叫什么，例如「空庭」——名字随你，别太短就行。',
      Voice.heiressJa: '自分の酒蔵の名前よ、例えば「空庭」——好きにつけていいけど、短すぎないこと。',
    
      Voice.minister:
          'What your own cellar is called, for instance 空庭',},
  
  );
  static const namesChoice = CopyLine.withLanguages(
    Translated.authored('同步时使用的名义'),
    Translated.authored('Which name to present when syncing'),
    also: {'zh-HK': '同步時使用的名義', 'zh-TW': '同步時使用的名義', 'ja': '同期のときに名乗る名前'},
  );
  static const namesUseDevice = CopyLine.withLanguages(
    Translated.authored('用设备名称'),
    Translated.authored('The device name'),
    also: {'zh-HK': '用設備名稱', 'zh-TW': '用裝置名稱', 'ja': '端末名を使う'},
  );
  static const namesUseCellar = CopyLine.withLanguages(
    Translated.authored('用空庭名称'),
    Translated.authored('The cellar name'),
    also: {'zh-HK': '用空庭名稱', 'zh-TW': '用空庭名稱', 'ja': '酒蔵名を使う'},
  );
  static const namesShownAs = CopyLine.withLanguages(
    Translated.authored('对方看到的'),
    Translated.authored('Other devices see'),
    also: {'zh-HK': '對方看到的', 'zh-TW': '對方看到的', 'ja': '相手に見える名前'},
  );
  static const namesUnnamedCellar = CopyLine.withLanguages(
    Translated.authored('选了空庭名称，但还没给空庭起名——现在对方看到的是设备名称。'),
    Translated.authored(
      'The cellar name is chosen but the cellar has none yet, so the device name is what goes out.',
    ),
    also: {'zh-HK': '選了空庭名稱，但還沒給空庭起名——現在對方看到的是設備名稱。', 'zh-TW': '選了空庭名稱，但還沒給空庭起名——現在對方看到的是裝置名稱。', 'ja': '酒蔵名を選びましたが、まだ名前がありません。いま相手に見えているのは端末名です。'},
    voices: {
      Voice.heiress: '名字是选了「空庭」，可还没给空庭起名——现在对方看到的还是设备名。起一个吧，人家又不会替你取。',
      Voice.heiressJa: '名前は「空庭」を選んだけれど、まだ空庭に名前をつけていないの——今、相手に見えているのは端末名のままよ。つけてあげなさいよ、人が代わりに名付けてはあげないわ。',
    
      Voice.minister:
          'The cellar name has been chosen, but the cellar has not yet been given one, and it is the device name that accordingly goes out.',},
  
  );

  /// What a share carries: everything, or one Bar.
  static const syncScope = CopyLine.withLanguages(
    Translated.authored('共享范围'),
    Translated.authored('What this share carries'),
    also: {'zh-HK': '共享範圍', 'zh-TW': '共享範圍', 'ja': '共有する範囲'},
  );

  static const syncScopeNote = CopyLine.withLanguages(
    Translated.authored('可以只给一个货架——其余的酒不会被传过去。'),
    Translated.authored(
      'A share can be limited to one shelf. Everything else stays here.',
    ),
    also: {'zh-HK': '可以只給一個貨架——其餘的酒不會被傳過去。', 'zh-TW': '可以只給一個貨架——其餘的酒不會被傳過去。', 'ja': 'ひとつの棚だけに限定できます。残りはこちらに留まります。'},
    voices: {
      Voice.heiress: '可以只给一个货架——其余的酒不会被传过去。给多少你自己定，人家不会多拿。',
      Voice.heiressJa: 'ひとつの棚だけに限定してもいいの——残りの酒はそちらへ渡らないわ。どこまで渡すかは自分で決めなさい、人が余計に取ったりはしないから。',
    
      Voice.minister:
          'A share may be confined to a single shelf. Everything else remains here.',},
  
  );

  static const syncScopeAll = CopyLine.withLanguages(
    Translated.authored('全部酒窖'),
    Translated.authored('The whole cellar'),
    also: {'zh-HK': '全部酒窖', 'zh-TW': '全部酒窖', 'ja': '酒蔵全体'},
  );

  /// Shown on the hosting side when the address in the code is one nobody else can reach.
  ///
  /// **A loopback or link-local address in a pairing code is a code that cannot work**, and the failure
  /// it produces on the other device is about the handshake -- so the machine that has the problem says
  /// nothing. This is that machine saying something.
  static const syncAddressProblem = CopyLine.withLanguages(
    Translated.authored(
      '这个码里的地址只有本机能连上——另一台设备会连不上。检查网络，或暂时关掉 VPN/虚拟网卡。',
    ),
    Translated.authored(
      'The address in this code is reachable only from this machine. Check the network, or turn off a '
      'VPN or virtual adapter for a moment.',
    ),
    also: {'zh-HK': '這個碼裏的地址只有本機能連上——另一台設備會連不上。檢查網絡，或暫時關掉 VPN/虛擬網卡。', 'zh-TW': '這個碼裡的地址只有本機能連上——另一臺裝置會連不上。檢查網路，或暫時關掉 VPN/虛擬網絡卡。', 'ja': 'このコードの住所はこの端末からしか届きません。ネットワークを確認するか、VPN／仮想アダプタを一時的に切ってください。'},
  );

  /// And the joining side's own way out.
  static const syncEditHostHint = CopyLine.withLanguages(
    Translated.authored('连不上时，可以把码里的地址改成对方屏幕上显示的那个。'),
    Translated.authored(
      'If it cannot connect, the address inside the code can be corrected by hand.',
    ),
    also: {'zh-HK': '連不上時，可以把碼裏的地址改成對方螢幕上顯示的那個。', 'zh-TW': '連不上時，可以把碼裡的地址改成對方螢幕上顯示的那個。', 'ja': 'つながらないときは、コードの中の住所を相手の画面のものに書き換えられます。'},
    voices: {
      Voice.heiress: '连不上时，可以把码里的地址改成对方屏幕上显示的那个。地址对不上，谁也连不上谁。',
      Voice.heiressJa: 'つながらないときは、コードの中の住所を相手の画面に出ているものに書き換えていいわ。住所が合わなければ、誰も誰にもつながらないのよ。',
    
      Voice.minister:
          'In the event that a connection cannot be made, the address within the code may be corrected by hand.',},
  
  );

  /// The devices this one has learned, and the way back to them without a code.
  static const syncKnownHeading = CopyLine.withLanguages(
    Translated.authored('已记住的设备'),
    Translated.authored('Remembered devices'),
    also: {'zh-HK': '已記住的設備', 'zh-TW': '已記住的裝置', 'ja': '記憶している端末'},
  );

  /// Explains what "remembered" is worth, because a reader who does not know will not know what they
  /// agreed to.
  static const syncKnownNote = CopyLine.withLanguages(
    Translated.authored('第一次用配对码见面时各记下对方的密钥，之后不必再输码。'),
    Translated.authored(
      "The first meeting is authenticated by the pairing code; each side learns the other's "
      'key and no code is needed after that.',
    ),
    also: {'zh-HK': '第一次用配對碼見面時各記下對方的密鑰，之後不必再輸碼。', 'zh-TW': '第一次用配對碼見面時各記下對方的金鑰，之後不必再輸碼。', 'ja': '初回はペアリングコードで認証し、以後はコードは要りません。'},
    voices: {
      Voice.heiress: '第一次用配对码见面时，各记下对方的密钥——之后就不必再输码了。记住的是它，不是你的记性。',
      Voice.heiressJa: '初回にペアリングコードで顔を合わせたとき、互いの鍵を控えておくの——以後はコードを入れなくて済むわ。頼りになるのはそれであって、あなたの記憶力じゃないのよ。',
    
      Voice.minister:
          'The first meeting is authenticated by the pairing code; each side is made acquainted with the other\'s key, and no code is required thereafter.',},
  
  );

  /// Shown before anything has been paired, and it is a first-run state rather than a warning.
  static const syncKnownEmpty = CopyLine.withLanguages(
    Translated.authored('还没有记住任何设备。配对成功一次就会记下。'),
    Translated.authored('No devices remembered yet. One successful pairing is enough.'),
    also: {'zh-HK': '還沒有記住任何設備。配對成功一次就會記下。', 'zh-TW': '還沒有記住任何裝置。配對成功一次就會記下。', 'ja': 'まだどの端末も記憶していません。一度成功すれば記憶します。'},
    voices: {
      Voice.heiress: '还没有记住任何设备——配对成功一次就会记下了。本小姐不替你记，它自己记。',
      Voice.heiressJa: 'まだどの端末も記憶していないわ——一度成功すれば記憶するの。あたしが覚えるんじゃない、これが覚えるのよ。',
    
      Voice.minister:
          'No devices are as yet remembered. A single successful pairing is sufficient.',},
  
  );

  static const syncKnownSync = CopyLine.withLanguages(
    Translated.authored('再同步一次'),
    Translated.authored('Sync again'),
    also: {'zh-HK': '再同步一次', 'zh-TW': '再同步一次', 'ja': 'もう一度同期'},
  );

  static const syncKnownForget = CopyLine.withLanguages(
    Translated.authored('忘记这台设备'),
    Translated.authored('Forget this device'),
    also: {'zh-HK': '忘記這台設備', 'zh-TW': '忘記這臺裝置', 'ja': 'この端末を忘れる'},
  );

  /// The identity's fingerprint, which is what two screens can be compared against.
  ///
  /// Named as a fingerprint rather than as a key: the value is derived from the public key and is
  /// for reading aloud, not for checking by machine.
  static const syncThisDevice = CopyLine.withLanguages(
    Translated.authored('这台设备'),
    Translated.authored('This device'),
    also: {'zh-HK': '這台設備', 'zh-TW': '這臺裝置', 'ja': 'この端末'},
  );

  static const syncNothingToDo = CopyLine.withLanguages(
    Translated.authored('两边已经一样了，没有需要传的。'),
    Translated.authored('Both sides already match; nothing needed to travel.'), also: {'ja': '両側はすでに同じです。送るものはありません。', 'zh-HK': '兩邊已經一樣了，沒有需要傳的。', 'zh-TW': '兩邊已經一樣了，沒有需要傳的。'},
    voices: {
      Voice.heiress: '两边已经一样了，没有需要传的——本小姐不替你找事做。',
      Voice.heiressJa: '両側はもう同じよ、送るものは何もないの——あたしは余計な仕事を探してあげたりしないわ。',
    
      Voice.minister:
          'The two sides are already the same, and there is nothing to convey.',},
  );

  static const syncMoved = CopyLine.withLanguages(
    Translated.authored('收到 / 送出'),
    Translated.authored('Received / sent'), also: {'ja': '受信 / 送信', 'zh-HK': '收到 / 送出', 'zh-TW': '收到 / 送出'});

  static const syncWith = CopyLine.withLanguages(
    Translated.authored('对方'),
    Translated.authored('Peer'), also: {'ja': '相手', 'zh-HK': '對方', 'zh-TW': '對方'});

  /// Was 「这个构建里还没有实现，所以打不开。」, and it said something that was true in the wrong place.
  ///
  /// **Reworded because it moved, and because an apology is not a state.** The four seams are
  /// declarations in the code -- they have kinds and a registry -- and none of them is included in
  /// this build, which is section 11.1's offline-first position rather than a missing feature. The
  /// sentence now states that on a screen that is *about the build*; the Cellar tab, where a person
  /// looks at their bottles, no longer mentions doors it does not open at all.


  // The three of section 13, each named for what it does rather than for the vendor
  // behind it: the bartender is a role, and which service fills it is a later decision.

  static const adapterPriceComparison = CopyLine.withLanguages(
    Translated.authored('比价'),
    Translated.authored('Price comparison'), also: {'ja': '価格比較', 'zh-HK': '比價', 'zh-TW': '比價'});

  static const adapterBarcode = CopyLine.withLanguages(
    Translated.authored('条码'),
    Translated.authored('Barcode'), also: {'ja': 'バーコード', 'zh-HK': '條碼', 'zh-TW': '條碼'});

  /// **The disclosure, as fragments rather than as a sentence.**
  ///
  /// Section 11's registry keeps a disclosure as *facts* -- hosts, payload keys, one boolean -- and expects the
  /// screen to compose the sentence from them, so that what a reader is told cannot drift away from what the
  /// code does. Composing it out of translatable pieces is how that survives section 12.4: a hostname is a
  /// literal and stays one, while "Contacts" and "Sends" are words and are translated.
  static const adapterContacts = CopyLine.withLanguages(
    Translated.authored('联系'), Translated.authored('Contacts'),
    also: {'ja': '接続先', 'zh-HK': '聯絡', 'zh-TW': '聯絡'});
  /// **What the device has to have, said before anything is switched on.**
  ///
  /// A disclosure that only lists hosts is a disclosure about *sending*; a reader deciding whether to enable a
  /// camera needs to be told that it is a camera. These two are that sentence, and they are the reason
  /// `AdapterDisclosure` grew the two flags beside its hosts.
  /// **The barcode field, which is typed as often as it is scanned.**
  ///
  /// The owner asked for manual entry on 2026-09-25, and it is not a fallback: a desktop has no camera, a label
  /// wears away, and a number read off a receipt is typed. It also makes the whole feature testable and usable
  /// before any camera plugin exists, which is why it comes first in the order of work.
  static const barcodeLabel = CopyLine.withLanguages(
    Translated.authored('条码（可手动输入）'), Translated.authored('Barcode (type or scan)'),
    also: {'ja': 'バーコード（入力可）', 'zh-HK': '條碼（可手動輸入）', 'zh-TW': '條碼（可手動輸入）'});
  static const barcodeProblemLength = CopyLine.withLanguages(
    Translated.authored('条码是 8、12、13 或 14 位数字'),
    Translated.authored('A barcode is 8, 12, 13 or 14 digits'),
    also: {'ja': 'バーコードは 8/12/13/14 桁です', 'zh-HK': '條碼是 8、12、13 或 14 位數字', 'zh-TW': '條碼是 8、12、13 或 14 位數字'},
    voices: {
      Voice.heiress: '条码是 8、12、13 或 14 位数字——不是这个长度，本小姐认不出来。',
      Voice.heiressJa: 'バーコードは 8/12/13/14 桁よ——この長さでなければ、あたしには読めないわ。',
    
      Voice.minister:
          'A barcode consists of 8, 12, 13 or 14 digits',},
  );
  static const barcodeProblemCheck = CopyLine.withLanguages(
    Translated.authored('校验位不对，最后一位应为 '),
    Translated.authored('Check digit is wrong; the last digit should be '),
    also: {'ja': 'チェックデジットが違います。最後は ', 'zh-HK': '校驗位不對，最後一位應為 ', 'zh-TW': '校驗位不對，最後一位應為 '},
      voices: {
        Voice.heiress: '最后一位算错了。应该是 ',
        Voice.heiressJa: '最後の一桁が違うわ。正しくは ',
        Voice.minister:
            'The check digit is not correct. It should read ',
      },);
  static const barcodeKnown = CopyLine.withLanguages(
    Translated.authored('这个条码记过：'), Translated.authored('This barcode is remembered as '),
    also: {'ja': 'このバーコードは既知：', 'zh-HK': '這個條碼記過：', 'zh-TW': '這個條碼記過：'});
  static const barcodeNew = CopyLine.withLanguages(
    Translated.authored('这个条码还没记过，保存时会记下'),
    Translated.authored('Not seen before; saving will remember it'),
    also: {'ja': '未登録です。保存時に記録します', 'zh-HK': '這個條碼還沒記過，儲存時會記下', 'zh-TW': '這個條碼還沒記過，儲存時會記下'},
    voices: {
      Voice.heiress: '这个条码还没记过，保存时会记下——记错的话，回头自己来改。',
      Voice.heiressJa: 'このバーコードはまだ記録していないの、保存したときに記録されるわ——間違えたら、あとで自分で直しなさい。',
    
      Voice.minister:
          'This barcode has not been recorded before; it is recorded on saving.',},
  );

  static const adapterNeedsCamera = CopyLine.withLanguages(
    Translated.authored('需要摄像头'), Translated.authored('Needs the camera'),
    also: {'ja': 'カメラが必要', 'zh-HK': '需要鏡頭', 'zh-TW': '需要鏡頭'});
  static const adapterNeedsNetwork = CopyLine.withLanguages(
    Translated.authored('需要联网'), Translated.authored('Needs the network'),
    also: {'ja': 'ネットワークが必要', 'zh-HK': '需要聯網', 'zh-TW': '需要聯網'});

  static const adapterSends = CopyLine.withLanguages(
    Translated.authored('发送'), Translated.authored('Sends'),
    also: {'ja': '送信', 'zh-HK': '傳送', 'zh-TW': '傳送'});
  static const adapterSendsCellar = CopyLine.withLanguages(
    Translated.authored('，其中包含你酒窖里的内容（瓶子与剩余量）。'),
    Translated.authored(', including what is in your cellar (bottles and what is left).'),
    also: {
      'ja': '（ボトルと残量を含む）',
      'zh-HK': '，其中包括你酒窖裡的內容（瓶子與剩餘量）。',
      'zh-TW': '，其中包括你酒窖裡的內容（瓶子與剩餘量）。',
    },
    voices: {
      Voice.heiress: '，其中包含你酒窖里的内容（瓶子与剩余量）。把话说到这份上，你自己掂量。',
      Voice.heiressJa: '（ボトルと残量を含む）——ここまで言えば、分かるわね。',
    
      Voice.minister:
          ', including that which is in your cellar (bottles and what remains).',},
  );
  static const adapterLocalHost = CopyLine.withLanguages(
    Translated.authored('这个地址就在本机，请求不离开这台设备。'),
    Translated.authored('That address is on this machine, so the request does not leave the device.'),
    also: {
      'ja': 'この宛先は同じマシン上にあり、要求は端末の外に出ません。',
      'zh-HK': '這個位址就在本機，請求不離開這台裝置。',
      'zh-TW': '這個位址就在本機，請求不離開這台裝置。',
    },
    voices: {
      Voice.heiress: '这个地址就在本机——请求不离开这台设备。别搞错了，它一步都没出过门。',
      Voice.heiressJa: 'この宛先は同じマシン上にあるの——要求は端末の外に出ないわ。勘違いしないで、一歩も外へは出ていないのよ。',
    
      Voice.minister:
          'That address is on this machine, and the request accordingly does not leave the device.',},
  );

  /// Section 11.2's peripherals, and the one adapter whose privacy question answers itself:
  /// nothing leaves, a reading arrives.
  static const adapterMeasurement = CopyLine.withLanguages(
    Translated.authored('电子测量'),
    Translated.authored('Measuring instruments'), also: {'ja': '電子計量', 'zh-HK': '電子測量', 'zh-TW': '電子測量'});

  // The price chart's period control. Three labels and not a template: a segmented button
  // draws one line per option and a `CopyLine` fits there, which is why these are pairs
  // while [stockBottles] is not.
  static const periodDay = CopyLine.withLanguages(
    Translated.authored('日'),
    Translated.authored('Day'), also: {'ja': '日', 'zh-HK': '日', 'zh-TW': '日'});

  static const periodWeek = CopyLine.withLanguages(
    Translated.authored('周'),
    Translated.authored('Week'), also: {'ja': '週', 'zh-HK': '周', 'zh-TW': '周'});

  static const periodMonth = CopyLine.withLanguages(
    Translated.authored('月'),
    Translated.authored('Month'), also: {'ja': '月', 'zh-HK': '月', 'zh-TW': '月'});

  /// Recording a bottle is a quiet act and the word for it is quiet.
  static const stockSaved = CopyLine.withLanguages(
    Translated.authored('记下了。'),
    Translated.authored('Recorded.'), also: {'ja': '記録しました。', 'zh-HK': '記下了。', 'zh-TW': '記下了。'});

  /// **Single-line: it is interpolated into a count** (`在架 · 3`), and a
  /// [CopyLine] cannot go inside a string. Composition is the second wall, beside
  /// the platform's, and it is the one that catches people out: the string looks
  /// like copy and is really an operand.
  static const stockBottles = '在架';

  /// **Single-line: a button label.** [stockAddBottle] is the same situation with a
  /// heading attached to it, and the heading is what pairs.
  static const stockSave = '记下';

  /// The label before the sentence that says why a unit set was chosen.
  static const stockUnitBecause = CopyLine.withLanguages(
    Translated.authored('为什么是这套单位：'),
    Translated.authored('Why this unit set: '),
    also: {
      'zh-HK': '為什麼是這套單位：',
      'zh-TW': '為什麼是這套單位：',
      'ja': 'この単位セットの理由：',
    },
  );

  static const stockPickIngredient = CopyLine.withLanguages(
    Translated.authored('先选一味配料。'),
    Translated.authored('Choose an ingredient first.'), also: {'ja': 'まず材料を一つ選んでください。', 'zh-HK': '先選一味配料。', 'zh-TW': '先選一味配料。'});

  static const stockVolumeProblem = CopyLine.withLanguages(
    Translated.authored('容量要是一个正数。'),
    Translated.authored('The volume has to be a positive number.'), also: {'ja': '容量は正の数で入力してください。', 'zh-HK': '容量要是一個正數。', 'zh-TW': '容量要是一個正數。'},
      voices: {
        Voice.heiress: '容量得写个正数——零和负数我不收。',
        Voice.heiressJa: '容量は正の数にして。ゼロやマイナスは受け取らないわ。',
        Voice.minister:
            'A positive figure would be required for the volume.',
      },);

  static const stockNoVocabulary = CopyLine.withLanguages(
    Translated.authored('没有酒库，也就没有可选的配料 —— 先把它建起来。'),
    Translated.authored(
      'There is no library, so there is nothing to choose from. Build it first.',
    ), also: {'ja': 'ライブラリが無いため、選べる材料もありません。まずはそれを用意してください。', 'zh-HK': '沒有酒庫，也就沒有可選的配料 —— 先把它建起來。', 'zh-TW': '沒有酒庫，也就沒有可選的配料 —— 先把它建起來。'},
    voices: {
      Voice.heiress: '没有酒库，也就没有可选的配料——先把它建起来。等着它自己长出来，那可等不到。',
      Voice.heiressJa: 'ライブラリが無ければ、選べる材料も無いの——まずそれを用意すること。勝手に生えてくるのを待っても、来ないわよ。',
    
      Voice.minister:
          'There being no library, there is nothing from which to choose. It would be as well to establish one first.',},
  );

  /// The one hint that has to name the join between the two layers: the name has to
  /// match, or the recipes will not know the bottle.
  static const stockPickHint = CopyLine.withLanguages(
    Translated.authored('从酒库已有的配料里选一格。名字要对得上，配方才认得这瓶酒。'),
    Translated.authored(
      'Choose from the ingredients the library already has. The name has to match, '
      'or the recipes will not know this bottle.',
    ), also: {'ja': 'ライブラリにある材料から選びます。名前が一致してはじめて、レシピがこの瓶を認識します。', 'zh-HK': '從酒庫已有的配料裏選一格。名字要對得上，配方才認得這瓶酒。', 'zh-TW': '從酒庫已有的配料裡選一格。名字要對得上，配方才認得這瓶酒。'},
    voices: {
      Voice.heiress: '从酒库已有的配料里选一格。名字要对得上——对得上，配方才认得这瓶酒。名字对不上，本小姐也认不出它是什么。',
      Voice.heiressJa: 'ライブラリにある材料から一枠選ぶの。名前が一致してこそ、レシピがこの瓶を認識するんだから。名前が違えば、あたしにも何の瓶か分からないわ。',
    
      Voice.minister:
          'The choice is made from among the ingredients the library already holds. The name must correspond, without which the recipes will not know this bottle.',},
  );

  // Recipes.
  static const recipesTitle = CopyLine.withLanguages(
    Translated.authored('配方'),
    Translated.authored('Recipes'), also: {'ja': 'レシピ', 'zh-HK': '配方', 'zh-TW': '配方'});

  /// The heading for the reader's own ingredients.
  static const ingredientHeading = CopyLine.withLanguages(
    Translated.authored('原料'),
    Translated.authored('Ingredients'),
    voices: {
      Voice.heiress: '原料。库里有的，和本小姐这里记着的，都在下面。',
      Voice.heiressJa: '材料。ライブラリにあるものと、あたしが預かっているもの、両方ここ。',
      Voice.minister: 'Ingredients -- what the library carries, and what one has added to it.',
    },
    also: {'ja': '材料', 'zh-HK': '原料', 'zh-TW': '原料'},
  );

  /// What the section says it is for, above the list.
  ///
  /// **It states the count of the reader's own separately from the library's**, because the two are different kinds
  /// of thing and a reader who has added three of their own should be able to see that at a glance rather than count
  /// rows.
  static const ingredientIntro = CopyLine.withLanguages(
    Translated.authored('随应用发布的那些改不了。你自己加的，可以改、可以删。'),
    Translated.authored('The ones that ship with the application cannot be changed. Your own can be edited and removed.'),
    also: {
      'ja': 'アプリに同梱のものは変更できません。自分で足したものは編集も削除もできます。',
      'zh-HK': '隨應用發布嘅改唔到。你自己加嘅，可以改、可以刪。',
      'zh-TW': '隨應用發布的改不了。你自己加的，可以改、可以刪。',
    },
  );

  /// The heading over the reader's own side of the tab: what they hold a bottle of, and what they wrote.
  ///
  /// **The two halves are named rather than implied**, which is the whole of stage ① of
  /// `docs/catalogue-and-stock.md`: the tab used to draw 189 library ingredients as one list, and a reader who
  /// actually manages twenty of them had to find those twenty in it. A heading is what turns *a list* into *your
  /// list and the library's*, and no data model had to change for it.
  static const ingredientMine = CopyLine.withLanguages(
    Translated.authored('你手上的'),
    Translated.authored('Yours'),
    voices: {
      Voice.heiress: '你手上有瓶子的，和你自己写的。这一半是本小姐替你看着的。',
      Voice.heiressJa: '手持ちの瓶があるもの、そして自分で書いたもの。こちらはあたしが預かっている側よ。',
      Voice.minister: 'What one holds a bottle of, and what one has written down. This half is kept.',
    },
    also: {'ja': '手持ちのもの', 'zh-HK': '你手上嘅', 'zh-TW': '你手上的'},
  );

  /// The heading over the library's side: the catalogue, less everything already on the reader's side.
  ///
  /// **What the split buys, said where it can be read**: `docs/ingredient-gap.md` measured that 68 of the 189
  /// shipped ingredients are used by no recipe at all -- 36% dead stock, carried because the library was derived
  /// from recipes that each kept every item. A reader cannot be told that today, because the tab never
  /// distinguished the third they are responsible for from the third nothing uses.
  static const ingredientLibrary = CopyLine.withLanguages(
    Translated.authored('库里的'),
    Translated.authored('The library'),
    voices: {
      Voice.heiress: '库里剩下的。这些不是你的责任，想要的时候再来翻。',
      Voice.heiressJa: 'ライブラリの残り。これはあなたの責務ではないわ、要るときに覗きなさい。',
      Voice.minister: 'What remains in the library. Not one\'s charge -- consulted when it is wanted.',
    },
    also: {'ja': 'ライブラリのもの', 'zh-HK': '庫裏嘅', 'zh-TW': '庫裡的'},
  );

  /// What the reader's half says when it is empty.
  ///
  /// **Two sentences rather than one shared "nothing here"**, because the halves are empty for opposite reasons and
  /// the useful reply differs: an empty reader's side means *add a bottle or write an ingredient*, and an empty
  /// library side means *you have all of it*.
  static const ingredientMineEmpty = CopyLine.withLanguages(
    Translated.authored('这里还是空的。记下一瓶酒，或者自己加一种原料。'),
    Translated.authored('Nothing here yet. Record a bottle, or add an ingredient of your own.'),
    also: {
      'ja': 'ここはまだ空です。瓶を記録するか、自分で材料を足してください。',
      'zh-HK': '呢度仲係空嘅。記低一瓶酒，或者自己加一種原料。',
      'zh-TW': '這裡還是空的。記下一瓶酒，或者自己加一種原料。',
    },
  );

  static const ingredientLibraryEmpty = CopyLine.withLanguages(
    Translated.authored('库里已经没有别的了 —— 目录上的你都有了。'),
    Translated.authored('Nothing left in the library -- you hold all of it.'),
    also: {
      'ja': 'ライブラリに残りはありません。カタログのものは全部手元にあります。',
      'zh-HK': '庫裏已經冇其他嘢喇 —— 目錄上嘅你都有齊。',
      'zh-TW': '庫裡已經沒有別的了 —— 目錄上的你都有了。',
    },
  );

  /// The four demand classes, as a reader meets them: most wanted first, nothing-wants-it last.
  ///
  /// **The threshold is in the sentence rather than left to the name.** "Core" over a grid of 33 says nothing about
  /// *why* those 33; `docs/ingredient-gap.md` measured the buckets, so the buckets can say what they are, and a
  /// reader who has never heard of ABC still reads the line correctly. The alternative -- a caption under each
  /// heading -- would have been four more lines on a page that already has five headings on it.
  ///
  /// **The vocabulary is the warehouse's, because the problem is the warehouse's.** 死库存 is the retail term for
  /// the same thing English calls dead stock; Japanese pairs **死に筋** with **稼ぎ筋**, which is the trade's own
  /// word for the line that carries a shop, so the two ends of this table are the two ends of that one; Cantonese
  /// says 死貨 and Taiwanese retail says 滯銷. **Each language gets its own term rather than a translation of the
  /// English**, because a reader who manages a store already has the word and a literal rendering would not be it.
  static const demandCore = CopyLine.withLanguages(
    Translated.authored('核心（四个以上的配方用到）'),
    Translated.authored('Core (four or more recipes)'),
    voices: {
      Voice.heiress: '核心。四个以上的配方都要它 —— 这几样缺了，吧台就停了。',
      Voice.heiressJa: '主力。4つ以上のレシピが求めているもの。これが欠けるとバーが止まるわ。',
      Voice.minister: 'Core: four or more recipes call for it. Without these the bar stops.',
    },
    also: {
      'ja': '主力（4つ以上のレシピが使う）',
      'zh-HK': '核心（四個以上嘅配方用到）',
      'zh-TW': '核心（四個以上的配方用到）',
    },
  );

  static const demandOccasional = CopyLine.withLanguages(
    Translated.authored('偶尔（两三个配方用到）'),
    Translated.authored('Occasional (two or three recipes)'),
    voices: {
      Voice.heiress: '偶尔。两三个配方的事 —— 备着不亏，缺了也只是少几杯。',
      Voice.heiressJa: '時々。2、3のレシピのこと。備えておいて損はないけれど、無ければ数杯が作れないだけ。',
      Voice.minister: 'Occasional: two or three recipes. Worth keeping, and their absence costs a few drinks.',
    },
    also: {
      'ja': '時々（2〜3のレシピが使う）',
      'zh-HK': '間中（兩三個配方用到）',
      'zh-TW': '偶爾（兩三個配方用到）',
    },
  );

  static const demandRare = CopyLine.withLanguages(
    Translated.authored('少见（只有一个配方用到）'),
    Translated.authored('Rare (exactly one recipe)'),
    voices: {
      Voice.heiress: '少见。只有一个配方指名要它 —— 那杯酒你想喝的时候，它才重要。',
      Voice.heiressJa: 'まれ。たった1つのレシピだけが名指しするもの。その一杯を飲みたいときに、初めて要る。',
      Voice.minister: 'Rare: exactly one recipe names it. It matters on the day one wants that drink.',
    },
    also: {
      'ja': 'まれ（1つのレシピだけが使う）',
      'zh-HK': '少見（得一個配方用到）',
      'zh-TW': '少見（只有一個配方用到）',
    },
  );

  /// The class stage ② exists for, and the reason it is not merged into [demandRare].
  static const demandDead = CopyLine.withLanguages(
    Translated.authored('死库存（没有任何配方用到）'),
    Translated.authored('Dead stock (no recipe at all)'),
    voices: {
      Voice.heiress: '死库存。没有任何配方用到 —— 这不是你的责任，是库自己带来的。',
      Voice.heiressJa: '死に筋。どのレシピも使わない。これはあなたの責務じゃない、ライブラリが抱えてきたものよ。',
      Voice.minister: 'Dead stock: no recipe calls for it. Not one\'s responsibility -- the library brought it along.',
    },
    also: {
      'ja': '死に筋（どのレシピにも使われない）',
      'zh-HK': '死貨（冇任何配方用到）',
      'zh-TW': '滯銷（沒有任何配方用到）',
    },
  );

  /// What the page says when a query matched nothing at all.
  ///
  /// **One line at the foot rather than one per empty half**, because with a query typed an empty half is the
  /// query's doing rather than the reader's: saying "nothing here yet" over a half that holds twenty things the
  /// query simply did not match would be false, and saying it twice would be noise.
  static const ingredientNoMatch = CopyLine.withLanguages(
    Translated.authored('没有匹配的。'),
    Translated.authored('Nothing matches that.'),
    also: {
      'ja': '一致するものはありません。',
      'zh-HK': '冇嘢夾得到。',
      'zh-TW': '沒有符合的。',
    },
  );

  static const ingredientAdd = CopyLine.withLanguages(
    Translated.authored('加一种原料'),
    Translated.authored('Add an ingredient'),
    voices: {
      Voice.heiress: '库里有你手头这种吗？没有就自己加一个，本小姐给你记上。',
      Voice.heiressJa: '手持ちの材料、ライブラリに無い？なら自分で足しなさい、控えておくわ。',
      Voice.minister: 'If the library does not carry it, add it, and it shall be kept.',
    },
    also: {'ja': '材料を足す', 'zh-HK': '加一種原料', 'zh-TW': '加一種原料'},
  );

  static const ingredientOwnTitle = CopyLine.withLanguages(
    Translated.authored('自己的一种原料'),
    Translated.authored('An ingredient of your own'),
    voices: {
      Voice.heiress: '你自己的原料。叫什么、算哪一类，写吧。',
      Voice.heiressJa: 'あなた自身の材料。名前と分類を書きなさい。',
      Voice.minister: 'An ingredient of one\'s own. Its name and its kind are one\'s to state.',
    },
    also: {'ja': 'あなた自身の材料', 'zh-HK': '自己嘅一種原料', 'zh-TW': '自己的一種原料'},
  );

  /// The label above the kind field.
  ///
  /// **Its own line rather than a substitution of another's.** The first version of the editor built this label by
  /// replacing 备注 inside the note field's line, which produced the right characters and the wrong thing: a label is
  /// copy and copy is written, and the day either sentence is edited the other would silently break.
  static const ingredientFieldKind = CopyLine.withLanguages(
    Translated.authored('类别'),
    Translated.authored('Kind'),
    also: {'ja': '分類', 'zh-HK': '類別', 'zh-TW': '類別'},
  );

  /// What the kind field says under itself.
  ///
  /// **The kind is free text rather than a menu**, and the proposal is why: the kinds are *data*, so a reader can add
  /// 茶 or 酊剂 the way they add a collection. A closed list would mean a build to add a shape.
  static const ingredientKindHint = CopyLine.withLanguages(
    Translated.authored('spirit、liqueur、syrup、tea……库里有的照抄，没有的自己写。'),
    Translated.authored('spirit, liqueur, syrup, tea… copy one the library uses, or write your own.'),
    also: {
      'ja': 'spirit、liqueur、syrup、tea… ライブラリのを使うか、自分で書く。',
      'zh-HK': 'spirit、liqueur、syrup、tea……庫裏有嘅照抄，冇嘅自己寫。',
      'zh-TW': 'spirit、liqueur、syrup、tea……庫裡有的照抄，沒有自己寫。',
    },
  );

  static const ingredientFieldAliases = CopyLine.withLanguages(
    Translated.authored('别名'),
    Translated.authored('Also called'),
    also: {'ja': '別名', 'zh-HK': '別名', 'zh-TW': '別名'},
  );

  static const ingredientAliasesHint = CopyLine.withLanguages(
    Translated.authored('用逗号分开。收据上写的是别的名字时有用。'),
    Translated.authored('Separated by commas. Useful when a receipt calls it something else.'),
    also: {
      'ja': 'カンマ区切り。レシートが別の名前で書いている時に。',
      'zh-HK': '用逗號分開。收據寫嘅係第二個名嗰陣有用。',
      'zh-TW': '用逗號分開。收據上寫的是別的名字時有用。',
    },
  );

  static const ingredientSave = CopyLine.withLanguages(
    Translated.authored('收下'),
    Translated.authored('Keep it'),
    also: {'ja': '收める', 'zh-HK': '收下', 'zh-TW': '收下'},
  );

  static const ingredientNeedsName = CopyLine.withLanguages(
    Translated.authored('得有个名字。'),
    Translated.authored('It needs a name.'),
    also: {'ja': '名前が要ります。', 'zh-HK': '要有個名。', 'zh-TW': '要有個名字。'},
  );

  static const ingredientDelete = CopyLine.withLanguages(
    Translated.authored('不要这种原料了'),
    Translated.authored('Remove this ingredient'),
    also: {'ja': 'この材料を消す', 'zh-HK': '唔要呢種原料', 'zh-TW': '不要這種原料'},
  );

  /// **What is said before the button is pressed, because a removal here is not free.** A recipe or a bottle may
  /// name this ingredient, and those references are not rewritten -- so the reader is told what they will be left
  /// with rather than finding out on the shelf.
  static const ingredientDeleteKeepsReferences = CopyLine.withLanguages(
    Translated.authored('用它的配方和酒瓶会留着，只是认不出名字了。'),
    Translated.authored('Recipes and bottles that name it stay — they simply stop resolving its name.'),
    also: {
      'ja': 'それを使うレシピや瓶は残ります。名前が引けなくなるだけです。',
      'zh-HK': '用佢嘅配方同酒瓶會留低，只係認唔出個名。',
      'zh-TW': '用它的配方和酒瓶會留著，只是認不出名字了。',
    },
  );

  /// The action that renames, describes, recolours or reorders a folder.
  static const packEdit = CopyLine.withLanguages(
    Translated.authored('改这个文件夹'),
    Translated.authored('Edit this folder'),
    also: {'ja': 'このフォルダを編集', 'zh-HK': '改呢個文件夾', 'zh-TW': '改這個資料夾'},
  );

  static const packOwnTitle = CopyLine.withLanguages(
    Translated.authored('自己的一个文件夹'),
    Translated.authored('A folder of your own'),
    voices: {
      Voice.heiress: '你自己的文件夹。叫什么、什么颜色，你说了算。',
      Voice.heiressJa: 'あなた自身のフォルダ。名前も色もあなたが決めるの。',
      Voice.minister: 'A folder of one\'s own. Its name and its colour are one\'s to decide.',
    },
    also: {'ja': 'あなた自身のフォルダ', 'zh-HK': '自己嘅一個文件夾', 'zh-TW': '自己的一個資料夾'},
  );

  static const packFieldName = CopyLine.withLanguages(
    Translated.authored('名字'),
    Translated.authored('Name'),
    also: {'ja': '名前', 'zh-HK': '名字', 'zh-TW': '名字'},
  );

  /// What the note field says under itself.
  ///
  /// **「里头是谁的」 is section 15's rule rather than a nicety**: a 友方酒 folder has to be able to say *whose* it
  /// is, and a note is where that goes.
  static const packFieldNote = CopyLine.withLanguages(
    Translated.authored('备注'),
    Translated.authored('Note'),
    also: {'ja': 'メモ', 'zh-HK': '備註', 'zh-TW': '備註'},
  );

  static const packNoteHint = CopyLine.withLanguages(
    Translated.authored('里头是谁的酒、什么时候收的，随便写。'),
    Translated.authored('Whose drinks these are, or when you got them.'),
    also: {
      'ja': '誰のお酒か、いつ手に入れたか、自由に。',
      'zh-HK': '裏頭係邊個嘅酒、幾時收嘅，隨便寫。',
      'zh-TW': '裡頭是誰的酒、什麼時候收的，隨便寫。',
    },
  );

  static const packFieldAccent = CopyLine.withLanguages(
    Translated.authored('颜色'),
    Translated.authored('Colour'),
    also: {'ja': '色', 'zh-HK': '顏色', 'zh-TW': '顏色'},
  );

  /// What the accent field says under itself, and it says the format because that is what it accepts.
  static const packAccentHint = CopyLine.withLanguages(
    Translated.authored('#RRGGBB，不填就用界面的金色。'),
    Translated.authored('#RRGGBB, or leave it empty for the interface gold.'),
    also: {
      'ja': '#RRGGBB、空なら画面の金色。',
      'zh-HK': '#RRGGBB，唔填就用界面嘅金色。',
      'zh-TW': '#RRGGBB，不填就用介面的金色。',
    },
  );

  static const packFieldOrder = CopyLine.withLanguages(
    Translated.authored('排位'),
    Translated.authored('Order'),
    also: {'ja': '並び順', 'zh-HK': '排位', 'zh-TW': '排序'},
  );

  static const packSave = CopyLine.withLanguages(
    Translated.authored('收下'),
    Translated.authored('Keep it'),
    also: {'ja': '收める', 'zh-HK': '收下', 'zh-TW': '收下'},
  );

  /// Shown when the reader presses save with no name.
  static const packNeedsName = CopyLine.withLanguages(
    Translated.authored('得有个名字。'),
    Translated.authored('It needs a name.'),
    also: {'ja': '名前が要ります。', 'zh-HK': '要有個名。', 'zh-TW': '要有個名字。'},
  );

  /// Shown when a colour is not a colour, so the reader knows the field was the problem.
  static const packAccentNotAColour = CopyLine.withLanguages(
    Translated.authored('颜色要写成 #RRGGBB，比如 #8A5A32。'),
    Translated.authored('A colour is written #RRGGBB, like #8A5A32.'),
    also: {
      'ja': '色は #RRGGBB の形で、たとえば #8A5A32。',
      'zh-HK': '顏色要寫成 #RRGGBB，例如 #8A5A32。',
      'zh-TW': '顏色要寫成 #RRGGBB，例如 #8A5A32。',
    },
  );

  /// The action that removes a folder the reader made.
  static const packDelete = CopyLine.withLanguages(
    Translated.authored('不要这个文件夹了'),
    Translated.authored('Remove this folder'),
    also: {'ja': 'このフォルダを消す', 'zh-HK': '唔要呢個文件夾', 'zh-TW': '不要這個資料夾'},
  );

  /// **What the proposal asks be asked rather than done silently**, in its own words: *"deleting one asks what
  /// happens to its recipes rather than silently orphaning them."*
  static const packDeleteKeepsRecipes = CopyLine.withLanguages(
    Translated.authored('里头的配方会留下，只是不再属于任何文件夹。'),
    Translated.authored('The recipes stay — they simply belong to no folder.'),
    also: {
      'ja': '中のレシピは残ります。どのフォルダにも属さなくなるだけです。',
      'zh-HK': '裏頭嘅配方會留低，只係唔再屬於任何文件夾。',
      'zh-TW': '裡頭的配方會留下，只是不再屬於任何資料夾。',
    },
  );

  /// The button that enters selection mode.
  ///
  /// **A long press could not be both "edit this" and "start selecting".** The owner's rule is that a long press on a
  /// collection or a folder opens its own editor -- renaming it, giving it a colour, putting it in order -- and that
  /// had to keep working, which left selection with no way in. So it gets one of its own, next to the two buttons that
  /// already make things.
  static const collectStart = CopyLine.withLanguages(
    Translated.authored('挑几个'),
    Translated.authored('Select'),
    voices: {
      Voice.heiress: '想挑几杯收在一起？按这个，本小姐看着。',
      Voice.heiressJa: 'いくつか選んでまとめたいの？これを押しなさい。',
      Voice.minister: 'To gather several, begin here.',
    },
    also: {'ja': 'いくつか選ぶ', 'zh-HK': '揀幾個', 'zh-TW': '挑幾個'},
  );

  /// The action that gathers what is ticked into one collection.
  static const collectMake = CopyLine.withLanguages(
    Translated.authored('收成一个合集'),
    Translated.authored('Collect these'),
    voices: {
      Voice.heiress: '挑好了？那就收成一个合集吧。',
      Voice.heiressJa: '選んだ？なら一つにまとめなさい。',
      Voice.minister: 'Then let them be gathered into one.',
    },
    also: {'ja': '一つにまとめる', 'zh-HK': '收成一個合集', 'zh-TW': '收成一個合集'},
  );

  /// How many things are ticked, said as a count.
  static String collectCount(int n) => CopyLine.withLanguages(
    Translated.authored('选了 $n 个'),
    Translated.authored('$n selected'),
    also: {'ja': '$n 個選択', 'zh-HK': '揀咗 $n 個', 'zh-TW': '選了 $n 個'},
  ).textFor('zh-Hans');

  /// The action that leaves the selection without doing anything with it.
  static const collectCancel = CopyLine.withLanguages(
    Translated.authored('算了'),
    Translated.authored('Cancel'),
    also: {'ja': 'やめる', 'zh-HK': '算數', 'zh-TW': '算了'},
  );

  /// What is said while a selection is being made, so a reader knows what the gesture did.
  static const collectHint = CopyLine.withLanguages(
    Translated.authored('长按可以再选，点一下也能选。'),
    Translated.authored('Long press or tap to add more.'),
    also: {
      'ja': '長押しかタップで足せます。',
      'zh-HK': '長按可以再揀，㩒一下都得。',
      'zh-TW': '長按可以再選，點一下也能選。',
    },
  );

  /// The heading of the sheet that chooses where the selection goes.
  static const collectWhere = CopyLine.withLanguages(
    Translated.authored('收进哪个合集'),
    Translated.authored('Which collection'),
    voices: {
      Voice.heiress: '收进哪个？新开一个也行。',
      Voice.heiressJa: 'どれに入れる？新しく作ってもいいわ。',
      Voice.minister: 'Into which, or into a new one.',
    },
    also: {'ja': 'どのコレクションへ', 'zh-HK': '收進邊個合集', 'zh-TW': '收進哪個合集'},
  );

  /// The action that makes the selection into a **new** collection, which the owner asked be customisable.
  static const collectIntoNew = CopyLine.withLanguages(
    Translated.authored('新开一个合集'),
    Translated.authored('A new collection'),
    also: {'ja': '新しいコレクション', 'zh-HK': '新開一個合集', 'zh-TW': '新開一個合集'},
  );

  /// The button that opens the pack editor, now that a long press means "select".
  ///
  /// **The gesture had to move.** A long press is what the owner asked for selecting, and a folder row cannot mean
  /// both "start a selection" and "rename me" -- so renaming gets a control of its own, which is what it should have
  /// had: a gesture that does two things is a gesture a reader cannot predict.
  static const packEditShort = CopyLine.withLanguages(
    Translated.authored('改名'),
    Translated.authored('Rename'),
    also: {'ja': '名前を変える', 'zh-HK': '改名', 'zh-TW': '改名'},
  );

  /// The action that removes a recipe the reader wrote.
  static const recipeDelete = CopyLine.withLanguages(
    Translated.authored('不要这条配方了'),
    Translated.authored('Remove this recipe'),
    also: {'ja': 'このレシピを消す', 'zh-HK': '唔要呢條配方', 'zh-TW': '不要這條配方'},
  );

  /// The button that starts a collection.
  ///
  /// **A noun with a verb under it** would be two controls; this is one, and the sheet that opens is where the name
  /// and the membership are chosen. The word is 集合 rather than 文件夹 because the application already has folders
  /// -- derived ones, made from the drinks themselves -- and a reader who is offered "folder" for both would have no
  /// way to tell which kind they were making.
  static const collectionNew = CopyLine.withLanguages(
    Translated.authored('编一个集合'),
    Translated.authored('Make a collection'),
    voices: {
      Voice.heiress: '想把几杯收在一起？说吧，本小姐给你编。',
      Voice.heiressJa: 'いくつかまとめたいの？言いなさい、編んであげる。',
      Voice.minister: 'A collection of one\'s own devising. Name it, and I shall keep it.',
    },
    also: {'ja': 'コレクションを作る', 'zh-HK': '編一個集合', 'zh-TW': '編一個集合'},
  );

  /// The sheet's title, and it says whose collection this is.
  static const collectionOwnTitle = CopyLine.withLanguages(
    Translated.authored('自己的一个集合'),
    Translated.authored('A collection of your own'),
    voices: {
      Voice.heiress: '你自己的集合。里头放什么，你说了算。',
      Voice.heiressJa: 'あなた自身のコレクション。中身はあなたが決めるの。',
      Voice.minister: 'A collection of one\'s own. Its contents are one\'s to decide.',
    },
    also: {'ja': 'あなた自身のコレクション', 'zh-HK': '自己嘅一個集合', 'zh-TW': '自己的一個集合'},
  );

  static const collectionFieldName = CopyLine.withLanguages(
    Translated.authored('名字'),
    Translated.authored('Name'),
    also: {'ja': '名前', 'zh-HK': '名字', 'zh-TW': '名字'},
  );

  static const collectionFieldMembers = CopyLine.withLanguages(
    Translated.authored('里头放什么'),
    Translated.authored('What goes in it'),
    also: {'ja': '中に入れるもの', 'zh-HK': '裏頭放咩', 'zh-TW': '裡頭放什麼'},
  );

  /// What the member list says when the reader has picked nothing.
  static const collectionMembersHint = CopyLine.withLanguages(
    Translated.authored('空着也行，回头再放。'),
    Translated.authored('Empty is fine — it will keep until you fill it.'),
    also: {
      'ja': '空でもいい、あとで入れなさい。',
      'zh-HK': '空住都冇問題，遲啲再放。',
      'zh-TW': '空著也行，回頭再放。',
    },
  );

  static const collectionSave = CopyLine.withLanguages(
    Translated.authored('收下'),
    Translated.authored('Keep it'),
    also: {'ja': '收める', 'zh-HK': '收下', 'zh-TW': '收下'},
  );

  /// Shown when the reader presses save with no name.
  static const collectionNeedsName = CopyLine.withLanguages(
    Translated.authored('得有个名字。'),
    Translated.authored('It needs a name.'),
    also: {'ja': '名前が要ります。', 'zh-HK': '要有個名。', 'zh-TW': '要有個名字。'},
  );

  /// Shown when a collection is about to contain itself, which `checkMembership` refuses before writing.
  ///
  /// **The sentence a reader gets instead of a stack overflow.** Without it the loop would be in the log and in
  /// every synced copy of it before anybody noticed.
  static const collectionWouldContainItself = CopyLine.withLanguages(
    Translated.authored('这样它就装进自己里面了——绕不出来。把那一项去掉。'),
    Translated.authored('That would put it inside itself, and it could never come back out. Take that one off.'),
    also: {
      'ja': 'それだと自分自身の中に入ってしまいます。外せません。その項目を外してください。',
      'zh-HK': '咁樣佢就裝入自己裏面——走唔返出嚟。攞走嗰項。',
      'zh-TW': '這樣它就裝進自己裡面了——繞不出來。把那一項去掉。',
    },
  );

  /// The button that starts writing a recipe.
  ///
  /// **A verb rather than a noun**, which is the rule the rest of this file follows for buttons: 记一瓶 on the
  /// stock page, 开始检查 on the integrity screen. What the reader is doing is writing something down, and the
  /// sheet that opens is where they do it.
  static const recipeNew = CopyLine.withLanguages(
    Translated.authored('写一条配方'),
    Translated.authored('Write a recipe'),
    voices: {
      Voice.heiress: '想自己写一条？那就写吧，本小姐看着。',
      Voice.heiressJa: '自分で書きたいの？なら書きなさい、あたしが見ててあげる。',
      Voice.minister: 'One may compose one\'s own, should one wish. I shall look on.',
    },
    also: {'ja': 'レシピを書く', 'zh-HK': '寫一條配方', 'zh-TW': '寫一條配方'},
  );

  /// The sheet's own title, and it says whose recipe this is.
  ///
  /// **「自己的」 and not 「新建」**, because the distinction this whole screen is about is *whose* recipe it is: the
  /// library's are shipped and identical on every install, and these are the reader's. A title that only said "new"
  /// would leave the difference to be inferred from a delete button appearing later.
  static const recipeOwnTitle = CopyLine.withLanguages(
    Translated.authored('自己的一条配方'),
    Translated.authored('A recipe of your own'),
    voices: {
      Voice.heiress: '你自己的配方。写吧，本小姐不催你。',
      Voice.heiressJa: 'あなた自身のレシピ。書きなさい、急かさないわ。',
      Voice.minister: 'A recipe of one\'s own. Take the time it needs.',
    },
    also: {'ja': 'あなた自身のレシピ', 'zh-HK': '自己的一條配方', 'zh-TW': '自己的一條配方'},
  );

  static const recipeFieldName = CopyLine.withLanguages(
    Translated.authored('名字'),
    Translated.authored('Name'),
    also: {'ja': '名前', 'zh-HK': '名字', 'zh-TW': '名字'},
  );

  static const recipeFieldMethod = CopyLine.withLanguages(
    Translated.authored('做法'),
    Translated.authored('Method'),
    also: {'ja': '作り方', 'zh-HK': '做法', 'zh-TW': '做法'},
  );

  /// What the method field says under itself.
  ///
  /// **It says the field is free text, because that is the decision the proposal records.** A closed list of
  /// 摇/搅/直调 would eventually demand that somebody shake a pour-over, so the vocabulary is offered rather than
  /// required -- and a reader who cannot tell whether a suggestion is a suggestion will write what they mean.
  static const recipeMethodHint = CopyLine.withLanguages(
    Translated.authored('随便写——搅、摇、直调都行，写别的也行。'),
    Translated.authored('Anything — stirred, shaken, built, or your own words.'),
    also: {
      'ja': '自由に——ステア、シェイク、ビルド、それ以外でも。',
      'zh-HK': '隨便寫——攪、搖、直調都行，寫別的也行。',
      'zh-TW': '隨便寫——攪、搖、直調都行，寫別的也行。',
    },
  );

  static const recipeFieldIngredients = CopyLine.withLanguages(
    Translated.authored('原料'),
    Translated.authored('Ingredients'),
    also: {'ja': '材料', 'zh-HK': '原料', 'zh-TW': '原料'},
  );

  static const recipeAddLine = CopyLine.withLanguages(
    Translated.authored('加一行'),
    Translated.authored('Add a line'),
    also: {'ja': '一行足す', 'zh-HK': '加一行', 'zh-TW': '加一行'},
  );

  static const recipeSave = CopyLine.withLanguages(
    Translated.authored('收下'),
    Translated.authored('Keep it'),
    voices: {
      Voice.heiress: '写好了就收下吧，本小姐给你留着。',
      Voice.heiressJa: '書き終わったなら預かりなさい、あたしが取っておくわ。',
      Voice.minister: 'It shall be kept, once one is satisfied with it.',
    },
    also: {'ja': '收める', 'zh-HK': '收下', 'zh-TW': '收下'},
  );

  /// Shown when the reader presses save with nothing written.
  ///
  /// **Says which two things are missing rather than "invalid"**, because a form that refuses without saying why is
  /// a form somebody fills in twice.
  static const recipeNeedsNameAndLine = CopyLine.withLanguages(
    Translated.authored('至少要有名字和一行原料。'),
    Translated.authored('It needs a name and at least one ingredient line.'),
    also: {
      'ja': '名前と材料が一行は要ります。',
      'zh-HK': '至少要有名字同一行原料。',
      'zh-TW': '至少要有名字和一行原料。',
    },
  );

  /// Shown when a line gives an amount but names no ingredient.
  ///
  /// **Found by a UI test on 2026-10-01**: typing `30` and never choosing what it was thirty *of* used to save a
  /// recipe whose ingredient id was the empty string, and nothing afterwards could say which line was wrong.
  static const recipeLineNeedsIngredient = CopyLine.withLanguages(
    Translated.authored('有一行写了份量，但没选是什么。'),
    Translated.authored('A line gives an amount but does not say what it is an amount of.'),
    also: {
      'ja': '分量だけ書いてあって、何の分量か選んでいません。',
      'zh-HK': '有一行寫了份量，但冇揀係咩。',
      'zh-TW': '有一行寫了份量，但沒選是什麼。',
    },
  );

  /// Shown when a line names an ingredient this build cannot resolve.
  static const recipeUnknownIngredient = CopyLine.withLanguages(
    Translated.authored('这一行点到的原料，这个构建不认识。'),
    Translated.authored('A line names an ingredient this build does not know.'),
    also: {
      'ja': 'この行の材料は、このビルドには分かりません。',
      'zh-HK': '這一行指到的原料，這個版本唔識。',
      'zh-TW': '這一行指到的原料，這個版本不認識。',
    },
  );

  static const recipesEmpty = CopyLine.withLanguages(
    Translated.authored('酒库还没有建好。'),
    Translated.authored('The library is not built yet.'), also: {'ja': 'ライブラリがまだありません。', 'zh-HK': '酒庫還沒有建好。', 'zh-TW': '酒庫還沒有建好。'});

  static const recipesEmptyHint = CopyLine.withLanguages(
    Translated.authored('配方库随应用一起提供。如果这里还是空的，说明这一份安装不完整，重装一次即可。'),
    Translated.authored(
      'The recipe library ships with the application. If this is still empty, the installation is '
      'incomplete; installing once more is all it takes.',
    ),
    voices: {
      Voice.heiress: '配方库是随本小姐的应用一起奉上的——这里若是空的，说明这一份装得不全。重装一次就好，不必自己动手去补。',
      Voice.heiressJa: 'レシピ集はあたしのアプリに最初から付いてくるの——ここが空なら、このインストールが不完全なだけ。入れ直せば済むわ、自分で埋め合わせる必要なんてないの。',
      Voice.minister:
          'The recipe library accompanies the application. Should this remain empty, the installation is '
          'incomplete rather than the library absent; installing once more is the whole of the remedy.',
    },
    also: {
      'ja': 'レシピライブラリはアプリに同梱されています。ここが空のままであれば、このインストールは不完全です。入れ直してください。',
      'zh-HK': '配方庫隨應用一起提供。如果這裡還是空的，說明這一份安裝不完整，重裝一次即可。',
      'zh-TW': '配方庫隨應用一起提供。如果這裡還是空的，說明這一份安裝不完整，重裝一次即可。',
    },
  );

  // The rest of this section is single-line, and each one for a reason rather than
  // a preference. [recipesMissing], [recipesMissingCount] and [recipesCount] go
  // through [withCount] and are substituted into a sentence -- `{count}` is the
  // clearest case of all, because the placeholder has to be replaced by a `String`
  // and a pair cannot survive that. [recipesNothingMissing] and [recipesGarnishOnly]
  // are the second line of a badge that already has two. [filterAll], [recipesMain]
  // and [recipesGarnish] are chip and inline tag labels, and [mixIt] and [garnish]
  // are a button and a tag.
  static const recipesMissing = '还缺';
  /// Not `{count}` alone: the noun has to be there, because a bare number in
  /// a badge reads as a score rather than as a shortage.
  static const recipesMissingCount = '缺 {count} 味';
  static const recipesNothingMissing = '配料齐全';
  static const recipesGarnishOnly = '只缺装饰';
  static const recipesCount = '共 {count} 条';
  static const filterAll = '全部';
  static const recipesMain = '本体';
  static const recipesGarnish = '装饰';
  static const mixIt = '调这一杯';
  static const garnish = '装饰';

  // The note on a recipe: section 8's overlay at its first consumer.
  //
  // **All four are single-line, for the two reasons this file's second group
  // exists.** Two are `InputDecoration` strings and one is a button label; the
  // fourth is an icon's semantic label. The note's own text is the user's and is
  // not copy at all, which is the whole point of the layer.
  static const recipeNote = '我的备注';
  static const recipeNoteHint = '例如：糖浆减半';
  static const recipeNoteSave = '记下';
  static const recipeHasNote = '有备注';

  // The three verdicts of section 9, in the character's register rather than in
  // a scorecard's. None of them is congratulatory.
  //
  // **Single-line, and this is the one place the split costs something worth
  // naming.** A verdict is drawn as two lines already -- the verdict, then what is
  // missing -- so pairing it would make three, and it is a filter chip's label
  // besides. So her register is here in Chinese and its English waits for the
  // `.arb` layer with the other confined sites; the register survives the wait, and
  // a three-line badge would not survive being built.
  static const verdictMakeable = '可以做';
  static const verdictClose = '差一点';
  static const verdictInsufficient = '做不了';

  // The two screens that are section 14's P2. Both pair: a heading and a sentence
  // under it, with a whole screen's height to spend.
  static const barTitle = CopyLine.withLanguages(
    Translated.authored('吧台'),
    Translated.authored('Bar'), also: {'ja': 'バー', 'zh-HK': '吧枱', 'zh-TW': '吧檯'});
  // The Bar page, at P2's first pass: the shelf exists, the bottles stand on it,
  // and a position is written to the log rather than kept on the screen.
  static const barShelfMain = CopyLine.withLanguages(
    Translated.authored('主架'),
    Translated.authored('Main shelf'), also: {'ja': 'メインの棚', 'zh-HK': '主架', 'zh-TW': '主架'});
  static const barInTheBox = CopyLine.withLanguages(
    Translated.authored('还没上架'),
    Translated.authored('Still in the box'), also: {'ja': 'まだ棚に置いていません', 'zh-HK': '還沒上架', 'zh-TW': '還沒上架'});
  static const barDragHint = CopyLine.withLanguages(
    Translated.authored('把瓶子拖到架子上，位置会记进日志。'),
    Translated.authored(
      'Drag a bottle onto a shelf. The position is written to the log, so the '
      'next device that reads it sees the same shelf.',
    ), also: {'ja': '瓶を棚へドラッグすると、位置がログに記録されます。', 'zh-HK': '把瓶子拖到架子上，位置會記進日誌。', 'zh-TW': '把瓶子拖到架子上，位置會記進日誌。'},
    voices: {
      Voice.heiress: '把瓶子拖到架子上，位置会记进日志——位置也是账目的一部分。',
      Voice.heiressJa: '瓶を棚にドラッグしなさい、位置は記録に残るの——位置もまた帳簿のうちよ。',
    
      Voice.minister:
          'Drag the bottle to the shelf; the position is entered in the record.',},
  );
  static const barShelfEmpty = CopyLine.withLanguages(
    Translated.authored('这层架子还空着。'),
    Translated.authored('Nothing stands on this shelf yet.'), also: {'ja': 'この段はまだ空いています。', 'zh-HK': '這層架子還空着。', 'zh-TW': '這層架子還空著。'},
      voices: {
        Voice.heiress: '这一层还空着。摆什么，你自己挑。',
        Voice.heiressJa: 'この段はまだ空いているわ。何を置くかは、あなたが決めなさい。',
        Voice.minister:
            'The shelf in question is at present unoccupied; the selection is a matter for you.',
      },);
  static const barNothingToPlace = CopyLine.withLanguages(
    Translated.authored('架上有东西，但还没记下位置。'),
    Translated.authored(
      'There is stock and none of it has a position -- the bottles are still in '
      'the box.',
    ), also: {'ja': '棚には物がありますが、位置がまだ記録されていません。', 'zh-HK': '架上有東西，但還沒記下位置。', 'zh-TW': '架上有東西，但還沒記下位置。'},
      voices: {
        Voice.heiress: '东西是有的——就是谁在哪儿，你还没告诉我。',
        Voice.heiressJa: '物はあるのよ。ただ、どれがどこにあるか、まだ教えてもらっていないだけ。',
        Voice.minister:
            'Stock is held, although no position has been recorded for it.',
      },);
  static const barPlacedButEmpty = CopyLine.withLanguages(
    Translated.authored('位置还记着，瓶子已经空了。'),
    Translated.authored(
      'A position is recorded for a bottle that is empty. The place stays until '
      'somebody moves the bottle or clears it.',
    ), also: {'ja': '位置は残っていますが、瓶はもう空です。', 'zh-HK': '位置還記着，瓶子已經空了。', 'zh-TW': '位置還記著，瓶子已經空了。'},
      voices: {
        Voice.heiress: '位置还给你留着，瓶子却空了。等你有新的一瓶，它还在那儿。',
        Voice.heiressJa: '場所は残してあるのに、瓶はもう空よ。次のが来たら、そこに戻してあげる。',
        Voice.minister:
            'A position has been retained for a bottle which is no longer there.',
      },);

  static const cellarTitle = CopyLine.withLanguages(
    Translated.authored('记录'),
    Translated.authored('Journal'), also: {'ja': '記録', 'zh-HK': '記錄', 'zh-TW': '記錄'});
  /// Retired with [cellarNotYetHint]'s subject: 「还没有什么可记的。」 was what the tab said while it
  /// had nothing on it, and the tab has had statistics, a curve, value, a shopping list, devices and
  /// sync for some time. A line with no caller is copy a translator would be asked to carry for
  /// nothing, so both went.
  /// Deleted, and its history is worth one line: it read 「这一页属于 P2：消耗曲线、价值、设备与同步。」
  /// and stayed on the screen after all four of those had been built -- a placeholder that outlived
  /// its subject, telling every reader that the tab they were looking at did not exist yet.
  ///
  /// Nothing replaced it. The page is now what section 12.3 asks it to be, and the honest way to say
  /// so is to stop saying otherwise.

  // The plan flag, which is what a shopping list is derived from.
  static const recipePlan = '计划做';
  static const recipePlanned = '已列入计划';
  static const recipeNotPlanned = '加入计划';

  // The shopping list, derived from the plan marks.
  static const cellarShopping = CopyLine.withLanguages(
    Translated.authored('要买什么'),
    Translated.authored('What to buy'), also: {'ja': '買うもの', 'zh-HK': '要買什麼', 'zh-TW': '要買什麼'});
  static const cellarShoppingNoPlans = CopyLine.withLanguages(
    Translated.authored('还没有计划做的配方。'),
    Translated.authored(
      'No recipe is on the plan yet. Mark one on the Recipes tab and its missing '
      'ingredients appear here.',
    ), also: {'ja': '作る予定のレシピはまだありません。', 'zh-HK': '還沒有計劃做的配方。', 'zh-TW': '還沒有計劃做的配方。'},
      voices: {
        Voice.heiress: '你还没挑要做什么。挑一个，缺点儿什么我替你算。',
        Voice.heiressJa: 'まだ何を作るか決めていないのね。決めたら、足りないものを数えてあげる。',
        Voice.minister:
            'No recipe has as yet been selected for the plan.',
      },);
  static const cellarShoppingNothing = CopyLine.withLanguages(
    Translated.authored('计划里的东西架上都有。'),
    Translated.authored('Everything the plan needs is already on the shelf.'), also: {'ja': '予定しているものは棚にそろっています。', 'zh-HK': '計劃裏的東西架上都有。', 'zh-TW': '計劃裡的東西架上都有。'},
      voices: {
        Voice.heiress: '清单上的东西，我早都备齐了——不用你再吩咐。',
        Voice.heiressJa: 'リストのものなら、もう全部そろえてあるわ。指示されなくてもね。',
        Voice.minister:
            'The requirements of the plan are, so far as can be established, already met.',
      },);
  static const cellarShoppingNeededBy = '计划中的';
  static const cellarShoppingOrphaned = '计划里已经不存在的配方';

  // What the shopping list costs, priced from the reader's own receipts rather than from a price source.
  //
  // **This is where section 7's open question ended, and it ended by measurement.** No open price database covers
  // China, so "which sources may we query" had no answer; "what did this cost me last time" does, and the reader
  // has already told the application. See `shopping_spend.dart`.
  static const shoppingSpendTotal = CopyLine.withLanguages(
    Translated.authored('按你上次付的价，这些大约'),
    Translated.authored('At the prices you last paid, about'),
    also: {
      'ja': '前回払った値段で見ると、およそ',
      'zh-HK': '按你上次付的價，這些大約',
      'zh-TW': '按你上次付的價，這些大約'},
      voices: {
        Voice.heiress: '照你上次付的价算，这一批大概要',
        Voice.heiressJa: '前回払った値段で数えれば、この分はおよそ',
        Voice.minister: 'At the prices last paid, the requirement is of the order of',
      },);

  /// **The qualifier, and the reason it is on the screen rather than in a comment.** Two of the list's
  /// ingredients may have no price at all, and the figure is a sum over the last known price of each -- not over
  /// the quantities the recipes call for, which the shopping list does not carry.
  static const shoppingSpendPartial = CopyLine.withLanguages(
    Translated.authored('有配料还没记过价，所以这不是全部。'),
    Translated.authored('Some ingredients have no price recorded, so this is not the whole of it.'),
    also: {
      'ja': '値段を記録していない材料があるので、これが全部ではありません。',
      'zh-HK': '有配料還沒記過價，所以這不是全部。',
      'zh-TW': '有配料還沒記過價，所以這不是全部。'},
      voices: {
        Voice.heiress: '有几样你还没告诉过我价钱，所以这数目不全。',
        Voice.heiressJa: 'いくつか値段を聞いていないものがあるから、これで全部ではないわ。',
        Voice.minister: 'Certain ingredients have no recorded figure, and the sum is consequently incomplete.',
      },);

  /// Printed in place of a total when the list's prices are in more than one currency.
  static const shoppingSpendMixed = CopyLine.withLanguages(
    Translated.authored('清单里的价不止一种货币，所以这里不合计。'),
    Translated.authored('These prices are in more than one currency, so no total is given.'),
    also: {
      'ja': 'この一覧の値段は通貨が一つではないので、合計は出しません。',
      'zh-HK': '清單裡的價不止一種貨幣，所以這裡不合計。',
      'zh-TW': '清單裡的價不止一種貨幣，所以這裡不合計。'},
      voices: {
        Voice.heiress: '两种钱混在一块儿，合起来就是个没意义的数——我不给你算。',
        Voice.heiressJa: '通貨が混ざっているの。足したところで意味のない数字になるから、合計は出さないわ。',
        Voice.minister: 'The figures are denominated in more than one currency, and no total is therefore offered.',
      },);

  // Section 12.3's statistics, on the Cellar tab.
  static const cellarStats = CopyLine.withLanguages(
    Translated.authored('统计'),
    Translated.authored('Statistics'), also: {'ja': '統計', 'zh-HK': '統計', 'zh-TW': '統計'});
  static const cellarStatsEmpty = CopyLine.withLanguages(
    Translated.authored('还没有可统计的。'),
    Translated.authored('Nothing to count yet.'), also: {'ja': 'まだ集計できるものがありません。', 'zh-HK': '還沒有可統計的。', 'zh-TW': '還沒有可統計的。'},
      voices: {
        Voice.heiress: '要统计什么？桌上还什么都没有呢。',
        Voice.heiressJa: '集計するものなんて、まだ何も並んでいないわ。',
        Voice.minister:
            'There is at present no material on which a figure could be based.',
      },);
  static const cellarStatsBottles = '瓶';
  static const cellarStatsStanding = '还有剩';
  static const cellarStatsEmptyBottles = '已空';
  static const cellarStatsOnHand = '在手';
  static const cellarStatsDrunk = '倒入杯中';
  static const cellarStatsDiscarded = '倒掉';
  static const cellarStatsMostPoured = '倒得最多';
  static const cellarStatsOverdrawn = '记录超支';

  // The takings over the bar's four windows, on the 记录 tab above the statistics.
  //
  // **The domain for this has existed since 2026-09-21 and no screen read it.** `cashflow.dart` carries the four
  // windows, the arithmetic, the unattributed list and the deposit comparison with ten tests behind them, and
  // `docs/TODO.md` section 十 recorded why: the feature's problem was never its behaviour but where it belonged.
  // The assistant placed it on 2026-09-30 by the screen's own logic -- 记录 is the page whose headline facts are
  // already the reader's money, and the shelf that used to occupy this slot is off the interface.
  static const cellarCashflow = CopyLine.withLanguages(
    Translated.authored('收支'),
    Translated.authored('Takings'), also: {'ja': '収支', 'zh-HK': '收支', 'zh-TW': '收支'});

  /// The label on each of the four windows, written out rather than derived from the enum's name.
  ///
  /// **`CashflowWindow` carries its own `name` for storage and this is not that.** A name that is also a wire
  /// format cannot be reworded without breaking stored data, so the two are kept apart on purpose: the enum's
  /// name goes in files, and this goes on the screen.
  static const cashflowToday = '当日';
  static const cashflowWeek = '7 日';
  static const cashflowMonth = '30 日';
  static const cashflowQuarter = '90 日';

  static const cashflowSpent = CopyLine.withLanguages(
    Translated.authored('支出'),
    Translated.authored('Spent'), also: {'ja': '支出', 'zh-HK': '支出', 'zh-TW': '支出'},
      voices: {
        Voice.heiress: '花掉的部分。',
        Voice.heiressJa: '使った分よ。',
        Voice.minister: 'Expenditure, as recorded.',
      },);

  static const cashflowNet = CopyLine.withLanguages(
    Translated.authored('净额'),
    Translated.authored('Net'), also: {'ja': '純額', 'zh-HK': '淨額', 'zh-TW': '淨額'},
      voices: {
        Voice.heiress: '进的和出的抵完还剩多少。',
        Voice.heiressJa: '入って出て、残った分ね。',
        Voice.minister: 'The difference between what came in and what went out.',
      },);

  /// **Why there is no income figure, said on the screen rather than left as a zero.**
  ///
  /// Nothing in the event log says a drink was sold: `BottleConsumed` records that a bottle is lighter, which is
  /// a fact about stock rather than about money, and no event records taking payment. `cashflowOf` takes income
  /// as a parameter for exactly this reason, and its own comment gives the rule -- a takings screen that quietly
  /// counts nothing as income would show a bar that only ever loses money. A zero would be read as an answer, so
  /// the gap is named instead.
  static const cashflowNoIncome = CopyLine.withLanguages(
    Translated.authored('收入还记不了：现在没有任何事件记录「卖出」这件事，所以上面只有支出。'),
    Translated.authored('Takings cannot be recorded yet: no event says a drink was sold, so only the spending '
        'side is counted above.'), also: {
      'ja': '売り上げはまだ記録できません。何かを売ったという出来事が無いため、上は支出だけです。',
      'zh-HK': '收入還記不了：現在沒有任何事件記錄「賣出」這件事，所以上面只有支出。',
      'zh-TW': '收入還記不了：現在沒有任何事件記錄「賣出」這件事，所以上面只有支出。'},
      voices: {
        Voice.heiress: '卖了多少？这个本小姐记不了——账本里根本没有「卖出」这一笔，只有你买了什么。',
        Voice.heiressJa: 'いくら売れたか？それは記録できないのよ。帳面には「売った」なんて一行も無いんだから。',
        Voice.minister: 'I am unable to account for receipts. No entry in the record states that anything was '
            'sold; only that something was bought.',
      },);

  static const cashflowEmpty = CopyLine.withLanguages(
    Translated.authored('这段时间里没有花过钱。'),
    Translated.authored('Nothing was spent in this period.'), also: {
      'ja': 'この期間に使ったお金はありません。',
      'zh-HK': '這段時間裡沒有花過錢。',
      'zh-TW': '這段時間裡沒有花過錢。'},
      voices: {
        Voice.heiress: '这段时间你什么都没买呢。',
        Voice.heiressJa: 'この期間は何も買っていないわね。',
        Voice.minister: 'No expenditure has been recorded in this period.',
      },);

  /// The amounts a window could not count: another currency, or a line with no price to attribute.
  ///
  /// Named rather than folded in, following the rule the recipe costing already states -- a figure that silently
  /// absorbs a line it did not understand is worse than no figure, because somebody will decide on it.
  static const cashflowUnattributed = CopyLine.withLanguages(
    Translated.authored('没有计入'),
    Translated.authored('Not counted'), also: {'ja': '計上せず', 'zh-HK': '沒有計入', 'zh-TW': '沒有計入'});

  static const cashflowDeposit = CopyLine.withLanguages(
    Translated.authored('开局本钱'),
    Translated.authored('Starting float'), also: {'ja': '元手', 'zh-HK': '開局本錢', 'zh-TW': '開局本錢'},
      voices: {
        Voice.heiress: '一开始抽屉里有多少？',
        Voice.heiressJa: '最初に引き出しにいくら入っていたの？',
        Voice.minister: 'The sum with which the bar began.',
      },);

  static const cashflowCounted = CopyLine.withLanguages(
    Translated.authored('现在数的钱'),
    Translated.authored('Counted now'), also: {'ja': '数えた現金', 'zh-HK': '現在數的錢', 'zh-TW': '現在數的錢'},
      voices: {
        Voice.heiress: '你刚数出来的是多少？',
        Voice.heiressJa: 'いま数えた分はいくら？',
        Voice.minister: 'The amount you have just counted.',
      },);

  static const cashflowImplied = CopyLine.withLanguages(
    Translated.authored('账上应有'),
    Translated.authored('The log implies'), also: {'ja': '帳簿上の残高', 'zh-HK': '帳上應有', 'zh-TW': '帳上應有'});

  static const cashflowDifference = CopyLine.withLanguages(
    Translated.authored('差额'),
    Translated.authored('Difference'), also: {'ja': '差額', 'zh-HK': '差額', 'zh-TW': '差額'});

  static const cashflowBalances = CopyLine.withLanguages(
    Translated.authored('对得上。'),
    Translated.authored('The till agrees with the log.'), also: {
      'ja': '帳簿と一致しています。',
      'zh-HK': '對得上。',
      'zh-TW': '對得上。'},
      voices: {
        Voice.heiress: '分毫不差呢。',
        Voice.heiressJa: 'ぴったり一致よ。',
        Voice.minister: 'The count and the record are in agreement.',
      },);

  /// The difference explained without deciding which cause it is, which is the rule `CashReconciliation` sets.
  static const cashflowDifferenceNote = CopyLine.withLanguages(
    Translated.authored('比账上多，通常是有一笔收入没记；比账上少，通常是有一笔支出没记。'),
    Translated.authored('More than the log implies is usually a sale nobody recorded; less is usually a purchase '
        'nobody entered.'), also: {
      'ja': '帳簿より多いのは売上の記録漏れ、少ないのは仕入れの記録漏れが普通です。',
      'zh-HK': '比帳上多，通常是有筆收入沒記；比帳上少，通常是有筆支出沒記。',
      'zh-TW': '比帳上多，通常是有筆收入沒記；比帳上少，通常是有筆支出沒記。'},
      // **Written when this line was added, because it arrived after the prose pool had emptied.** The three
      // batches of 2026-09-29 covered every piece of prose the application had; this sentence came with the
      // takings view and is the only ≥18-character line without a voice. `voice_facts_test` is the constraint
      // they were written to: a register may change the phrasing, the subject or the tone, and may not drop a
      // fact. Both directions and both causes are therefore still in all three.
      voices: {
        Voice.heiress: '抽屉里比账上多，那就是有一笔卖出你忘了记；少了，就是有一笔买进你忘了写。',
        Voice.heiressJa: '引き出しが帳簿より多ければ、売ったのに書き忘れたの。少なければ、買ったのに書き忘れたのよ。',
        Voice.minister: 'A sum greater than the record implies is, as a rule, a sale that went unentered; a sum '
            'less than it implies is a purchase that did.',
      },);

  // Section 12.4's settings, on the Cellar tab beside the device section: both are
  // facts about this device rather than about the cellar.
  /// The heading of the Settings tab itself.
  ///
  /// **Distinct from [settingsTitle], which is the language *subsection's* heading inside it.** The
  /// two read as near-duplicates in a list of keys and are not: one names the screen, the other
  /// names the first group of controls on it.
  static const settingsPageTitle = CopyLine.withLanguages(
    Translated.authored('设置'),
    Translated.authored('Settings'), also: {'ja': '設定', 'zh-HK': '設置', 'zh-TW': '設定'});

  /// Says where the line is drawn, because a reader who came here looking for their devices has
  /// been sent to the wrong tab and should be told rather than left to search.
  static const settingsIntro = CopyLine.withLanguages(
    Translated.authored('这里调的是程序本身。酒窖里发生过什么，在「记录」那一栏。'),
    Translated.authored(
      'These are facts about the program. What has happened to your bottles is on Cellar.',
    ), also: {'ja': 'ここで調整するのはアプリそのものです。酒蔵で起きたことは「記録」のタブにあります。', 'zh-HK': '這裏調的是程式本身。酒窖裏發生過什麼，在「記錄」那一欄。', 'zh-TW': '這裡調的是程式本身。酒窖裡發生過什麼，在「記錄」那一欄。'},
    voices: {
      Voice.heiress: '这里调的是程序本身——酒窖里发生过什么，在「记录」那一栏。一个是设置，一个是账目，别混。',
      Voice.heiressJa: 'ここで調整するのはアプリそのものよ——酒蔵で起きたことは「記録」のタブにあるの。片方は設定、片方は記録、混ぜないこと。',
    
      Voice.minister:
          'These are matters of fact concerning the program. What has befallen your bottles is to be found under Cellar.',},
  );

  // ---------------------------------------------------------------- correcting a bottle

  static const bottleEditTitle = CopyLine.withLanguages(
    Translated.authored('改这一瓶'),
    Translated.authored('Correct this bottle'), also: {'ja': 'この瓶を編集', 'zh-HK': '改這一瓶', 'zh-TW': '改這一瓶'});

  /// Says what this screen is for before anything on it is pressed, because two of the six things it
  /// can do are destructive.
  static const bottleEditHint = CopyLine.withLanguages(
    Translated.authored('名字不是事实，数量是观察：改数量记的是一次重数，不是把数字擦掉重写。'),
    Translated.authored(
      'A name is a label; a quantity is an observation. Changing the quantity records a recount '
      'rather than rewriting a number.',
    ), also: {'ja': '名前は事実ではなく、数量は観察です。数量の変更は数え直しの記録であって、数字を消して書き直すことではありません。', 'zh-HK': '名字不是事實，數量是觀察：改數量記的是一次重數，不是把數字擦掉重寫。', 'zh-TW': '名字不是事實，數量是觀察：改數量記的是一次重數，不是把數字擦掉重寫。'},
    voices: {
      Voice.heiress: '名字不是事实，数量才是观察——改数量，记的是本小姐又数了一遍，不是把数字擦掉重写。',
      Voice.heiressJa: '名前は事実じゃないの、数こそが観察よ——数を直すのは、あたしがもう一度数えたという記録。数字を消して書き直すのとは違うの。',
      Voice.minister:
          'A name is an assertion; a quantity is an observation. Correcting the quantity records '
          'that somebody counted again -- it does not erase the number and write another in its '
          'place.',
    },
  );

  static const bottleEditName = CopyLine.withLanguages(
    Translated.authored('这一瓶叫什么'),
    Translated.authored('What this bottle is called'), also: {'ja': 'この瓶の名前', 'zh-HK': '這一瓶叫什麼', 'zh-TW': '這一瓶叫什麼'});
  static const bottleEditNameSave = CopyLine.withLanguages(
    Translated.authored('改这一瓶'),
    Translated.authored('Rename this bottle'), also: {'ja': 'この瓶を変更', 'zh-HK': '改這一瓶', 'zh-TW': '改這一瓶'});
  static const bottleEditIngredient = CopyLine.withLanguages(
    Translated.authored('这个配料叫什么'),
    Translated.authored('What the ingredient is called'), also: {'ja': 'この材料の名前', 'zh-HK': '這個配料叫什麼', 'zh-TW': '這個配料叫什麼'});
  static const bottleEditIngredientSave = CopyLine.withLanguages(
    Translated.authored('改所有同名'),
    Translated.authored('Rename every one'), also: {'ja': '同名をすべて変更', 'zh-HK': '改所有同名', 'zh-TW': '改所有同名'});
  static const bottleEditAmount = CopyLine.withLanguages(
    Translated.authored('还剩多少'),
    Translated.authored('How much is left'), also: {'ja': '残りどのくらい', 'zh-HK': '還剩多少', 'zh-TW': '還剩多少'});
  static const bottleEditRecount = CopyLine.withLanguages(
    Translated.authored('记一次重数'),
    Translated.authored('Record a recount'), also: {'ja': '数え直しを記録', 'zh-HK': '記一次重數', 'zh-TW': '記一次重數'});
  static const bottleEditDiscard = CopyLine.withLanguages(
    Translated.authored('倒掉这些'),
    Translated.authored('Discard this much'), also: {'ja': 'これを捨てる', 'zh-HK': '倒掉這些', 'zh-TW': '倒掉這些'});
  static const bottleEditPrice = CopyLine.withLanguages(
    Translated.authored('这瓶多少钱'),
    Translated.authored('What it cost'), also: {'ja': 'この瓶の値段', 'zh-HK': '這瓶多少錢', 'zh-TW': '這瓶多少錢'});
  static const bottleEditPriceSave = CopyLine.withLanguages(
    Translated.authored('记一次价格'),
    Translated.authored('Record a price'), also: {'ja': '価格を記録', 'zh-HK': '記一次價格', 'zh-TW': '記一次價格'});
  static const bottleEditRemoveNote = CopyLine.withLanguages(
    Translated.authored('记错了一整行，可以撤回——已经倒过或喝过的不行，那请用「倒掉」。'),
    Translated.authored(
      'A line that should never have been written can be retracted. One that has been poured from '
      'cannot: use Discard for that.',
    ), also: {'ja': '一行まるごと間違えたなら取り消せます。すでに注いだり飲んだりした分は取り消せません。その場合は「捨てる」を使ってください。', 'zh-HK': '記錯了一整行，可以撤回——已經倒過或喝過的不行，那請用「倒掉」。', 'zh-TW': '記錯了一整行，可以撤回——已經倒過或喝過的不行，那請用「倒掉」。'},
    voices: {
      Voice.heiress: '一整行记错了？可以撤回——不过已经倒过或喝过的那些不行。那种情况，请用「倒掉」。',
      Voice.heiressJa: '一行まるごと間違えた？取り消していいわ——でも、もう注いだり飲んだりした分は駄目よ。それは「捨てる」を使って。',
      Voice.minister:
          'A line entered in error may be retracted. Where the bottle has since been poured from '
          'or drunk, retraction is not available, and the discarding entry is the correct one.',
    },
  );
  static const bottleEditRemove = CopyLine.withLanguages(
    Translated.authored('撤回这一行'),
    Translated.authored('Retract this line'), also: {'ja': 'この行を取り消す', 'zh-HK': '撤回這一行', 'zh-TW': '撤回這一行'});
  static const bottleEditRemoveRefused = CopyLine.withLanguages(
    Translated.authored('这瓶已经倒过或喝过，所以不能撤回——请用「倒掉」记剩下的。'),
    Translated.authored(
      'This one has been poured from, so it cannot be retracted. Use Discard for what is left.',
    ), also: {'ja': 'この瓶はすでに注いだか飲んだため、取り消せません。残りは「捨てる」で記録してください。', 'zh-HK': '這瓶已經倒過或喝過，所以不能撤回——請用「倒掉」記剩下的。', 'zh-TW': '這瓶已經倒過或喝過，所以不能撤回——請用「倒掉」記剩下的。'},
    voices: {
      Voice.heiress: '这一瓶已经倒过、也喝过了——撤回可不行。剩下的那些，请用「倒掉」记下来。本小姐不是在为难你，是账目不能乱。',
      Voice.heiressJa: 'この瓶はもう注いだし飲んだの——取り消しはできないわ。残りは「捨てる」で記録して。あたしが意地悪してるんじゃないの、帳尻は合わせたいだけよ。',
      Voice.minister:
          'A line that has already been poured from or drunk cannot be retracted; the record of '
          'what happened is not the record of what we would have preferred. For what remains, '
          'the discarding entry is the appropriate instrument.',
    },
  );
  static const bottleEditFailed = CopyLine.withLanguages(
    Translated.authored('没能记下，再试一次。'),
    Translated.authored('That could not be recorded. Try again.'), also: {'ja': '記録できませんでした。もう一度お試しください。', 'zh-HK': '沒能記下，再試一次。', 'zh-TW': '沒能記下，再試一次。'},
      voices: {
        Voice.heiress: '……没写进去。再来一次，这次我盯着。',
        Voice.heiressJa: '……書き込めなかったの。もう一度やって。今度は私が見ているから。',
        Voice.minister:
            'The entry was not, on this occasion, recorded. A further attempt would be advisable.',
      },);

  // ---------------------------------------------------------------- about

  /// The About tab's heading, and the sentence under it.
  static const aboutHeading = CopyLine.withLanguages(
    Translated.authored('关于空庭'),
    Translated.authored('About Hollow Court'), also: {'ja': '空庭について', 'zh-HK': '關於空庭', 'zh-TW': '關於空庭'});

  /// What the program is, in one sentence, for somebody who opened this screen to find out.
  ///
  /// Section 1.2's non-goals are the honest half of this: no account, no cloud, no community. A
  /// reader who wants to know what they have installed is better served by that than by a feature
  /// list.
  static const aboutWhat = CopyLine.withLanguages(
    Translated.authored('一个你真正拥有的酒窖：三端、离线、没有账号，也没有服务器。'),
    Translated.authored(
      'A cellar you actually own: three platforms, offline, no account and no server.',
    ), also: {'ja': '本当に自分のものになる酒蔵。三つの環境、オフライン、アカウントもサーバーもありません。', 'zh-HK': '一個你真正擁有的酒窖：三端、離線、沒有賬號，也沒有服務器。', 'zh-TW': '一個你真正擁有的酒窖：三端、離線、沒有賬號，也沒有伺服器。'},
    voices: {
      Voice.heiress: '一个你真正拥有的酒窖——三端、离线、没有账号，也没有服务器。哼，别人的东西随时能收回去，本小姐这个不会。',
      Voice.heiressJa: '本当にあなたのものになる酒蔵よ——三つの環境、オフライン、アカウントもサーバーもないの。ふん、人のものはいつでも取り上げられるけど、これは違うわ。',
    
      Voice.minister:
          'A cellar of your own: three platforms, offline, with no account and no server.',},
  );

  /// **Who publishes this, on every platform that shows such a thing.** The `.msi` carries it as
  /// `Manufacturer`, the AppImage's desktop entry as `X-AppImage-Vendor`, and here as a row -- one name in three
  /// places rather than three names that drift.
  static const aboutPublisher = CopyLine.withLanguages(
    Translated.authored('发行'), Translated.authored('Published by'),
    also: {'ja': '発行', 'zh-HK': '發行', 'zh-TW': '發行'});

  /// **The motto, and it is not translated because a motto is a proper noun.** Shown beside the publisher, and
  /// set as the installer's comment on Windows, which is the only place that platform offers for one.
  static const aboutMotto = 'F.D.C.U.S.';

  /// The repository, said plainly, because a reader who wants the source should not have to guess a URL.
  static const aboutRepository = CopyLine.withLanguages(
    Translated.authored('源码'),
    Translated.authored('Source'),
    also: {'ja': 'ソース', 'zh-HK': '原始碼', 'zh-TW': '原始碼'});

  /// It says what a tap will do rather than what the link is: the address itself is shown when a tap cannot
  /// work, which is more useful than repeating it while it can.
  static const aboutRepositoryHint = CopyLine.withLanguages(
    Translated.authored('在浏览器里打开仓库'),
    Translated.authored('Opens the repository in your browser'),
    also: {'ja': 'ブラウザでリポジトリを開きます', 'zh-HK': '在瀏覽器裡打開倉庫', 'zh-TW': '在瀏覽器裡開啟倉庫'});

  /// The support link, and **the first line in this application that is not the same sentence in every
  /// language.**
  ///
  /// **Why it has to be per-language rather than translated.** Afdian is a Chinese platform, and that decides what
  /// the sentence is *for*. A Chinese reader is being told *you may support this if you want to*; a reader in
  /// another language is being told *this is where support goes, and it is a Chinese site, so your card may not
  /// work there*. Those are two different sentences, and translating either one into the other language would
  /// produce a sentence about the wrong reader. `CopyLine.localised` exists for exactly this and had no caller
  /// until now.
  ///
  /// **It is the label tonight, and it was a sentence first.** Written as prose it overflowed the settings row by
  /// 242 pixels -- that row is a label and an icon on one line, and a paragraph in the label slot is a paragraph
  /// that cannot fit. So the label is the word 支持 and the sentence goes below it in the hint slot, which is what
  /// the source row above does and what section 12.9.1's row convention asks for.
  /// **Where the author is, and every one of these is a fact rather than a request.**
  ///
  /// The first of them was 支持 / Support, written when the row pointed at a donation page, and the change of
  /// word is the whole of what changed when the owner replaced that address on 2026-09-30.
  ///
  /// **Why the word matters and not only the spirit.** PCL covers the two pieces in `art/`, and its
  /// Article 3.2(1) forbids collecting compensation of any kind under any name, *even where the use is not for
  /// profit* -- 「非営利目的であっても、あらゆる名目の対価を徴収しまたは報酬を受けてはならない」. A row labelled
  /// 支持 beside a work containing that artwork is a request for exactly that; 作者 is not, because nothing
  /// flows from the work to its author.
  ///
  /// **None of the three carries a voice, and that is the rule rather than an oversight.** Section 十二 says a
  /// voice belongs to a sentence and not to a label: these are the names of things, like 琥珀庭 or a unit's id.
  /// The hint that used to sit under the first one is gone too -- bilibili, 网易云音乐 and SoundCloud each name
  /// themselves, and prose explaining what a music profile is would be the interface telling a reader something
  /// they already know.
  static const aboutAuthor = CopyLine.localised({
    'zh-Hans': '作者',
    'zh-HK': '作者',
    'zh-TW': '作者',
    'en': 'The author',
    'ja': '作者',
  });

  /// The two music sites, **spelled the way each site spells itself.** 网易云音乐 is the name its own readers
  /// use and an English transliteration would be a name nobody calls it; SoundCloud is one word with two capitals
  /// in the middle, which is its own spelling and not a styling choice made here.
  static const aboutNetease = CopyLine.localised({
    'zh-Hans': '网易云音乐',
    'zh-HK': '網易雲音樂',
    'zh-TW': '網易雲音樂',
    'en': 'NetEase Cloud Music',
    'ja': 'NetEase Cloud Music',
  });

  static const aboutSoundcloud = CopyLine.localised({
    'zh-Hans': 'SoundCloud',
    'zh-HK': 'SoundCloud',
    'zh-TW': 'SoundCloud',
    'en': 'SoundCloud',
    'ja': 'SoundCloud',
  });

  /// The address itself, shown when the browser cannot be reached -- the same treatment the source link gets.
  static const aboutSupportFailed = CopyLine.withLanguages(
    Translated.authored('这台设备上没有能打开浏览器的程序。地址是：'),
    Translated.authored('This device has nothing capable of opening a browser. The address is:'),
    also: {
      'ja': 'この端末にはブラウザを開けるものがないの。宛先はこちら：',
      'zh-HK': '這台裝置上沒有能打開瀏覽器的程式。地址是：',
      'zh-TW': '這台裝置上沒有能開啟瀏覽器的程式。地址是：'});

  /// Shown when there is nothing that can open a browser, with the address beside it so the reader can still
  /// get there. A link that silently does nothing is the same failure as a switch that moves and leads nowhere.
  static const aboutRepositoryFailed = CopyLine.withLanguages(
    Translated.authored('这台设备上没有能打开浏览器的程序。地址是：'),
    Translated.authored('This device has nothing that can open a browser. The address is:'),
    also: {
      'ja': 'この端末にはブラウザを開けるものがありません。宛先はこちらです：',
      'zh-HK': '這台裝置上沒有能打開瀏覽器的程式。位址是：',
      'zh-TW': '這台裝置上沒有能開啟瀏覽器的程式。位址是：',
    },
    voices: {
      Voice.heiress: '这台设备上没有能打开浏览器的程序。哼，本小姐也没辙——地址是：',
      Voice.heiressJa: 'この端末にはブラウザを開けるものがないの。ふん、あたしにもどうにもならないわ——宛先はこちら：',
    
      Voice.minister:
          'This device has nothing capable of opening a browser. The address is:',},
  );

  static const aboutVersion = CopyLine.withLanguages(
    Translated.authored('版本'),
    Translated.authored('Version'), also: {'ja': 'バージョン', 'zh-HK': '版本', 'zh-TW': '版本'});

  static const aboutCommit = CopyLine.withLanguages(
    Translated.authored('构建自提交'),
    Translated.authored('Built from commit'), also: {'ja': 'ビルド元のコミット', 'zh-HK': '構建自提交', 'zh-TW': '構建自提交'});

  /// Shown when the build did not record a commit, which is every debug run and every test.
  ///
  /// **"unknown" rather than a plausible-looking hash.** A build that cannot say which source it
  /// came from should say so; a substituted value is a claim nobody can check.
  static const aboutCommitUnknown = 'unknown';

  static const aboutNaming = CopyLine.withLanguages(
    Translated.authored('一个名字，三种写法：中文是「空庭」，英文是 Hollow Court，日文是「虚ろな庭」。'),
    Translated.authored('One name in three scripts: 空庭, Hollow Court, 虚ろな庭 -- whichever the reader reads.'),
    also: {
      'zh-HK': '一個名字，三種寫法：中文是「空庭」，英文是 Hollow Court，日文是「虚ろな庭」。',
      'zh-TW': '一個名字，三種寫法：中文是「空庭」，英文是 Hollow Court，日文是「虚ろな庭」。',
      'ja': '一つの名前、三つの書き方。中国語では「空庭」、英語では Hollow Court、日本語では「虚ろな庭」。',
    },
    voices: {
      Voice.heiress: '一个名字，三种写法：中文是「空庭」，英文是 Hollow Court，日文是「虚ろな庭」——本小姐的名字可不止一种念法。',
      Voice.heiressJa: '一つの名前、三つの書き方——中国語では「空庭」、英語では Hollow Court、日本語では「虚ろな庭」。あたしの名前は一つじゃないのよ。',
      Voice.minister:
          'One name, three scripts: 空庭 in Chinese, Hollow Court in English, 虚ろな庭 in Japanese. It '
          'is a matter of which the reader reads, and no rendering takes precedence over '
          'another.',
    },
  );
  /// The icon's typeface, said out loud because a licence is a fact about what a reader has.
  ///
  /// permission, so this sentence is a statement rather than a caveat. It replaced a face whose licence allowed
  /// personal builds only, which is not a thing to discover after shipping.
  static const aboutTypeface = CopyLine.withLanguages(
    Translated.authored('图标由本项目自行绘制，不借用任何字体'),
    Translated.authored('The mark is drawn in this repository; no typeface is borrowed for it'),
    voices: {
      Voice.heiress: '图标是本小姐自己画的，才没借谁的字体呢。',
      Voice.minister: "The mark is drawn in this house. We have not, on this occasion, availed ourselves of anybody else's typeface.",
      Voice.heiressJa: 'アイコンはあたしが自分で描いたの。誰かのフォントなんて借りてないわよ。',
    },
    also: {
      'ja': 'アイコンは本リポジトリで描画しており、フォントを借用していません',
      'zh-HK': '圖示由本專案自行繪製，不借用任何字體',
      'zh-TW': '圖示由本專案自行繪製，不借用任何字體',
    });

  /// **The credit PCL asks for, in PCL's own words, and the one string in this application that is not ours to
  /// word.**
  ///
  /// `art/miku-wide.svg` and `art/miku-tall.svg` depict 初音ミク, a character of Crypton Future Media, INC., used
  /// under the Piapro Character Licence. Article 3.3 asks for the credit below to be shown alongside the work --
  /// 「表示するよう努めるものとします」, an obligation to endeavour rather than a condition, honoured anyway -- and
  /// the guideline gives the sentence verbatim:
  ///
  /// > この作品はピアプロ・キャラクター・ライセンスに基づいてクリプトン・フューチャー・メディア株式会社の
  /// > キャラクター「初音ミク」を描いたものです。
  ///
  /// **So the Japanese is quoted and not translated into this project's voice, and the other languages paraphrase
  /// it.** A credit is not copy: it exists to name a rights holder, and rewording it to sound like the rest of the
  /// interface would weaken the one thing it does. The character's name is 初音ミク in every language for the same
  /// reason -- it is the name the rights holder uses.
  ///
  /// **The Latin reading is added beside it in the two lines that are not the licensed wording**, on the owner's
  /// instruction of 2026-09-30: *「可以用 Hatsune Miku 进行注释」*. A reader who cannot read katakana was
  /// otherwise being given no way to know who the credit is about, and a credit nobody can resolve is decoration
  /// rather than a credit. **The Japanese line does not gain it**, because that line is the sentence the licence
  /// provides verbatim (Article 3.3) and the character's name in it is 「初音ミク」 and nothing else. The Latin
  /// reading is not a translation of the name; it is how the same name is written in Latin letters, which is why
  /// it is a parenthetical rather than a replacement.
  ///
  /// **The link is the summary page rather than the licence itself**, because the summary is what a reader should land on;
  /// `docs/licensing.md` is where the clauses themselves are quoted for anyone checking.
  static const aboutCharacterCredit = '''
この作品はピアプロ・キャラクター・ライセンスに基づいて
クリプトン・フューチャー・メディア株式会社のキャラクター「初音ミク」を描いたものです。

This work depicts 初音ミク (Hatsune Miku), a character of Crypton Future Media, INC., under the Piapro
Character Licence.
https://piapro.jp/license/pcl/summary

本作品描绘的是 Crypton Future Media, INC. 的角色「初音ミク」（Hatsune Miku），依ピアプロ・キャラクター・ライセンス使用。''';


  // ---------------------------------------------------------------- display

  static const displayHeading = CopyLine.withLanguages(
    Translated.authored('界面样式'),
    Translated.authored('Interface'), also: {'ja': '表示スタイル', 'zh-HK': '介面樣式', 'zh-TW': '介面樣式'});

  static const displayTextSize = CopyLine.withLanguages(
    Translated.authored('字号'),
    Translated.authored('Text size'), also: {'ja': '文字サイズ', 'zh-HK': '字號', 'zh-TW': '字號'});

  /// Says whose scale this is, because the platform has one too and the two multiply.
  static const displayTheme = CopyLine.withLanguages(
    Translated.authored('主题'),
    Translated.authored('Theme'), also: {'ja': 'テーマ', 'zh-HK': '主題', 'zh-TW': '主題'});

  /// The four themes, named for what they look like rather than for their ids.
  /// **How the application speaks.** Not a language: the same language, in a register the reader may choose.
  /// See `l10n/voice.dart` for the two voices and for the rule about which language each answers in.
  static const displayVoice = CopyLine.withLanguages(
    Translated.authored('说话方式'),
    Translated.authored('Voice'),
    also: {'ja': '話し方', 'zh-HK': '說話方式', 'zh-TW': '說話方式'});
  static const voicePlain = CopyLine.withLanguages(
    Translated.authored('平常'),
    Translated.authored('Plain'),
    also: {'ja': 'ふつう', 'zh-HK': '平常', 'zh-TW': '平常'});

  /// **The worlds are named for colours now, not for courts, and that is the owner's restructure of 2026-10-01.**
  ///
  /// They used to be places -- 琥珀庭, 白庭, 冬庭 -- with 永遠の歌姫 as the one title among them, and an earlier note
  /// here argued that the three courts and the one epithet were different kinds of name. **The owner has removed
  /// that distinction by naming three of them after what they look like.** The old names had also stopped describing
  /// their own colours -- 冬庭 was a deep blue night and never read as winter -- so the rename corrects an
  /// inaccuracy as well as a taxonomy.
  ///
  /// **The stored `name` on each palette is deliberately NOT renamed with them.** Those strings are a wire format no
  /// reader ever sees (see `HollowPaletteValue.name`), so renaming one would reset the theme of everybody who had
  /// chosen it, in exchange for a cosmetic change. `honeyed` still means 銅鳴 and `winter` still means 群青 in the
  /// settings file; only what a reader sees moves.
  static const themeAmber = CopyLine.withLanguages(
    Translated.authored('銅鳴'),
    Translated.authored('Brazen Bell'),
    also: {'ja': '銅鳴', 'zh-HK': '銅鳴', 'zh-TW': '銅鳴'});

  /// **Scheduled for removal, and kept until `CL` exists.** See `docs/memo-themes.md`: its `#F4F1E9` and the
  /// planned 宇宙拿铁's `FFF8E7` are under 1% apart in every channel, so two light worlds cannot both ship. It stays
  /// until the world that replaces it is built, because removing it now would leave this application with **no light
  /// theme at all** -- a worse state than a duplicate, and it is also the only world the light-mode contrast rules
  /// are exercised against.
  static const themeWhiteCourt = CopyLine.withLanguages(
    Translated.authored('白庭'),
    Translated.authored('White Court'),
    also: {'ja': '白の庭', 'zh-HK': '白庭', 'zh-TW': '白庭'});

  static const themeWinter = CopyLine.withLanguages(
    Translated.authored('群青'),
    Translated.authored('Ultramarine'),
    also: {'ja': '群青', 'zh-HK': '群青', 'zh-TW': '群青'});

  /// **The fifth world, and the first whose ground is a saturated colour rather than a near-black.**
  ///
  /// 銅鳴, 群青 and 永遠の歌姫 all sit between five and seventeen RGB units of each other -- they are told apart by
  /// their accents rather than their grounds, and their luminance ratios are 1.00 to 1.01, meaning they are the same
  /// brightness. **酒红 is the first that is a different colour to look at rather than a different tint**: 79 units
  /// from 銅鳴, further than any two existing worlds are from each other. Worth recording because it changes what
  /// the theme list *is* -- until now a reader chose between four shades of dark, and now one of the rooms is red.
  static const themeWine = CopyLine.withLanguages(
    Translated.authored('酒红'),
    Translated.authored('Wine Red'),
    also: {'ja': '酒紅', 'zh-HK': '酒紅', 'zh-TW': '酒紅'});

  /// 永遠の歌姫's name. The note that used to sit here described a taxonomy this rename has removed -- it said the
  /// others were courts and this one was a title, which is no longer the shape of the list. What survives is the part
  /// that was never about courts: **no voice is written for it**, because a name is a label rather than a sentence,
  /// and section 十二's rule is that a voice belongs to a sentence and not to a label. The colour names have none
  /// either.
  static const themeEternalDiva = CopyLine.withLanguages(
    Translated.authored('永遠の歌姫'),
    Translated.authored('The Eternal Diva'),
    also: {'ja': '永遠の歌姫', 'zh-HK': '永遠の歌姫', 'zh-TW': '永遠の歌姫'});


  static const displayTextSizeNote = CopyLine.withLanguages(
    Translated.authored('在系统字号之上再放大或缩小。'),
    Translated.authored('Applied on top of your system text size.'), also: {'ja': 'システムの文字サイズを基準に拡大・縮小します。', 'zh-HK': '在系統字號之上再放大或縮小。', 'zh-TW': '在系統字號之上再放大或縮小。'});

  static const textSizeSmall = CopyLine.withLanguages(
    Translated.authored('小'),
    Translated.authored('Small'), also: {'ja': '小', 'zh-HK': '小', 'zh-TW': '小'});
  static const textSizeStandard = CopyLine.withLanguages(
    Translated.authored('标准'),
    Translated.authored('Standard'), also: {'ja': '標準', 'zh-HK': '標準', 'zh-TW': '標準'});
  static const textSizeLarge = CopyLine.withLanguages(
    Translated.authored('大'),
    Translated.authored('Large'), also: {'ja': '大', 'zh-HK': '大', 'zh-TW': '大'});
  static const textSizeExtraLarge = CopyLine.withLanguages(
    Translated.authored('特大'),
    Translated.authored('Extra large'), also: {'ja': '特大', 'zh-HK': '特大', 'zh-TW': '特大'});

  // ---------------------------------------------------------------- developer tools

  static const developerHeading = CopyLine.withLanguages(
    Translated.authored('开发者工具'),
    Translated.authored('Developer tools'), also: {'ja': '開発者ツール', 'zh-HK': '開發者工具', 'zh-TW': '開發者工具'});

  /// What this screen is for, said before anything on it is read.
  static const developerIntro = CopyLine.withLanguages(
    Translated.authored('这些是这个构建自己的状态：日志、外部连接、诊断。改了东西再打开这里。'),
    Translated.authored(
      'Facts about this build: the log, the outside connections, the diagnostics. Look here after changing '
      'something.',
    ), also: {'ja': 'ここにあるのはこのビルド自身の状態です。ログ、接続点、診断。何かを変えたらここを開いてください。', 'zh-HK': '這些是這個構建自己的狀態：日誌、接縫、診斷。改了東西再打開這裏。', 'zh-TW': '這些是這個構建自己的狀態：日誌、接縫、診斷。改了東西再開啟這裡。'},
    voices: {
      Voice.heiress: '这里放的是这个构建自己的状态：日志、外部连接、诊断。改完东西再回来开这一页——不看就改，回头可别来问本小姐为什么。',
      Voice.heiressJa: 'ここにあるのはこのビルド自身の状態よ：ログ、接続点、診断。何か変えたらもう一度ここを開くの——見ずに変えて、あとであたしに文句を言うのはなしよ。',
    
      Voice.minister:
          'Matters of fact concerning this build: the log, the outside connections, the diagnostics. It is here that one looks after changing something.',},
  );

  static const developerLogHeading = CopyLine.withLanguages(
    Translated.authored('事件日志'),
    Translated.authored('Event log'), also: {'ja': 'イベントログ', 'zh-HK': '事件日誌', 'zh-TW': '事件日誌'});

  static const developerLogPath = CopyLine.withLanguages(
    Translated.authored('文件'),
    Translated.authored('File'), also: {'ja': 'ファイル', 'zh-HK': '檔案', 'zh-TW': '檔案'});
  static const developerLogEvents = CopyLine.withLanguages(
    Translated.authored('事件'),
    Translated.authored('Events'), also: {'ja': 'イベント', 'zh-HK': '事件', 'zh-TW': '事件'});
  static const developerLogBytes = CopyLine.withLanguages(
    Translated.authored('字节'),
    Translated.authored('Bytes'), also: {'ja': 'バイト', 'zh-HK': '字節', 'zh-TW': '位元組'});
  static const developerLogNode = CopyLine.withLanguages(
    Translated.authored('本机节点'),
    Translated.authored('This node'), also: {'ja': 'この端末のノード', 'zh-HK': '本機節點', 'zh-TW': '本機節點'});

  /// The adapter seams, which are declarations rather than features.
  ///
  /// **This is where the four "not implemented in this build" rows went.** They were on the Cellar
  /// tab, under 设备与同步, phrased as an apology; a reader opening that screen was told four times
  /// that something did not exist. The seams are real -- they are in the code, they have kinds and a
  /// registry -- so what belongs on a reader's screen is nothing, and what belongs here is what they
  /// actually are: four doors this build does not open, listed so a developer can see the shape.
  static const developerSeamsHeading = CopyLine.withLanguages(
    Translated.authored('外部连接'),
    Translated.authored('Outside connections'),
    also: {'ja': '外部接続', 'zh-HK': '外部連接', 'zh-TW': '外部連接'});

  static const developerSeamsNote = CopyLine.withLanguages(
    Translated.authored('默认全部关闭；这里只列出本构建真能用的那些。'),
    Translated.authored(
      'Off by default, and only the ones this build can actually use are listed here.',
    ),
    voices: {
      Voice.heiress: '默认都关着。这里只列本构建真能用的那几个——做不到的事，本小姐可不会替你摆出来。',
      Voice.minister: 'They are, I need hardly add, disabled by default; and only those this build can actually operate are listed.',
      Voice.heiressJa: '既定では全部オフよ。ここには、このビルドで本当に使えるものしか並べてないんだから。',
    },
    also: {'ja': '既定ではすべて無効。ここには、このビルドで実際に使えるものだけを並べています。', 'zh-HK': '預設全部關閉；這裡只列出本構建真能用的那些。', 'zh-TW': '預設全部關閉；這裡只列出本建置真能用的那些。'});

  static const seamAvailable = CopyLine.withLanguages(
    Translated.authored('已包含'),
    Translated.authored('included'), also: {'ja': '含む', 'zh-HK': '已包含', 'zh-TW': '已包含'});
  static const seamAbsent = CopyLine.withLanguages(
    Translated.authored('未包含'),
    Translated.authored('not included'), also: {'ja': '含まない', 'zh-HK': '未包含', 'zh-TW': '未包含'});

  // ---------------------------------------------------------------- integrity

  /// The heading for the reader's own archives.
  ///
  /// **A noun rather than a verb**, unlike 检查完整性 beside it: that section does something when pressed, and this one
  /// is a state of affairs -- there are packages, or there are not, and the reader decides which are in play.
  static const archiveHeading = CopyLine.withLanguages(
    Translated.authored('归档'),
    Translated.authored('Archives'),
    voices: {
      Voice.heiress: '更早的那些，本小姐替你收在文件里了——要看就挑一份。',
      Voice.heiressJa: 'もっと前のものは、ファイルにしまってあるわ——見たいなら選びなさい。',
      Voice.minister: 'The earlier years are kept in files. One selects which to consult.',
    },
    also: {'ja': 'アーカイブ', 'zh-HK': '歸檔', 'zh-TW': '歸檔'},
  );

  /// What an archive is, said before anything else on the section.
  ///
  /// **The one sentence that has to be right**, because the whole feature rests on it: nothing is deleted, and the
  /// reader's history is in a file rather than in this application. A reader who believes the second half has an
  /// obligation to look after that file, and is entitled to know it.
  static const archiveExplain = CopyLine.withLanguages(
    Translated.authored(
      '早于五年的记录可以收进一个文件，放在你的文档里。收走的那些不会被删——它们从工作日志里搬出去，'
      '历史仍然是完整的。',
    ),
    Translated.authored(
      'Records older than five years can be moved into a file in your documents. Nothing is deleted: they leave '
      'the working log, and the history stays complete.',
    ),
    also: {
      'ja': '五年より前の記録は、書類フォルダのファイルに移せます。消えるのではなく、作業ログから出るだけで、'
          '履歴は完全なままです。',
      'zh-HK': '早過五年嘅記錄可以收進一個文件，放喺你嘅文件夾。收走嘅唔會刪——佢哋由工作日誌搬出去，'
          '歷史仍然完整。',
      'zh-TW': '早於五年的記錄可以收進一個檔案，放在你的文件裡。收走的那些不會被刪——它們從工作日誌搬出去，'
          '歷史仍然是完整的。',
    },
  );

  /// Shown when there is nothing old enough to archive.
  static const archiveNothingOld = CopyLine.withLanguages(
    Translated.authored('还没有早于五年的记录，暂时没什么可收的。'),
    Translated.authored('Nothing is older than five years yet, so there is nothing to move.'),
    also: {
      'ja': 'まだ五年より前の記録がないので、移すものはありません。',
      'zh-HK': '暫時未有早過五年嘅記錄，冇嘢好收。',
      'zh-TW': '還沒有早於五年的記錄，暫時沒什麼可收的。',
    },
  );

  /// What the button does, and it says what will be moved rather than "archive now".
  static String archiveMovePrompt(int count, String through) => CopyLine.withLanguages(
    Translated.authored('把到 $through 为止的 $count 条收进一个文件'),
    Translated.authored('Move $count events, up to $through, into a file'),
    also: {
      'ja': '$through までの $count 件をファイルに移す',
      'zh-HK': '把到 $through 為止嘅 $count 條收進一個文件',
      'zh-TW': '把到 $through 為止的 $count 條收進一個檔案',
    },
  ).textFor('zh-Hans');

  /// The heading over the list of packages.
  static const archiveWhich = CopyLine.withLanguages(
    Translated.authored('读哪些'),
    Translated.authored('Which to read'),
    voices: {
      Voice.heiress: '要看哪几年的，自己挑。不挑就只有最近这些。',
      Voice.heiressJa: 'どの年を見るか、自分で選びなさい。選ばなければ最近の分だけよ。',
      Voice.minister: 'One chooses which years to consult. Unchosen, only the recent ones are read.',
    },
    also: {'ja': 'どれを読むか', 'zh-HK': '讀邊幾份', 'zh-TW': '讀哪幾份'},
  );

  /// What the list says when there are no packages at all.
  static const archiveNone = CopyLine.withLanguages(
    Translated.authored('一个归档都还没有。'),
    Translated.authored('There are no archives yet.'),
    also: {'ja': 'アーカイブはまだありません。', 'zh-HK': '一個歸檔都未有。', 'zh-TW': '一個歸檔都還沒有。'},
  );

  /// The two controls the owner asked for by name.
  static const archiveSelectAll = CopyLine.withLanguages(
    Translated.authored('全选'),
    Translated.authored('Select all'),
    also: {'ja': 'すべて選ぶ', 'zh-HK': '全選', 'zh-TW': '全選'},
  );

  static const archiveInvert = CopyLine.withLanguages(
    Translated.authored('反选'),
    Translated.authored('Invert'),
    also: {'ja': '選択を反転', 'zh-HK': '反選', 'zh-TW': '反選'},
  );

  /// How many events the selected packages hold, said under the list.
  static String archiveAttached(int packages, int events) => CopyLine.withLanguages(
    Translated.authored('已挂上 $packages 份，共 $events 条旧记录。'),
    Translated.authored('$packages attached, holding $events older events.'),
    also: {
      'ja': '$packages 件を接続中、古い記録 $events 件。',
      'zh-HK': '掛上咗 $packages 份，共 $events 條舊記錄。',
      'zh-TW': '已掛上 $packages 份，共 $events 條舊記錄。',
    },
  ).textFor('zh-Hans');

  /// Shown on a package this build cannot use, with the reason.
  static String archiveUnusable(String reason) => CopyLine.withLanguages(
    Translated.authored('这一份读不出来：$reason'),
    Translated.authored('This one cannot be read: $reason'),
    also: {
      'ja': 'これは読めません：$reason',
      'zh-HK': '呢份讀唔出：$reason',
      'zh-TW': '這一份讀不出來：$reason',
    },
  ).textFor('zh-Hans');

  static const integrityHeading = CopyLine.withLanguages(
    Translated.authored('检查完整性'),
    Translated.authored('Check integrity'), also: {'ja': '整合性の検査', 'zh-HK': '檢查完整性', 'zh-TW': '檢查完整性'});

  static const integrityExplain = CopyLine.withLanguages(
    Translated.authored(
      '把日志从头读一遍，报告读不懂的行、重复的时钟、指向不存在瓶子的事件。',
    ),
    Translated.authored(
      'Reads the whole log and reports lines it cannot parse, repeated clocks, and events naming a '
      'bottle that was never added.',
    ), also: {'ja': 'ログを最初から読み直し、読めない行、重複した時計、存在しない瓶を指すイベントを報告します。', 'zh-HK': '把日誌從頭讀一遍，報告讀不懂的行、重複的時鐘、指向不存在瓶子的事件。', 'zh-TW': '把日誌從頭讀一遍，報告讀不懂的行、重複的時鐘、指向不存在瓶子的事件。'});

  static const integrityRun = CopyLine.withLanguages(
    Translated.authored('开始检查'),
    Translated.authored('Run the check'), also: {'ja': '検査を始める', 'zh-HK': '開始檢查', 'zh-TW': '開始檢查'});

  static const integrityRunning = CopyLine.withLanguages(
    Translated.authored('正在读……'),
    Translated.authored('Reading...'), also: {'ja': '読み込み中……', 'zh-HK': '正在讀……', 'zh-TW': '正在讀……'});

  static const integrityClean = CopyLine.withLanguages(
    Translated.authored('日志干净，没有发现问题。'),
    Translated.authored('The log is clean. Nothing was found.'), also: {'ja': 'ログは綺麗で、問題は見つかりませんでした。', 'zh-HK': '日誌乾淨，沒有發現問題。', 'zh-TW': '日誌乾淨，沒有發現問題。'},
      voices: {
        Voice.heiress: '我逐条看过来了——没有一处不对。不必谢我。',
        Voice.heiressJa: '一本ずつ見てきたわ。おかしなところは一箇所もない。礼なんていいのよ。',
        Voice.minister:
            'The log has been examined in full and no irregularity has been identified.',
      },);

  static const integrityFound = CopyLine.withLanguages(
    Translated.authored('发现了问题，逐条列在下面。'),
    Translated.authored('Something was found, listed below.'), also: {'ja': '問題が見つかりました。以下に一件ずつ挙げます。', 'zh-HK': '發現了問題，逐條列在下面。', 'zh-TW': '發現了問題，逐條列在下面。'},
      voices: {
        Voice.heiress: '有几处不对。都写在下面了，别想蒙混过去。',
        Voice.heiressJa: 'おかしなところがあるわ。下に全部書いてあるから、見てちょうだい。',
        Voice.minister:
            'Certain irregularities have been identified and are set out below.',
      },);

  static const integrityUnreadable = CopyLine.withLanguages(
    Translated.authored('读不懂的行'),
    Translated.authored('Unreadable lines'), also: {'ja': '読めない行', 'zh-HK': '讀不懂的行', 'zh-TW': '讀不懂的行'});
  static const integrityRepeated = CopyLine.withLanguages(
    Translated.authored('重复的时钟读数'),
    Translated.authored('Repeated clock readings'), also: {'ja': '重複した時計の読み', 'zh-HK': '重複的時鐘讀數', 'zh-TW': '重複的時鐘讀數'});
  static const integrityOrphaned = CopyLine.withLanguages(
    Translated.authored('指向不存在的瓶子'),
    Translated.authored('Naming a bottle that was never added'), also: {'ja': '存在しない瓶を指すもの', 'zh-HK': '指向不存在的瓶子', 'zh-TW': '指向不存在的瓶子'});
  static const integrityDuplicateAdds = CopyLine.withLanguages(
    Translated.authored('同一瓶子被记了两次'),
    Translated.authored('The same bottle added twice'), also: {'ja': '同じ瓶が二度記録されている', 'zh-HK': '同一瓶子被記了兩次', 'zh-TW': '同一瓶子被記了兩次'});
  static const integrityCounted = CopyLine.withLanguages(
    Translated.authored('读过的行'),
    Translated.authored('Lines read'), also: {'ja': '読んだ行', 'zh-HK': '讀過的行', 'zh-TW': '讀過的行'});

  /// Shown when there is no log to check, which is a first run rather than a failure.
  static const integrityNoLog = CopyLine.withLanguages(
    Translated.authored('还没有日志可查。'),
    Translated.authored('There is no log to check yet.'), also: {'ja': 'まだ調べるログがありません。', 'zh-HK': '還沒有日誌可查。', 'zh-TW': '還沒有日誌可查。'},
      voices: {
        Voice.heiress: '查什么？你还什么都没记呢。',
        Voice.heiressJa: '調べるって言われても、まだ何も記録していないじゃない。',
        Voice.minister:
            'There is at present no record for which an examination could be undertaken.',
      },);

  static const settingsTitle = CopyLine.withLanguages(
    Translated.authored('语言与字幕'),
    Translated.authored('Language and subtitles'), also: {'ja': '言語と字幕', 'zh-HK': '語言與字幕', 'zh-TW': '語言與字幕'});
  static const settingsPrimary = CopyLine.withLanguages(
    Translated.authored('主语言'),
    Translated.authored('Primary language'), also: {'ja': '主言語', 'zh-HK': '主語言', 'zh-TW': '主語言'});
  static const settingsSecondary = CopyLine.withLanguages(
    Translated.authored('副语言'),
    Translated.authored('Secondary language'), also: {'ja': '副言語', 'zh-HK': '副語言', 'zh-TW': '副語言'});
  static const settingsDualCopy = CopyLine.withLanguages(
    Translated.authored('双字幕'),
    Translated.authored('Dual copy'), also: {'ja': '二言語併記', 'zh-HK': '雙字幕', 'zh-TW': '雙字幕'});
  /// **每条设置都要说清「代价或理由」**（DESIGN.md 12.9.1，借自 a rhythm game 的设置行四件套：
  /// `*Label` + `*Description` + `*Text` + `*Button`，而说明是结构里的必备件）。这三条补的是原先**只有标签**
  /// 的三处：主语言、副语言、双字幕。
  static const settingsPrimaryNote = CopyLine.withLanguages(
    Translated.authored('主语言决定界面与库的文字默认用哪一种，也是找不到译文时的回退目标。'),
    Translated.authored(
      'The primary language is what text is shown in by default, and what a missing translation falls '
      'back to.',
    ),
    also: {
      'zh-HK': '主語言決定介面與庫的文字預設用哪一種，也是找不到譯文時的回退目標。',
      'zh-TW': '主語言決定介面與庫的文字預設用哪一種，也是找不到譯文時的回退目標。',
      'ja': '主言語は、画面とライブラリの文字を既定でどの言語で出すか、そして訳が無いときの代替先を決めます。',
    },
    voices: {
      Voice.heiress: '主语言决定界面与库的文字默认用哪一种——它同时还是找不到译文时的回退目标。换句话说：选它，就是在选那个兜底的。',
      Voice.heiressJa: '主言語は、画面とライブラリの文字を既定でどの言語で出すかを決めるの——そして訳が無いときの代替先でもあるわ。つまり、それを選ぶというのは受け皿を選ぶということよ。',
    
      Voice.minister:
          'The primary language determines the language in which text is shown by default, and it is to this that a missing translation falls back.',},
  
  );

  static const settingsSecondaryNote = CopyLine.withLanguages(
    Translated.authored('副语言只在开启双字幕时出现；两边选了同一种时，让位的是它。'),
    Translated.authored(
      'The secondary line appears only when dual copy is on, and it is the one that gives way when both '
      'sides are the same language.',
    ),
    also: {
      'zh-HK': '副語言只在開啟雙字幕時出現；兩邊選了同一種時，讓位的是它。',
      'zh-TW': '副語言只在開啟雙字幕時出現；兩邊選了同一種時，讓位的是它。',
      'ja': '副言語は二言語併記のときだけ現れ、両側が同じ言語のときはこれが譲ります。',
    },
    voices: {
      Voice.heiress: '副语言只在开启双字幕时出现——两边选了同一种时，让位的是它。它本来就是备用的那个。',
      Voice.heiressJa: '副言語は二言語併記のときだけ現れるの——両側が同じ言語なら、譲るのはこちらよ。もともと控えの立場なんだから。',
    
      Voice.minister:
          'The secondary line appears only where dual copy is in use, and it is the one that gives way when both sides are the same language.',},
  
  );

  static const settingsDualCopyNote = CopyLine.withLanguages(
    Translated.authored('开启后每个标签显示两行——你的语言与副语言。代价是每屏更密，长句会换行。'),
    Translated.authored(
      'With it on, every label shows two lines -- your language and the secondary one. The cost is a '
      'denser screen and longer sentences wrapping.',
    ),
    also: {
      'zh-HK': '開啟後每個標籤顯示兩行——你的語言與副語言。代價是每屏更密，長句會換行。',
      'zh-TW': '開啟後每個標籤顯示兩行——你的語言與副語言。代價是每屏更密，長句會換行。',
      'ja': 'オンにすると各ラベルが二行——自分の言語と副言語——になります。代わりに画面は密になり、長い文は折り返します。',
    },
    voices: {
      Voice.heiress: '开了以后，每个标签显示两行——你的语言与副语言。代价说清楚：每屏更密，长句会换行。划算不划算，你自己看着办。',
      Voice.heiressJa: 'オンにすると各ラベルが二行になるわ——自分の言語と副言語。代わりに画面は密になるし、長い文は折り返すの。割に合うかどうかは、自分で決めなさい。',
    
      Voice.minister:
          'With it in use, every label displays two lines -- your language and the secondary one. The cost is a denser screen and longer sentences wrapping.',},
  
  );

  static const settingsSameTagNote = CopyLine.withLanguages(
    Translated.authored('两边选了同一种语言时，让位的是副语言。'),
    Translated.authored(
      'When both pick the same language, the secondary is the one that moves.',
    ), also: {'ja': '両側で同じ言語を選んだ場合、譲るのは副言語です。', 'zh-HK': '兩邊選了同一種語言時，讓位的是副語言。', 'zh-TW': '兩邊選了同一種語言時，讓位的是副語言。'},
    voices: {
      Voice.heiress: '两边选了同一种语言时，让位的是副语言——本来就是它该让。',
      Voice.heiressJa: '両側で同じ言語を選んだ場合、譲るのは副言語よ——もともと譲る側なんだから。',
    
      Voice.minister:
          'Where both sides select the same language, it is the secondary that moves aside.',},
  );
  static const settingsUnits = CopyLine.withLanguages(
    Translated.authored('计量单位'),
    Translated.authored('Units'), also: {'ja': '計量単位', 'zh-HK': '計量單位', 'zh-TW': '計量單位'});
  static const settingsMoney = CopyLine.withLanguages(
    Translated.authored('货币'),
    Translated.authored('Money'), also: {'ja': '通貨', 'zh-HK': '貨幣', 'zh-TW': '貨幣'});
  static const settingsAdd = CopyLine.withLanguages(
    Translated.authored('添加'),
    Translated.authored('Add'), also: {'ja': '追加', 'zh-HK': '添加', 'zh-TW': '新增'});
  static const settingsStateSolid = CopyLine.withLanguages(
    Translated.authored('固体'),
    Translated.authored('Solid'), also: {'ja': '固体', 'zh-HK': '固體', 'zh-TW': '固體'});
  static const settingsStateLiquid = CopyLine.withLanguages(
    Translated.authored('液体'),
    Translated.authored('Liquid'), also: {'ja': '液体', 'zh-HK': '液體', 'zh-TW': '液體'});
  static const settingsStateEither = CopyLine.withLanguages(
    Translated.authored('两者皆可'),
    Translated.authored('Either'), also: {'ja': 'どちらでも', 'zh-HK': '兩者皆可', 'zh-TW': '兩者皆可'});

  static const settingsUnknown = CopyLine.withLanguages(
    Translated.authored('这个构建不认识'),
    Translated.authored('not shipped in this build'), also: {'ja': 'このビルドでは不明', 'zh-HK': '這個構建不認識', 'zh-TW': '這個構建不認識'});

  // Section 12.3's consumption curve, on the Cellar tab.
  static const cellarConsumption = CopyLine.withLanguages(
    Translated.authored('消耗'),
    Translated.authored('Consumption'), also: {'ja': '消費', 'zh-HK': '消耗', 'zh-TW': '消耗'});
  static const cellarConsumptionEmpty = CopyLine.withLanguages(
    Translated.authored('还没有消耗记录。'),
    Translated.authored('Nothing has been poured yet.'), also: {'ja': 'まだ消費の記録がありません。', 'zh-HK': '還沒有消耗記錄。', 'zh-TW': '還沒有消耗記錄。'},
      voices: {
        Voice.heiress: '一滴都没倒出去过。杯子都还是干的。',
        Voice.heiressJa: 'まだ一滴も注いでいないの。グラスは乾いたままよ。',
        Voice.minister:
            'No measure has been dispensed, and the record consequently shows nothing.',
      },);
  static const cellarDrunk = CopyLine.withLanguages(
    Translated.authored('倒入杯中'),
    Translated.authored('Poured into drinks'), also: {'ja': 'グラスに注いだ', 'zh-HK': '倒入杯中', 'zh-TW': '倒入杯中'});
  static const cellarDiscarded = CopyLine.withLanguages(
    Translated.authored('倒掉'),
    Translated.authored('Discarded'), also: {'ja': '捨てた', 'zh-HK': '倒掉', 'zh-TW': '倒掉'});

  // The state a fresh clone is in.
  static const noLibrary = CopyLine.withLanguages(
    Translated.authored('酒库不在。'),
    Translated.authored('The library is not here.'), also: {'ja': 'ライブラリがありません。', 'zh-HK': '酒庫不在。', 'zh-TW': '酒庫不在。'});
  static const noLibraryHint = CopyLine.withLanguages(
    Translated.authored(
      '这份构建里没有种子数据。在仓库根目录运行：\n'
      'dart run tools/build_seed.dart',
    ),
    Translated.authored(
      'This build has no seed data. From the repository root, run:\n'
      'dart run tools/build_seed.dart',
    ), also: {'ja': 'このビルドにはレシピライブラリが入っていません。再インストールすると復旧します。', 'zh-HK': '這份構建裏沒有種子數據。在倉庫根目錄運行：\n', 'zh-TW': '這份構建裡沒有種子資料。在倉庫根目錄執行：\n'});

  static String withCount(String template, int count) =>
      template.replaceFirst('{count}', '$count');
}
