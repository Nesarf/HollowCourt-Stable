import 'package:hollow_court/domain/events/event.dart';
import 'package:hollow_court/domain/events/hlc.dart';
import 'package:hollow_court/domain/events/shelf.dart';
import 'package:hollow_court/domain/events/stock.dart';
import 'package:hollow_court/domain/units/quantity.dart';
import 'package:test/test.dart';

/// A clock reading from [node], [millis] into the log's own timeline.
Hlc at(String node, int millis, [int counter = 0]) =>
    Hlc(physicalMillis: millis, counter: counter, nodeId: node);

/// Reading numbers for helper-created events, kept well clear of the small
/// explicit values the ordering tests use.
int _seq = 1000;

/// A placement, with a clock reading that advances on its own.
///
/// **The default has to advance, and finding that out was the first thing these
/// tests did.** Giving every helper-created event the same reading made the fold
/// drop all but one as a sync duplicate -- correctly, because two events with an
/// identical Hlc are the same event as far as any device can tell. An HLC only
/// orders the events of one node if that node moves it, which is what HlcClock
/// does and what a hand-written test helper has to do too.
Event place(
  String bottle,
  String shelf,
  int x,
  int y, {
  String node = 'laptop',
  int? millis,
}) => ShelfEvents.bottlePlaced(
  hlc: at(node, millis ?? ++_seq),
  bottleId: bottle,
  shelfId: shelf,
  posXPermille: x,
  posYPermille: y,
);

