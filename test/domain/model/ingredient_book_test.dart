import 'package:hollow_court/domain/events/event.dart';
import 'package:hollow_court/domain/events/hlc.dart';
import 'package:hollow_court/domain/events/ingredient_authoring.dart';
import 'package:hollow_court/domain/model/ingredient_category.dart';
import 'package:hollow_court/domain/model/ingredient_book.dart';
import 'package:test/test.dart';

/// The ingredients a reader added, folded out of the log.
///
/// **Why this family exists, in numbers measured on 2026-10-01**: the shipped catalogue is 189 ingredients and the
/// reader cannot add a 190th; **only 47 of them carry a category at all**, the enum declares 33 categories and the
/// seed uses 17, and `tequilaAndMezcal` -- a base spirit -- has nothing in it. So somebody who keeps the plum wine
/// their neighbour makes can write a bottle of it, price it and pour it, and then file it under nothing for ever.
void main() {
  Hlc at(int millis, [int counter = 0]) =>
      Hlc(physicalMillis: millis, counter: counter, nodeId: 'a');

  AuthoredIngredient mine(String name, {String? category, List<String> aliases = const []}) =>
      AuthoredIngredient(
        id: AuthoredIngredientId.from(name, at(1000)),
        name: name,
        category: category,
        aliases: aliases,
      );

  Event written(AuthoredIngredient i, [int millis = 1000]) =>
      IngredientAuthoredEvents.set(hlc: at(millis), ingredient: i);

  test('**an ingredient that was added is in the book**', () {
    final book = IngredientBook.of([written(mine('梅酒'))]);
    expect(book.length, 1);
    expect(book.all.single.name, '梅酒');
  });

  test('nothing added is an empty book rather than a null one', () {
    expect(IngredientBook.of(const <Event>[]).isEmpty, isTrue);
    expect(IngredientBook.of(const <Event>[]).all, isEmpty);
  });

  test('**writing the same id twice leaves one, and the later write wins**', () {
    // The event is the whole record, so an edit is a second write -- and a fold that kept the first would show a
    // reader their correction being ignored.
    final first = mine('plum wine');
    final edited = AuthoredIngredient(id: first.id, name: 'ume wine');
    final book = IngredientBook.of([written(first, 1000), written(edited, 2000)]);
    expect(book.length, 1);
    expect(book.all.single.name, 'ume wine');
  });

  test('**clock order decides, not arrival order**', () {
    final first = mine('plum wine');
    final edited = AuthoredIngredient(id: first.id, name: 'ume wine');
    final book = IngredientBook.of([written(edited, 2000), written(first, 1000)]);
    expect(book.all.single.name, 'ume wine', reason: 'the later clock reading is the surviving record');
  });

  test('**a removal takes the ingredient out**', () {
    final i = mine('temporary');
    final book = IngredientBook.of([
      written(i, 1000),
      IngredientAuthoredEvents.removed(hlc: at(2000), id: i.id),
    ]);
    expect(book.isEmpty, isTrue);
    expect(book.isMine(i.id), isFalse);
  });

  test('a removal arriving before the write still removes', () {
    final i = mine('gone');
    final book = IngredientBook.of([
      IngredientAuthoredEvents.removed(hlc: at(3000), id: i.id),
      written(i, 1000),
    ]);
    expect(book.isEmpty, isTrue);
  });

  test('**a shipped ingredient cannot be removed by writing an event**', () {
    // The guard is here rather than in a screen, so no build can make something disappear from the catalogue by
    // recording that somebody asked it to.
    expect(
      () => IngredientAuthoredEvents.removed(hlc: at(1), id: 'ginPlymouth'),
      throwsArgumentError,
    );
    expect(
      IngredientAuthoredEvents.removed(hlc: at(1), id: 'own.mine-1-0').type,
      IngredientAuthoredEvent.removed,
    );
  });

  group('the category is a name, not an index into this build\'s enum', () {
    test('**a grouping this build carries resolves to it**', () {
      // A reader's own ingredient may be filed under one of the three browse groupings, which is all
      // `IngredientCategory` holds since the substance categories became `kind`/`family`.
      final book = IngredientBook.of([written(mine('梅酒', category: 'itemsYouCanMake'))]);
      expect(book.categoryOf(book.all.single.id), IngredientCategory.itemsYouCanMake);
    });

    test('**a grouping this build does not carry resolves to nothing rather than to the nearest**', () {
      // What an ingredient written by a newer build produces. Returning a nearest match would silently reclassify
      // somebody's record, which is the reasoning the recipe's `method` and unit handling already follow -- and
      // `tea` is the live example, since a newer build may well have it as a grouping where this one has it as a
      // `kind`.
      final book = IngredientBook.of([written(mine('茶', category: 'tea'))]);
      expect(book.categoryOf(book.all.single.id), isNull);
    });

    test('an ingredient with no category resolves to nothing', () {
      final book = IngredientBook.of([written(mine('梅酒'))]);
      expect(book.categoryOf(book.all.single.id), isNull);
    });
  });

  group('the id', () {
    test('**is always the reader\'s own, whatever the name**', () {
      // The prefix is what keeps a reader's ingredient from colliding with the catalogue's. A collision would let one
      // overwrite the other, which looks like a save that did not work.
      for (final name in ['Plum Wine', '  ', '!!!', '梅酒', 'a' * 200]) {
        expect(AuthoredIngredientId.isMine(AuthoredIngredientId.from(name, at(42))), isTrue);
      }
      expect(AuthoredIngredientId.isMine('ginPlymouth'), isFalse);
    });

    test('is stable for the same name and clock, and differs across clocks', () {
      expect(
        AuthoredIngredientId.from('Ume', at(42)),
        AuthoredIngredientId.from('Ume', at(42)),
      );
      expect(
        AuthoredIngredientId.from('Ume', at(42, 1)),
        isNot(AuthoredIngredientId.from('Ume', at(42, 0))),
      );
    });

    test('survives a filename', () {
      final id = AuthoredIngredientId.from('Gin & Tonic / 金汤力!', at(42));
      expect(id, isNot(contains(' ')));
      expect(id, isNot(contains('/')));
      expect(id, matches(RegExp(r'^own\.[a-z0-9\u4e00-\u9fff-]+-\d+-\d+$')));
    });
  });

  group('what it refuses', () {
    test('**a nameless ingredient is refused**', () {
      final problems = validateAuthoredIngredient(
        mine('   '),
        existingIds: const {},
      );
      expect(problems, contains(isA<IngredientUnnamed>()));
    });

    test('**an id that is not the reader\'s own is refused, and named**', () {
      const borrowed = AuthoredIngredient(id: 'ginPlymouth', name: 'borrowed');
      final problems = validateAuthoredIngredient(borrowed, existingIds: const {});
      expect(problems.whereType<IngredientIdNotMine>().single.id, 'ginPlymouth');
    });

    test('a good one has no problems', () {
      expect(
        validateAuthoredIngredient(mine('梅酒', category: 'wine'), existingIds: const {}),
        isEmpty,
      );
    });
  });

  test('events from other families are ignored, not guessed at', () {
    final book = IngredientBook.of([
      Event(hlc: at(1), type: 'stock.bottle.added', data: const {'bottleId': 'b1'}),
      Event(hlc: at(2), type: 'recipe.authored.set', data: const {'recipe': '{}'}),
      written(mine('real one'), 3000),
    ]);
    expect(book.length, 1);
    expect(book.all.single.name, 'real one');
  });
}
