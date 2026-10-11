import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/model/ingredient.dart';
import '../domain/model/ingredient_demand.dart';
import 'ingredient_editor.dart';
import 'l10n/copy_resolution.dart';
import 'l10n/dual_copy.dart';
import 'l10n/dual_copy_text.dart';
import 'hollow_glyphs.dart';
import 'library.dart';
import 'seed_names.dart';
import 'theme.dart';

/// The reader's own ingredients, and the library's beside them.
///
/// **Stage ③'s screen, and the place an ingredient could be managed at all.** The authored-ingredient family, its
/// fold and its two write paths all landed before this, and nothing called them -- so a reader could not add the one
/// ingredient their cellar is full of. That is what the family was built for, and this is where it is used.
///
/// **It is the 原料 tab**, by the owner's instruction of 2026-10-06: it had lived at the bottom of 设置, and it is a
/// peer of 酒窖 / 配方 / 记录 rather than something buried in an application's settings. `ingredients_page.dart` is
/// the frame and this is everything in it.
///
/// **Both kinds are listed, and they are told apart.** The library's ingredients cannot be changed -- they are part
/// of the build and their ids are not `own.`-prefixed -- so a reader looking for the one they added needs to be able
/// to find it among 189 others, which is why the search field is there.
///
/// **And the 189 are drawn as two lists rather than one.** This is stage ① of `docs/catalogue-and-stock.md`, and the
/// finding behind it is the owner's: *a warehouse keeps the supplier's catalogue and its own stock as two tables and
/// never mixes them.* The tab mixed them -- it drew every ingredient the library carries, and a reader who actually
/// manages twenty of them had to find those twenty inside it. Nothing about the data changed for this: the predicate
/// already existed, as [Cellar.has], and the join is the one the shelf and every recipe score already use.
///
/// **So the reader's side is *what they hold a bottle of, plus what they wrote*, and the library's side is the
/// rest.** The two sentences that name them are [Copy.ingredientMine] and [Copy.ingredientLibrary], and the search
/// applies to both halves at once -- a reader who types a name is asking where a thing is, not which list it is in.
class IngredientSection extends ConsumerStatefulWidget {
  const IngredientSection({super.key});

  @override
  ConsumerState<IngredientSection> createState() => _IngredientSectionState();
}

/// One ingredient, and which of the two lists it is in.
///
/// **The list is the held-ness, so nothing has to carry it.** A library ingredient reaches the reader's side only
/// because a bottle of it stands on their shelf, and once it is there the partition has already said so -- a second
/// flag would be the same fact written twice, and two copies of one fact is how the two come to disagree.
///
/// **What is *not* implied by the list is whether the card may be changed**, and that is [isMine]: a library
/// ingredient the reader holds is theirs to look after and still not theirs to edit. That is the case the old
/// single list could not express, and it is the one thing the split genuinely needs a flag for.
class _Row {
  const _Row({
    required this.id,
    required this.name,
    required this.kind,
    required this.aliases,
    required this.isMine,
  });

  final String id;
  final String name;
  final String? kind;
  final List<String> aliases;
  final bool isMine;
}

