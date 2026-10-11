import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/events/shelf.dart';
import '../domain/events/shelf_authoring.dart';
import 'ingredient_colour.dart';
import 'shelf_label.dart';
import 'l10n/copy_resolution.dart';
import 'l10n/dual_copy.dart';
import 'l10n/dual_copy_text.dart';
import 'library.dart';
import 'seed_names.dart';
import 'theme.dart';

/// **Whether the shelf is drawn, and one constant is the whole of it.**
///
/// The owner's instruction on 2026-09-30 was 吧台先卸掉 -- take the bar off first -- and the reading
/// confirmed with them was: hide it from the interface, keep the code, and correct the record. So this
/// is `false`, `CellarPage` consults it at the one place it used to draw `BarShelfSection`, and nothing
/// else about the feature changed. **Setting it back to `true` is the whole of bringing it back**, which
/// is the property that makes hiding different from deleting.
///
/// It is a constant rather than a setting on purpose. A setting would put the choice in the reader's
/// hands for something that is not a preference but a decision about what this build ships, and it would
/// need a line of copy, a stored value and a migration -- a screen's worth of machinery for a feature
/// being paused.
const bool shelfPlacementIsShown = true;

/// One shelf of section 12.2: the bottles, standing where they were put.
///
/// **A section of the Cellar page rather than a tab of its own**, by the owner's decision of 2026-09-27:
/// 把「吧台」并进「酒窖」. The reason is in `DESIGN.md` 14.0.3 -- a shelf answers *where is the vermouth*, and it can
/// only answer that if a reader can tell the bottles apart; the page that carries the names, the values and the
/// curves was one tab away, so the two belong on one screen.
///
/// **And it is not drawn at the moment**: see [shelfPlacementIsShown]. Everything below still holds, and
/// the tests below still exercise it -- they build this widget directly rather than reaching it through
/// the cellar, which is why hiding it leaves them honest rather than stale.
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
class BarShelfSection extends ConsumerStatefulWidget {
  const BarShelfSection({super.key});

  @override
  ConsumerState<BarShelfSection> createState() => _BarShelfSectionState();
}

class _BarShelfSectionState extends ConsumerState<BarShelfSection> {
  /// Which shelf the reader is looking at, or null for *whichever comes first*.
  ///
  /// **Null rather than a default id**, because the first shelf may be one they have not named yet and the list is
  /// the fold's answer rather than the screen's. A reader who has just added a shelf is moved to it by [_addShelf];
  /// one who removes the shelf they are on falls back to the first, which is why the fallback is resolved on every
  /// build rather than fixed once.
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final cellar = ref.watch(cellarProvider);

