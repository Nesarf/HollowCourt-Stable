import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'display_providers.dart';
import 'prism.dart';
import 'theme.dart';

/// The instrument drawn faintly behind a world's pages.
///
/// **One grammar, three shapes.** Every world draws a hairline instrument at the same strength, in the same
/// colour, positioned by the same rule -- and each draws a *different* instrument. That is the whole idea of the
/// three worlds in one file: the restraint is shared, so the background stays a background; the drawing is not,
/// so two dark worlds are still two worlds once the words are gone.
///
/// The three are the halo (which is also the identity), engine-turning (which is what a printed page was decorated
/// with), and a snow crystal built out of the motif. None of them is a picture: each is a construction, which is
/// what lets it be drawn at any size on any display without a file per density.
class HollowOrnamentPainter extends CustomPainter {
  const HollowOrnamentPainter({
    this.ornament = Ornament.halo,
    this.strength = _strength,
    this.color,
  });

  final Ornament ornament;

  /// The line colour, defaulting to the palette's hairline.
  ///
  /// **Passed in rather than read, because a painter may be drawing a world that is not the current one.** A
  /// review sheet does exactly that, and the first version of the sheets came back with Winter's ground and
  /// Amber Court's line colour on it -- the same fault as the backdrop that would not rebuild, seen from the
  /// other side: one read the world too rarely, this read it too eagerly.
  final Color? color;

  /// How much of the hairline colour to let through. Defaults to the page's own restraint; a review sheet passes
  /// something higher, because a drawing meant to be looked at cannot be drawn to be overlooked.
  final double strength;

  /// How much of the hairline colour is let through.
  ///
  /// **[decision] A third, and it was arrived at by looking.** At half the strokes read as content; at
  /// a fifth they vanish on a bright screen outdoors. A third leaves them visible when looked at and
  /// absent when read past, which is the property a background needs.
  static const double _strength = 0.34;

  /// Where the instrument's centre sits, as fractions of the viewport.
  ///
  /// **[decision] Off-centre, and the same place in every world.** A drawing centred behind a page of text puts
  /// its busiest part exactly where the reading is; moving it up and to the right keeps it whole on a phone held
  /// upright and on a desktop window at the same time, which a centred one cannot do.
  static const double _centreX = 0.74;
  static const double _centreY = 0.30;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = (color ?? HollowPalette.hairline).withValues(alpha: strength);
    final centre = Offset(size.width * _centreX, size.height * _centreY);
    // The diagonal rather than the width: a phone held upright and a desktop window are wildly
    // different shapes, and radii taken from the width alone would put the plate off-screen on one of
    // them and make it a bullseye on the other.
    final span = math.sqrt(size.width * size.width + size.height * size.height);
    final hairline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = stroke;

