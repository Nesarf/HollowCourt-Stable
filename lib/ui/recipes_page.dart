import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/matching/match_score.dart';
import '../domain/model/item_role.dart';
import '../domain/model/recipe.dart';
import '../data/folder_styles.dart';
import '../domain/model/recipe_folders.dart';
import 'hollow_glyphs.dart';
import 'folder_providers.dart';
import '../domain/overlay/overlay_key.dart';
import '../ui/library.dart';
import '../ui/liquid_swatch.dart';
import 'prism.dart';
import 'seed_names.dart';
import '../ui/theme.dart';
import 'l10n/dual_copy_text.dart';

/// Section 12.3's Recipes tab, at P1's scope.
///
/// Section 12.3 asks for "a recipe list with match badges; filter by
/// makeability, flavour, base spirit, glassware". **Makeability is the filter
/// built here**, because it is the one P1's acceptance criterion needs and the
/// one that only exists once the shelf and the seed are wired to each other. The
/// other three are filters over fields the seed already carries, so they are
/// cheap and simply not done yet rather than blocked.
class RecipesPage extends ConsumerStatefulWidget {
  const RecipesPage({super.key});

  @override
  ConsumerState<RecipesPage> createState() => _RecipesPageState();
}

enum _Filter { everything, makeable, close }

class _RecipesPageState extends ConsumerState<RecipesPage> {
  _Filter _filter = _Filter.everything;

  /// **The folder that is open, or null for the folder list.** The owner asked for the IBA list to have its
  /// own column, shaped like a notes application's folders: you see the folders, you open one, you come back.
  /// One level, because a second level would be a tree nobody asked for and this is a library of a hundred
  /// drinks, not of ten thousand notes.
  String? _openFolder;

