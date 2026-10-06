import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/model/ingredient.dart';
import 'ingredient_editor.dart';
import 'l10n/copy_resolution.dart';
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
/// **It lives in 设置 rather than on a tab of its own**, because it is a thing a reader does occasionally rather than
/// a place they work: the tabs are the cellar, the recipes, the record and the settings, and an ingredient list is
/// maintenance rather than any of those four. It sits above the developer section, which is where the page puts the
/// things that are about the application rather than about the cellar.
///
/// **Both kinds are listed, and they are told apart.** The library's ingredients cannot be changed -- they are part
/// of the build and their ids are not `own.`-prefixed -- so a reader looking for the one they added needs to be able
/// to find it among 189 others, which is why the search field is there and why the reader's own sort to the top.
class IngredientSection extends ConsumerStatefulWidget {
  const IngredientSection({super.key});

  @override
  ConsumerState<IngredientSection> createState() => _IngredientSectionState();
}

class _IngredientSectionState extends ConsumerState<IngredientSection> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Everything, with the reader's own first and both in a stable order.
  List<AuthorIngredientView> _rows(List<Ingredient> library, Cellar cellar) {
    final names = ref.read(seedNamesProvider).value;
    final locale = ref.read(seedNameLocaleProvider);
    String shown(Ingredient i) => names?.nameFor(i.id, locale, fallback: i.name) ?? i.name;

    final mine = [
      for (final authored in cellar.authoredIngredients.all)
        AuthorIngredientView(
          id: authored.id,
          name: authored.name,
          kind: authored.category,
          aliases: authored.aliases,
          note: authored.note,
          isMine: true,
        ),
    ];
    final theirs = [
      for (final ingredient in library)
        AuthorIngredientView(
          id: ingredient.id,
          name: shown(ingredient),
          // **The library's own two-level classification**, so a reader can see what a shipped ingredient is as well
          // as what their own is -- and so that copying a kind for their own addition means copying a real one.
          kind: ingredient.kind,
          aliases: ingredient.aliases,
          note: ingredient.note,
          isMine: false,
        ),
    ];
    mine.sort((a, b) => a.name.compareTo(b.name));
    theirs.sort((a, b) => a.name.compareTo(b.name));

    final needle = _search.text.trim().toLowerCase();
    bool matches(AuthorIngredientView v) =>
        needle.isEmpty ||
        v.name.toLowerCase().contains(needle) ||
        (v.kind ?? '').toLowerCase().contains(needle) ||
        v.aliases.any((a) => a.toLowerCase().contains(needle));

    return [
      ...mine.where(matches),
      ...theirs.where(matches),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final seed = ref.watch(seedProvider).value;
    final cellar = ref.watch(cellarProvider).value;
    if (seed == null || cellar == null) return const SizedBox.shrink();

    final rows = _rows(seed.ingredients, cellar);
    final mineCount = cellar.authoredIngredients.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DualCopyText(Copy.ingredientHeading, style: HollowType.heading),
        const SizedBox(height: 6),
        DualCopyText(Copy.ingredientIntro, style: HollowType.caption),
        const SizedBox(height: 4),
        Text(
          // **The two counts, said separately.** A reader who has added three of their own should be able to see that
          // at a glance rather than count rows in a list of 189.
          '$mineCount / ${seed.ingredients.length}',
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
        const SizedBox(height: 12),
        for (final row in rows)
          ListTile(
            key: ValueKey('ingredient-${row.id}'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: HollowGlyphMark(
              // **The reader's own get a different mark**, because that is the fastest way to see which rows can be
              // edited -- and the alternative, a note repeated on every one, is the same information at a worse cost.
              row.isMine ? HollowGlyph.folder : HollowGlyph.book,
              color: row.isMine ? HollowPalette.rose : HollowPalette.gold,
            ),
            title: Text(row.name, style: HollowType.body),
            subtitle: Text(
              [if (row.kind != null) row.kind!, if (row.aliases.isNotEmpty) row.aliases.join(' · ')].join('  '),
              style: HollowType.caption,
            ),
            // **A long press, like a folder row**, and for the same reason: the list's job is to be scanned, so the
            // affordance for changing a row is the gesture a reader already uses to act on one. A library ingredient
            // opens read-only rather than not at all, so a reader can see what it is and copy its kind.
            onLongPress: () => showIngredientEditor(context, editing: row),
          ),
        if (rows.isEmpty) ...[
          const SizedBox(height: 8),
          Text(ref.copy(Copy.stockNoVocabulary), style: HollowType.caption),
        ],
      ],
    );
  }
}
