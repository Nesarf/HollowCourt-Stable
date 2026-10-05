import 'dart:convert';

import 'event.dart';
import 'hlc.dart';

/// The event type names for recipes the reader wrote.
///
/// **A fourth family of user-written operations, beside the overlay, the stock ledger and the collections**, and
/// the one the application was missing entirely: until now it had exactly two write paths — a bottle and a journal
/// entry — so there was no way to put a recipe of your own beside the shipped ones. `docs/proposal-recipes-and-packs.md`
/// §9 states the fault in its own words: *"Can a user create one? **No.**"*
///
/// **A user recipe is the same record shape as a shipped one**, which is the whole design. `id`, `name`, `items`,
/// `method`, `glass`, `ice`, `packId` — the same fields the library carries — so one page holds both and one search
/// finds both, and nothing downstream has to ask where a recipe came from in order to draw it.
///
/// **Whole-record operations, not field edits.** The overlay exists for single fields of things the application
/// already owns; a recipe is a structure the reader authored, and "add a line" / "change a line" events would make
/// a device that missed one event fold to a recipe nobody wrote. The same argument the collections make.
abstract final class RecipeAuthoredEvent {
  /// A recipe was created, or replaced wholesale.
  static const set = 'recipe.authored.set';

  /// A recipe the reader wrote was removed.
  ///
  /// **Only ever their own.** A shipped recipe cannot be deleted, and this event naming an id that exists in the
  /// library is a payload the fold refuses rather than a way to make a drink disappear from a build.
  static const removed = 'recipe.authored.removed';

  static const all = {set, removed};
}

/// Why a recipe could not be written.
///
/// **Sealed, and each case is something a screen has to say**, for the reason `CollectionProblem` gives: a message
/// assembled at the point of failure drifts from the rule it describes.
sealed class RecipeProblem {
  const RecipeProblem();
}

/// The name was empty, or only spaces.
final class RecipeUnnamed extends RecipeProblem {
  const RecipeUnnamed();
}

/// No ingredient lines at all.
///
/// **A recipe with nothing in it is not a recipe**, and the application can already say what is in the cellar; a
/// nameless, ingredientless record would be a note. Refused here rather than by a screen so that no build can
/// store one, which is the same reason `CollectionUnnamed` exists.
final class RecipeEmpty extends RecipeProblem {
  const RecipeEmpty();
}

/// A line names an ingredient this build does not know about.
///
/// **Refused rather than stored loosely.** An unknown ingredient id folds to a recipe that can never be made and
/// whose lines cannot be priced, and the reader would have no way to tell that from a recipe they simply cannot
/// make yet. The id has to exist in the library or in the reader's own ingredients first.
final class RecipeUnknownIngredient extends RecipeProblem {
  const RecipeUnknownIngredient(this.ingredientId);

  final String ingredientId;

  @override
  String toString() => 'unknown ingredient $ingredientId';
}

/// A line gives an amount but names no ingredient.
///
/// **Found by a UI test on 2026-10-01, and it is the kind of gap a form hides.** The composer drops a line that is
/// entirely blank, and blank meant "no ingredient *and* no amount" -- so a line where somebody typed `30` and never
/// chose what it was thirty *of* survived, and folded into a recipe whose ingredient id is the empty string. Nothing
/// downstream could make such a recipe or price it, and the reader would have had no idea which line was wrong.
final class RecipeLineWithoutIngredient extends RecipeProblem {
  const RecipeLineWithoutIngredient(this.index);

  /// Which line, counting from one, so a form can point at it.
  final int index;

  @override
  String toString() => 'line $index has an amount but no ingredient';
}

/// The id of a recipe the reader wrote, or of one they are about to.
abstract final class AuthoredRecipeId {
  /// **Prefixed, so that a reader's own recipe can never collide with a shipped id.** The library's ids are its
  /// own (`iba.negroni` and the like); anything beginning `own.` came from somebody at a keyboard. A collision
  /// would let one recipe overwrite another, which is the kind of fault that looks like a save that did not work.
  static const prefix = 'own.';