    return SafeArea(
      child: cellar.when(
        // **Bounded, because this is a section inside somebody else’s scroll view now.** A bare `Center`
        // takes whatever height it is offered, and inside a `ListView` that is unbounded -- which is what the
        // `_ViewportElement` null check was complaining about once the shelf became a section of the cellar.
        loading: () => const SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (error, _) => Center(
          child: Text('${ref.copy(Copy.barTitle)}: $error', style: HollowType.body),
        ),
        data: (state) {
          final shelves = state.shelfIds;
          final selected = (_selected != null && shelves.contains(_selected))
              ? _selected!
              : (shelves.isEmpty ? builtInShelfId : shelves.first);

          final onHand = [
            for (final bottle in state.stock.bottles)
              if (bottle.remaining.microlitres > 0) bottle,
          ];
          final onHandIds = {for (final bottle in onHand) bottle.bottleId};

          final placed = state.shelf.onShelf(selected);
          final standing = [
            for (final placement in placed)
              if (onHandIds.contains(placement.bottleId)) placement,
          ];
          final placedButEmpty = [
            for (final placement in placed)
              if (!onHandIds.contains(placement.bottleId)) placement,
          ];
          final inTheBox = state.shelf.unplacedAmong(onHandIds);

          // **Two facts about each bottle's ingredient, resolved once.** The old page labelled every bottle with
          // its *sku*, so even the tooltip said `gin`; the name here is the one the rest of the application shows,
          // and the kind is what colours it.
          final look = <String, _Look>{
            for (final bottle in onHand) bottle.bottleId: _lookUp(ref, state, bottle.sku),
          };

          // **Shrink-wrapped and non-scrolling.** The cellar page owns the scroll, and a second scroll view
          // inside it would fight for the gesture and be offered an unbounded height.
          return ListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            children: [
              DualCopyText(Copy.barTitle, style: HollowType.display),
              const SizedBox(height: 12),
              _ShelfChooser(
                shelves: shelves,
                selected: selected,
                nameOf: (id) => shelfName(ref, state, id),
                onSelect: (id) => setState(() => _selected = id),
                onAdd: () => _addShelf(context, state),
                onRename: (id) => _renameShelf(context, state, id),
              ),
              const SizedBox(height: 16),
              // **No `shelves.isEmpty` branch**, because `Cellar.shelfIds` always offers at least the built-in
              // shelf -- a cellar with bottles and nothing placed on them would otherwise have nowhere to put the
              // first one. A branch for a state that cannot happen is a branch no test can reach.
              ...[
                _ShelfBoard(
                  shelfId: selected,
                  shelfNameWidget: shelfName(ref, state, selected, style: HollowType.caption),
                  standing: standing,
                  labels: look,
                  onPlace: (bottleId, x, y) => ref
                      .read(cellarProvider.notifier)
                      .placeBottle(
                        bottleId: bottleId,
                        shelfId: selected,
                        posXPermille: x,
                        posYPermille: y,
                      ),
                ),
                const SizedBox(height: 10),
                if (standing.isEmpty)
                  DualCopyText(Copy.barShelfEmpty, style: HollowType.caption),
                if (placedButEmpty.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  DualCopyText(Copy.barPlacedButEmpty, style: HollowType.caption),
                ],
              ],
              const SizedBox(height: 28),
              DualCopyText(Copy.barInTheBox, style: HollowType.heading),
              const SizedBox(height: 8),
              if (inTheBox.isEmpty)
                DualCopyText(Copy.barNothingToPlace, style: HollowType.caption)
              else
                _Box(bottleIds: inTheBox, labels: look),
              const SizedBox(height: 12),
              DualCopyText(Copy.barDragHint, style: HollowType.caption),
            ],
          );
        },
      ),
    );
  }

  /// The name and the kind of whatever [sku] is.
  ///
  /// **Both questions asked in one place**, because a bottle is named by whichever book holds its ingredient: one
  /// the reader wrote is theirs, and one the library ships has to be translated for the language on screen.
  static _Look _lookUp(WidgetRef ref, Cellar state, String sku) {
    final authored = state.authoredIngredients[sku];
    if (authored != null) return (label: authored.name, kind: authored.category);
    final ingredient = ref.read(seedProvider).value?.ingredientById(sku);
    if (ingredient == null) return (label: sku, kind: null);
    final names = ref.read(seedNamesProvider).value;
    final locale = ref.read(seedNameLocaleProvider);
    return (
      label: names?.nameFor(ingredient.id, locale, fallback: ingredient.name) ?? ingredient.name,
      kind: ingredient.kind,
    );
  }

  /// Asks for a name and adds a shelf, then looks at it.
  ///
  /// **Selecting the new shelf is the point rather than a nicety**: a reader adds a shelf in order to put something
  /// on it, and leaving them looking at the one they were already on would make the gesture appear to do nothing.
  Future<void> _addShelf(BuildContext context, Cellar state) async {
    final name = await _askForName(context, title: Copy.shelfAdd, initial: '');
    if (name == null) return;
    final added = await ref.read(cellarProvider.notifier).declareShelf(name);
    if (added != null && mounted) setState(() => _selected = added.id);
  }

  /// Renames one, or takes its name away, from a sheet opened on a long press.
  Future<void> _renameShelf(BuildContext context, Cellar state, String id) async {
    final mine = state.shelves.isMine(id);
    final choice = await showModalBottomSheet<_ShelfAction>(
      // **`useSafeArea: true`**, the rule every sheet in this application follows: the default removes the top
      // padding and puts the first line of a sheet under the notch.
      context: context,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: DualCopyText(Copy.shelfRename, style: HollowType.body),
              enabled: mine,
              onTap: () => Navigator.of(context).pop(_ShelfAction.rename),
            ),
            ListTile(
              title: DualCopyText(Copy.shelfForget, style: HollowType.body),
              subtitle: DualCopyText(Copy.shelfForgetHint, style: HollowType.caption),
              enabled: mine,
              onTap: () => Navigator.of(context).pop(_ShelfAction.forget),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    if (choice == _ShelfAction.forget) {
      await ref.read(cellarProvider.notifier).removeAuthoredShelf(id);
      return;
    }
    final name = await _askForName(context, title: Copy.shelfRename, initial: state.shelves.nameOf(id));
    if (name == null) return;
    await ref.read(cellarProvider.notifier).declareShelf(name, id: id);
  }

  Future<String?> _askForName(
    BuildContext context, {
    required CopyLine title,
    required String initial,
  }) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _NameDialog(title: title, initial: initial),
    );
    return (name == null || name.trim().isEmpty) ? null : name;
  }
}