  @override
  Widget build(BuildContext context) {
    final seed = ref.watch(seedProvider);
    final cellar = ref.watch(cellarProvider);

    if (seed.isLoading || cellar.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final repository = seed.value;
    final state = cellar.value;
    if (repository == null) {
      return const _NoLibrary();
    }
    if (state == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // The translation table and the reader's language, read once for the whole list -- and **above the sort**,
    // which needs them: a list ordered by an English name it never draws is the defect this ordering fixes.
    final names = ref.watch(seedNamesProvider).value;
    final locale = ref.watch(seedNameLocaleProvider);

    // Scored by whether the shelf can actually make it, then madeable drinks
    // first -- which is the order a bar wants and not the order the seed happens
    // to be in.
    final scored = [
      for (final recipe in repository.recipes)
        (recipe: recipe, score: state.scoreOf(recipe)),
    ];
    // **Sorted by the name the reader is looking at.** The comparator used the seed's English while the row
    // drew the same string, so between the two fixes the list would have been ordered by a name that is nowhere
    // on the screen -- alphabetical for a reader who sees 内格罗尼 under "Negroni".
    String shown(Recipe recipe) =>
        names?.nameFor(recipe.id, locale, fallback: recipe.name) ?? recipe.name;
    scored.sort((a, b) {
      final rank = _rank(a.score.verdict).compareTo(_rank(b.score.verdict));
      if (rank != 0) return rank;
      return shown(a.recipe).compareTo(shown(b.recipe));
    });

    final visible = switch (_filter) {
      _Filter.everything => scored,
      _Filter.makeable =>
        scored.where((s) => s.score.verdict == MatchVerdict.makeable).toList(),
      _Filter.close =>
        scored.where((s) => s.score.verdict == MatchVerdict.close).toList(),
    };

    // **The folder list, and the one that is open.** Derived from what the filter left visible, so a folder
    // count is a count of what the reader can actually see -- a folder that said "12" while its contents were
    // filtered to three would be a number that argues with the screen.
    // **The reader's own names and order, laid over what the data derives.** A folder is still derived; a style
    // is an override on top of it, so a reader who has renamed nothing sees exactly the folders they saw before
    // -- and one who has renamed something keeps their words across updates, because the styles live beside the
    // cellar rather than inside the build.
    final styles = ref.watch(folderStylesProvider).asData?.value ?? const <String, FolderStyle>{};
    final folders = foldersOf(visible.map((e) => e.recipe));
    folders.sort((a, b) {
      final ao = styles[a.key]?.order;
      final bo = styles[b.key]?.order;
      if (ao == null && bo == null) return 0; // the derived order stands
      if (ao == null) return 1;
      if (bo == null) return -1;
      return ao.compareTo(bo);
    });
    final openFolder = _openFolder == null
        ? null
        : folders.where((f) => f.key == _openFolder).firstOrNull;
    final rows = openFolder == null
        ? folders.length + 1
        : openFolder.recipes.length + 1;

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DualCopyText(Copy.recipesTitle, style: HollowType.display),
                  const SizedBox(height: 4),
                  Text(
                    Copy.withCount(Copy.recipesCount, visible.length),
                    style: HollowType.caption,
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final filter in _Filter.values)
                        ChoiceChip(
                          label: Text(switch (filter) {
                            _Filter.everything => Copy.filterAll,
                            _Filter.makeable => Copy.verdictMakeable,
                            _Filter.close => Copy.verdictClose,
                          }, style: HollowType.caption),
                          selected: _filter == filter,
                          onSelected: (_) => setState(() => _filter = filter),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SliverList.builder(
            itemCount: rows,
            itemBuilder: (context, index) {
              // **Folders first, then the drinks inside one.** The same builders serve both levels so that
              // the filter chips above keep meaning the same thing either way -- a filter applied to a folder
              // is a filter applied to its contents.
              if (_openFolder == null) {
                if (index < folders.length) {
                  final folder = folders[index];
                  final style = styles[folder.key];
                  // **The motif between rows**, at the smallest size it survives (10 px -- the size the study
                  // measured in a rhythm game's own dividers). It is here rather than in a special place because this is
                  // the list a reader scans to find a drink: the motif is what the interface looks like when
                  // nobody is looking at anything in particular.
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (index > 0)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 4),
                          child: PrismDivider(size: 8),
                        ),
                      ListTile(
                    key: ValueKey('folder-${folder.key}'),
                    // **This project's own marks, not Material's icon font.** The folder row was using
                    // `menu_book_outlined` and `folder_outlined`, which is the same borrowing the navigation bar
                    // was cured of -- and this is the row a reader scans most often.
                    leading: HollowGlyphMark(
                      folder.isOfficial ? HollowGlyph.book : HollowGlyph.folder,
                      color: style?.accent != null
                          ? _colourOf(style!.accent!)
                          : HollowPalette.gold,
                    ),
                    title: Text(style?.name ?? folder.label, style: HollowType.title),
                    subtitle: Text(
                      style?.note ?? '${folder.count}',
                      style: HollowType.caption,
                    ),
                        onTap: () => setState(() => _openFolder = folder.key),
                      ),
                    ],
                  );
                }
                if (index == folders.length) {
                  return const SizedBox(height: 8);
                }
                return const SizedBox.shrink();
              }

              final open = openFolder;
              if (open == null) return const SizedBox.shrink();
              if (index == 0) {
                return ListTile(
                  key: const ValueKey('folder-back'),
                  leading: const Icon(Icons.arrow_back),
                  title: Text(open.label, style: HollowType.title),
                  subtitle: DualCopyText(Copy.folderBack, style: HollowType.caption),
                  onTap: () => setState(() => _openFolder = null),
                );
              }
              final entry = visible.firstWhere((e) => e.recipe.id == open.recipes[index - 1].id);
              // Read once and used twice: for the flag the row draws and for the value the
              // toggle decides against. Reading it from `state` rather than from the widget
              // is what makes the toggle and the icon agree -- a toggle that flipped its own
              // local state would drift from the overlay the moment anything re-folded.
              final isPlanned =
                  state.overlay.value(
                    OverlayKey.recipe(entry.recipe.id, 'plan'),
                  ) ==
                  '1';
              return _RecipeRow(
                recipe: entry.recipe,
                score: entry.score,
                // The reader's language and their translation table, passed rather than looked up: the row is
                // a `StatelessWidget` and has no `ref`, which is the same reason `hasNote` is passed beside it.
                names: names,
                locale: locale,
                // Section 8's overlay, read here because this is where the fold is:
                // the row has no `ref`, so a note reaches it as a fact about the
                // recipe rather than being looked up beside it.
                hasNote: state.overlay.recipeNote(entry.recipe.id) != null,
                planned: isPlanned,
                onTogglePlan: () {
                  final notifier = ref.read(cellarProvider.notifier);
                  if (isPlanned) {
                    notifier.clearOverlay(
                      OverlayKey.recipe(entry.recipe.id, 'plan'),
                    );
                  } else {
                    notifier.setOverlay(
                      OverlayKey.recipe(entry.recipe.id, 'plan'),
                      '1',
                    );
                  }
                },
                onTap: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: HollowPalette.surface,
                  builder: (_) => _RecipeSheet(
                    recipe: entry.recipe,
                    score: entry.score,
                  ),
                ),
              );
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  static int _rank(MatchVerdict verdict) => switch (verdict) {
    MatchVerdict.makeable => 0,
    MatchVerdict.close => 1,
    MatchVerdict.insufficient => 2,
  };
}

class _NoLibrary extends StatelessWidget {
  const _NoLibrary();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // **The motif in the empty state**, and this is the landing that matters most: an empty screen is the
          // one a reader looks at longest, and a shape there says the application is furnished rather than
          // broken (DESIGN.md 12.9.1).
          const Prism(size: 28, facet: false),
          const SizedBox(height: 14),
          DualCopyText(Copy.recipesEmpty, style: HollowType.heading),
          const SizedBox(height: 10),
          DualCopyText(
            Copy.noLibraryHint,
            style: HollowType.body.copyWith(color: HollowPalette.inkSoft),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

class _RecipeRow extends StatelessWidget {
  const _RecipeRow({
    required this.recipe,
    required this.score,
    required this.names,
    required this.locale,
    required this.hasNote,
    required this.planned,
    required this.onTogglePlan,
    required this.onTap,
  });

  final Recipe recipe;

  /// The translation table, or null when it has not loaded: a row that cannot translate shows the drink's own
  /// instructions rather than an empty space.
  final SeedNames? names;

  /// The reader's language, as every text lookup in this application needs it.
  final String locale;
  final MatchScore score;

  /// Whether this recipe is on the plan, which is what the shopping list is derived from.
  ///
  /// A fact about the overlay like [hasNote], and passed in for the same reason: a recipe
  /// cannot know what a person put on top of it. `OverlayKey.recipe(id, 'plan')` is the
  /// key, so no new storage was invented for it -- section 8's dividend is that the event
  /// log is already an overlay layer.
  final bool planned;

  final VoidCallback onTogglePlan;

  /// Whether somebody wrote a note on this recipe.
  ///
  /// A fact about the overlay and not about the recipe, which is why it is passed
  /// in: a recipe cannot know what a person put on top of it, and a marker drawn
  /// from the seed would be claiming the library shipped one.
  final bool hasNote;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Row(
        children: [
          LiquidSwatch(liquid: recipe.liquid, glass: recipe.glass, ice: recipe.ice),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // **The drink's name in the reader's language, and this was the reported defect.**
                // `data/names/names.json` has carried all 88 official names in zh-Hans, zh-HK, zh-TW and ja
                // since the owner asked for them, and this row drew `recipe.name` -- the seed's English --
                // because the table was only ever consulted for the *steps*. The fields were already passed in
                // here and unused, which is how it went unnoticed: `names` and `locale` sat beside a line that
                // did not read them.
                Text(
                  names?.nameFor(recipe.id, locale, fallback: recipe.name) ?? recipe.name,
                  style: HollowType.title,
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    if (recipe.origin != null) recipe.origin!,
                    '${recipe.items.length} 味',
                  ].join(' · '),
                  style: HollowType.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onTogglePlan,
            visualDensity: VisualDensity.compact,
            tooltip: Copy.recipePlan,
            icon: Icon(
              planned ? Icons.bookmark : Icons.bookmark_border,
              size: 17,
              color: planned ? HollowPalette.gold : HollowPalette.inkFaint,
              semanticLabel: planned ? Copy.recipePlanned : Copy.recipeNotPlanned,
            ),
          ),
          if (hasNote) ...[
            const SizedBox(width: 8),
            Icon(
              Icons.sticky_note_2_outlined,
              size: 14,
              color: HollowPalette.inkFaint,
              semanticLabel: Copy.recipeHasNote,
            ),
          ],
          const SizedBox(width: 12),
          _VerdictBadge(score: score),
        ],
      ),
    ),
  );
}

