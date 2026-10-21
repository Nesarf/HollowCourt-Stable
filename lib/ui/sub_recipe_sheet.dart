import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/model/item_role.dart';
import '../domain/model/recipe.dart';
import 'library.dart';
import 'seed_names.dart';
import 'theme.dart';

/// **A finished thing may be an ingredient, and it arrives with its method.**
///
/// The owner's instruction: rather than writing `espressoCoffee` into an item list and leaving the reader to wonder
/// where it came from, the ingredient carries `extras.madeBy` pointing at the recipe that makes it. This file is
/// where that becomes reachable — from a drink's ingredient line and from the ingredient list itself, because the
/// question "how is this made" is asked in both places.
///
/// **It lives here rather than in `recipes_page.dart`** because it stopped being that page's property: the
/// ingredient list needs the same sheet, and two copies of a sheet that has to stay in step is exactly the kind of
/// duplicate this project keeps finding.
class SubRecipeItemRow extends ConsumerWidget {
  const SubRecipeItemRow({
    super.key,
    required this.item,
    required this.available,
    this.name,
    this.depth = 0,
    this.visited = const <String>{},
  });

  final RecipeItem item;
  final bool available;
  final String? name;

  /// How far down the sub-recipe tree this row already is. **Bounded on purpose**: a finished thing can be an
  /// ingredient, and an ingredient with a recipe behind it opens, but the opening has to stop somewhere or a
  /// mistake in the data becomes a screen that never closes.
  final int depth;

  /// **The bases already open above this row.** A depth number alone would let a cycle of two bases open for ever,
  /// and the data is now two levels deep rather than one, so the guard is the set rather than the number. The depth
  /// stays as a second bound because a long chain that is not a cycle is still a screen nobody can get out of.
  final Set<String> visited;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A measured line shows millilitres; a counted one shows the count, because section 5.2 is firm that four
    // leaves are not millilitres and printing "0 ml" there would be a worse lie than printing nothing.
    //
    // **A line with neither shows nothing, and this is a fix from the phone.** It used to fall back to
    // `originalText`, which put the importer's own string on screen: a garnish row read `garnish: Lemon (Twist)` in
    // English, duplicating the 装饰 tag already beside it.
    final amount = item.count != null
        ? '${item.count} × ${item.unit?.id ?? ""}'
        : item.amount > 0
            ? '${(item.amount / 1000).toStringAsFixed(item.amount % 1000 == 0 ? 0 : 1)} ml'
            : '';

    final library = ref.watch(seedProvider).value;
    final madeBy = library?.ingredientById(item.ingredientId)?.extras['madeBy'];
    final base = madeBy == null ? null : library?.recipeById(madeBy);
    final canOpen = base != null && depth < 3 && !visited.contains(base.id);

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
                color: available ? HollowPalette.ink : HollowPalette.text.faint,
              ),
            ),
          ),
          if (item.role == ItemRole.garnish)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(Copy.garnish, style: HollowType.caption),
            ),
          Text(amount, style: HollowType.numeric),
          if (canOpen) TreeButton(recipe: base, depth: depth, visited: visited),
        ],
      ),
    );
  }
}

/// The small button that opens a finished thing's own method.
///
/// Its own widget so the ingredient card can put the same affordance on itself without pretending to be a row.
class TreeButton extends StatelessWidget {
  const TreeButton({
    super.key,
    required this.recipe,
    required this.depth,
    required this.visited,
  });

  final Recipe recipe;
  final int depth;
  final Set<String> visited;

  @override
  Widget build(BuildContext context) => InkWell(
        key: ValueKey('sub-recipe-${recipe.id}'),
        onTap: () => showSubRecipeSheet(
          context,
          recipe: recipe,
          depth: depth + 1,
          visited: {...visited, recipe.id},
        ),
        child: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Icon(
            Icons.account_tree_outlined,
            size: 15,
            color: HollowPalette.text.faint,
          ),
        ),
      );
}

void showSubRecipeSheet(
  BuildContext context, {
  required Recipe recipe,
  required int depth,
  required Set<String> visited,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => SubRecipeSheet(recipe: recipe, depth: depth, visited: visited),
  );
}

/// A finished thing's own method, opened from whatever names it.
///
/// **It is a smaller sheet than the drink's, and the difference is deliberate.** There is no score, no mix button and
/// no note: those are about *this drink*, and a base is not a drink a reader orders. What a base has is a name, the
/// one line of method behind it, and its own ingredient lines -- which may themselves open, up to the depth the row
/// carries.
class SubRecipeSheet extends ConsumerWidget {
  const SubRecipeSheet({
    super.key,
    required this.recipe,
    required this.depth,
    required this.visited,
  });

  final Recipe recipe;
  final int depth;
  final Set<String> visited;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final names = ref.watch(seedNamesProvider).value;
    final locale = ref.watch(seedNameLocaleProvider);
    final cellar = ref.watch(cellarProvider).value;
    final library = ref.watch(seedProvider).value;
    final steps = names?.stepsFor(recipe.id, locale) ?? recipe.methodSteps;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            names?.nameFor(recipe.id, locale, fallback: recipe.name) ?? recipe.name,
            style: HollowType.heading,
          ),
          if (recipe.description != null) ...[
            const SizedBox(height: 6),
            Text(recipe.description!, style: HollowType.caption),
          ],
          if (steps.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final step in steps.take(6))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(step, style: HollowType.body),
              ),
          ],
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 10),
          for (final item in recipe.items)
            SubRecipeItemRow(
              item: item,
              available: cellar?.has(item.ingredientId) ?? false,
              depth: depth,
              visited: visited,
              name: names?.nameFor(
                    item.ingredientId,
                    locale,
                    fallback: library?.ingredientById(item.ingredientId)?.name ?? '',
                  ) ??
                  library?.ingredientById(item.ingredientId)?.name,
            ),
        ],
      ),
    );
  }
}
