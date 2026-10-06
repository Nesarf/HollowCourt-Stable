import 'package:hollow_court/data/folder_styles.dart';
import 'package:hollow_court/domain/events/court_pack.dart';
import 'package:hollow_court/domain/events/event.dart';
import 'package:hollow_court/domain/events/hlc.dart';
import 'package:hollow_court/domain/model/pack_book.dart';
import 'package:test/test.dart';

/// The packs a reader defined, folded out of the log.
///
/// **What this family fixes, rather than what it adds.** A recipe already carried a `packId`, and the reader's own
/// name for that folder lived in `folder_styles.json` -- **a file beside the cellar**, outside the log. So everything
/// else in this application travelled between devices and the folder names did not. `docs/proposal-recipes-and-packs.md`
/// §1 is where the owner asked for it: *"Folders (`packId`) become real, and the user defines them."*
void main() {
  Hlc at(int millis, [int counter = 0]) =>
      Hlc(physicalMillis: millis, counter: counter, nodeId: 'a');

  CourtPack pack(String id, String name, {int? order, String? note, String? accent}) =>
      CourtPack(id: id, name: name, order: order, note: note, accent: accent);

  Event written(CourtPack p, [int millis = 1000]) =>
      CourtPackEvents.set(hlc: at(millis), pack: p);

  test('**a pack that was defined is in the book**', () {
    final book = PackBook.of([written(pack('house', '自作酒'))]);
    expect(book.length, 1);
    expect(book['house']!.name, '自作酒');
  });

  test('nothing defined is an empty book rather than a null one', () {
    expect(PackBook.of(const <Event>[]).isEmpty, isTrue);
    expect(PackBook.of(const <Event>[]).all, isEmpty);
  });

  test('**writing the same id twice leaves one, and the later write wins**', () {
    // The event is the whole record, so a rename is a second write -- and a fold that kept the first would show a
    // reader their renaming being ignored, which is what they would notice first.
    final book = PackBook.of([
      written(pack('house', '旧名'), 1000),
      written(pack('house', '新名', note: '2026 秋'), 2000),
    ]);
    expect(book.length, 1);
    expect(book['house']!.name, '新名');
    expect(book['house']!.note, '2026 秋');
  });

  test('**clock order decides, not arrival order**', () {
    final book = PackBook.of([
      written(pack('house', '新名'), 2000),
      written(pack('house', '旧名'), 1000),
    ]);
    expect(book['house']!.name, '新名', reason: 'the later clock reading is the surviving record');
  });

  test('**a removal takes the pack out**', () {
    final book = PackBook.of([
      written(pack('house', '自作酒'), 1000),
      CourtPackEvents.removed(hlc: at(2000), id: 'house'),
    ]);
    expect(book.isEmpty, isTrue);
    expect(book.isMine('house'), isFalse);
  });

  test('a removal arriving before the write still removes', () {
    final book = PackBook.of([
      CourtPackEvents.removed(hlc: at(3000), id: 'house'),
      written(pack('house', '自作酒'), 1000),
    ]);
    expect(book.isEmpty, isTrue);
  });

  test('**the official pack cannot be removed by writing an event**', () {
    // The guard is here rather than in a screen, so no build can make the shipped pack disappear by recording that
    // somebody asked it to.
    expect(
      () => CourtPackEvents.removed(hlc: at(1), id: officialPackId),
      throwsArgumentError,
    );
    expect(CourtPackEvents.removed(hlc: at(1), id: 'house').type, CourtPackEvent.removed);
  });

  group('what it refuses', () {
    test('**a nameless pack is refused**', () {
      expect(validatePack(pack('house', '   ')), contains(isA<PackUnnamed>()));
    });

    test('**the official id is refused even with a good name**', () {
      // "This came with the application" is a fact about the build rather than a property somebody chooses, so the id
      // is what decides -- and a reader cannot claim it by typing it.
      final problems = validatePack(pack(officialPackId, '我的官方包'));
      expect(problems.whereType<PackIsBuiltIn>().single.id, officialPackId);
    });

    test('a good one has no problems', () {
      expect(validatePack(pack('house', '自作酒', order: 20)), isEmpty);
    });

    test('the built-in flag follows the id rather than a field', () {
      expect(pack(officialPackId, 'x').isBuiltIn, isTrue);
      expect(pack('house', 'x').isBuiltIn, isFalse);
    });
  });

  group('order', () {
    test('**a pack with an order sorts by it, and one without keeps the derived order**', () {
      final book = PackBook.of([
        written(pack('b', 'b', order: 20), 1000),
        written(pack('a', 'a', order: 10), 2000),
        written(pack('c', 'c'), 3000),
      ]);
      final names = book.ordered.map((p) => p.id).toList();
      expect(names.take(2), ['a', 'b'], reason: 'the two that said where they go are in that order');
      expect(names.last, 'c', reason: 'the one that did not say falls to the end');
    });
  });

  group('**the migration from the old style file**', () {
    // Until 2026-10-01 a reader's own folder name lived in `folder_styles.json` -- a file beside the cellar -- so it
    // never synced while every other kind of reader-written thing did. The page reads the log now, which **would have
    // silently dropped the names already in that file** if nothing read them.
    //
    // **The mapping is a pure function so the decision inside it can be tested without a file system**: the store's
    // `name` is optional and a pack's is not.
    test('**a named style becomes a pack with that name**', () {
      final pack = PackBook.packFromStyle(
        'iba/The Unforgettables',
        const FolderStyle(name: 'IBA 经典', note: 'reference', accent: '#8A5A32', order: 20),
      );
      expect(pack.id, 'iba/The Unforgettables');
      expect(pack.name, 'IBA 经典');
      expect(pack.note, 'reference');
      expect(pack.accent, '#8A5A32');
      expect(pack.order, 20);
    });

    test('**an unnamed style keeps the name the reader is already looking at**', () {
      // The key is `source/category`, which is what the folder is called on screen today -- so a migrated pack keeps
      // that rather than arriving blank. **Dropping the entry would be the quiet failure**: a style with only an
      // `order` or only an `accent` is a real thing a reader can have, and losing it would silently reorder their
      // folders.
      final pack = PackBook.packFromStyle('iba/New Era', const FolderStyle(order: 5));
      expect(pack.name, 'iba/New Era');
      expect(pack.order, 5);
    });

    test('a migrated pack is read by the page exactly as the style was', () {
      // The view is what the recipes page consumes, so a migration that produced packs the view cannot express would
      // be invisible until somebody opened the app.
      final book = PackBook.of([
        written(
          PackBook.packFromStyle('iba/New Era', const FolderStyle(name: '新时代', accent: '#123456', order: 3)),
        ),
      ]);
      final styles = book.asFolderStyles;
      expect(styles['iba/New Era']!.name, '新时代');
      expect(styles['iba/New Era']!.accent, '#123456');
      expect(styles['iba/New Era']!.order, 3);
    });
  });

  test('events from other families are ignored, not guessed at', () {
    // The log holds stock, prices, overlays, recipes, ingredients and collections too. A fold that read those as
    // packs would be inventing folders out of other people's sentences.
    final book = PackBook.of([
      Event(hlc: at(1), type: 'stock.bottle.added', data: const {'bottleId': 'b1'}),
      Event(hlc: at(2), type: 'recipe.authored.set', data: const {'recipe': '{}'}),
      written(pack('house', 'real one'), 3000),
    ]);
    expect(book.length, 1);
    expect(book.all.single.name, 'real one');
  });

  test('a note and an accent survive the round trip', () {
    final book = PackBook.of([
      written(pack('house', '自作酒', note: '2026 秋, 自己调的', accent: '#8A5A32')),
    ]);
    final p = book.all.single;
    expect(p.note, '2026 秋, 自己调的');
    expect(p.accent, '#8A5A32');
  });
}
