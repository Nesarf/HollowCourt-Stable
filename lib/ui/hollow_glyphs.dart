import 'package:flutter/widgets.dart';

import 'theme.dart';

/// The five marks the navigation is written in, drawn here rather than taken from an icon font.
///
/// **Why they exist at all.** The first version of the bar used `Icons.inventory_2`, `Icons.grid_view`,
/// `Icons.local_bar`, `Icons.insights` and `Icons.settings` -- Material's own glyphs, in Material's own font. That
/// made the application's most-seen furniture the least of its own work: every screen carries this bar, and every
/// screen was therefore announcing that it is a Flutter application. The owner's instruction on 2026-09-25 was
/// that the interface itself has to be made here, so these are made here.
///
/// **The vocabulary is the mark's.** The bismuth prism is already this project's motif -- in the halo, in the
/// dividers, in the ornament behind every page -- and the study of a rhythm game recommended exactly this: one motif,
/// repeated through the icons, the rules and the selected state, so that a reader recognises the furniture
/// without being told. So the shapes below are angular, built from straight edges and diamonds, and the settings
/// mark *is* the prism.
///
/// **A 24-unit grid, stroked rather than filled**, because a filled glyph at 21 logical pixels loses its
/// features and a stroked one keeps them. [fill] swaps to solid, which the selected state uses.
enum HollowGlyph {
  /// A bottle: the cellar. Shoulder, neck, and a wax seal.
  cellar,

  /// A shelf with two bottles on it: the bar.
  bar,

  /// A coupe: recipes, and the same glass the cup outlines are drawn from.
  recipes,

  /// A page with ruled lines: the journal.
  journal,

  /// The prism itself: settings.
  settings,

  /// **A folder**, for a collection of recipes. Angular like the rest: a tab, a body, and a corner cut the way
  /// every other shape in this vocabulary is cut.
  folder,

  /// **A bound book**, for the official list -- the reference the other folders are read against.
  book,
}

/// Paints one [HollowGlyph] inside the box it is given.
class HollowGlyphPainter extends CustomPainter {
  const HollowGlyphPainter({
    required this.glyph,
    required this.color,
    this.fill = false,
    this.strokeWidth = 1.6,
  });

  final HollowGlyph glyph;
  final Color color;

  /// Solid instead of stroked. The selected destination draws its mark this way.
  final bool fill;

  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    // Normalised to a square so a caller can give any box; the shapes are authored on a 24-unit grid.
    final scale = size.shortestSide / 24;
    canvas.save();
    canvas.translate((size.width - size.shortestSide) / 2, (size.height - size.shortestSide) / 2);
    canvas.scale(scale);

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = color;
    final solid = Paint()
      ..style = PaintingStyle.fill
      ..color = color;

    for (final path in _paths(glyph)) {
      canvas.drawPath(path, fill ? solid : stroke);
    }
    canvas.restore();
  }

  /// The outlines, on the 24-unit grid. Straight edges only: a curve here would be the one soft thing in a
  /// vocabulary built out of corners.
  static List<Path> _paths(HollowGlyph glyph) {
    switch (glyph) {
      case HollowGlyph.cellar:
        // A bottle: a straight body, a stepped shoulder, a short neck, and a diamond seal.
        return [
          Path()
            ..moveTo(9, 21)
            ..lineTo(9, 10)
            ..lineTo(11, 7)
            ..lineTo(11, 4)
            ..lineTo(13, 4)
            ..lineTo(13, 7)
            ..lineTo(15, 10)
            ..lineTo(15, 21)
            ..close(),
          Path()
            ..moveTo(12, 1.4)
            ..lineTo(13.6, 3)
            ..lineTo(12, 4.6)
            ..lineTo(10.4, 3)
            ..close(),
        ];
      case HollowGlyph.bar:
        // The shelf, with two bottles standing on it.
        return [
          Path()
            ..moveTo(3, 17)
            ..lineTo(21, 17),
          Path()
            ..moveTo(6.5, 17)
            ..lineTo(6.5, 8)
            ..lineTo(9.5, 8)
            ..lineTo(9.5, 17),
          Path()
            ..moveTo(13.5, 17)
            ..lineTo(13.5, 5)
            ..lineTo(16.5, 5)
            ..lineTo(16.5, 17),
          Path()
            ..moveTo(3, 20.5)
            ..lineTo(21, 20.5),
        ];
      case HollowGlyph.recipes:
        // A coupe: a shallow bowl, a stem, a foot.
        return [
          Path()
            ..moveTo(4, 5)
            ..lineTo(20, 5)
            ..lineTo(14.6, 12)
            ..lineTo(9.4, 12)
            ..close(),
          Path()
            ..moveTo(12, 12)
            ..lineTo(12, 19),
          Path()
            ..moveTo(7.5, 20)
            ..lineTo(16.5, 20),
        ];
      case HollowGlyph.journal:
        // A page, with two ruled lines and a corner cut the way the dividers are cut.
        return [
          Path()
            ..moveTo(5, 4)
            ..lineTo(16, 4)
            ..lineTo(19, 7)
            ..lineTo(19, 20)
            ..lineTo(5, 20)
            ..close(),
          Path()
            ..moveTo(8, 11)
            ..lineTo(16, 11),
          Path()
            ..moveTo(8, 15)
            ..lineTo(16, 15),
        ];
      case HollowGlyph.folder:
        return [
          Path()
            ..moveTo(3, 6)
            ..lineTo(9.5, 6)
            ..lineTo(11.5, 8.5)
            ..lineTo(21, 8.5)
            ..lineTo(21, 20)
            ..lineTo(3, 20)
            ..close(),
          Path()
            ..moveTo(3, 11.5)
            ..lineTo(21, 11.5),
        ];
      case HollowGlyph.book:
        return [
          // A spine, a cover, and a page edge: enough to read as a bound book at twenty pixels.
          Path()
            ..moveTo(5, 4)
            ..lineTo(19, 4)
            ..lineTo(19, 20)
            ..lineTo(5, 20)
            ..close(),
          Path()
            ..moveTo(8.5, 4)
            ..lineTo(8.5, 20),
          Path()
            ..moveTo(11.5, 8)
            ..lineTo(16.5, 8),
          Path()
            ..moveTo(11.5, 12)
            ..lineTo(16.5, 12),
        ];
      case HollowGlyph.settings:
        // The motif itself: the prism, with its facet.
        return [
          Path()
            ..moveTo(12, 2.6)
            ..lineTo(20.4, 12)
            ..lineTo(12, 21.4)
            ..lineTo(3.6, 12)
            ..close(),
          Path()
            ..moveTo(12, 2.6)
            ..lineTo(12, 21.4),
        ];
    }
  }

  @override
  bool shouldRepaint(HollowGlyphPainter old) =>
      old.glyph != glyph || old.color != color || old.fill != fill || old.strokeWidth != strokeWidth;
}

/// The mark on its own, for a caller that has a box and wants the glyph in it.
class HollowGlyphMark extends StatelessWidget {
  const HollowGlyphMark(
    this.glyph, {
    super.key,
    this.size = 21,
    this.color,
    this.fill = false,
  });

  final HollowGlyph glyph;
  final double size;
  final Color? color;
  final bool fill;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: HollowGlyphPainter(
          glyph: glyph,
          color: color ?? HollowPalette.inkSoft,
          fill: fill,
        ),
      ),
    );
  }
}