class _IngredientSectionState extends ConsumerState<IngredientSection> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// The catalogue, cut in two along the line the reader's own shelf draws.
  ///
  /// **One pass, one predicate, and both lists come out of it.** `cellar.has` is asked once per library ingredient
  /// rather than once per list, and the reader's authored ingredients are placed without being asked at all -- they
  /// are theirs by construction, and a bottle of one would be a bottle whose sku happens to match an `own.` id.
  ({List<_Row> mine, List<_Row> library}) _split(List<Ingredient> library, Cellar cellar) {
    final names = ref.read(seedNamesProvider).value;
    final locale = ref.read(seedNameLocaleProvider);

    final mine = <_Row>[
      for (final authored in cellar.authoredIngredients.all)
        _Row(
          id: authored.id,
          name: authored.name,
          kind: authored.category,
          aliases: authored.aliases,
          isMine: true,
        ),
    ];
    final theirs = <_Row>[];

    for (final ingredient in library) {
      final held = cellar.has(ingredient.id);
      final row = _Row(
        id: ingredient.id,
        name: names?.nameFor(ingredient.id, locale, fallback: ingredient.name) ?? ingredient.name,
        // **The library's own two-level classification**, so a reader can see what a shipped ingredient is as well
        // as what their own is -- and so that copying a kind for their own addition means copying a real one.
        kind: ingredient.kind,
        aliases: ingredient.aliases,
        isMine: false,
      );
      // **A held library ingredient joins the reader's side, and stays read-only.** It is on their shelf, so it is
      // theirs to look after; it is still part of the build, so it is not theirs to change. Both facts survive,
      // which is the reason the two flags are separate.
      (held ? mine : theirs).add(row);
    }

    final needle = _search.text.trim().toLowerCase();
    bool matches(_Row v) =>
        needle.isEmpty ||
        v.name.toLowerCase().contains(needle) ||
        (v.kind ?? '').toLowerCase().contains(needle) ||
        v.aliases.any((a) => a.toLowerCase().contains(needle));

    // **Alphabetical within each half rather than the reader's own first.** The two halves are already the
    // grouping; sorting a half by anything else would make it two groups wearing one heading, and the glyph and the
    // border already say which cards are editable.
    mine.sort((a, b) => a.name.compareTo(b.name));
    theirs.sort((a, b) => a.name.compareTo(b.name));
    return (mine: mine.where(matches).toList(), library: theirs.where(matches).toList());
  }

  @override
  Widget build(BuildContext context) {
    final seed = ref.watch(seedProvider).value;
    final cellar = ref.watch(cellarProvider).value;
    if (seed == null || cellar == null) return const SizedBox.shrink();

    final split = _split(seed.ingredients, cellar);
    final mineCount = cellar.authoredIngredients.length;
    final heldCount = split.mine.where((row) => !row.isMine).length;
    final searching = _search.text.trim().isNotEmpty;
    void open(_Row row) => showIngredientEditor(context, editing: _editing(row));

    // **The demand index is over both kinds of recipe**, and that is the same rule every fold in this application
    // follows: a drink the reader wrote is a drink, so an ingredient only their own recipe calls for is not dead.
    // The two record shapes differ (`RecipeItem` and `AuthoredItem`) and neither belongs in the index, so what is
    // handed over is the ids.
    final demand = IngredientDemand.of([
      for (final recipe in seed.recipes)
        [for (final item in recipe.items) item.ingredientId],
      for (final recipe in cellar.authoredRecipes.all)
        [for (final item in recipe.items) item.ingredientId],
    ]);

    // The library's half, cut again by how much is actually asked of it. `DemandClass.values` is already in
    // reader order -- core first, dead last -- so the iteration order is the display order and there is no second
    // place for that decision to live.
    final buckets = <DemandClass, List<_Row>>{};
    for (final row in split.library) {
      buckets.putIfAbsent(demand.classOf(row.id), () => []).add(row);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DualCopyText(Copy.ingredientHeading, style: HollowType.heading),
        const SizedBox(height: 6),
        DualCopyText(Copy.ingredientIntro, style: HollowType.caption),
        const SizedBox(height: 4),
        Text(
          // **The counts, said separately.** A reader who has added three of their own should be able to see that at
          // a glance rather than count rows in a list of 189 -- and now that the two lists are drawn apart, the
          // second number is the size of the catalogue *they are not looking after*, which is the fact the tab has
          // never been able to state.
          '$mineCount + $heldCount / ${seed.ingredients.length}',
          style: HollowType.numeric,
        ),
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey('ingredient-search'),
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: ref.copy(Copy.packFieldName)),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            key: const ValueKey('ingredient-add'),
            onPressed: () => showIngredientEditor(context),
            icon: const Icon(Icons.add, size: 18),
            label: Text(ref.copy(Copy.ingredientAdd)),
          ),
        ),
        const SizedBox(height: 18),
        _Half(
          key: const ValueKey('ingredient-group-mine'),
          heading: Copy.ingredientMine,
          count: split.mine.length,
          // **A sentence only when there is nothing to have qualified it.** With a query typed, "nothing here yet"
          // is a lie -- the half may hold twenty things and the query matched none of them -- so an empty half says
          // nothing and the one line at the foot of the page says what actually happened.
          emptyText: searching ? null : ref.copy(Copy.ingredientMineEmpty),
          children: [_Grid(rows: split.mine, onOpen: open)],
        ),
        const SizedBox(height: 20),
        _Half(
          key: const ValueKey('ingredient-group-library'),
          heading: Copy.ingredientLibrary,
          count: split.library.length,
          emptyText: searching ? null : ref.copy(Copy.ingredientLibraryEmpty),
          children: [
            for (final entry in DemandClass.values)
              if (buckets[entry] case final rows? when rows.isNotEmpty) ...[
                _Half(
                  key: ValueKey('ingredient-demand-${entry.name}'),
                  heading: _classCopy[entry]!,
                  count: rows.length,
                  // **Smaller than the two halves above it.** A class is a subdivision of the library rather than a
                  // peer of it, and the depth has to be visible or five headings read as five of the same thing.
                  style: HollowType.label,
                  children: [_Grid(rows: rows, onOpen: open)],
                ),
                const SizedBox(height: 16),
              ],
          ],
        ),
        if (searching && split.mine.isEmpty && split.library.isEmpty) ...[
          const SizedBox(height: 12),
          Text(ref.copy(Copy.ingredientNoMatch), style: HollowType.caption),
        ],
      ],
    );
  }

  /// The four class names, as copy.
  ///
  /// **A map rather than a method on the enum**, because `DemandClass` is domain vocabulary and the words a reader
  /// reads are the interface's: an enum that knew how to name itself in five languages would be a model that has
  /// to be rebuilt to change a sentence.
  static const _classCopy = <DemandClass, CopyLine>{
    DemandClass.core: Copy.demandCore,
    DemandClass.occasional: Copy.demandOccasional,
    DemandClass.rare: Copy.demandRare,
    DemandClass.dead: Copy.demandDead,
  };

  /// One row, as the editor expects it.
  ///
  /// **The conversion is here rather than on the row**, because `AuthorIngredientView` is the editor's shape and the
  /// editor is not what this screen is organized around: the split is about which list a thing is in, and the
  /// editor only ever asks whether it may be changed.
  AuthorIngredientView _editing(_Row row) => AuthorIngredientView(
    id: row.id,
    name: row.name,
    kind: row.kind,
    aliases: row.aliases,
    isMine: row.isMine,
  );
}