    switch (ornament) {
      case Ornament.halo:
        _halo(canvas, centre, span, stroke, hairline);
      case Ornament.guilloche:
        _guilloche(canvas, centre, span, hairline);
      case Ornament.snowCrystal:
        _snowCrystal(canvas, centre, span, hairline);
      case Ornament.songRings:
        _songRings(canvas, centre, span, hairline);
      case Ornament.cooperage:
        _cooperage(canvas, centre, span, hairline);
    }
  }

  /// **The halo**, which is the character's own and therefore the world's: three rings, the prism ring between
  /// the outer two, sixty graduations, and the twelve hour rules -- all of it turned fifteen degrees, which is the
  /// angle the halo is worn at and the reason the drawing reads as *hers* rather than as an instrument.
  void _halo(Canvas canvas, Offset centre, double span, Color stroke, Paint hairline) {
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.rotate(math.pi / 12); // fifteen degrees, the halo's own tilt
    canvas.translate(-centre.dx, -centre.dy);

    final radii = [span * 0.42, span * 0.31, span * 0.19];
    for (final radius in radii) {
      canvas.drawCircle(centre, radius, hairline);
    }

    // The prism ring: the motif, as the halo wears it, between the outer two rings.
    final band = (radii[0] + radii[1]) / 2;
    final prismRing = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = stroke;
    for (var i = 0; i < 24; i++) {
      final angle = i * math.pi / 12;
      final direction = Offset(math.cos(angle), math.sin(angle));
      final at = centre + direction * band;
      final half = span * 0.016;
      canvas.drawPath(
        Path()
          ..moveTo(at.dx, at.dy - half * 1.6)
          ..lineTo(at.dx + half, at.dy)
          ..lineTo(at.dx, at.dy + half * 1.6)
          ..lineTo(at.dx - half, at.dy)
          ..close(),
        prismRing,
      );
    }

    // The graduations, on the outer ring only: one degree would be 360 strokes for no more meaning,
    // and sixty is what an instrument of this size carried.
    final outer = radii.first;
    for (var i = 0; i < 60; i++) {
      final angle = i * math.pi / 30;
      final long = i % 5 == 0;
      final inner = outer - (long ? 16 : 8);
      final direction = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(centre + direction * inner, centre + direction * outer, hairline);
    }

    // The hours, from the second ring outwards, so they read as rules rather than as spokes.
    for (var i = 0; i < 12; i++) {
      final angle = i * math.pi / 6;
      final direction = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(centre + direction * radii[1], centre + direction * radii.first, hairline);
    }
    canvas.restore();
  }

  /// **Engine-turning.** Two rose curves laid over one another, the way a guilloché lathe cuts a watch case or a
  /// banknote's margin: each is `r = R·cos(k·θ)` sampled as one continuous line, and the two together fill an
  /// area with a pattern that has no repeated tile in it.
  ///
  /// Chosen for the white world because that is what decorated printed paper before it was decorated with
  /// pictures -- and because a rose curve is a *construction*, so it costs nothing to draw at any size.
  void _guilloche(Canvas canvas, Offset centre, double span, Paint hairline) {
    for (final (k, radius, step) in [(6.0, span * 0.40, 720), (9.0, span * 0.27, 1080)]) {
      final path = Path();
      for (var i = 0; i <= step; i++) {
        final theta = i * 2 * math.pi / step;
        final r = radius * math.cos(k * theta);
        final point = centre + Offset(math.cos(theta), math.sin(theta)) * r;
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(path, hairline);
    }
  }

  /// **A snow crystal out of the motif.** Six arms at sixty degrees, each a chain of three rhombi shrinking
  /// outwards, plus a ring of small ones joining the arms -- which is how a snow crystal is actually built
  /// (a hexagon with branches) drawn in this project's vocabulary instead of in water's.
  void _snowCrystal(Canvas canvas, Offset centre, double span, Paint hairline) {
    for (var i = 0; i < 6; i++) {
      final angle = i * math.pi / 3;
      final direction = Offset(math.cos(angle), math.sin(angle));
      final across = Offset(-direction.dy, direction.dx);

      // The chain: three rhombi along the arm, each two-thirds of the last.
      var at = span * 0.06;
      var half = span * 0.055;
      for (var n = 0; n < 3; n++) {
        final point = centre + direction * at;
        final along = half * 1.5;
        canvas.drawPath(
          Path()
            ..moveTo(point.dx + direction.dx * along, point.dy + direction.dy * along)
            ..lineTo(point.dx + across.dx * half, point.dy + across.dy * half)
            ..lineTo(point.dx - direction.dx * along, point.dy - direction.dy * along)
            ..lineTo(point.dx - across.dx * half, point.dy - across.dy * half)
            ..close(),
          hairline,
        );
        // A short branch off every joint, which is what separates a crystal from a star.
        if (n < 2) {
          final joint = centre + direction * (at + along);
          for (final side in [1.0, -1.0]) {
            canvas.drawLine(
              joint,
              joint + (direction * 0.6 + across * (side * 0.5)) * (half * 1.4),
              hairline,
            );
          }
        }
        at += along * 2 + half * 0.7;
        half *= 0.66;
      }
    }
    canvas.drawCircle(centre, span * 0.038, hairline);
  }

  /// **Sounding rings, for 永遠の歌姫.**
  ///
  /// Concentric rings with a radial burst across them, drawn as the ripple a note leaves rather than as an
  /// instrument's dial -- the distinction that keeps it from being the halo again. The halo is marked, graduated
  /// and turned fifteen degrees because it is *worn*; this is even and ungraduated because it is *heard*.
  ///
  /// **Nothing here quotes anything.** The world is homage and borrows no mark: the shape says sound, and the name
  /// the owner gave says the rest. A theme that drew somebody's logo would be the one thing this project does not
  /// do with other people's work.

  /// **A barrel's head, seen face on.** Arched bands with staves between them.
  ///
  /// The first ornament here whose subject is a container rather than a sky, and the first a reader could put a hand
  /// on -- which is the right subject for the room this world is. It is built from the same motif as everything
  /// else: the **staves are radial lines between two arcs**, which is the prism ring's own construction opened out
  /// from a circle into a face.
  ///
  /// **The bands bow outward** rather than running straight, because that is what a barrel looks like from in front
  /// and a set of parallel lines would read as a ladder instead. The bow is a fixed fraction of the span, so the
  /// drawing scales with the window rather than with the pixel.
  void _cooperage(Canvas canvas, Offset centre, double span, Paint hairline) {
    final radius = span * 0.40;
    // Five bands, closer together toward the rim, which is what perspective does to a curved face.
    final bands = <double>[-0.92, -0.52, 0.0, 0.52, 0.92];
    for (final at in bands) {
      final y = centre.dy + radius * at;
      // How much the band bows: nothing at the centre, most at the edges.
      final bow = radius * 0.22 * at.abs();
      final path = Path()
        ..moveTo(centre.dx - radius * 0.94, y + bow)
        ..quadraticBezierTo(centre.dx, y - bow * 0.6, centre.dx + radius * 0.94, y + bow);
      canvas.drawPath(path, hairline);
    }

    // The staves: radial lines from the outer band to the rim, every twelfth of the face.
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = hairline.color;
    for (var i = 0; i <= 12; i++) {
      final x = centre.dx - radius * 0.94 + (radius * 1.88) * (i / 12);
      // The face is an ellipse, so a stave's length depends on how far along it sits.
      final t = (i / 12) * 2 - 1;
      final halfHeight = radius * 0.92 * math.sqrt(math.max(0.0, 1 - t * t));
      canvas.drawLine(Offset(x, centre.dy - halfHeight), Offset(x, centre.dy + halfHeight), rim);
    }
  }

  void _songRings(Canvas canvas, Offset centre, double span, Paint hairline) {
    // Six rings, evenly spaced and thinning outward, the way a ripple loses amplitude rather than the way a dial
    // is ruled. The innermost is left out so the centre stays quiet.
    for (var i = 1; i <= 6; i++) {
      canvas.drawCircle(centre, span * (0.075 + i * 0.055), hairline);
    }

    // The burst: strokes crossing the rings, which is what makes the field read as something travelling outward
    // instead of as a target. Every third one runs the whole width so the burst has grain rather than a comb.
    final inner = span * 0.13;
    final outer = span * 0.40;
    for (var i = 0; i < 108; i++) {
      final angle = i * math.pi / 54;
      final direction = Offset(math.cos(angle), math.sin(angle));
      final whole = i % 3 == 0;
      final from = inner + (whole ? 0.0 : span * 0.10);
      final to = outer - (whole ? 0.0 : span * 0.06);
      canvas.drawLine(centre + direction * from, centre + direction * to, hairline);
    }
  }

  @override
  bool shouldRepaint(HollowOrnamentPainter old) =>
      old.ornament != ornament || old.strength != strength || old.color != color;
}

