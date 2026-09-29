import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// **The one geometric motif, drawn at whatever size the interface needs.**
///
/// The first convention borrowed from a study of a rhythm game (`docs/DESIGN.md` 12.9.1): *"one motif, repeated to the
/// end"*. Its diamond appears as a **10×10 divider ornament**, as a **card frame** and as a **button** — the same
/// shape at three scales, not three drawings that resemble each other. Ours is the **bismuth prism of 空庭's
/// halo**: a diamond whose upper-left facet is separated by a fine line, which is what makes a bismuth crystal
/// look stepped rather than flat.
///
/// **Why a painter rather than an asset.** A motif has to be the *same* geometry everywhere; three PNGs exported
/// at three sizes are three places for it to drift, and the moment one of them is redrawn by hand the motif stops
/// being one thing. One painter with a size parameter cannot drift from itself.
///
/// **And why the facet survives at ten pixels.** The prism is a diamond plus one line; at 10 px the line is a
/// single pixel and the shape still reads as a faceted stone rather than a dot. That was the test the study set:
/// a motif is only a motif if its smallest use is still recognisable.
class Prism extends StatelessWidget {
  const Prism({
    super.key,
    required this.size,
    this.color,
    this.facet = true,
    this.strokeWidth,
  });

  /// The full width and height of the prism, in logical pixels.
  final double size;

  /// Defaults to the palette's gold: the motif marks what is chosen or what matters, and gold means exactly that
  /// here (12.9's two-colour system).
  final Color? color;

  /// The line that separates the upper-left facet. Off for the smallest sizes if a caller needs a plain diamond.
  final bool facet;

  /// Defaults to a width that stays visible at ten pixels: one logical pixel below 24, two above.
  final double? strokeWidth;

  @override
  Widget build(BuildContext context) {
    final width = strokeWidth ?? (size < 24 ? 1.0 : 2.0);
    // **Not `const`, and that is the rule in this project**: the palette is one mutable global, so a const widget
    // would freeze the colour it was built with (a mistake this repository has already made once).
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _PrismPainter(color: color ?? HollowPalette.gold, facet: facet, strokeWidth: width),
      ),
    );
  }
}

class _PrismPainter extends CustomPainter {
  const _PrismPainter({required this.color, required this.facet, required this.strokeWidth});

  final Color color;
  final bool facet;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - strokeWidth / 2;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..isAntiAlias = true;

    // The diamond: four vertices on the axes. Drawn as a path rather than a rotated square so the stroke stays
    // one pixel wide at small sizes instead of being antialiased twice.
    final top = centre.translate(0, -radius);
    final right = centre.translate(radius, 0);
    final bottom = centre.translate(0, radius);
    final left = centre.translate(-radius, 0);
    final diamond = Path()
      ..moveTo(top.dx, top.dy)
      ..lineTo(right.dx, right.dy)
      ..lineTo(bottom.dx, bottom.dy)
      ..lineTo(left.dx, left.dy)
      ..close();
    canvas.drawPath(diamond, paint);

    if (!facet || radius < 3) return;

    // **The facet is what makes it bismuth rather than a diamond.** One line from the top vertex down to the
    // centre, plus a short line out to the left vertex: two faces meeting, which is the stepped structure a
    // bismuth crystal has and a jewel does not.
    canvas.drawLine(top, centre, paint);
    canvas.drawLine(centre, left, paint);
  }

  @override
  bool shouldRepaint(_PrismPainter old) =>
      old.color != color || old.facet != facet || old.strokeWidth != strokeWidth;
}

/// **A divider: a hairline with the prism set into it.**
///
/// The direct borrowing from the study — a rhythm game's dividers are a line plus small diamonds — and the reason it is
/// worth having rather than a plain rule is that it puts the motif into the ordinary furniture of the interface.
/// A motif that only appears in special places is decoration; one that appears in the dividers is the interface's
/// handwriting.
class PrismDivider extends StatelessWidget {
  const PrismDivider({super.key, this.size = 10});

  /// The prism's size. Ten is the default because that is the size the study measured in a rhythm game's own dividers.
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Container(height: 1, color: HollowPalette.line)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Prism(size: size),
        ),
        Expanded(child: Container(height: 1, color: HollowPalette.line)),
      ],
    );
  }
}

/// **The rule between one option and the next, and the reason it is not a `Divider`.**
///
/// Material's `Divider` takes its colour from the theme's outline and its thickness from the density, and
/// neither is this interface's decision. This one is a single pixel of [HollowPalette.line] with the spacing
/// the settings lists use, so a group of options reads as a group and the boundary between groups is
/// something a reader can see.
///
/// It is deliberately **not** a [PrismDivider]: the motif marks a *section*, and putting a prism on every row
/// would turn the handwriting into a texture. Rows get the rule, sections get the motif.
class HollowRule extends StatelessWidget {
  const HollowRule({super.key, this.indent = 0});

  /// Space kept clear on the left, for a rule that sits under a row's label rather than under its icon.
  final double indent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: Container(height: 1, color: HollowPalette.line),
    );
  }
}