void main() {
  group('a bottle nobody has put anywhere', () {
    test('has no position rather than the default one', () {
      // The distinction this whole fold turns on, and the same one library.dart
      // makes between an empty shelf and a bare cellar. Reporting 0/0 for an
      // unplaced bottle would say somebody stood it against the left wall, and
      // a screen that drew it there would be inventing an arrangement.
      final layout = ShelfLayout.of([place('b1', 'bar', 100, 200)]);

      expect(layout.placementOf('b1'), isNotNull);
      expect(layout.placementOf('b2'), isNull);
      expect(layout.isPlaced('b2'), isFalse);
    });

    test('an empty log places nothing, which is not an error', () {
      final layout = ShelfLayout.of(const <Event>[]);

      expect(layout.placedCount, 0);
      expect(layout.shelves, isEmpty);
      expect(layout.malformedEvents, 0);
      expect(layout.ignoredEvents, 0);
    });
  });

  group('a move is a placement with a later clock reading', () {
    test('the later one wins, whatever order the log arrived in', () {
      // A sync delivers events in whatever order the network produced them, so
      // folding in arrival order would make the arrangement depend on the
      // network. Given the same two events in the opposite order, the answer has
      // to be the same.
      final first = place('b1', 'bar', 100, 200, millis: 1);
      final second = place('b1', 'fridge', 800, 100, millis: 2);

      for (final order in [
        [first, second],
        [second, first],
      ]) {
        final layout = ShelfLayout.of(order);
        expect(layout.placementOf('b1')!.shelfId, 'fridge');
        expect(layout.placementOf('b1')!.posXPermille, 800);
      }
    });

    test('an earlier placement is not counted as an error', () {
      // Two applied placements and one bottle is the normal case, not a
      // duplicate: a bottle that was moved was placed twice.
      final layout = ShelfLayout.of([
        place('b1', 'bar', 100, 200, millis: 1),
        place('b1', 'fridge', 800, 100, millis: 2),
      ]);

      expect(layout.placedCount, 1);
      expect(layout.placedEvents, 2);
      expect(layout.duplicateEvents, 0);
      expect(layout.malformedEvents, 0);
    });

    test('two devices at the same moment resolve by node, not by luck', () {
      // Hlc compares physical time, then counter, then node id, so this order is
      // total and has no tie to break. Both devices compute the same winner
      // without talking to each other.
      final a = place('b1', 'bar', 100, 100, node: 'aaa', millis: 5);
      final b = place('b1', 'bar', 900, 100, node: 'bbb', millis: 5);

      final layout = ShelfLayout.of([b, a]);

      expect(layout.placementOf('b1')!.posXPermille, 900);
      expect(layout.placementOf('b1')!.hlc.nodeId, 'bbb');
    });
  });

  group('what the fold refuses and what it merely counts', () {
    test('a duplicate across a sync is applied once', () {
      final one = place('b1', 'bar', 250, 250, millis: 3);
      final layout = ShelfLayout.of([one, one]);

      expect(layout.placedCount, 1);
      expect(layout.placedEvents, 1);
      expect(layout.duplicateEvents, 1);
    });

    test('a position outside the shelf is reported, not clamped to the edge', () {
      // Pinning 1001 to 1000 would hide a real disagreement between two builds
      // -- a different resolution, or a bad write -- behind an arrangement that
      // looks plausible. The good placement underneath it survives untouched.
      //
      // Built as raw events on purpose. The builder asserts, so it refuses to
      // *write* an out-of-range position; the fold still has to decide what to
      // do with one that *arrives*, because a log can come from a build with a
      // different resolution. Refusing to write and refusing to read are two
      // different jobs and this pair is where they are told apart.
      Event raw(String id, int x, int y, int millis) => Event(
        hlc: at('laptop', millis),
        type: ShelfEvent.bottlePlaced,
        data: {
          'bottleId': id,
          'shelfId': 'bar',
          'posXPermille': x,
          'posYPermille': y,
        },
      );
      final layout = ShelfLayout.of([
        place('b1', 'bar', 400, 400, millis: 1),
        raw('b1', 1001, 400, 2),
        raw('b2', -1, 0, 3),
      ]);

      expect(layout.malformedEvents, 2);
      expect(layout.placementOf('b1')!.posXPermille, 400);
      expect(layout.isPlaced('b2'), isFalse);
    });

    test('an event with no bottle, no shelf, or no position is malformed', () {
      final layout = ShelfLayout.of([
        Event(
          hlc: at('laptop', 4),
          type: ShelfEvent.bottlePlaced,
          data: {'shelfId': 'bar', 'posXPermille': 1, 'posYPermille': 1},
        ),
        Event(
          hlc: at('laptop', 5),
          type: ShelfEvent.bottlePlaced,
          data: {'bottleId': 'b1', 'posXPermille': 1, 'posYPermille': 1},
        ),
        Event(
          hlc: at('laptop', 6),
          type: ShelfEvent.bottlePlaced,
          data: {'bottleId': 'b1', 'shelfId': 'bar'},
        ),
      ]);

      expect(layout.malformedEvents, 3);
      expect(layout.placedCount, 0);
    });

    test('a stock event is ignored rather than read as a bad placement', () {
      // The two families share one log. A fold that counted every foreign event
      // as malformed would report the whole cellar as broken.
      final layout = ShelfLayout.of([
        StockEvents.bottleAdded(
          hlc: at('laptop', 1),
          bottleId: 'b1',
          sku: 'gin',
          volume: Volume.fromMillilitres(700),
        ),
        place('b1', 'bar', 10, 20, millis: 2),
      ]);

      expect(layout.ignoredEvents, 1);
      expect(layout.malformedEvents, 0);
      expect(layout.placedCount, 1);
    });
  });

  group('reading one shelf back', () {
    test('order is left to right, then front to back, then by id', () {
      // The tie-break by id matters because two bottles at the same position is
      // a thing a person can do by accident. Without it the order would come
      // from map iteration, which is stable for one run and not a promise.
      final layout = ShelfLayout.of([
        place('right', 'bar', 900, 0),
        place('left', 'bar', 100, 0),
        place('tie-b', 'bar', 500, 500),
        place('tie-a', 'bar', 500, 500),
        place('other', 'fridge', 0, 0),
      ]);

      final onBar = layout.onShelf('bar');

      expect(onBar.map((p) => p.bottleId), ['left', 'tie-a', 'tie-b', 'right']);
      expect(layout.onShelf('fridge').single.bottleId, 'other');
      expect(layout.onShelf('nowhere'), isEmpty);
    });

    test('the shelves are the ones that hold something', () {
      final layout = ShelfLayout.of([
        place('b1', 'bar', 1, 1),
        place('b2', 'fridge', 1, 1),
        place('b3', 'fridge', 2, 2),
      ]);

      expect(layout.shelves, {'bar', 'fridge'});
      expect(layout.shelves.length, 2);
    });

    test('bottles still in the box are told apart from bottles on a shelf', () {
      final layout = ShelfLayout.of([place('b1', 'bar', 0, 0)]);

      expect(layout.unplacedAmong(['b1', 'b2', 'b3']), ['b2', 'b3']);
      // b1 stands at 0/0 and is therefore placed; this is the case the default
      // position would have got wrong in the other direction.
      expect(layout.unplacedAmong(['b1']), isEmpty);
    });
  });

  group('the event is a wire format, not display copy', () {
    test('the payload keys are ASCII, because they are read by another build', () {
      final event = place('b1', 'bar', 250, 750);

      expect(event.type, 'stock.bottle.placed');
      for (final key in event.data.keys) {
        expect(key, matches(RegExp(r'^[\x20-\x7E]+$')), reason: 'key $key');
      }
      expect(event.optional<String>('bottleId'), 'b1');
      expect(event.optional<String>('shelfId'), 'bar');
      expect(event.optional<int>('posXPermille'), 250);
      expect(event.optional<int>('posYPermille'), 750);
    });

    test('the stored position stays whole and only the display converts', () {
      final layout = ShelfLayout.of([place('b1', 'bar', 250, 750)]);
      final p = layout.placementOf('b1')!;

      expect(p.posXPermille, 250);
      expect(p.x, 0.25);
      expect(p.y, 0.75);
    });

    test('the builder refuses a position it would have to guess about', () {
      expect(
        () => place('b1', 'bar', 1001, 0),
        throwsA(isA<AssertionError>()),
      );
      expect(() => place('b1', 'bar', 0, -1), throwsA(isA<AssertionError>()));
      expect(() => place('', 'bar', 0, 0), throwsA(isA<AssertionError>()));
      expect(() => place('b1', '', 0, 0), throwsA(isA<AssertionError>()));
    });

    test('a placement knows where it stands without consulting the log', () {
      final layout = ShelfLayout.of([place('b1', 'bar', 100, 200, millis: 7)]);

      expect(
        layout.placementOf('b1'),
        BottlePlacement(
          bottleId: 'b1',
          shelfId: 'bar',
          posXPermille: 100,
          posYPermille: 200,
          hlc: at('laptop', 7),
        ),
      );
      expect(layout.placementOf('b1').hashCode, isNotNull);
    });
  });
}
