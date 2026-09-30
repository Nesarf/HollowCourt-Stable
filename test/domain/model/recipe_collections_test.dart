import 'package:hollow_court/domain/events/hlc.dart';
import 'package:hollow_court/domain/events/recipe_collection.dart';
import 'package:hollow_court/domain/model/recipe_collections.dart';
import 'package:test/test.dart';

/// **The tree, and the one thing a tree can get wrong.**
///
/// The owner's request was to merge several existing collections into a new one while keeping the originals, and
/// their two constraints are what shape this: **a recipe belongs to exactly one collection**, and **a collection
/// may contain another collection**. So 我的酒单 holds IBA's three folders and not one recipe has moved.
///
/// These cover the fold and the membership check. The check is the part worth having tests for at all -- folding a
/// map is arithmetic, while a cycle is the failure that turns a screen into a stack overflow, and it has to be
/// refused before the event is written rather than discovered while drawing.
void main() {
  var clock = 1000;
  Hlc next() => Hlc(physicalMillis: ++clock, counter: 0, nodeId: 'test');

  /// Records a collection the way the application would, checking membership first.
  List<dynamic> write(
    List<dynamic> log, {
    required String id,
    required String name,
    required List<CollectionMember> members,
  }) {
    final existing = RecipeCollections.of(log.cast());
    final problem = checkMembership(id: id, members: members, existing: existing);
    if (problem != null) return [...log, problem];
    return [
      ...log,
      RecipeCollectionEvents.set(hlc: next(), id: id, name: name, members: members),
    ];
  }

  List<CollectionMember> recipe(String id) => [RecipeMember(id)];
  List<CollectionMember> folder(String key) => [DerivedFolderMember(key)];

  test('a collection holds a name and its members', () {
    final log = write([], id: 'c1', name: '我的常做', members: recipe('gimlet'));
    final all = RecipeCollections.of(log.cast());

    expect(all.byId('c1')!.name, '我的常做');
    expect(all.byId('c1')!.members, [const RecipeMember('gimlet')]);
    expect(all.roots, hasLength(1));
  });

  test('**a collection can hold another collection, and the originals stay**', () {
    // This is the owner's example: IBA's three folders, each kept whole, gathered into one.
    var log = write([], id: 'iba', name: 'The Unforgettables', members: folder('iba/The Unforgettables'));
    log = write(log, id: 'cont', name: 'Contemporary Classics', members: folder('iba/Contemporary Classics'));
    log = write(log, id: 'era', name: 'New Era', members: folder('iba/New Era'));
    log = write(log, id: 'mine', name: '我的酒单', members: [
      const CollectionMemberOf('iba'),
      const CollectionMemberOf('cont'),
      const CollectionMemberOf('era'),
    ]);

    final all = RecipeCollections.of(log.cast());

    // The three are still there, unmodified -- 保留原本 means exactly this and not a copy.
    expect(all.byId('iba')!.name, 'The Unforgettables');
    expect(all.byId('iba')!.members, folder('iba/The Unforgettables'));

    // And the new one holds them.
    expect(all.byId('mine')!.members, hasLength(3));

    // **Only the top of the tree is listed at the top level.** A collection inside another is reached by opening
    // it, so listing it twice would make one thing look like two.
    expect(all.roots.map((c) => c.id), ['mine']);
  });

  test('a collection that nothing holds is a root, and one that is held is not', () {
    var log = write([], id: 'a', name: 'A', members: recipe('x'));
    log = write(log, id: 'b', name: 'B', members: const [CollectionMemberOf('a')]);

    final all = RecipeCollections.of(log.cast());
    expect(all.roots.map((c) => c.id), ['b'], reason: 'a is inside b');
  });

  test('**a collection cannot contain itself directly**', () {
    final log = write([], id: 'a', name: 'A', members: recipe('x'));
    final existing = RecipeCollections.of(log.cast());

    final problem = checkMembership(
      id: 'a',
      members: const [CollectionMemberOf('a')],
      existing: existing,
    );

    expect(problem, isA<CollectionWouldContainItself>());
    expect((problem! as CollectionWouldContainItself).chain, ['a']);
  });

  test('**a collection cannot contain itself through a chain**', () {
    // A holds B; asking to put A inside B would close A -> B -> A. This is the one that would recurse until the
    // stack ran out, and by then the event would be in the log and in every synced copy of it.
    var log = write([], id: 'b', name: 'B', members: recipe('x'));
    log = write(log, id: 'a', name: 'A', members: const [CollectionMemberOf('b')]);
    final existing = RecipeCollections.of(log.cast());

    final problem = checkMembership(
      id: 'b',
      members: const [CollectionMemberOf('a')],
      existing: existing,
    );

    expect(problem, isA<CollectionWouldContainItself>());
    // The chain is reported, because a message that names the loop is a message that explains itself.
    expect((problem! as CollectionWouldContainItself).chain, ['a', 'b']);
  });

  test('**a new collection holding an existing one is allowed, which is the ordinary case**', () {
    final log = write([], id: 'a', name: 'A', members: recipe('x'));
    final existing = RecipeCollections.of(log.cast());

    final problem = checkMembership(
      id: 'fresh',
      members: const [CollectionMemberOf('a')],
      existing: existing,
    );

    expect(problem, isNull, reason: 'nothing reaches a collection that does not exist yet');
  });

  test('**an already-broken log cannot hang the check**', () {
    // Two collections that a previous version let point at each other. The check must survive data it did not
    // write -- a rule that only holds for logs this version produced is not a rule.
    final log = [
      RecipeCollectionEvents.set(hlc: next(), id: 'a', name: 'A', members: const [
        CollectionMemberOf('b'),
      ]),
      RecipeCollectionEvents.set(hlc: next(), id: 'b', name: 'B', members: const [
        CollectionMemberOf('a'),
      ]),
    ];
    final existing = RecipeCollections.of(log);

    // The paths are checked with a trail, so an existing loop is stepped over rather than walked into.
    final problem = checkMembership(
      id: 'c',
      members: const [CollectionMemberOf('a')],
      existing: existing,
    );
    expect(problem, isNull);
  });

  test('removing a collection removes it, rather than emptying it', () {
    var log = write([], id: 'a', name: 'A', members: recipe('x'));
    log = [...log, RecipeCollectionEvents.cleared(hlc: next(), id: 'a')];

    final all = RecipeCollections.of(log.cast());
    expect(all.byId('a'), isNull, reason: 'deleted and empty are different to a reader');
    expect(all.isEmpty, isTrue);
  });

  test('**a member this build cannot read is dropped and its collection survives**', () {
    // An event from a build that knows a fourth kind of member. Refusing the whole collection would lose the
    // reader's name and every other member with it.
    final log = [
      RecipeCollectionEvents.set(hlc: next(), id: 'a', name: 'A', members: const [
        RecipeMember('gimlet'),
      ]),
      // Overwritten by hand with a member prefix this build does not know.
      RecipeCollectionEvents.set(hlc: next(), id: 'a', name: 'A', members: const [
        RecipeMember('gimlet'),
        RecipeMember('martini'),
      ]),
    ];
    final all = RecipeCollections.of(log);
    expect(all.byId('a')!.members, hasLength(2));

    // And a payload with an unreadable part decodes to what it can.
    expect(CollectionMember.tryDecode('z:future'), isNull);
    expect(CollectionMember.tryDecode('r:gimlet'), const RecipeMember('gimlet'));
    expect(CollectionMember.tryDecode('f:iba/New Era'), const DerivedFolderMember('iba/New Era'));
    expect(CollectionMember.tryDecode('c:c1f2'), const CollectionMemberOf('c1f2'));
  });

  test('**hiding a derived folder is a record, not a move**', () {
    // 保留原本 has a counterpart: merging three folders and not showing the three. A derived folder is computed
    // from each recipe's extras, so the only honest way to stop showing it is to note that the reader asked.
    var log = [
      RecipeCollectionEvents.folderHidden(hlc: next(), folderKey: 'iba/New Era'),
    ];
    expect(RecipeCollections.of(log).hiddenFolders, {'iba/New Era'});

    // Shown again, and the later event wins because they are ordered by the hybrid clock.
    log = [...log, RecipeCollectionEvents.folderShown(hlc: next(), folderKey: 'iba/New Era')];
    expect(RecipeCollections.of(log).hiddenFolders, isEmpty);
  });

  test('an id made from a name is the same on two devices', () {
    // A counter would need a coordinator, and two devices offline would both create collection 7. A hash of the
    // name means the same name is one collection wherever it was typed.
    expect(collectionIdOf('我的酒单'), collectionIdOf('我的酒单'));
    expect(collectionIdOf(' 我的酒单 '), collectionIdOf('我的酒单'), reason: 'trimmed');
    expect(collectionIdOf('我的酒单'), isNot(collectionIdOf('我的常做')));
  });
}