/// The instrument, filling whatever it is put behind -- with the prism wash under it.
///
/// **Ignoring hits, because a background that can be tapped is a bug.** A `CustomPaint` in a `Stack`
/// takes part in hit testing by default, and this one covers the whole screen -- so without this it
/// would swallow every tap that missed a button by one pixel. Both layers are built to ignore pointers on
/// their own as well, so the rule holds wherever either is used.
///
/// **Two layers, and their order is the reading order.** The wash is the texture; the instrument is the floor.
/// A texture more visible than the floor would push the instrument back, so the wash goes *under* it and is
/// drawn at half the ceiling its own measurement allows (`PrismWash`, and the reference study §10.1). Both are
/// still behind the content: the third treatment of the motif in the reference is laid over the screen, and
/// over text is the one place it must not go here -- this is a tool, and its text is meant to be read.
///
/// **And it watches the world rather than being told about it.** The first version read the palette when it was
/// built, which looked right and was not: the backdrop sits under a subtree that does not rebuild, so switching
/// to the white world recoloured the screen and left **Amber Court's lattice** drawn on it. The colours followed
/// and the art did not -- caught by a screenshot, and now by `test/ui/world_art_fidelity_test.dart`, which drives
/// the real settings change and then asks these two painters what they are drawing.
class OrnamentBackdrop extends ConsumerWidget {
  const OrnamentBackdrop({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watched, not read once: this is what makes a world change reach the art.
    final world = ref.watch(displaySettingsProvider).theme;
    return Stack(
      children: [
        // The wash resolves the world itself, for the same reason this widget does.
        Positioned.fill(child: PrismWash(texture: world.texture)),
        // **The world's own picture, if it has one, and only one of the four does.** Under the ornament and over
        // the wash, because it is a material rather than a subject: it belongs to the same layer as the ground's
        // texture, and anything drawn on top of it is still the interface.
        //
        // **Held to the wash's ceiling.** The picture is one ink at full strength, which is 7.35:1 against its own
        // ground -- the highest-contrast thing on the screen, which is precisely what `prismWashCeiling` exists to
        // prevent. So it is drawn at the same cap: a reader should find it after the text, not instead of it.
        if (world.artwork case final artwork?)
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // **Which shape is a question about the window, not about the platform.** The owner's split --
                    // 竖版用于安卓, 横版用于 windows 和 linux -- is what the two files are for, and this is the
                    // rule that produces it without asking the operating system: a window taller than it is wide
                    // gets the upright drawing, and every desktop window is wider than it is tall.
                    final upright = constraints.maxHeight > constraints.maxWidth;
                    return Opacity(
                      opacity: prismWashDefaultAlpha,
                      child: Image.asset(
                        upright ? artwork.tall : artwork.wide,
                        fit: BoxFit.cover,
                        // Nearest rather than the default filter: the source is a two-colour vector render, and
                        // a smoothing filter on flat ink at low opacity produces a grey mush at the edges.
                        filterQuality: FilterQuality.medium,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: HollowOrnamentPainter(ornament: world.ornament),
                size: Size.infinite,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Decodes a world's picture before it is asked for, so that choosing the world does not show a delay.
///
/// **This is the fix for the only real cost of adding artwork, and it is deliberately not an animation.**
/// Section 12.8 of the design record says motion is not in this edition at all -- not "not yet", none -- and
/// gives the argument: a pressed state is *another drawing*, which needs no transition to be right. A theme is
/// the same shape of thing. Four worlds are four palettes, four materials, four ornaments and one picture, and
/// cross-fading between them would be describing them as one drawing with different numbers.
///
/// **What is wrong without this is not the abruptness.** It is that a 1920x960 PNG has to be decoded, and a
/// decode that finishes after the frame it was needed in looks like the picture arriving late rather than like
/// the world changing. On this handset the gap would be short and visible; on a slower one it would be a wait
/// with a changed background colour and nothing else. **So the answer to "should the switch be animated?" is
/// the answer this repository already gives -- no -- and the answer to "is anything wrong with the switch?" is
/// yes, and it is a decode that happens too late.**
///
/// **Both shapes are warmed, not the one the window wants.** Which is drawn depends on the window's
/// proportions, so a rotated device or a resized desktop window would otherwise pay for the second decode at
/// exactly the moment somebody is looking. Both together are under a megabyte of bitmap.
class WorldArtworkWarmer extends StatefulWidget {
  const WorldArtworkWarmer({super.key, required this.child});

  /// What this widget exists to keep ready. Passed through rather than wrapped in anything.
  final Widget child;

  @override
  State<WorldArtworkWarmer> createState() => _WorldArtworkWarmerState();
}

class _WorldArtworkWarmerState extends State<WorldArtworkWarmer> {
  /// What has already been handed to the image cache, so a rebuild does not re-request a decode that has
  /// happened -- `precacheImage` on a cached image is nearly free, and "nearly" every frame is not.
  final Set<String> _warmed = <String>{};

  @override
  Widget build(BuildContext context) {
    // **Warmed during build rather than on a lifecycle callback**, because it has to happen on the frame the
    // world changed and a rebuild is the only event that is guaranteed to coincide with that. Reading the world
    // from `HollowPalette` rather than from the provider is what lets this be a plain widget: it sits inside
    // `MaterialApp` below the root that applies the palette, so the world on the context is the world in force.
    final artwork = HollowPalette.current.artwork;
    if (artwork != null) {
      for (final asset in <String>[artwork.tall, artwork.wide]) {
        if (!_warmed.add(asset)) continue;
        // Not awaited: this is a head start, and the frame that needs the picture waits for the decode anyway.
        // Awaiting would make this frame wait instead, which is the cost it exists to remove.
        unawaited(precacheImage(AssetImage(asset), context));
      }
    }
    return widget.child;
  }
}