  static bool isMine(String id) => id.startsWith(prefix);

  /// A stable id from a name and a clock reading.
  ///
  /// **Not random, and not a uuid.** `Hlc` already carries a wall clock and a counter, so the pair is unique
  /// without a source of entropy -- and a deterministic id means a fold on two devices that saw the same edit
  /// agrees on what to call it. The name is folded in so that two recipes made in the same millisecond do not
  /// compete, and it is sanitised to something that survives a filename and a URL.
  static String from(String name, Hlc hlc) {
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final millis = hlc.physicalMillis;
    return '$prefix${slug.isEmpty ? 'recipe' : slug}-$millis-${hlc.counter}';
  }
}

/// One line of a reader's recipe, as the log carries it.
///
/// **Separate from `RecipeItem` on purpose.** The domain model is free to grow validation, derived fields and
/// behaviour; what crosses the log has to stay readable by an older build, so it carries the fields and nothing
/// else. A model that is also its own wire format cannot be changed without breaking every device that has not
/// updated.
final class AuthoredItem {
  const AuthoredItem({
    required this.ingredientId,
    required this.amount,
    this.unit,
    this.role,
    this.note,
  });

  final String ingredientId;

  /// **A string, not a number.** The rest of this application refuses to carry floats outside the domain layer
  /// (`Rating` says why at length), and a quantity typed by a reader is the place that rule earns its keep: `1/2`
  /// and `0.5` are the same drink and must not become two.
  final String amount;

  final String? unit;
  final String? role;
  final String? note;

  Map<String, Object?> toJson() => {
    'ingredient': ingredientId,
    'amount': amount,
    if (unit != null) 'unit': unit,
    if (role != null) 'role': role,
    if (note != null) 'note': note,
  };

  static AuthoredItem fromJson(Map<String, Object?> json) => AuthoredItem(
    ingredientId: json['ingredient']! as String,
    amount: json['amount']! as String,
    unit: json['unit'] as String?,
    role: json['role'] as String?,
    note: json['note'] as String?,
  );
}

/// The whole of one reader-written recipe, as the log carries it.
final class AuthoredRecipe {
  const AuthoredRecipe({
    required this.id,
    required this.name,
    required this.items,
    this.subtitle,
    this.folder,
    this.description,
    this.method,
    this.glass,
    this.ice,
    this.garnish,
  });

  final String id;
  final String name;
  final List<AuthoredItem> items;
  final String? subtitle;

  /// The folder this recipe belongs to, if the reader put it in one. **A pack id or a collection id**, because a
  /// recipe belongs to exactly one collection and a collection may itself be inside another -- see
  /// `RecipeCollections`, which resolves the rest.
  final String? folder;

  final String? description;

  /// Free text rather than the library's `Method` enum.
  ///
  /// **The owner's own point, from the proposal**: a closed list of `shaken / stirred / built` would eventually
  /// demand that somebody shake a pour-over. The vocabulary is offered as suggestions and never as a requirement,
  /// which is why this crosses the log as a string.
  final String? method;

  final String? glass;
  final String? ice;
  final String? garnish;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'items': items.map((i) => i.toJson()).toList(),
    if (subtitle != null) 'subtitle': subtitle,
    if (folder != null) 'folder': folder,
    if (description != null) 'description': description,
    if (method != null) 'method': method,
    if (glass != null) 'glass': glass,
    if (ice != null) 'ice': ice,
    if (garnish != null) 'garnish': garnish,
  };

  static AuthoredRecipe fromJson(Map<String, Object?> json) => AuthoredRecipe(
    id: json['id']! as String,
    name: json['name']! as String,
    items: (json['items']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .map(AuthoredItem.fromJson)
        .toList(growable: false),
    subtitle: json['subtitle'] as String?,
    folder: json['folder'] as String?,
    description: json['description'] as String?,
    method: json['method'] as String?,
    glass: json['glass'] as String?,
    ice: json['ice'] as String?,
    garnish: json['garnish'] as String?,
  );
}

