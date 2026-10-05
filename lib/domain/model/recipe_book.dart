import '../events/event.dart';
import '../events/recipe_authoring.dart';

/// The recipes the reader wrote, folded from the log.
///
/// **The fold that makes `docs/proposal-recipes-and-packs.md` §2 true.** That section states the gap in its own
/// words -- *"Can a user create one? **No.**"* -- and the event family in `recipe_authoring.dart` is what a reader's
/// recipe looks like on disk. This is the other half: what those events mean once they are read back, so a screen
/// can show a recipe somebody wrote beside the shipped ones.
///
/// **Same record shape as a shipped recipe, on purpose.** A `Recipe` from the library and an `AuthoredRecipe` here
/// carry the same fields, which is what lets one page hold both and one search find both -- and it is why this
/// class does not try to be clever about the difference. The difference is *provenance*, and the only thing that
/// needs to know about it is the screen deciding whether to offer a delete button.
final class RecipeBook {
  const RecipeBook(this.recipes);

  /// Every recipe this reader has written and not removed, by id.
  ///
  /// Insertion order follows the clock order of the events that made them, so a page listing them shows them in
  /// the order they were written rather than in whatever order a map happens to iterate.
  final Map<String, AuthoredRecipe> recipes;

  static const RecipeBook none = RecipeBook({});

  bool get isEmpty => recipes.isEmpty;
  int get length => recipes.length;

  /// The recipes, newest last.
  List<AuthoredRecipe> get all => recipes.values.toList(growable: false);

  AuthoredRecipe? operator [](String id) => recipes[id];

  /// Whether [id] names a recipe the reader wrote.
  ///
  /// **The question a screen asks before offering to delete something.** A shipped recipe cannot be removed --
  /// `RecipeAuthoredEvents.removed` refuses an id that is not the reader's own -- so a page that offered the button
  /// for every row would offer one that cannot work.
  bool isMine(String id) => recipes.containsKey(id);

  /// Folds every authored-recipe event in [events].
  ///
  /// **Sorted by clock rather than read in file order**, which is the rule every fold in this project follows and
  /// the reason is the same each time: a merged log holds a peer's events interleaved with local ones, and a write
  /// that replaced a recipe must be applied after the write it replaced however the arrivals happened to land.
  /// Two devices folding the same set of events therefore agree, which is what makes this safe to derive rather
  /// than store.
  factory RecipeBook.of(Iterable<Event> events) {
    final ordered = events
        .where((event) => RecipeAuthoredEvent.all.contains(event.type))
        .toList()
      ..sort((a, b) => a.hlc.compareTo(b.hlc));

    final out = <String, AuthoredRecipe>{};
    for (final event in ordered) {
      if (event.type == RecipeAuthoredEvent.removed) {
        // A removal of something never seen is not an error: it is what a device that has just been sent a
        // deletion sees, and the fold's answer -- that this recipe is not held -- is the right one either way.
        final id = RecipeAuthoredOp.removedId(event);
        if (id != null) out.remove(id);
        continue;
      }

      // Only `set` reaches here -- a removal was handled above, and the other types in the family carry no recipe.
      if (event.type != RecipeAuthoredEvent.set) continue;
      final op = RecipeAuthoredOp.tryParse(event);
      final recipe = op?.recipe;
      // A malformed payload of a known type throws inside `tryParse` rather than arriving null, so null here means
      // the event was not one of ours after all -- skipped rather than guessed at.
      if (recipe == null) continue;
      out[recipe.id] = recipe;
    }
    return RecipeBook(out);
  }
}