/// **The mark beside something that is chosen.** Small, quiet, and the same shape as everything else.
class PrismMark extends StatelessWidget {
  const PrismMark({super.key, this.size = 12, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => Prism(size: size, color: color, facet: false);
}

/// **The third treatment of the motif: a wash, laid behind the content rather than beside it.**
///
/// The first two treatments are the fill and the outline -- [PrismMark] and [PrismDivider] -- and the reference
/// third treatment appears on titles with more than one artist: the same lattice drawn as hairlines and shipped at **alpha 91 of 255, thirty-six per cent**, to be
/// laid *over* what is on screen. That is the treatment this class is.
///
/// **[decision] The ceiling is a rule, the value is a hierarchy.** The measurement gives the cap
/// ([prismWashCeiling], 0.36) and the cap is **enforced in code** so no caller can make the background compete
/// with the content -- a caller asking for 1.0 gets 0.36. What the wash actually uses by default is **0.18**,
/// half of it, because the backdrop already has a floor: the astrolabe is drawn at a third of the hairline
/// colour, and a wash more visible than the floor would put the texture in front of the instrument in the
/// reading order. Two numbers, two different jobs.
///
/// **And it ignores pointers for the same reason the backdrop does**: it covers the window, so if it took part
/// in hit testing it would swallow every tap that missed a control by a pixel.
class PrismWash extends StatelessWidget {
  const PrismWash({
    super.key,
    this.cell = 96,
    this.color,
    this.alpha = prismWashDefaultAlpha,
    this.texture,
  });

  /// The ground's texture. Defaults to **the world's own** -- a wash that does not say otherwise draws the room
  /// it is in, which is the point of a world having a material at all.
  final GroundTexture? texture;

  /// The spacing of the lattice, in logical pixels. Two rows per cell, offset by half, which is what makes a
  /// grid of diamonds read as a lattice rather than as a table.
  final double cell;

  /// Defaults to [HollowPalette.line], the colour the palette keeps close to the page on purpose -- so the
  /// wash cannot become the highest-contrast thing on the screen.
  final Color? color;

  final double alpha;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: PrismWashPainter(
            color: color ?? HollowPalette.line,
            alpha: prismWashAlpha(alpha),
            cell: math.max(cell, 12),
            // The world's own ground unless a caller insists on something else.
            texture: texture ?? HollowPalette.current.texture,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

/// The most of the hairline colour a wash may ever use, and it comes from a measurement rather than a taste:
/// the reference ships its faint variant at alpha 91 of 255. See the reference study, §10.1.
const double prismWashCeiling = 91 / 255;

/// What [PrismWash] uses unless told otherwise: half the ceiling, so the wash stays under the astrolabe.
const double prismWashDefaultAlpha = prismWashCeiling / 2;

/// The clamp, as its own function so it can be tested without reaching into a private painter.
double prismWashAlpha(double requested) => requested.clamp(0, prismWashCeiling).toDouble();

class PrismWashPainter extends CustomPainter {
  const PrismWashPainter({
    required this.color,
    required this.alpha,
    required this.cell,
    this.texture = GroundTexture.lattice,
  });

  final Color color;
  final double alpha;
  final double cell;
  final GroundTexture texture;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..isAntiAlias = true;

    switch (texture) {
      case GroundTexture.lattice:
        _lattice(canvas, size, paint);
      case GroundTexture.laid:
        _laid(canvas, size, paint);
      case GroundTexture.frost:
        _frost(canvas, size, paint);
    }
  }

  /// **Laid paper.** Horizontal laid lines every `cell / 24` -- fine enough to read as texture rather than as
  /// rules -- with a chain line every `cell`, drawn a little darker because that is what the wires did.
  ///
  /// This is what paper actually looked like before wove, and it is the reason a page in this texture reads as
  /// paper and not as graph paper: the two directions are not the same weight and not the same distance apart.
  void _laid(Canvas canvas, Size size, Paint paint) {
    final gap = (cell / 24).clamp(2.0, 8.0);
    for (var y = 0.0; y < size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    final chain = Paint()
      ..color = paint.color.withValues(alpha: (alpha * 2.2).clamp(0.0, 1.0))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var x = cell / 2; x < size.width + cell; x += cell) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), chain);
    }
  }

  /// **Frost.** Rhombi at two scales, on the same tiling as the lattice but with most of them absent, so the
  /// field reads as ice that grew rather than as a pattern that was printed.
  ///
  /// Which ones are absent is decided by the cell's own coordinates rather than by a random number, so a repaint
  /// -- a resize, a scroll, a theme switch -- puts every crystal back exactly where it was.
  void _frost(Canvas canvas, Size size, Paint paint) {
    var row = 0;
    for (var y = cell / 2; y < size.height + cell; y += cell / 2) {
      final offset = row.isEven ? 0.0 : cell / 2;
      row++;
      for (var x = cell / 2 + offset; x < size.width + cell; x += cell) {
        final column = (x / cell).round();
        // A cheap deterministic scatter: two of every three cells are empty, and the survivors alternate scale.
        final pick = (row * 7 + column * 5) % 3;
        if (pick == 0) continue;
        final radius = pick == 1 ? cell / 2.4 : cell / 4.6;
        canvas.drawPath(
          Path()
            ..moveTo(x, y - radius)
            ..lineTo(x + radius * 0.78, y)
            ..lineTo(x, y + radius)
            ..lineTo(x - radius * 0.78, y)
            ..close(),
          paint,
        );
      }
    }
  }

  void _lattice(Canvas canvas, Size size, Paint paint) {
    // The same four vertices as `_PrismPainter`, at the same proportion of the cell, so the wash is the motif
    // rather than a lookalike: a diamond whose half-diagonals are a third of the cell.
    final radius = cell / 3;
    var row = 0;
    for (var y = cell / 2; y < size.height + cell; y += cell / 2) {
      final offset = row.isEven ? 0.0 : cell / 2;
      row++;
      for (var x = cell / 2 + offset; x < size.width + cell; x += cell) {
        canvas.drawPath(
          Path()
            ..moveTo(x, y - radius)
            ..lineTo(x + radius, y)
            ..lineTo(x, y + radius)
            ..lineTo(x - radius, y)
            ..close(),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(PrismWashPainter old) =>
      old.color != color || old.alpha != alpha || old.cell != cell || old.texture != texture;
}
