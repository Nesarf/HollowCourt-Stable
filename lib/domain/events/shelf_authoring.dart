import 'dart:convert';

import 'event.dart';
import 'hlc.dart';

/// The event type names for **shelves the reader named**.
///
/// **A shelf already existed as a key and had no name.** `shelf.dart` carries *placements* -- which bottle stands
/// where -- and `shelfId` has been a string in them since the first version. `shelf_test` places bottles on
/// `'fridge'`, `SyncScope.shelf('back')` scopes a share by one. **And the interface has only ever written `'bar'`**,
/// deliberately: `bar_page.dart` says a shelf picker over one shelf would be furniture, and section 12.3's chooser
/// was left for later. This is that later.
///
/// **So this family does not invent shelves, it names them.** The key stays whatever the placements already use; what
/// is added is a record saying *this id is a place, and here is what it is called*. That is why a log written before
/// this file existed is not broken by it: a placement on a shelf nobody declared is a shelf whose name is its id, and
/// `ShelfBook.nameOf` is where that is decided.
///
/// **A whole record, like an ingredient and a recipe.** A shelf is two fields rather than one, and "rename" events
/// would let a device that missed one fold to a shelf with no name at all. The same argument the collections, the
/// recipes and the ingredients each make.
///
/// **Not shared, and that is a decision rather than an omission.** `SyncScope._shareable` carries an explicit list
/// and its comment says adding an event type is a decision somebody makes there. This family stays off it, beside the
/// authored recipes and the collections: **what such a share decides is whose places these are.** Placements do
/// travel (`stock.bottle.placed` is `SyncKind.stock`), so a peer can receive a bottle standing on a shelf it has no
/// name for -- and it shows the id, which is the honest answer rather than a name invented for somebody else's
/// cupboard.
abstract final class ShelfAuthoredEvent {
  /// A shelf was named, or renamed -- the same event, because a rename is a declaration whose clock reading is
  /// later. `ShelfEvent.bottlePlaced` argues the same way about a move.
  static const declared = 'shelf.authored.declared';

  /// A shelf the reader named was removed.
  ///
  /// **The bottles standing on it are not moved.** A removal is a statement about the *name*, not about the
  /// cupboards: a shelf that held four bottles still exists as a place those bottles are standing, and the fold
  /// falls back to its id -- so the worst a mistaken removal does is lose a word.
  static const removed = 'shelf.authored.removed';

  static const all = {declared, removed};
}

/// The shelf the first version wrote, and the one every placement made before shelves could be named points at.
///
/// **A domain constant rather than a screen's**, because it is not a piece of layout: it is the id inside every
/// `stock.bottle.placed` event written before `shelf.authored.declared` existed, so it is a fact about the log. Two
/// screens resolve it to a readable name and they must agree about which id they are resolving.
const String builtInShelfId = 'bar';

/// Why a shelf could not be named.
sealed class ShelfProblem {
  const ShelfProblem();
}

/// The name was empty, or only spaces.
final class ShelfUnnamed extends ShelfProblem {
  const ShelfUnnamed();
}

/// An id that is not one a reader's shelf may carry.
///
/// **The guard that keeps [ShelfAuthoredEvent.removed] from meaning "remove any shelf".** The built-in shelf's id is
/// `bar` and carries no prefix; a reader's carries `own.`, so removing the one the first version wrote is refused
/// here rather than by a screen forgetting to offer it.
final class ShelfIdNotMine extends ShelfProblem {
  const ShelfIdNotMine(this.id);

  final String id;
}

/// The reader's own shelves carry this prefix.
///
/// The same device `AuthoredIngredientId` and `AuthoredRecipeId` use, and here it earns its keep twice: the built-in
/// shelf's id is the bare word `bar`, so without a prefix a reader naming a shelf "bar" would take over the shelf
/// every existing placement already points at. A collision there is not a failed save, it is a cupboard that
/// silently becomes somebody else's.
abstract final class AuthoredShelfId {
  static const prefix = 'own.';