class _VerdictBadge extends StatelessWidget {
  const _VerdictBadge({required this.score});

  final MatchScore score;

  @override
  Widget build(BuildContext context) {
    final (label, colour) = switch (score.verdict) {
      MatchVerdict.makeable => (Copy.verdictMakeable, HollowPalette.gold),
      MatchVerdict.close => (Copy.verdictClose, HollowPalette.rose),
      MatchVerdict.insufficient => (Copy.verdictInsufficient, HollowPalette.absent),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(label, style: HollowType.caption.copyWith(color: colour)),
        const SizedBox(height: 2),
        // **The second line counts what is missing from the drink itself, and
        // the garnish is deliberately not in that count.** The first version
        // showed "ingredients complete" whenever the *garnish* was complete, so
        // a drink missing its vermouth read as "insufficient" and "ingredients
        // complete" at the same time -- two lines contradicting each other, on
        // the real screen, on the very first run.
        //
        // Section 9 scores the garnish apart precisely so a missing twist of
        // peel cannot make a Negroni look impossible. Saying "only the garnish
        // is missing" is honest exactly when that is all that is missing.
        Text(
          verdictDetail(score),
          style: HollowType.caption.copyWith(color: HollowPalette.inkFaint),
        ),
      ],
    );
  }

}

/// The second line of a recipe's badge: what is missing from the drink.
///
/// **A function rather than a branch inside the widget, because the first
/// version of this was wrong on the phone and the fix has to stay fixed.** It
/// reported "ingredients complete" whenever the *garnish* was complete, so a
/// drink missing its vermouth read as `insufficient` and `ingredients complete`
/// on the same two lines. Counting the drink separately from the garnish is the
/// only reading that cannot contradict the verdict above it.
///
/// Section 9 scores the garnish apart precisely so a missing twist of peel
/// cannot make a Negroni look impossible; this is that decision, on screen.
String verdictDetail(MatchScore score) {
  final missingDrink =
      score.missing.where((r) => r.role != ItemRole.garnish).length;
  if (missingDrink > 0) {
    return Copy.withCount(Copy.recipesMissingCount, missingDrink);
  }
  final missingGarnish =
      score.missing.where((r) => r.role == ItemRole.garnish).length;
  if (missingGarnish > 0) return Copy.recipesGarnishOnly;
  return Copy.recipesNothingMissing;
}

