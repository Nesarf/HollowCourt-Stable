import '../events/event.dart';
import '../events/recipe_collection.dart';

/// The reader's own collections, folded from the log, and checked for the one thing a tree can get wrong.
///
/// **Why this is a tree and not a tag on a recipe.** The owner's request was to merge several existing collections
/// into a new one *while keeping the originals*, and the two constraints they set are what make it a tree:
/// **a recipe belongs to exactly one collection**, and **a collection may contain another collection**. So
/// 我的酒单 can hold IBA's three folders, each still whole, and not one recipe has moved. The alternative -- recipes
/// carrying many memberships -- would have contradicted the first constraint, and it is also worse: renaming a
/// folder would then mean rewriting every recipe in it.
///
/// **Nothing here is stored that can be derived.** The three IBA folders keep being computed from each recipe's
/// `extras` by `foldersOf`; a collection that contains one holds a *reference* to it by key. That is what lets a
/// recipe added to the library land in its right folder with no migration, and what keeps the two layers honest --
/// a copy would drift from what it copied, silently.
final class RecipeCollections {
  const RecipeCollections({
    required this.collections,
    required this.hiddenFolders,
  });

  /// Every collection the reader has made, by id.
  final Map<String, RecipeCollection> collections;

  /// The keys of derived folders the reader asked not to see.
  final Set<String> hiddenFolders;

  static const RecipeCollections none =
      RecipeCollections(collections: {}, hiddenFolders: {});

  bool get isEmpty => collections.isEmpty;

  /// The collections that are not held by another one.
  ///
  /// **What a screen lists at the top level**, and the reason a collection shows up once: a collection that is
  /// inside another is reachable by opening that one, and listing it twice would make the same thing look like two.
  List<RecipeCollection> get roots {
    final held = <String>{};
    for (final collection in collections.values) {
      for (final member in collection.members) {
        if (member is CollectionMemberOf) held.add(member.collectionId);
      }
    }
    final out =
        collections.values.where((c) => !held.contains(c.id)).toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    return out;
  }

  RecipeCollection? byId(String id) => collections[id];

  /// Folds the log into the reader's collections.
  ///
  /// **Last write wins per id, by the hybrid clock**, which is the same rule the overlay uses for a field: two
  /// devices that both wrote a collection settle on the later event, and the fold does not need to know which
  /// arrived first. A cleared collection is removed rather than emptied, because "deleted" and "empty" are
  /// different things to a reader.
  factory RecipeCollections.of(Iterable<Event> events) {
    final ordered = events
        .where((event) =>
            event.type == RecipeCollectionEvent.set ||
            event.type == RecipeCollectionEvent.cleared)
        .toList()
      ..sort((a, b) => a.hlc.compareTo(b.hlc));

    final out = <String, RecipeCollection>{};
    for (final event in ordered) {
      final id = event.require<String>('id');
      if (event.type == RecipeCollectionEvent.cleared) {
        out.remove(id);
        continue;
      }
      final members = <CollectionMember>[];
      for (final part in event.require<String>('members').split(',')) {
        final member = CollectionMember.tryDecode(part);
        // **A member this build cannot read is dropped and the collection survives.** An event written by a newer
        // build may name a kind of member that does not exist here; refusing the whole collection would lose the
        // reader's name and every other member with it.
        if (member != null) members.add(member);
      }
      out[id] = RecipeCollection(
        id: id,
        name: event.require<String>('name'),
        members: List<CollectionMember>.unmodifiable(members),
      );
    }

    return RecipeCollections(
      collections: Map<String, RecipeCollection>.unmodifiable(out),
      hiddenFolders: hiddenFoldersOf(events),
    );
  }
}

/// One collection the reader made.
final class RecipeCollection {
  const RecipeCollection({required this.id, required this.name, required this.members});

  final String id;
  final String name;
  final List<CollectionMember> members;

  /// How many recipes are reachable from here, counting through nested collections.
  ///
  /// **Recipes, not members.** A screen that said "3" for a collection holding three folders would be counting the
  /// wrong thing -- the reader wants to know how many drinks are in there. Cycles are already impossible by
  /// construction (see [RecipeCollections.record]), but this carries a visited set anyway: a fold that can loop
  /// forever on bad data is not made safe by the writer being careful.
  int countIn(RecipeCollections all, {Set<String>? visited}) {
    final seen = visited ?? <String>{};
    var total = 0;
    for (final member in members) {
      switch (member) {
        case RecipeMember():
          total += 1;
        case DerivedFolderMember():
          // A derived folder is counted by its resolver, which the UI supplies -- the domain does not read the
          // library. It counts as at least one, so a collection of folders never reads as empty.
          total += 1;
        case CollectionMemberOf(:final collectionId):
          if (!seen.add(collectionId)) continue;
          total += all.byId(collectionId)?.countIn(all, visited: seen) ?? 0;
      }
    }
    return total;
  }
}

/// Whether a collection may contain what it is about to contain.
///
/// **The check has to happen before the event is written.** A cycle is not a rendering problem a screen can dodge:
/// the fold that lists a collection's contents would recurse until the stack ran out, and by then the bad event is
/// in the log and in every synced copy of it. Refusing at the door costs a message; refusing later costs a
/// migration.
///
/// Returns null when the membership is fine, and the problem when it is not.
CollectionProblem? checkMembership({
  required String id,
  required Iterable<CollectionMember> members,
  required RecipeCollections existing,
}) {
  // Adding a member to a collection that does not exist yet cannot close a loop, because nothing can reach it.
  final chain = _pathTo(id, members, existing, <String>[]);
  return chain == null ? null : CollectionWouldContainItself(chain);
}

/// The path from one of [members] to [target], or null when none leads there.
List<String>? _pathTo(
  String target,
  Iterable<CollectionMember> from,
  RecipeCollections existing,
  List<String> trail,
) {
  for (final member in from) {
    if (member is! CollectionMemberOf) continue;
    if (member.collectionId == target) return [...trail, member.collectionId];
    // A member that a previous pass is already inside is a loop that already exists -- not this operation's doing,
    // and not something to walk into. Skipping it means an already-broken log cannot hang the check either.
    if (trail.contains(member.collectionId)) continue;
    final nested = existing.byId(member.collectionId);
    if (nested == null) continue;
    final deeper = _pathTo(target, nested.members, existing, [...trail, member.collectionId]);
    if (deeper != null) return deeper;
  }
  return null;
}