/// Checks a recipe against the rules above, returning everything wrong with it.
///
/// **A list rather than the first problem**, so a screen can show all of them at once instead of making somebody
/// submit four times to learn four things. The same shape `Rating.validate` uses.
///
/// [known] is the set of ingredient ids this build can resolve — the library's and the reader's own. It is passed
/// in rather than looked up because the domain layer does not own the library, and a validation that reaches for a
/// global is a validation that cannot be tested against a library that is deliberately wrong.
List<RecipeProblem> validateAuthored(AuthoredRecipe recipe, {required Set<String> known}) {
  final problems = <RecipeProblem>[];
  if (recipe.name.trim().isEmpty) problems.add(const RecipeUnnamed());
  if (recipe.items.isEmpty) problems.add(const RecipeEmpty());
  for (var i = 0; i < recipe.items.length; i++) {
    final item = recipe.items[i];
    if (item.ingredientId.trim().isEmpty) {
      problems.add(RecipeLineWithoutIngredient(i + 1));
      continue;
    }
    if (!known.contains(item.ingredientId)) {
      problems.add(RecipeUnknownIngredient(item.ingredientId));
    }
  }
  return problems;
}

/// A recipe operation read off the log.
final class RecipeAuthoredOp {
  const RecipeAuthoredOp({required this.hlc, required this.recipe});

  final Hlc hlc;

  /// The recipe as written. Null for [RecipeAuthoredEvent.removed], which carries only an id.
  final AuthoredRecipe? recipe;

  /// **A removal carries no recipe, so this class does not pretend to have one.** `removedId` reads the id off
  /// the event instead, and `tryParse` returns a null [recipe] for a removal rather than inventing an empty record
  /// that a fold could mistake for a real one.
  /// Reads an op off an event, or returns null when this is not one of ours.
  ///
  /// The rule the overlay states applies unchanged: **an event of a type this build does not know is a peer from a
  /// future version and is carried untouched**, so "not mine" is ordinary. **A malformed payload of a type this
  /// build does know throws** through `Event.require` — that is drift, and drift is worth surfacing.
  static RecipeAuthoredOp? tryParse(Event event) {
    if (!RecipeAuthoredEvent.all.contains(event.type)) return null;
    return switch (event.type) {
      RecipeAuthoredEvent.set => RecipeAuthoredOp(
        hlc: event.hlc,
        recipe: AuthoredRecipe.fromJson(
          jsonDecode(event.require<String>('recipe')) as Map<String, Object?>,
        ),
      ),
      RecipeAuthoredEvent.removed => RecipeAuthoredOp(
        hlc: event.hlc,
        recipe: null,
      ),
      _ => null,
    };
  }

  /// The id a removal names, or null when this is not a removal.
  static String? removedId(Event event) {
    if (event.type != RecipeAuthoredEvent.removed) return null;
    return event.require<String>('id');
  }

  static bool isRemoval(Event event) => event.type == RecipeAuthoredEvent.removed;
}

abstract final class RecipeAuthoredEvents {
  /// Writes a recipe, whole.
  ///
  /// **[recipe] is the entire record, not a change to one**, for the reason the collections give: a device folding
  /// a log has to arrive at a state, and an incremental form makes that state depend on whether every earlier
  /// event was seen.
  static Event set({required Hlc hlc, required AuthoredRecipe recipe}) => Event(
    hlc: hlc,
    type: RecipeAuthoredEvent.set,
    data: {'recipe': jsonEncode(recipe.toJson())},
  );

  /// Removes a recipe the reader wrote.
  static Event removed({required Hlc hlc, required String id}) {
    if (!AuthoredRecipeId.isMine(id)) {
      throw ArgumentError.value(
        id,
        'id',
        'only a recipe the reader wrote can be removed; a shipped one is part of the build',
      );
    }
    return Event(hlc: hlc, type: RecipeAuthoredEvent.removed, data: {'id': id});
  }
}
