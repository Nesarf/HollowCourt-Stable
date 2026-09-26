import 'package:flutter/material.dart';

import 'hollow_glyphs.dart';
import 'theme.dart';

/// One destination in [HollowNavBar].
class HollowNavDestination {
  const HollowNavDestination({required this.glyph, required this.label});

  final HollowGlyph glyph;

  /// Already resolved for the reader's language by the caller, which is where the locale lives.
  final String label;
}

/// **The application's own navigation bar, because the last one was Flutter's.**
///
/// What it replaces: `NavigationBar` with `NavigationDestination`s, whose icons came from Material's icon font
/// and whose selected state was Material's pill indicator. Both are somebody else's design, on the furniture
/// every screen carries -- so the most-seen part of this application was also the least its own.
///
/// **What it is made of.** A hairline along the top in [HollowPalette.line] -- the same rule that separates rows
/// and sections, so the bar is part of the same grammar rather than a panel bolted underneath. Each destination
/// is one of this project's own glyphs ([HollowGlyph]), its label in the interface's own label style, and the
/// selected one is marked by **the prism**: the motif that already appears in the halo, in the dividers and in the
/// ornament behind every page. The study of a rhythm game recommended exactly that -- one motif, repeated through the
/// icons, the rules and the selected state -- and this is where it earns its keep.
///
/// **No ripple.** A Material ripple is a signature of the toolkit, and this bar draws its own press instead: the
/// destination's own surface lifts for as long as the finger is down. It is the smallest possible state change
/// and it is ours.
class HollowNavBar extends StatefulWidget {
  const HollowNavBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.destinations,
    this.height = 68,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<HollowNavDestination> destinations;
  final double height;

  @override
  State<HollowNavBar> createState() => _HollowNavBarState();
}

class _HollowNavBarState extends State<HollowNavBar> {
  /// Which destination is under the finger right now. One integer, because a bar this size only ever has one.
  int? _pressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: HollowPalette.surface,
        border: Border(top: BorderSide(color: HollowPalette.line)),
      ),
      // **Clamped, because a fixed height and an unbounded text scale cannot both be satisfied.** The phone
      // this was tested on runs large fonts, and the labels grew into the marks above them. A navigation label
      // is furniture: it scales a little and never pushes the bar apart.
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.15,
        child: SizedBox(
        height: widget.height,
        child: Row(
          children: [
            for (var index = 0; index < widget.destinations.length; index++)
              Expanded(
                child: _Destination(
                  destination: widget.destinations[index],
                  selected: index == widget.selectedIndex,
                  pressed: index == _pressed,
                  onTapDown: () => setState(() => _pressed = index),
                  onTapCancel: () => setState(() => _pressed = null),
                  onTap: () {
                    setState(() => _pressed = null);
                    widget.onSelected(index);
                  },
                ),
              ),
          ],
        ),
        ),
      ),
    );
  }
}

class _Destination extends StatelessWidget {
  const _Destination({
    required this.destination,
    required this.selected,
    required this.pressed,
    required this.onTap,
    required this.onTapDown,
    required this.onTapCancel,
  });

  final HollowNavDestination destination;
  final bool selected;
  final bool pressed;
  final VoidCallback onTap;
  final VoidCallback onTapDown;
  final VoidCallback onTapCancel;

  @override
  Widget build(BuildContext context) {
    final colour = selected ? HollowPalette.gold : HollowPalette.inkSoft;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => onTapDown(),
      onTapUp: (_) => onTap(),
      onTapCancel: onTapCancel,
      // **Deliberately not animated.** A transition is motion, and motion belongs to the G edition, which is an
      // independent product rather than a later stage of this one (DESIGN 12.10). The pressed state is an instant
      // change of colour -- which is also what a study of a rhythm game recommends: a pressed state is another drawing,
      // not something tweened towards.
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: pressed ? HollowPalette.surfaceRaised : const Color(0x00000000),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // The selected mark is solid and the others are stroked: a difference of weight rather than of
            // colour alone, so it survives being glanced at.
            HollowGlyphMark(destination.glyph, size: 21, color: colour, fill: selected),
            const SizedBox(height: 5),
            Text(
              destination.label,
              style: HollowType.label.copyWith(color: colour),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 3),
            // The indicator: the motif, present only for the destination in force. Reserved space either way,
            // so selecting one does not move the row.
            SizedBox(
              height: 6,
              child: selected ? const _Indicator() : const SizedBox(width: 6),
            ),
          ],
        ),
      ),
    );
  }
}

/// The prism, at the size the bar can afford.
class _Indicator extends StatelessWidget {
  const _Indicator();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 6,
      height: 6,
      child: CustomPaint(
        painter: HollowGlyphPainter(
          glyph: HollowGlyph.settings,
          color: HollowPalette.gold,
          fill: true,
        ),
      ),
    );
  }
}

/// The five destinations this application has, in the order section 12.3 gives them.
///
/// The labels arrive already resolved for the reader's language, because the language is a value the caller
/// holds -- which is the same reason the bar this replaces could not be `const`.
List<HollowNavDestination> hollowDestinations(List<String> labels) => [
  HollowNavDestination(glyph: HollowGlyph.cellar, label: labels[0]),
  HollowNavDestination(glyph: HollowGlyph.bar, label: labels[1]),
  HollowNavDestination(glyph: HollowGlyph.recipes, label: labels[2]),
  HollowNavDestination(glyph: HollowGlyph.journal, label: labels[3]),
  HollowNavDestination(glyph: HollowGlyph.settings, label: labels[4]),
];