/// One recipe in full: what it needs, what the shelf has, and the pour.
class _RecipeSheet extends ConsumerWidget {
  const _RecipeSheet({required this.recipe, required this.score});

  final Recipe recipe;
  final MatchScore score;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cellar = ref.watch(cellarProvider).value;
    // The two things the steps need, read here because this is the widget that draws them.
    final sheetNames = ref.watch(seedNamesProvider).value;
    final sheetLocale = ref.watch(seedNameLocaleProvider);
    // **Both insets, and the second one was missing.** viewInsets is the
    // keyboard; padding is the system navigation bar. A sheet that accounts
    // only for the keyboard puts its button under the navigation bar when the
    // keyboard is down, which is exactly what the first run on the phone did.
    final insets = MediaQuery.viewInsetsOf(context);
    final systemPadding = MediaQuery.paddingOf(context);
    final canMix = score.verdict == MatchVerdict.makeable;

    // **Scrollable, and it was not before.** This sheet has grown three times now --
    // steps, items, and section 8's note field -- and a `Column` that only ever grows
    // eventually grows past a phone and hides its own button. That is the same class
    // of mistake as the navigation-bar one the two inset comments above record, found
    // the same way.
    //
    // `SingleChildScrollView` carries the padding itself rather than being wrapped in
    // a `Padding`, so the widget tree keeps the depth it had and this stays a
    // one-widget change instead of a re-indent of the whole sheet.
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + insets.bottom + systemPadding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LiquidSwatch(
                liquid: recipe.liquid,
                glass: recipe.glass,
                ice: recipe.ice,
                width: 52,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sheetNames?.nameFor(recipe.id, sheetLocale, fallback: recipe.name) ?? recipe.name,
                      style: HollowType.heading,
                    ),
                    if (recipe.subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(recipe.subtitle!, style: HollowType.caption),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      '${Copy.recipesMain} ${score.mainPercent}% · '
                      '${Copy.recipesGarnish} ${score.garnishPercent}%',
                      style: HollowType.numeric,
                    ),
                  ],
                ),
              ),
            ],
          ),
          // **The reader's instructions, or the drink's own English ones.** Falling back is deliberate: a
          // drink nobody has translated yet shows the text that exists rather than nothing, and the counter in
          // `tool/l10n_status.dart` is what says how many are still in that state. This sheet is a
          // `ConsumerWidget`, so it reads the table itself instead of being handed it.
          if ((sheetNames?.stepsFor(recipe.id, sheetLocale) ?? recipe.methodSteps).isNotEmpty) ...[
            const SizedBox(height: 14),
            for (final step
                in (sheetNames?.stepsFor(recipe.id, sheetLocale) ?? recipe.methodSteps).take(4))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(step, style: HollowType.body),
              ),
          ],
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 12),
          for (final item in recipe.items)
            _ItemRow(
              item: item,
              available: cellar?.has(item.ingredientId) ?? false,
              // **The ingredient in the reader's language too.** The same table carries all 187 of them, and the
              // sheet was drawing the seed's English for the same reason the drink name was: nothing here asked
              // for a translation.
              name: sheetNames?.nameFor(
                    item.ingredientId,
                    sheetLocale,
                    fallback:
                        ref.watch(seedProvider).value?.ingredientById(item.ingredientId)?.name ?? '',
                  ) ??
                  ref.watch(seedProvider).value?.ingredientById(item.ingredientId)?.name,
            ),
          const SizedBox(height: 14),
          _RecipeNote(recipeId: recipe.id),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: canMix && cellar != null
                  ? () async {
                      final pours = <String, int>{};
                      for (final item in recipe.items) {
                        if (item.amount <= 0) continue;
                        pours[item.ingredientId] =
                            (pours[item.ingredientId] ?? 0) + item.amount;
                      }
                      await ref
                          .read(cellarProvider.notifier)
                          .pour(pours, batchId: recipe.id);
                      if (context.mounted) Navigator.of(context).pop();
                    }
                  : null,
              child: Text(canMix ? Copy.mixIt : Copy.verdictInsufficient),
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.available, this.name});

  final RecipeItem item;
  final bool available;
  final String? name;

  @override
  Widget build(BuildContext context) {
    // A measured line shows millilitres; a counted one shows the count, because
    // section 5.2 is firm that four leaves are not millilitres and printing
    // "0 ml" there would be a worse lie than printing nothing.
    //
    // **A line with neither shows nothing, and this is a fix from the phone.**
    // It used to fall back to `originalText`, which put the importer's own
    // string on screen: a garnish row read `garnish: Lemon (Twist)` in English,
    // duplicating the 装饰 tag already beside it. `originalText` is the
    // importer's record of what the source said, and it belongs in a
    // reverse-engineering record rather than in a person's way.
    final amount = item.count != null
        ? '${item.count} × ${item.unit?.id ?? ""}'
        : item.amount > 0
            ? '${(item.amount / 1000).toStringAsFixed(item.amount % 1000 == 0 ? 0 : 1)} ml'
            : '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            child: Icon(
              available ? Icons.check : Icons.remove,
              size: 15,
              color: available ? HollowPalette.gold : HollowPalette.absent,
            ),
          ),
          Expanded(
            child: Text(
              name ?? item.ingredientId,
              style: HollowType.body.copyWith(
                color: available ? HollowPalette.ink : HollowPalette.inkFaint,
              ),
            ),
          ),
          if (item.role == ItemRole.garnish)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(Copy.garnish, style: HollowType.caption),
            ),
          Text(amount, style: HollowType.numeric),
        ],
      ),
    );
  }
}