  static bool isMine(String id) => id.startsWith(prefix);

  /// A stable id derived from the name and a clock reading.
  ///
  /// Not random, for the reason the ingredients and the recipes give: an id derived from the same inputs is one two
  /// devices which saw the same edit agree on.
  static String from(String name, Hlc hlc) {
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return '$prefix${slug.isEmpty ? 'shelf' : slug}-${hlc.physicalMillis}-${hlc.counter}';
  }
}

/// A shelf the reader named, as the log carries it.
final class AuthoredShelf {
  const AuthoredShelf({required this.id, required this.name});

  final String id;

  /// What the reader calls it. Free text, like an ingredient's kind and a pack's name, because the places a person
  /// keeps things in are *data*: a closed list would mean a build to add 冰箱.
  final String name;

  Map<String, Object?> toJson() => {'id': id, 'name': name};

  static AuthoredShelf fromJson(Map<String, Object?> json) => AuthoredShelf(
    id: json['id']! as String,
    name: json['name']! as String,
  );

  @override
  String toString() => 'AuthoredShelf($id: $name)';

  @override
  bool operator ==(Object other) =>
      other is AuthoredShelf && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}

/// Checks a shelf against the rules above, returning everything wrong with it.
///
/// A list rather than the first problem, so a form can say all of it at once -- the shape
/// `validateAuthoredIngredient` uses for ingredients.
List<ShelfProblem> validateAuthoredShelf(AuthoredShelf shelf) {
  final problems = <ShelfProblem>[];
  if (shelf.name.trim().isEmpty) problems.add(const ShelfUnnamed());
  if (!AuthoredShelfId.isMine(shelf.id)) problems.add(ShelfIdNotMine(shelf.id));
  return problems;
}

/// A shelf operation read off the log.
final class ShelfAuthoredOp {
  const ShelfAuthoredOp({required this.hlc, required this.shelf});

  final Hlc hlc;

  /// The shelf as written. Null for [ShelfAuthoredEvent.removed], which carries only an id.
  final AuthoredShelf? shelf;

  /// Reads an op off an event, or returns null when this is not one of ours.
  ///
  /// The rule the other families spell out: an event of an unknown type is a peer from a future version and is
  /// carried untouched, while a malformed payload of a type this build knows throws through `Event.require`.
  static ShelfAuthoredOp? tryParse(Event event) {
    if (!ShelfAuthoredEvent.all.contains(event.type)) return null;
    return switch (event.type) {
      ShelfAuthoredEvent.declared => ShelfAuthoredOp(
        hlc: event.hlc,
        shelf: AuthoredShelf.fromJson(
          jsonDecode(event.require<String>('shelf')) as Map<String, Object?>,
        ),
      ),
      ShelfAuthoredEvent.removed => ShelfAuthoredOp(hlc: event.hlc, shelf: null),
      _ => null,
    };
  }

  /// The id a removal names, or null when this is not a removal.
  static String? removedId(Event event) {
    if (event.type != ShelfAuthoredEvent.removed) return null;
    return event.require<String>('id');
  }
}

abstract final class ShelfAuthoredEvents {
  /// Names a shelf, whole.
  static Event declared({required Hlc hlc, required AuthoredShelf shelf}) => Event(
    hlc: hlc,
    type: ShelfAuthoredEvent.declared,
    data: {'shelf': jsonEncode(shelf.toJson())},
  );

  /// Removes a shelf the reader named.
  static Event removed({required Hlc hlc, required String id}) {
    if (!AuthoredShelfId.isMine(id)) {
      throw ArgumentError.value(
        id,
        'id',
        'only a shelf the reader named can be removed; the built-in one is what every existing placement points at',
      );
    }
    return Event(hlc: hlc, type: ShelfAuthoredEvent.removed, data: {'id': id});
  }
}
