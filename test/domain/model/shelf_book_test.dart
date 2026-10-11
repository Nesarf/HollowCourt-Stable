import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:hollow_court/domain/events/event.dart';
import 'package:hollow_court/domain/events/hlc.dart';
import 'package:hollow_court/domain/events/shelf.dart';
import 'package:hollow_court/domain/events/shelf_authoring.dart';
import 'package:hollow_court/domain/events/stock.dart';
import 'package:hollow_court/domain/model/shelf_book.dart';
import 'package:hollow_court/domain/units/quantity.dart';
import 'package:hollow_court/ui/library.dart';
import '../../support/open_logs.dart';

/// **A shelf existed as a key before it existed as a word** -- stage ③ of `docs/catalogue-and-stock.md`.
///
/// `ShelfLayout` has carried a `shelfId` on every placement since its first version, and the interface only ever
/// wrote `'bar'`. So the tests here are mostly about one thing: **a log written before anybody could name a shelf
/// still folds correctly**, and the name is the only thing this family adds.
void main() {
  var clock = 1000;
  Hlc at(int millis) => Hlc(physicalMillis: millis, counter: 0, nodeId: 'test');

  Event named(String id, String name, int millis) => ShelfAuthoredEvents.declared(
    hlc: at(millis),
    shelf: AuthoredShelf(id: id, name: name),
  );

  group('the fold', () {
    test('**a shelf nobody declared is called by its id**', () {
      // The migration, and the whole reason no event is back-filled: every cellar written before this family exists
      // has bottles on `bar` and no declaration of it. An invented name would be a word nobody said, in a log that
      // is supposed to be the only truth.
      expect(ShelfBook.none.nameOf('bar'), 'bar');
      expect(ShelfBook.none.isMine('bar'), isFalse);
      expect(ShelfBook.of(const []).nameOf('own.fridge-1-0'), 'own.fridge-1-0');
    });

    test('a declared shelf answers with the reader\'s word for it', () {
      final book = ShelfBook.of([named('own.fridge-1-0', '冰箱', 1)]);
      expect(book.nameOf('own.fridge-1-0'), '冰箱');
      expect(book.isMine('own.fridge-1-0'), isTrue);
      expect(book.length, 1);
      // And a shelf it has never heard of is still only itself.
      expect(book.nameOf('bar'), 'bar');
    });

    test('**a rename is a declaration whose clock reading is later, so the clock decides**', () {
      // Fed in the wrong order on purpose. A fold that read the list in file order would answer 后柜 here, and two
      // devices holding the same two events would disagree -- which is the rule every fold in this project follows.
      final book = ShelfBook.of([
        named('own.s-1-0', '后柜', 20),
        named('own.s-1-0', '冰箱', 10),
      ]);
      expect(book.nameOf('own.s-1-0'), '后柜');
      expect(book.length, 1);
    });

    test('**a removal takes the word away and leaves the place**', () {
      final book = ShelfBook.of([
        named('own.fridge-1-0', '冰箱', 1),
        ShelfAuthoredEvents.removed(hlc: at(2), id: 'own.fridge-1-0'),
      ]);
      // The shelf is still a shelf -- bottles may be standing on it -- and it is back to being called by its id.
      expect(book.nameOf('own.fridge-1-0'), 'own.fridge-1-0');
      expect(book.isMine('own.fridge-1-0'), isFalse);
    });

    test('removing a shelf nobody named is not an error', () {
      // What a device that has just been sent a deletion sees. The fold's answer -- no name -- is right either way.
      final book = ShelfBook.of([ShelfAuthoredEvents.removed(hlc: at(1), id: 'own.gone-1-0')]);
      expect(book.isEmpty, isTrue);
    });

    test('**the built-in shelf cannot be removed, and the refusal is in the domain**', () {
      // `bar` is what every placement written before this family existed points at, so a removal naming it would be
      // a reader erasing the only shelf most cellars have. Refused at the builder rather than by a screen.
      expect(
        () => ShelfAuthoredEvents.removed(hlc: at(1), id: 'bar'),
        throwsArgumentError,
      );
      // And a declaration cannot take it over either -- the id is the payload, so a reader's shelf cannot be `bar`.
      expect(AuthoredShelfId.isMine('bar'), isFalse);
      expect(AuthoredShelfId.from('bar', at(1)), startsWith(AuthoredShelfId.prefix));
    });

    test('an empty name is what the form is for, and the rule is written down', () {
      expect(
        validateAuthoredShelf(const AuthoredShelf(id: 'own.x-1-0', name: '  ')),
        [isA<ShelfUnnamed>()],
      );
      expect(
        validateAuthoredShelf(const AuthoredShelf(id: 'bar', name: '冰箱')),
        [isA<ShelfIdNotMine>()],
      );
      expect(
        validateAuthoredShelf(const AuthoredShelf(id: 'own.x-1-0', name: '冰箱')),
        isEmpty,
      );
    });
  });

  group('the cellar joins the two', () {
    late Directory home;
    setUp(() => home = Directory.systemTemp.createTempSync('hollow-shelf'));
    tearDown(() async {
      await releaseCellars();
      if (home.existsSync()) home.deleteSync(recursive: true);
    });

    Future<Cellar> cellar(List<Event> events) async {
      final log = await openTracked(
        file: File('${home.path}${Platform.pathSeparator}cellar.ndjson'),
        nodeId: 'test',
        nowMillis: () => ++clock,
      );
      for (final event in events) {
        await log.record((_) => event);
      }
      return Cellar.of(log);
    }

    Event bottle(String id, String sku, int millis) => StockEvents.bottleAdded(
      hlc: at(millis),
      bottleId: id,
      sku: sku,
      volume: Volume.fromMillilitres(700),
    );

    Event stand(String bottleId, String shelfId, int millis) => ShelfEvents.bottlePlaced(
      hlc: at(millis),
      bottleId: bottleId,
      shelfId: shelfId,
      posXPermille: 100,
      posYPermille: 100,
    );

    test('**a bottle on the built-in shelf makes that shelf exist, unnamed**', () async {
      // The state every existing cellar is in: one shelf, no declaration, and a screen that has to offer it.
      final built = await cellar([bottle('b1', 'gin', 1), stand('b1', 'bar', 2)]);
      expect(built.shelfIds, ['bar']);
      expect(built.shelfName('bar'), 'bar');
    });

    test('**a shelf just named exists before anything stands on it**', () async {
      // The union's other half, and neither alone is enough: a list built from placements would hide a shelf the
      // reader has just added, and one built from declarations would hide the built-in shelf they already use.
      final built = await cellar([named('own.fridge-1-0', '冰箱', 1)]);
      expect(built.shelfIds, ['own.fridge-1-0']);
      expect(built.shelfName('own.fridge-1-0'), '冰箱');
    });

    test('named shelves come first, then the ones only something stands on', () async {
      final built = await cellar([
        bottle('b1', 'gin', 1),
        stand('b1', 'zzz-unnamed', 2),
        named('own.fridge-1-0', '冰箱', 3),
      ]);
      expect(built.shelfIds, ['own.fridge-1-0', 'zzz-unnamed']);
    });

    test('**where an ingredient is is a join, and nothing new is stored for it**', () async {
      final built = await cellar([
        bottle('b1', 'gin', 1),
        stand('b1', 'own.fridge-1-0', 2),
        named('own.fridge-1-0', '冰箱', 3),
      ]);
      final where = built.shelfOf('gin');
      expect(where, 'own.fridge-1-0');
      expect(built.shelfName(where!), '冰箱');
    });

    test('**a bottle nobody has stood anywhere answers null rather than guessing**', () async {
      // The ordinary state, not a fault: the bar page names those bottles as "in the box" for the same reason.
      final built = await cellar([bottle('b1', 'gin', 1)]);
      expect(built.shelfOf('gin'), isNull);
    });

    test('**an empty bottle does not answer either**', () async {
      // Standing an empty bottle somewhere is a placement the bar page counts and names rather than draws, and
      // "where is the gin" must not answer with the shelf a finished bottle is still sitting on.
      final built = await cellar([
        bottle('b1', 'gin', 1),
        stand('b1', 'bar', 2),
        StockEvents.bottleConsumed(
          hlc: at(3),
          bottleId: 'b1',
          volume: Volume.fromMillilitres(700),
        ),
      ]);
      expect(built.has('gin'), isFalse);
      expect(built.shelfOf('gin'), isNull);
    });

    test('an ingredient nobody holds has no place, whatever is on a shelf', () async {
      final built = await cellar([bottle('b1', 'gin', 1), stand('b1', 'bar', 2)]);
      expect(built.shelfOf('campari'), isNull);
    });
  });
}
