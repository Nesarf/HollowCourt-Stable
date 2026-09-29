import 'package:flutter/material.dart';

import '../domain/model/glass.dart';
import '../domain/model/ice.dart';
import '../domain/model/liquid_visual.dart';
import 'theme.dart';

/// Section 12.1's renderer: a drink recognised at a glance from six fields.
///
/// The design's claim is that a colour, an opacity and a layering flag are
/// enough, and this is where that claim is either true or not. **It is drawn
/// rather than illustrated**, which is the whole reason it belongs in the stable
/// release: a silhouette from four numbers and a colour from two costs a few
/// hundred bytes of code and no asset pack at all, and section 14.1 puts
/// everything measured in megabytes on the other side of the download.
///
/// Every glass below is a path built from a top width, a bottom width, a height
/// and whether it stands on a stem. That is not a 3D model and is not meant to
/// be -- it is the least a shape can be and still be recognised in a list, which
/// is exactly what section 12.1 asked for.
class LiquidSwatch extends StatelessWidget {
  const LiquidSwatch({
    super.key,
    required this.liquid,
    this.glass,
    this.ice,
    this.fill = 0.72,
    this.width = 40,
  });

  /// Null when the source did not say, which is the whole of one of the two
  /// seed sources. A drink with no colour is drawn as an empty glass rather than
  /// as a guessed colour.
  final LiquidVisual? liquid;

  final Glass? glass;
  final IceKind? ice;

  /// How full the glass is drawn, 0 to 1, before the drink's own data.
  final double fill;

  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: width * 1.5,
    child: CustomPaint(
      painter: _GlassPainter(
        liquid: liquid,
        glass: glass,
        ice: ice,
        fill: fill,
      ),
    ),
  );
}

/// The four numbers that make a silhouette, per glass.
///
/// Kept as data rather than as eight hand-written paths, so that adding a glass
/// is a row and so that the difference between a highball and a pint is visible
/// as two numbers rather than as two drawings nobody can compare.
class _Silhouette {
  const _Silhouette({
    required this.top,
    required this.bottom,
    required this.height,
    this.stem = false,
  });

  /// Bowl width at the rim and at the base, as a fraction of the swatch width.
  final double top;
  final double bottom;

  /// Bowl height as a fraction of the swatch height.
  final double height;

  /// Whether the bowl sits on a stem and foot.
  final bool stem;

  static const _values = <Glass, _Silhouette>{
    // A stemmed, wide, shallow bowl.
    Glass.cocktail: _Silhouette(top: 0.94, bottom: 0.10, height: 0.44, stem: true),
    // The same family, rounder and a little deeper.
    Glass.coupe: _Silhouette(top: 0.90, bottom: 0.22, height: 0.38, stem: true),
    // Straight-sided and tall.
    Glass.highball: _Silhouette(top: 0.62, bottom: 0.58, height: 0.68),
    // Short and wide.
    Glass.lowball: _Silhouette(top: 0.70, bottom: 0.64, height: 0.48),
    // Narrow, tall, and gently flared.
    Glass.flute: _Silhouette(top: 0.40, bottom: 0.24, height: 0.70, stem: true),
    // Small and heavy-based.
    Glass.shot: _Silhouette(top: 0.52, bottom: 0.46, height: 0.26),
    // Tall, slightly tapered, the widest of the straight ones.
    Glass.pint: _Silhouette(top: 0.72, bottom: 0.56, height: 0.74),
    // A stemmed bowl with a taper, fuller than a cocktail glass.
    Glass.wine: _Silhouette(top: 0.66, bottom: 0.24, height: 0.46, stem: true),
  };

  static _Silhouette of(Glass? glass) =>
      _values[glass] ?? const _Silhouette(top: 0.66, bottom: 0.5, height: 0.58);
}

/// The colour a `LiquidColour` is drawn in.
///
/// `LiquidColour` carries a **family** (the hue) and a **tone** (the depth), and
/// the enum's own comment is firm that the family and tone are *derived from* the
/// observed list rather than the other way round -- so this maps a family to a
/// base hue and lets the tone move the lightness, which is the one direction that
/// does not turn the list back into a grid.
///
/// Saturations are low throughout. Section 20.3 asks for low-contrast warm
/// mid-tones, and a cocktail list is exactly where a saturated palette would
/// shout: twenty of these are on screen at once, and each one is a liquid rather
/// than a signal.
Color liquidColour(LiquidColour colour) {
  final (hue, saturation) = switch (colour.family) {
    'neutral' => (36.0, 0.06),
    'brown' => (24.0, 0.38),
    'yellow' => (44.0, 0.44),
    'red' => (356.0, 0.42),
    'green' => (96.0, 0.24),
    'orange' => (26.0, 0.52),
    'purple' => (286.0, 0.26),
    'blue' => (208.0, 0.28),
    'pink' => (344.0, 0.38),
    'turquoise' => (176.0, 0.26),
    _ => (36.0, 0.2),
  };

  final lightness = switch (colour.tone) {
    Tone.lightest => 0.80,
    Tone.light => 0.68,
    Tone.base => 0.55,
    Tone.dark => 0.42,
    Tone.darkest => 0.30,
  };

  return HSLColor.fromAHSL(1, hue, saturation, lightness).toColor();
}