/// One heading, the count beside it, and whatever is under it.
///
/// **A heading and a count on one line rather than a heading and then a number**, because the number is the whole
/// point of the subdivision: *死库存 68* is the sentence stage ② exists to say, and *死库存* over a grid a reader
/// would have to count answers a different question.
///
/// **The same widget serves both depths** -- the two halves and the four classes inside the library's -- because the
/// only difference is [style]. Two widgets would have been two places to change the day a third depth arrives, and
/// the depth is already carried by the palette rather than by the layout.
class _Half extends StatelessWidget {
  const _Half({
    super.key,
    required this.heading,
    required this.count,
    required this.children,
    this.style,
    this.emptyText,
  });

  final CopyLine heading;
  final int count;
  final List<Widget> children;
  final TextStyle? style;

  /// What this part says when it has nothing in it, or null for nothing at all -- see the caller, where null means
  /// *a query is typed and the empty part is the query's doing rather than the reader's*.
  ///
  /// **[count] is what decides whether it is shown**, and that is not a detail: the first version rendered the
  /// sentence whenever one was passed, and the caller passed one unconditionally -- so the library's half said
  /// "nothing left in the library, you hold all of it" directly above four grids of the things it holds. A sentence
  /// about emptiness has to be conditional on the emptiness, and the count is the only thing here that knows.
  final String? emptyText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(child: DualCopyText(heading, style: style ?? HollowType.title)),
            const SizedBox(width: 8),
            Text('$count', style: HollowType.numeric),
          ],
        ),
        const SizedBox(height: 8),
        if (emptyText case final text? when count == 0) Text(text, style: HollowType.caption),
        ...children,
      ],
    );
  }
}

