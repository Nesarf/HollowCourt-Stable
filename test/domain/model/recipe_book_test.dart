import 'package:hollow_court/domain/events/event.dart';
import 'package:hollow_court/domain/events/hlc.dart';
import 'package:hollow_court/domain/events/recipe_authoring.dart';
import 'package:hollow_court/domain/model/recipe_book.dart';
import 'package:test/test.dart';

/// The recipes a reader wrote, folded out of the log.
///
/// **The fold that makes a user-written recipe visible**, which is the half of `docs/proposal-recipes-and-packs.md`
/// §2 that was missing: the event family said what a reader's recipe looks like on disk, and this says what those
/// events mean once they are read back. The gap is stated in the proposal's own words -- *"Can a user create one?
/// **No.**"*
void main() {
  Hlc at(int millis, [int counter = 0, String node = 'a']) =>
      Hlc(physicalMillis: millis, counter: counter, nodeId: node);

  AuthoredRecipe recipe(String name, {String? folder, List<AuthoredItem>? items}) => AuthoredRecipe(
    id: AuthoredRecipeId.from(name, at(1000)),
    name: name,
    folder: folder,
    items: items ??
        const [AuthoredItem(ingredientId: 'ginPlymouth', amount: '30', unit: 'ml')],
  );

  Event written(AuthoredRecipe r, [int millis = 1000]) =>
      RecipeAuthoredEvents.set(hlc: at(millis), recipe: r);

  test('**a recipe that was written is in the book**', () {
    final book = RecipeBook.of([written(recipe('自己的尼格罗尼'))]);
    expect(book.length, 1);
    expect(book.all.single.name, '自己的尼格罗尼');
  });

  test('nothing written is an empty book rather than a null one', () {
    // Every screen reads this, so "no recipes yet" has to be a value rather than an absence to check for.
    expect(RecipeBook.of(const <Event>[]).isEmpty, isTrue);
    expect(RecipeBook.of(const <Event>[]).all, isEmpty);
  });

  test('**writing the same id twice leaves one, and the later write wins**', () {
    // The event is the whole record rather than a change to it, so an edit is a second write -- and a fold that
    // kept the first would show a reader their edit being ignored.
    final first = recipe('first name');
    final edited = AuthoredRecipe(
      id: first.id,
      name: 'later name',
      items: first.items,
    );
    final book = RecipeBook.of([written(first, 1000), written(edited, 2000)]);
    expect(book.length, 1);
    expect(book.all.single.name, 'later name');
  });

  test('**clock order decides, not the order the events arrive in**', () {
    // A merged log holds a peer's events interleaved with local ones, so file order means nothing. Two devices
    // folding the same set must agree, which is what makes deriving this safe rather than storing it.
    final first = recipe('first name');
    final edited = AuthoredRecipe(id: first.id, name: 'later name', items: first.items);
    final book = RecipeBook.of([written(edited, 2000), written(first, 1000)]);
    expect(book.all.single.name, 'later name', reason: 'the later clock reading is the surviving record');
  });

  test('**a removal takes the recipe out**', () {
    final r = recipe('temporary');
    final book = RecipeBook.of([
      written(r, 1000),
      RecipeAuthoredEvents.removed(hlc: at(2000), id: r.id),
    ]);
    expect(book.isEmpty, isTrue);
    expect(book.isMine(r.id), isFalse);
  });

  test('a removal of something never written is not an error', () {
    // What a device sees when it is sent a deletion for a recipe it never had. The fold's answer -- that this
    // recipe is not held -- is correct either way, and refusing the event would make a sync fail over nothing.
    final book = RecipeBook.of([
      RecipeAuthoredEvents.removed(hlc: at(2000), id: 'own.never-seen-1-0'),
    ]);
    expect(book.isEmpty, isTrue);
  });

  test('**a removal arriving before the write still removes**', () {
    // Clock order, not arrival order: the write is older, so it is applied first and then removed.
    final r = recipe('gone');
    final book = RecipeBook.of([
      RecipeAuthoredEvents.removed(hlc: at(3000), id: r.id),
      written(r, 1000),
    ]);
    expect(book.isEmpty, isTrue);
  });

  test('**`isMine` is what a screen asks before offering to delete**', () {
    // A shipped recipe is part of the build and cannot be removed -- `RecipeAuthoredEvents.removed` refuses an id
    // that is not the reader's own -- so a page that offered the button for every row would offer one that cannot
    // work.
    final mine = recipe('mine');
    final book = RecipeBook.of([written(mine)]);
    expect(book.isMine(mine.id), isTrue);
    expect(book.isMine('iba.negroni'), isFalse);
  });

  test('events from other families are ignored, not guessed at', () {
    // The log holds stock, prices, overlays and collections too. A fold that tried to read those as recipes would
    // be inventing records out of other people's sentences.
    final book = RecipeBook.of([
      Event(hlc: at(1), type: 'stock.bottle.added', data: const {'bottleId': 'b1'}),
      Event(hlc: at(2), type: 'price.paid', data: const {'sku': 'gin'}),
      written(recipe('real one'), 3000),
    ]);
    expect(book.length, 1);
    expect(book.all.single.name, 'real one');
  });

  test('a folder and its lines survive the round trip', () {
    final book = RecipeBook.of([
      written(
        recipe(
          'foldered',
          folder: 'own.collection.favourites-1-0',
          items: const [
            AuthoredItem(ingredientId: 'ginPlymouth', amount: '30', unit: 'ml', role: 'base'),
            AuthoredItem(ingredientId: 'campari', amount: '1/2', unit: 'part', note: 'to taste'),
          ],
        ),
      ),
    ]);
    final r = book.all.single;
    expect(r.folder, 'own.collection.favourites-1-0');
    expect(r.items, hasLength(2));
    expect(r.items.last.amount, '1/2', reason: 'a fraction must not become a float');
    expect(r.items.last.note, 'to taste');
  });
}