/// The one-field dialog a shelf's name is typed into.
///
/// **Stateful so that it owns its controller**, and that is a fix rather than a style: the first version created the
/// controller in the caller and disposed it on the line after `showDialog` returned, which is *while the route is
/// still popping*. The field was therefore still attached to a disposed controller for the length of the exit
/// animation, and Flutter threw `'attached': is not true` from the rendering object -- three exceptions per naming,
/// in the tests and in the application alike. A controller belongs to the widget that shows the field, so that it is
/// disposed when that widget is and not a frame earlier.
class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, required this.initial});

  final CopyLine title;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _field = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: DualCopyText(widget.title, style: HollowType.title),
    content: TextField(
      key: const ValueKey('shelf-name'),
      controller: _field,
      autofocus: true,
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
      ),
      FilledButton(
        key: const ValueKey('shelf-name-confirm'),
        onPressed: () => Navigator.of(context).pop(_field.text),
        child: Text(MaterialLocalizations.of(context).okButtonLabel),
      ),
    ],
  );
}

/// What a long press on a shelf can do.
enum _ShelfAction { rename, forget }

/// The row of shelves, and the offer to add one.
///
/// **A chooser over one shelf would have been furniture**, which is what this file said when it hard-coded `bar` --
/// and that was right at the time, because nothing could make a second one. `shelf.authored.declared` can, so the
/// picker is now the thing it was waiting for.
class _ShelfChooser extends StatelessWidget {
  const _ShelfChooser({
    required this.shelves,
    required this.selected,
    required this.nameOf,
    required this.onSelect,
    required this.onAdd,
    required this.onRename,
  });

  final List<String> shelves;
  final String selected;
  final Widget Function(String id) nameOf;
  final void Function(String id) onSelect;
  final VoidCallback onAdd;
  final void Function(String id) onRename;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final id in shelves)
        GestureDetector(
          // **A long press rather than a second tap**, the idiom the ingredient cards and the folder rows already
          // use: what a reader does to a chip is choose it, and the rarer thing it can do is a gesture rather than
          // a control that would sit on every chip in the row.
          onLongPress: () => onRename(id),
          child: ChoiceChip(
            key: ValueKey('shelf-chip-$id'),
            label: nameOf(id),
            selected: id == selected,
            onSelected: (_) => onSelect(id),
          ),
        ),
      ActionChip(
        key: const ValueKey('shelf-add'),
        avatar: const Icon(Icons.add, size: 16),
        label: Text(Copy.shelfAdd.textFor(Localizations.localeOf(context).toLanguageTag())),
        onPressed: onAdd,
      ),
    ],
  );
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
    required this.shelfNameWidget,
    required this.standing,
    required this.labels,
    required this.onPlace,
  });

  final String shelfId;

  /// What this shelf is called, resolved by the caller: a reader's own word for it, or the built-in one's copy.
  ///
  /// **A widget rather than a string**, because the built-in shelf's name is copy and a reader's is data -- and copy
  /// in this application has two registers when the reader has asked for both.
  final Widget shelfNameWidget;
  final List<BottlePlacement> standing;
  final Map<String, _Look> labels;
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
      widget.shelfNameWidget,
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
                  left: placement.x * (constraints.maxWidth - _Bottle.width),
                  // the bottle is 62 tall plus its name, and stands on a board
                  // 26 from the bottom, so the reachable band is what is left
                  top: placement.y * (constraints.maxHeight - _Bottle.reach),
                  child: _Bottle(
                    bottleId: placement.bottleId,
                    label: widget.labels[placement.bottleId]?.label ?? placement.bottleId,
                    kind: widget.labels[placement.bottleId]?.kind,
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
  final Map<String, _Look> labels;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 10,
    children: [
      for (final id in bottleIds)
        _Bottle(
          bottleId: id,
          label: labels[id]?.label ?? id,
          kind: labels[id]?.kind,
          // **Draggable here too**, which is what makes the box worth drawing: a bottle in it has no position, and
          // the only way to give it one is to pick it up.
        ),
    ],
  );
}

