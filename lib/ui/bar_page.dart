import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/events/shelf.dart';
import 'l10n/copy_resolution.dart';
import 'l10n/dual_copy_text.dart';
import 'library.dart';
import 'theme.dart';

/// One shelf of section 12.2: the bottles, standing where they were put.
///
/// **What this page replaces, and what it does not.** Until now the Bar tab was a
/// placeholder that said the shelves were still on paper, which was true while no
/// position could be recorded. There is one now -- `ShelfLayout`, folded from the
/// same log as the stock -- so the tab draws a shelf and lets a bottle be put on
/// it. Statistics, a shopping list, devices and sync are still section 12.3's
/// business on the *Cellar* tab and are not claimed here.
///
/// **The stock cross-check is the point of drawing rather than listing.** A
/// position is a fact about a bottle, and a bottle can be poured away while its
/// position stays in the log. Drawing every placement would put a bottle on the
/// shelf that nobody can pour, so a placement whose bottle has no remaining volume
/// is counted and named instead of drawn -- the same reason `library.dart` refuses
/// to call an empty shelf a bare cellar.
class BarPage extends ConsumerWidget {
  const BarPage({super.key});

  /// The shelf a first-pass Bar draws.
  ///
  /// A constant rather than a chooser, because section 12.3's "the place to choose
  /// which Bar is being worked on" is a real feature and this is not it. One shelf
  /// with a name is honest; a shelf picker over one shelf would be furniture.
  static const defaultShelfId = 'bar';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cellar = ref.watch(cellarProvider);

    return SafeArea(
      child: cellar.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Text(
            '${ref.copy(Copy.barTitle)}: $error',
            style: HollowType.body,
          ),
        ),
        data: (state) {
          final onHand = [
            for (final bottle in state.stock.bottles)
              if (bottle.remaining.microlitres > 0) bottle,
          ];
          final onHandIds = {for (final bottle in onHand) bottle.bottleId};

          final placed = state.shelf.onShelf(defaultShelfId);
          final standing = [
            for (final placement in placed)
              if (onHandIds.contains(placement.bottleId)) placement,
          ];
          final placedButEmpty = [
            for (final placement in placed)
              if (!onHandIds.contains(placement.bottleId)) placement,
          ];
          final inTheBox = state.shelf.unplacedAmong(onHandIds);

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            children: [
              DualCopyText(Copy.barTitle, style: HollowType.display),
              const SizedBox(height: 20),
              _ShelfBoard(
                shelfId: defaultShelfId,
                standing: standing,
                labels: {
                  for (final bottle in onHand) bottle.bottleId: bottle.sku,
                },
                onPlace: (bottleId, x, y) => ref
                    .read(cellarProvider.notifier)
                    .placeBottle(
                      bottleId: bottleId,
                      shelfId: defaultShelfId,
                      posXPermille: x,
                      posYPermille: y,
                    ),
              ),
              const SizedBox(height: 10),
              if (standing.isEmpty)
                DualCopyText(Copy.barShelfEmpty, style: HollowType.caption),
              if (placedButEmpty.isNotEmpty) ...[
                const SizedBox(height: 6),
                DualCopyText(
                  Copy.barPlacedButEmpty,
                  style: HollowType.caption,
                ),
              ],
              const SizedBox(height: 28),
              DualCopyText(Copy.barInTheBox, style: HollowType.heading),
              const SizedBox(height: 8),
              if (inTheBox.isEmpty)
                DualCopyText(Copy.barNothingToPlace, style: HollowType.caption)
              else
                _Box(bottleIds: inTheBox, labels: {
                  for (final bottle in onHand) bottle.bottleId: bottle.sku,
                }),
              const SizedBox(height: 12),
              DualCopyText(Copy.barDragHint, style: HollowType.caption),
            ],
          );
        },
      ),
    );
  }
}

/// What is being dragged. A bottle id, and nothing else.
///
/// A type rather than a bare `String` so that a `DragTarget` cannot be given a
/// shelf id or a sku by mistake -- all three are strings, and the compiler would
/// not have noticed.
@immutable
class DraggedBottle {
  const DraggedBottle(this.bottleId);

  final String bottleId;
}

/// The shelf surface, and the drop target for it.
///
/// Stateful for one reason: the drop coordinates have to be converted against the
/// **drop area's own box**, and the first version measured the enclosing `Column`
/// instead -- which includes the shelf's caption and the gap under it, so every
/// drop landed a caption's height away from where the finger was. A `GlobalKey` on
/// the box that actually receives the drop is the difference between measuring the
/// thing and measuring something near it.
class _ShelfBoard extends StatefulWidget {
  const _ShelfBoard({
    required this.shelfId,
    required this.standing,
    required this.labels,
    required this.onPlace,
  });

  final String shelfId;
  final List<BottlePlacement> standing;
  final Map<String, String> labels;
  final void Function(String bottleId, int xPermille, int yPermille) onPlace;

  @override
  State<_ShelfBoard> createState() => _ShelfBoardState();
}

