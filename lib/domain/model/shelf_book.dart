import '../events/event.dart';
import '../events/shelf_authoring.dart';

/// What the reader calls their shelves, folded from the log.
///
/// **The fold that turns a key into a place.** `ShelfLayout` answers *where does this bottle stand*, by id; this
/// answers *what is that id called*, and the two are asked together whenever a screen says where something is.
///
/// **A shelf nobody declared is a shelf whose name is its id**, and that is the whole migration for logs written
/// before this existed. Every placement in every cellar so far names `bar`, and none of them was ever declared --
/// so [nameOf] returns `bar` for it, and the screen that draws it resolves that built-in id to copy rather than
/// showing a reader the word. **Nothing is rewritten and no event is back-filled**: a fact that was never written
/// down cannot be recovered by writing it down now, and pretending otherwise would put an invented name in a log
/// that is supposed to be the only truth.
final class ShelfBook {
  const ShelfBook(this.shelves);

  final Map<String, AuthoredShelf> shelves;

  static const ShelfBook none = ShelfBook({});

  bool get isEmpty => shelves.isEmpty;
  int get length => shelves.length;

  /// The reader's shelves, in the order they were named.
  List<AuthoredShelf> get all => shelves.values.toList(growable: false);

  AuthoredShelf? operator [](String id) => shelves[id];

  /// Whether the reader named this shelf.
  ///
  /// **Not whether the shelf exists** -- any id a placement uses exists. This is the question a screen asks before
  /// offering a rename or a removal, which is the same one `IngredientBook.isMine` answers about an ingredient.
  bool isMine(String id) => shelves.containsKey(id);

  /// What to call [shelfId]: the reader's word for it, or the id itself.
  ///
  /// **The id rather than an empty string or a placeholder.** A shelf id is short and was chosen to be a key; a peer
  /// that received placements on a shelf whose declaration did not travel is looking at `own.fridge-...`, which
  /// says less than a name would and more than nothing, and does not invent somebody else's word for their cupboard.
  String nameOf(String shelfId) => shelves[shelfId]?.name ?? shelfId;

  /// Folds every shelf-naming event in [events].
  ///
  /// Sorted by clock rather than read in file order, the rule every fold here follows: a rename has to be applied
  /// after the declaration it replaced however the arrivals happened to land, so that two devices folding the same
  /// set agree.
  factory ShelfBook.of(Iterable<Event> events) {
    final ordered = events
        .where((event) => ShelfAuthoredEvent.all.contains(event.type))
        .toList()
      ..sort((a, b) => a.hlc.compareTo(b.hlc));

    final out = <String, AuthoredShelf>{};
    for (final event in ordered) {
      if (event.type == ShelfAuthoredEvent.removed) {
        // A removal of something never seen is not an error: it is what a device just sent a deletion sees, and the
        // fold's answer -- that this shelf has no name of its own -- is right either way.
        final id = ShelfAuthoredOp.removedId(event);
        if (id != null) out.remove(id);
        continue;
      }
      if (event.type != ShelfAuthoredEvent.declared) continue;
      final shelf = ShelfAuthoredOp.tryParse(event)?.shelf;
      if (shelf == null) continue;
      out[shelf.id] = shelf;
    }
    return ShelfBook(out);
  }
}