/// Two columns of cards, by the owner's instruction of 2026-10-06.
///
/// A list row carried one fact per line and this tab is a thing a reader scans rather than reads -- a name, what it
/// is, and what else it is called fit in half a phone's width, so a single column spent the other half on nothing.
/// `maxCrossAxisExtent` rather than a fixed count so that a tablet or a wide window gets more columns instead of two
/// enormous ones, which is the failure mode of a hard-coded 2.
///
/// **The grid does not scroll.** It is inside the page's own scroll view, so a scrollable here would be a second
/// scroll region nested in the first -- the thing that makes a long list feel like it is fighting the finger.
/// `shrinkWrap` measures the children and lets the page do the scrolling.
class _Grid extends StatelessWidget {
  const _Grid({required this.rows, required this.onOpen});

  final List<_Row> rows;
  final void Function(_Row) onOpen;

  @override
  Widget build(BuildContext context) => GridView.extent(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    maxCrossAxisExtent: 260,
    mainAxisSpacing: 8,
    crossAxisSpacing: 8,
    childAspectRatio: 2.6,
    children: [
      for (final row in rows)
        _IngredientCard(
          key: ValueKey('ingredient-${row.id}'),
          row: row,
          // **A long press, like a folder row**, and for the same reason: what a reader does to a card is a gesture
          // rather than a control, and the grid is dense enough that a button on every card would be the loudest
          // thing on the page. A library ingredient opens read-only rather than not at all, so a reader can see what
          // it is and copy its kind for their own addition.
          onOpen: () => onOpen(row),
        ),
    ],
  );
}

/// One ingredient, as a card.
///
/// **A card rather than a row, and the difference is what fits beside it.** A row in a list may use the full width
/// and one line per fact; a card has half a phone to work with, so the name goes on its own line and the two facts
/// that qualify it go under it in one. `maxLines: 1` with an ellipsis on both, because a card that grew to fit
/// "Plymouth Gin · spirit · Plymouth" would make its neighbours different heights and the grid ragged.
class _IngredientCard extends StatelessWidget {
  const _IngredientCard({super.key, required this.row, required this.onOpen});

  final _Row row;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final qualifiers = [
      if (row.kind != null) row.kind!,
      if (row.aliases.isNotEmpty) row.aliases.join(' · '),
    ].join('  ·  ');
    return InkWell(
      onLongPress: onOpen,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: HollowPalette.surfaceRaised,
          borderRadius: BorderRadius.circular(10),
          // **A hairline in the reader's own colour for what they added**, which is the same signal the list gave
          // with a different mark: a reader has to be able to see at a glance which cards they can change, and a
          // border is the cheapest way to say it on a surface this small. **A held library ingredient does not get
          // it** -- it is on the reader's side of the split but it still ships with the build, and a border that
          // promised an edit the editor then refused would be worse than no border.
          border: Border.all(
            color: row.isMine ? HollowPalette.rose : HollowPalette.hairline,
            width: row.isMine ? 1.2 : 1,
          ),
        ),
        child: Row(
          children: [
            HollowGlyphMark(
              row.isMine ? HollowGlyph.folder : HollowGlyph.book,
              color: row.isMine ? HollowPalette.rose : HollowPalette.gold,
              size: 16,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.name,
                    style: HollowType.body,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (qualifiers.isNotEmpty)
                    Text(
                      qualifiers,
                      style: HollowType.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
