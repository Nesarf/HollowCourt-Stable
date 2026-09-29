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