/// How a bottle is named and coloured: two facts about its ingredient, looked up once.
///
/// **A record rather than two parallel maps**, because the two are always wanted together and two maps keyed by the
/// same id are two things that can disagree about which bottle they describe.
typedef _Look = ({String label, String? kind});

/// One bottle, as a glyph that can be picked up and put down.
///
/// **`LongPressDraggable`, and not because long-press is nicer.** This page is a
/// vertical `ListView`, and an immediate `Draggable` loses the gesture arena to
/// the scroll recogniser: an upward drag scrolls the page instead of lifting the
/// bottle, so a person could not place anything. Long-press wins that arena by
/// construction, which is why it is the ordinary answer for drag inside a
/// scrolling list. Two of this widget's tests found it by writing no event at all.
///
/// **Coloured by the ingredient's kind, and named underneath** -- the two fixes for the report that took this page
/// off the interface on 2026-09-30. The paragraph that used to stand here refused a `LiquidSwatch` because a drink's
/// colour is a fact about a recipe and painting it on a bottle would say the bottle holds one cocktail. **That
/// reasoning was sound and the screen it produced was a wall of identical grey rectangles**, which is what
/// *"没有颜色区分，很鸡肋"* describes. `ingredient_colour.dart` records the resolution: a colour per `kind`, which is
/// a fact about the ingredient and is complete over the library, standing beside the name so that the colour is
/// never the only thing a reader has to go on.
///
/// **The name is drawn rather than left to a tooltip.** A tooltip was the whole of it before, and a tooltip on a
/// handset does not appear -- so the shelf's labels existed only for a reader with a mouse, which is the wrong half
/// of the audience for a thing you look at while standing in a kitchen. It is also the *display* name now rather
/// than the sku: the old label was the ingredient id, so even the tooltip said `gin` rather than `Gin`.
class _Bottle extends StatelessWidget {
  const _Bottle({
    required this.bottleId,
    required this.label,
    required this.kind,
  });

  final String bottleId;
  final String label;
  final String? kind;

  /// How wide a bottle is, which is also how wide its name has to fit.
  static const width = 46.0;

  /// The vertical band a bottle's top can be dropped in, given a board 26 from the bottom of a 190-tall surface:
  /// the glyph, the gap, the name line, and the board. **Kept here rather than in the layout arithmetic**, because
  /// the number changed when the name was added and the two places it is used would otherwise have to be found.
  static const reach = 62 + 4 + 20 + 26;

  @override
  Widget build(BuildContext context) {
    final glyph = Semantics(
      label: label,
      child: SizedBox(
        width: width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              key: ValueKey('bottle-$bottleId'),
              width: 26,
              height: 62,
              decoration: BoxDecoration(
                color: ingredientKindColour(kind),
                border: Border.all(color: HollowPalette.inkFaint),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(4),
                  bottom: Radius.circular(7),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: HollowType.caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );

    return Tooltip(
      message: label,
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
