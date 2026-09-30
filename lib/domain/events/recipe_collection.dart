import 'dart:convert';

import 'event.dart';
import 'hlc.dart';

/// The event type names for recipe collections.
///
/// **A third family of user-written operations, beside the overlay and the stock ledger.** The overlay stores one
/// field of one thing; this stores a whole structure — a named collection and what is in it — because a collection
/// is only meaningful as a whole. Splitting it into "add a member" and "remove a member" events would make a rename
/// indistinguishable from a clear-then-set on every device that folds them, and the fold would have to guess.
abstract final class RecipeCollectionEvent {
  /// A collection was created or replaced: its name and its members, in one operation.
  static const set = 'recipe.collection.set';

  /// A collection was removed.
  static const cleared = 'recipe.collection.cleared';

  /// A folder that the application derives was hidden from the reader's list.
  ///
  /// **This is what makes 保留原本 a choice rather than the only possibility.** "Merge these three IBA folders into
  /// one, and stop showing the three" is a legitimate thing to want, and it cannot be expressed by moving recipes:
  /// a derived folder is *derived* — computed from each recipe's `extras` — so the only honest way to not show it
  /// is to record that the reader asked not to. A recipe's membership does not change at all.
  static const folderHidden = 'recipe.folder.hidden';

  /// A hidden derived folder was shown again.
  static const folderShown = 'recipe.folder.shown';

  static const all = {set, cleared, folderHidden, folderShown};
}

/// Why a collection could not be written.
///
/// **A sealed set rather than a thrown string**, because every one of these is something a screen has to say to a
/// person, and a message assembled at the point of failure is a message that drifts from the rule it describes.
sealed class CollectionProblem {
  const CollectionProblem();
}

/// The name was empty, or only spaces.
///
/// Refused here rather than by a screen, for the reason `OverlayEvents.fieldSet` refuses an empty value: a
/// nameless collection is a collection nobody can find, and "unnamed" is not a state this application should be
/// able to store.
final class CollectionUnnamed extends CollectionProblem {
  const CollectionUnnamed();
}

/// The collection would contain itself, directly or through a chain of others.
///
/// **Checked before the event is written, and it has to be.** A cycle is not a rendering problem that a screen
/// can dodge — the fold that lists a collection's contents would recurse until the stack ran out, and by then the
/// bad event is in the log and in every synced copy of it. An operation that would create one is refused at the
/// door, where the only cost is a message.
final class CollectionWouldContainItself extends CollectionProblem {
  const CollectionWouldContainItself(this.chain);

  /// The path that would close the loop, for a message that names the actual mistake.
  final List<String> chain;
}

/// What one member of a collection is.
///
/// **Two cases and not one**, because the two live in different places and are rebuilt differently: a recipe is an
/// id into the seed or the library, while a *derived* folder is a key computed from the recipes themselves. Storing
/// the second as a copy of the first would mean the copy could drift, and drift in a membership list is invisible.
sealed class CollectionMember {
  const CollectionMember();

  /// The wire form: one prefix and a name, so a payload stays readable by a person looking at the log.
  String encode() => switch (this) {
        RecipeMember(:final recipeId) => 'r:$recipeId',
        DerivedFolderMember(:final folderKey) => 'f:$folderKey',
        CollectionMemberOf(:final collectionId) => 'c:$collectionId',
      };

  /// Reads a member back, or null when this build cannot tell what it is.
  ///
  /// **Null rather than an exception**, so a payload written by a build that knows a fourth kind of member does not
  /// take the whole fold with it. The unknown member is dropped from the collection and the collection survives --
  /// the same choice `PriceOp.tryParse` makes about an event type it does not know.
  static CollectionMember? tryDecode(String encoded) {
    if (encoded.length < 3 || encoded[1] != ':') return null;
    final rest = encoded.substring(2);
    if (rest.isEmpty) return null;
    return switch (encoded[0]) {
      'r' => RecipeMember(rest),
      'f' => DerivedFolderMember(rest),
      'c' => CollectionMemberOf(rest),
      _ => null,
    };
  }
}

/// A recipe, by the id its library knows it by.
final class RecipeMember extends CollectionMember {
  const RecipeMember(this.recipeId);

  final String recipeId;

  @override
  bool operator ==(Object other) => other is RecipeMember && other.recipeId == recipeId;

  @override
  int get hashCode => recipeId.hashCode;

  @override
  String toString() => 'recipe:$recipeId';
}

/// A collection that the application derives, by the key `foldersOf` gives it (`source/category`).
///
/// **A reference, not a copy.** The folder keeps being computed from the recipes; putting it inside a collection
/// records that it belongs there, not what was in it when that was decided.
final class DerivedFolderMember extends CollectionMember {
  const DerivedFolderMember(this.folderKey);

  final String folderKey;

  @override
  bool operator ==(Object other) => other is DerivedFolderMember && other.folderKey == folderKey;

  @override
  int get hashCode => folderKey.hashCode;

  @override
  String toString() => 'folder:$folderKey';
}

/// A collection the reader made, by its id.
final class CollectionMemberOf extends CollectionMember {
  const CollectionMemberOf(this.collectionId);

  final String collectionId;

  @override
  bool operator ==(Object other) =>
      other is CollectionMemberOf && other.collectionId == collectionId;

  @override
  int get hashCode => collectionId.hashCode;

  @override
  String toString() => 'collection:$collectionId';
}