class _ShelfBoardState extends State<_ShelfBoard> {
  /// The box a drop lands in, and the box its coordinates are relative to.
  final _surface = GlobalKey();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      DualCopyText(Copy.barShelfMain, style: HollowType.caption),
      const SizedBox(height: 6),
      DragTarget<DraggedBottle>(
        onAcceptWithDetails: (details) {
          final box = _surface.currentContext?.findRenderObject() as RenderBox?;
          if (box == null) return;
          // `details.offset` is the dragged widget's TOP-LEFT, not the pointer,
          // so this is only the pointer position because the draggable uses
          // `pointerDragAnchorStrategy`. Measured before that was set: a drop at
          // (310, 208.7) arrived as (297, 177.7), which is exactly half a bottle
          // glyph -- (13, 31) -- to the upper left. Pinning the anchor to the
          // pointer fixes the arithmetic for free and makes the glyph follow the
          // finger instead of hanging half a body behind it.
          final local = box.globalToLocal(details.offset);
          final size = box.size;
          if (size.width <= 0 || size.height <= 0) return;
          widget.onPlace(
            details.data.bottleId,
            _permille(local.dx, size.width),
            _permille(local.dy, size.height),
          );
        },
        builder: (context, candidate, rejected) => Container(
          key: _surface,
          height: 190,
          decoration: BoxDecoration(
            color: HollowPalette.surface,
            border: Border.all(
              color: candidate.isEmpty ? HollowPalette.line : HollowPalette.gold,
              width: candidate.isEmpty ? 1 : 2,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          // LayoutBuilder rather than a fixed pixel extent: the first version of
          // this multiplied the fraction by a literal 260, which put every bottle
          // in the wrong place on any other window width. A layout that only
          // works at the size it was written at is not a layout.
          child: LayoutBuilder(
            builder: (context, constraints) => Stack(
            children: [
              // The board itself, drawn at the bottom so a bottle reads as
              // standing *on* something rather than floating in a box.
              Positioned(
                left: 0,
                right: 0,
                bottom: 26,
                child: Container(height: 2, color: HollowPalette.line),
              ),
              for (final placement in widget.standing)
                Positioned(
                  // Fractions of the measured box, so the arrangement survives a
                  // different window size, a phone rotation or a tablet. The
                  // stored value is whole per-mille; only this conversion is
                  // fractional, and it is the display's business.
                  left: placement.x * (constraints.maxWidth - 26),
                  // the bottle is 62 tall and stands on a board 26 from the
                  // bottom, so the reachable band is what is left above it
                  top: placement.y * (constraints.maxHeight - 88),
                  child: _Bottle(
                    bottleId: placement.bottleId,
                    sku:
                        widget.labels[placement.bottleId] ??
                        placement.bottleId,
                  ),
                ),
            ],
            ),
          ),
        ),
      ),
    ],
  );

  /// A pixel offset as whole per-mille, clamped into the shelf.
  ///
  /// Clamped here rather than at the write, because a drop slightly past the edge
  /// is a person aiming at the edge. The write refuses anything outside 0..1000,
  /// so a value that arrived unclamped would be silently dropped by the log.
  static int _permille(double offset, double extent) {
    final raw = (offset / extent * 1000).round();
    if (raw < 0) return 0;
    if (raw > 1000) return 1000;
    return raw;
  }
}

/// The bottles that have stock and no position yet, each one draggable.
class _Box extends StatelessWidget {
  const _Box({required this.bottleIds, required this.labels});

  final List<String> bottleIds;
  final Map<String, String> labels;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 14,
    runSpacing: 10,
    children: [
      for (final id in bottleIds)
        _Bottle(bottleId: id, sku: labels[id] ?? id),
    ],
  );
}

/// One bottle, as a glyph that can be picked up and put down.
///
/// **`LongPressDraggable`, and not because long-press is nicer.** This page is a
/// vertical `ListView`, and an immediate `Draggable` loses the gesture arena to
/// the scroll recogniser: an upward drag scrolls the page instead of lifting the
/// bottle, so a person could not place anything. Long-press wins that arena by
/// construction, which is why it is the ordinary answer for drag inside a
/// scrolling list. Two of this widget's tests found it by writing no event at all.
///
/// Deliberately not a `LiquidSwatch`: that widget draws a *drink in a glass* from
/// section 12.1's colour string, which is a fact about a recipe. A bottle on a
/// shelf is a fact about a container, and painting the drink inside it would say
/// the bottle holds one cocktail.
class _Bottle extends StatelessWidget {
  const _Bottle({required this.bottleId, required this.sku});

  final String bottleId;
  final String sku;

  @override
  Widget build(BuildContext context) {
    final glyph = Semantics(
      label: sku,
      child: Container(
        key: ValueKey('bottle-$bottleId'),
        width: 26,
        height: 62,
        decoration: BoxDecoration(
          color: HollowPalette.inkSoft,
          border: Border.all(color: HollowPalette.inkFaint),
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(4),
            bottom: Radius.circular(7),
          ),
        ),
      ),
    );

    return Tooltip(
      message: sku,
      child: LongPressDraggable<DraggedBottle>(
        data: DraggedBottle(bottleId),
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: Material(color: Colors.transparent, child: glyph),
        childWhenDragging: Opacity(opacity: 0.35, child: glyph),
        child: glyph,
      ),
    );
  }
}