/// The note somebody wrote on this recipe, and the field that changes it.
///
/// **Section 8's first consumer, and the reason it is a note on a recipe rather
/// than something easier to reach.** A recipe carries an id section 4.4 promised
/// not to renumber -- `recipe_id.dart` says a running index "would have been
/// simpler and wrong", and gives this section as the reason. So the note survives
/// the seed being replaced wholesale, which is the one thing the overlay exists to
/// make true. A note keyed on the recipe's *name*, or on its position in the list,
/// would look identical on screen and lose the user's words on the first update.
///
/// **Saving is explicit rather than on every keystroke.** An overlay write is an
/// event, so a note typed at speaking pace would be one event per character, and
/// the log is a thing people are meant to be able to read.
class _RecipeNote extends ConsumerStatefulWidget {
  const _RecipeNote({required this.recipeId});

  final String recipeId;

  @override
  ConsumerState<_RecipeNote> createState() => _RecipeNoteState();
}

class _RecipeNoteState extends ConsumerState<_RecipeNote> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    // Read once, at open. Watching the fold *into* the controller would fight the
    // field the user is typing in: saving changes the fold, and a controller
    // rebuilt from it mid-edit is a cursor that jumps to the end.
    _controller = TextEditingController(text: _stored)..addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onChanged)
      ..dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  /// What the overlay holds, or the empty string when nobody has written one.
  String get _stored =>
      ref.read(cellarProvider).value?.overlay.recipeNote(widget.recipeId) ?? '';

  /// True when the field says something the log does not.
  ///
  /// Compared trimmed, to match what `editOverlay` will store. The trim itself
  /// happens in the notifier rather than here, so that this comparison and the write
  /// cannot end up disagreeing about what the user said.
  bool _isDirty(String stored) => _controller.text.trim() != stored;

  Future<void> _save() async {
    // **One call, because the two rules that go with an edited field are decided
    // once, in the notifier.** An emptied field is a removal, and the value is
    // trimmed -- both belong beside the refusal that makes them necessary, because
    // a screen that decided them again could decide them differently.
    await ref
        .read(cellarProvider.notifier)
        .editOverlay(OverlayKey.recipe(widget.recipeId), _controller.text);
  }

  @override
  Widget build(BuildContext context) {
    // Re-read from the fold rather than kept in a field, so a save is reflected
    // without a second copy of the value to keep in step with the first.
    final stored =
        ref.watch(cellarProvider).value?.overlay.recipeNote(widget.recipeId) ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          minLines: 1,
          maxLines: 3,
          style: HollowType.body,
          decoration: const InputDecoration(
            labelText: Copy.recipeNote,
            hintText: Copy.recipeNoteHint,
          ),
        ),
        if (_isDirty(stored)) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _save,
              child: const Text(Copy.recipeNoteSave),
            ),
          ),
        ],
      ],
    );
  }
}

/// `#RRGGBB` to a colour, answering the interface's gold when the reader's string is not one.
///
/// **A colour a reader typed is data, and data can be wrong.** An unparsable accent must leave the row looking
/// like every other row rather than throw while a list is being built.
Color _colourOf(String value) {
  final text = value.startsWith('#') ? value.substring(1) : value;
  final parsed = int.tryParse(text, radix: 16);
  if (parsed == null || (text.length != 6 && text.length != 8)) return HollowPalette.gold;
  return Color(text.length == 6 ? 0xFF000000 | parsed : parsed);
}