/// One collection as an operation sees it: a name and its members.
///
/// Deliberately not the same type as the folded collection, because an operation is what was *written* and a folded
/// collection is what is *true* after every device's writes have been merged. The conversions between them live in
/// the fold, where the disagreement is handled.
final class RecipeCollectionOp {
  const RecipeCollectionOp({
    required this.hlc,
    required this.id,
    required this.name,
    required this.members,
  });

  final Hlc hlc;
  final String id;
  final String name;
  final List<CollectionMember> members;

  /// Reads an op off an event, or returns null when this is not one of ours.
  ///
  /// The overlay's rule applies unchanged: an event of a type this build does not know is a peer from a future
  /// version and is carried untouched, so "not mine" is the normal case during a sync and not an error. **A
  /// malformed payload of a type this build DOES know throws**, through `Event.require` -- that is drift, and drift
  /// is worth surfacing.
  static RecipeCollectionOp? tryParse(Event event) {
    if (!RecipeCollectionEvent.all.contains(event.type)) return null;
    return switch (event.type) {
      RecipeCollectionEvent.set => RecipeCollectionOp(
        hlc: event.hlc,
        id: event.require<String>('id'),
        name: event.require<String>('name'),
        members: _decodeMembers(event.require<String>('members')),
      ),
      RecipeCollectionEvent.cleared => RecipeCollectionOp(
        hlc: event.hlc,
        id: event.require<String>('id'),
        name: '',
        members: const [],
      ),
      // The folder operations carry their own shape and are read by their own fold; they are listed here so a
      // caller asking "is this a collection event" gets one answer rather than two.
      RecipeCollectionEvent.folderHidden => null,
      RecipeCollectionEvent.folderShown => null,
      _ => null,
    };
  }

  /// A comma-joined string rather than a JSON array.
  ///
  /// **A list of strings needs no structure, and structure nobody reads is a parser that can fail.** Every member
  /// encodes itself as `prefix:name`, ids never contain a comma (they are drink ids and `source/category` keys),
  /// and a member this build cannot read is dropped rather than refusing the event.
  static String encodeMembers(Iterable<CollectionMember> members) =>
      members.map((member) => member.encode()).join(',');

  static List<CollectionMember> _decodeMembers(String encoded) {
    if (encoded.isEmpty) return const [];
    final out = <CollectionMember>[];
    for (final part in encoded.split(',')) {
      final member = CollectionMember.tryDecode(part);
      if (member != null) out.add(member);
    }
    return out;
  }
}

/// Builders for the collection events.
///
/// Each takes the clock reading the caller obtained from an `HlcClock`, so nothing here reads the system clock and
/// an event's contents can be asserted exactly in a test.
abstract final class RecipeCollectionEvents {
  /// Creates or replaces a collection.
  ///
  /// **[members] is the whole membership, not a change to it.** The same reason the operation carries the name:
  /// a device folding a log needs to arrive at a state, and an incremental form makes the state depend on whether
  /// every earlier event was seen.
  static Event set({
    required Hlc hlc,
    required String id,
    required String name,
    required Iterable<CollectionMember> members,
  }) => Event(
    hlc: hlc,
    type: RecipeCollectionEvent.set,
    data: {
      'id': id,
      'name': name,
      'members': RecipeCollectionOp.encodeMembers(members),
    },
  );

  /// Removes a collection.
  ///
  /// **Membership is not rewritten.** Removing a collection that is a member of another leaves that membership
  /// pointing at something gone, and the fold drops a member it cannot resolve rather than cascading a change the
  /// reader did not ask for -- the same rule that makes a stock fold keep an empty bottle's placement.
  static Event cleared({required Hlc hlc, required String id}) =>
      Event(hlc: hlc, type: RecipeCollectionEvent.cleared, data: {'id': id});

  /// Hides a folder the application derives.
  static Event folderHidden({required Hlc hlc, required String folderKey}) =>
      Event(hlc: hlc, type: RecipeCollectionEvent.folderHidden, data: {'folder': folderKey});

  /// Shows a hidden derived folder again.
  static Event folderShown({required Hlc hlc, required String folderKey}) =>
      Event(hlc: hlc, type: RecipeCollectionEvent.folderShown, data: {'folder': folderKey});
}

/// Which derived folders the reader has hidden, oldest event first.
///
/// A fold of two event types and no state beyond a set: hidden and shown are the same key flipping, and the last
/// write wins because the events are ordered by their hybrid clock.
Set<String> hiddenFoldersOf(Iterable<Event> events) {
  final ordered = events
      .where((event) =>
          event.type == RecipeCollectionEvent.folderHidden ||
          event.type == RecipeCollectionEvent.folderShown)
      .toList()
    ..sort((a, b) => a.hlc.compareTo(b.hlc));

  final hidden = <String>{};
  for (final event in ordered) {
    final key = event.require<String>('folder');
    event.type == RecipeCollectionEvent.folderHidden ? hidden.add(key) : hidden.remove(key);
  }
  return hidden;
}

/// Encodes a collection id from a name, so a collection made from the same words twice is one collection.
///
/// **The id is derived from the name and is not a counter.** A counter would need a coordinator, and two devices
/// offline would both create collection 7; a hash of the name means the same name is the same collection on both,
/// which is what a reader would expect. The cost is that renaming changes the id, and that cost is paid at the call
/// site: a rename writes a new collection and clears the old one in the same breath.
String collectionIdOf(String name) {
  final trimmed = name.trim();
  final bytes = utf8.encode(trimmed);
  // FNV-1a, 32-bit, written out rather than imported: one hash function is not a dependency.
  var hash = 0x811c9dc5;
  for (final byte in bytes) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return 'c${hash.toRadixString(16).padLeft(8, '0')}';
}