class _GlassPainter extends CustomPainter {
  _GlassPainter({
    required this.liquid,
    required this.glass,
    required this.ice,
    required this.fill,
  });

  final LiquidVisual? liquid;
  final Glass? glass;
  final IceKind? ice;
  final double fill;

  @override
  void paint(Canvas canvas, Size size) {
    final shape = _Silhouette.of(glass);
    final centreX = size.width / 2;
    final bowlWidth = size.width * 0.92;
    final stemHeight = shape.stem ? size.height * 0.30 : 0.0;
    final bowlHeight = size.height - stemHeight - size.height * 0.06;
    final bowlTop = size.height * 0.04;
    final bowlBottom = bowlTop + bowlHeight;

    double halfTop() => bowlWidth * shape.top / 2;
    double halfBottom() => bowlWidth * shape.bottom / 2;

    // --- the stem and the foot ------------------------------------------
    if (shape.stem) {
      final stem = Paint()
        ..color = HollowPalette.hairline
        ..strokeWidth = 1.4
        ..style = PaintingStyle.stroke;
      canvas.drawLine(
        Offset(centreX, bowlBottom),
        Offset(centreX, bowlBottom + stemHeight * 0.72),
        stem,
      );
      final foot = Path()
        ..moveTo(centreX - size.width * 0.22, bowlBottom + stemHeight * 0.78)
        ..lineTo(centreX + size.width * 0.22, bowlBottom + stemHeight * 0.78);
      canvas.drawPath(foot, stem);
    }

    // --- the bowl, as a closed path -------------------------------------
    final bowl = Path()
      ..moveTo(centreX - halfTop(), bowlTop)
      ..lineTo(centreX + halfTop(), bowlTop)
      ..lineTo(centreX + halfBottom(), bowlBottom)
      ..lineTo(centreX - halfBottom(), bowlBottom)
      ..close();

    // --- the liquid -----------------------------------------------------
    final drink = liquid;
    if (drink != null) {
      canvas.save();
      canvas.clipPath(bowl);

      final level = fill.clamp(0.0, 1.0);
      final surfaceY = bowlBottom - (bowlBottom - bowlTop) * level;
      // A layered drink is drawn as two bands; a single one fills the same
      // region at its own opacity. The split is even because the data does not
      // say the proportion, and inventing one would be inventing a fact.
      final bands = <(Color, double, double)>[];
      if (drink.layered && drink.colourSecondary != null) {
        bands
          ..add((liquidColour(drink.colour), surfaceY, bowlBottom - (bowlBottom - surfaceY) * 0.45))
          ..add((
            liquidColour(drink.colourSecondary!),
            bowlBottom - (bowlBottom - surfaceY) * 0.45,
            bowlBottom,
          ));
      } else {
        bands.add((liquidColour(drink.colour), surfaceY, bowlBottom));
      }

      for (final (colour, top, bottom) in bands) {
        canvas.drawRect(
          Rect.fromLTRB(0, top, size.width, bottom),
          Paint()
            ..color = colour.withValues(
              alpha: (drink.opacityPercent.clamp(0, 100) / 100) * 0.85 + 0.15,
            ),
        );
      }

      // --- the ice ------------------------------------------------------
      // Only the three shapes that read at this size. A block or a rock is not
      // distinguishable at forty pixels and drawing one badly is worse than
      // drawing nothing.
      if (ice == IceKind.cubes || ice == IceKind.crushed || ice == IceKind.rock) {
        final cube = Paint()
          ..color = HollowPalette.ink.withValues(alpha: 0.16)
          ..style = PaintingStyle.fill;
        final side = size.width * (ice == IceKind.crushed ? 0.12 : 0.20);
        for (var i = 0; i < 3; i++) {
          final x = centreX - halfBottom() * 0.5 + i * side * 0.9;
          final y = surfaceY + size.height * 0.07 + (i.isOdd ? side * 0.4 : 0);
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(x, y, side, side),
              const Radius.circular(1.5),
            ),
            cube,
          );
        }
      }
      canvas.restore();
    }

    // --- the glass itself, drawn last so the rim sits over the liquid ----
    canvas.drawPath(
      bowl,
      Paint()
        ..color = HollowPalette.hairline
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_GlassPainter old) =>
      old.liquid != liquid ||
      old.glass != glass ||
      old.ice != ice ||
      old.fill != fill;
}
