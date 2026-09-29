import 'package:hollow_court/domain/events/event.dart';
import 'package:hollow_court/domain/events/hlc.dart';
import 'package:hollow_court/domain/events/price.dart';
import 'package:hollow_court/domain/events/stock.dart';
import 'package:hollow_court/domain/units/quantity.dart';
import 'package:test/test.dart';

/// A clock reading from [node], [millis] into the log's own timeline.
Hlc at(String node, int millis, [int counter = 0]) =>
    Hlc(physicalMillis: millis, counter: counter, nodeId: node);

Volume ml(int millilitres) => Volume.fromMillilitres(millilitres);

void main() {
  group('the case section 6 is written about', () {
    test('two devices that each poured a drink sum, rather than overwrite', () {
      // A poured 4 cl, B poured 2 cl, both from the same bottle, and neither
      // had heard of the other when they did it. Last-write-wins would report
      // 4 cl left of the 10 cl that started there. The answer is 4 cl.
      final events = [
        StockEvents.bottleAdded(
          hlc: at('laptop', 1),
          bottleId: 'b1',
          sku: 'gin',
          volume: ml(10),
        ),
        StockEvents.bottleConsumed(
          hlc: at('laptop', 2),
          bottleId: 'b1',
          volume: ml(4),
        ),
        StockEvents.bottleConsumed(
          hlc: at('phone', 2),
          bottleId: 'b1',
          volume: ml(2),
        ),
      ];

      final ledger = StockLedger.of(events);
      expect(ledger.bottle('b1')!.remaining, ml(4));
      expect(ledger.bottle('b1')!.consumed, ml(6));
    });

    test('the total does not depend on which order the two arrived in', () {
      final added = StockEvents.bottleAdded(
        hlc: at('laptop', 1),
        bottleId: 'b1',
        sku: 'gin',
        volume: ml(10),
      );
      final a = StockEvents.bottleConsumed(
        hlc: at('laptop', 2),
        bottleId: 'b1',
        volume: ml(4),
      );
      final b = StockEvents.bottleConsumed(
        hlc: at('phone', 2),
        bottleId: 'b1',
        volume: ml(2),
      );

      final oneWay = StockLedger.of([added, a, b]);
      final otherWay = StockLedger.of([added, b, a]);

      expect(oneWay.bottle('b1')!.remaining, otherWay.bottle('b1')!.remaining);
      expect(oneWay.bottle('b1')!.consumed, otherWay.bottle('b1')!.consumed);
    });
  });

  group('fold', () {
    test('a single added bottle is full', () {
      final ledger = StockLedger.of([
        StockEvents.bottleAdded(
          hlc: at('a', 1),
          bottleId: 'b1',
          sku: 'rye',
          volume: ml(700),
        ),
      ]);
      final bottle = ledger.bottle('b1')!;
      expect(bottle.remaining, ml(700));
      expect(bottle.consumed, Volume.zero);
      expect(bottle.isOverdrawn, isFalse);
      expect(ledger.bottleCount, 1);
    });

    test('discarding reduces the stock without counting as a drink', () {
      final ledger = StockLedger.of([
        StockEvents.bottleAdded(
          hlc: at('a', 1),
          bottleId: 'b1',
          sku: 'rye',
          volume: ml(700),
        ),
        StockEvents.bottleConsumed(
          hlc: at('a', 2),
          bottleId: 'b1',
          volume: ml(100),
        ),
        StockEvents.bottleDiscarded(
          hlc: at('a', 3),
          bottleId: 'b1',
          volume: ml(50),
        ),
      ]);
      final bottle = ledger.bottle('b1')!;
      expect(bottle.remaining, ml(550));
      expect(bottle.consumed, ml(100), reason: 'the discarded pour was not a drink');
      expect(bottle.discarded, ml(50));
    });

    test('a recount becomes the new truth, and later pours count from it', () {
      // Section 6's one order-dependent operation: looking at a bottle gives an
      // absolute reading, not a delta, so where it sits in the sequence matters.
      final ledger = StockLedger.of([
        StockEvents.bottleAdded(
          hlc: at('a', 1),
          bottleId: 'b1',
          sku: 'campari',
          volume: ml(1000),
        ),
        StockEvents.bottleConsumed(
          hlc: at('a', 2),
          bottleId: 'b1',
          volume: ml(200),
        ),
        // Someone weighed the bottle and found far less than the ledger said.
        StockEvents.bottleRecounted(
          hlc: at('a', 3),
          bottleId: 'b1',
          volume: ml(300),
        ),
        StockEvents.bottleConsumed(
          hlc: at('a', 4),
          bottleId: 'b1',
          volume: ml(100),
        ),
      ]);

      final bottle = ledger.bottle('b1')!;
      expect(bottle.recounts, 1);
      expect(bottle.remaining, ml(200));
      expect(bottle.added, ml(1000), reason: 'what went in is still a fact');
    });

    test('folds in clock order, not arrival order, when a recount is involved', () {
      final events = [
        StockEvents.bottleAdded(
          hlc: at('a', 1),
          bottleId: 'b1',
          sku: 'x',
          volume: ml(1000),
        ),
        StockEvents.bottleRecounted(
          hlc: at('a', 2),
          bottleId: 'b1',
          volume: ml(300),
        ),
        StockEvents.bottleConsumed(
          hlc: at('a', 3),
          bottleId: 'b1',
          volume: ml(100),
        ),
      ];

      // The same three events, shuffled. Clock order has to win.
      final straight = StockLedger.of(events);
      final shuffled = StockLedger.of([events[2], events[0], events[1]]);

      expect(straight.bottle('b1')!.remaining, ml(200));
      expect(shuffled.bottle('b1')!.remaining, ml(200));
    });

    test('applies each clock reading once, however many times it is sent', () {
      // Sync sends "everything you are missing". A device that is missing a
      // stretch rather than a single event will happily send one twice.
      final added = StockEvents.bottleAdded(
        hlc: at('a', 1),
        bottleId: 'b1',
        sku: 'x',
        volume: ml(700),
      );
      final pour = StockEvents.bottleConsumed(
        hlc: at('a', 2),
        bottleId: 'b1',
        volume: ml(100),
      );

      final ledger = StockLedger.of([added, pour, pour, added, pour]);
      expect(ledger.bottle('b1')!.remaining, ml(600));
      expect(ledger.appliedEvents, 2);
    });
  });

  group('anomalies are surfaced, not swallowed', () {
    test('a pour against a bottle that was never added', () {
      final ledger = StockLedger.of([
        StockEvents.bottleConsumed(
          hlc: at('a', 1),
          bottleId: 'ghost',
          volume: ml(50),
        ),
      ]);
      expect(ledger.bottleCount, 0);
      expect(ledger.unknownBottles, hasLength(1));
      expect(ledger.unknownBottles.single.bottleId, 'ghost');
    });

    test('a second add for a bottle id that already exists', () {
      // Two devices both recording the same purchase. Applying it would invent
      // stock that is not on the shelf.
      final ledger = StockLedger.of([
        StockEvents.bottleAdded(
          hlc: at('laptop', 1),
          bottleId: 'b1',
          sku: 'x',
          volume: ml(700),
        ),
        StockEvents.bottleAdded(
          hlc: at('phone', 5),
          bottleId: 'b1',
          sku: 'x',
          volume: ml(700),
        ),
      ]);
      expect(ledger.bottle('b1')!.remaining, ml(700));
      expect(ledger.duplicateAdds, hasLength(1));
    });

    test('an event from a newer build is kept out of the way, not misread', () {
      final ledger = StockLedger.of([
        StockEvents.bottleAdded(
          hlc: at('a', 1),
          bottleId: 'b1',
          sku: 'x',
          volume: ml(700),
        ),
        Event(hlc: at('a', 2), type: 'cellar.hologram', data: {'w': 42}),
      ]);
      expect(ledger.appliedEvents, 1);
      expect(ledger.ignoredEvents, 1);
      expect(ledger.bottle('b1')!.remaining, ml(700));
    });

    test('a bottle that has been emptied past full is flagged, not clamped', () {
      final ledger = StockLedger.of([
        StockEvents.bottleAdded(
          hlc: at('a', 1),
          bottleId: 'b1',
          sku: 'x',
          volume: ml(700),
        ),
        StockEvents.bottleConsumed(
          hlc: at('a', 2),
          bottleId: 'b1',
          volume: ml(800),
        ),
      ]);
      final bottle = ledger.bottle('b1')!;
      expect(bottle.remaining, ml(-100));
      expect(bottle.isOverdrawn, isTrue);
    });
  });

  group('per-sku totals', () {
    final events = [
      StockEvents.bottleAdded(
        hlc: at('a', 1),
        bottleId: 'gin1',
        sku: 'gin',
        volume: ml(700),
      ),
      StockEvents.bottleAdded(
        hlc: at('a', 2),
        bottleId: 'gin2',
        sku: 'gin',
        volume: ml(700),
      ),
      StockEvents.bottleAdded(
        hlc: at('a', 3),
        bottleId: 'rye1',
        sku: 'rye',
        volume: ml(700),
      ),
      StockEvents.bottleConsumed(
        hlc: at('a', 4),
        bottleId: 'gin1',
        volume: ml(200),
      ),
    ];

    test('sums across every bottle of the sku', () {
      final ledger = StockLedger.of(events);
      expect(ledger.remainingOf('gin'), ml(1200));
      expect(ledger.remainingOf('rye'), ml(700));
      expect(ledger.remainingOf('absent'), Volume.zero);
      expect(ledger.remainingTotal, ml(1900));
    });

    test('lists distinct skus only', () {
      final ledger = StockLedger.of(events);
      expect(ledger.skus.toSet(), {'gin', 'rye'});
    });

    test('a finished bottle is not an open bottle', () {
      final ledger = StockLedger.of([
        ...events,
        StockEvents.bottleConsumed(
          hlc: at('a', 5),
          bottleId: 'rye1',
          volume: ml(700),
        ),
      ]);
      expect(ledger.bottleCount, 3);
      expect(ledger.openBottles.map((b) => b.bottleId).toSet(), {'gin1', 'gin2'});
    });
  });

  group('a line that should never have been written can be retracted', () {
    // **The verb the shelf had no door for.** `BottleRecounted`, `BottleDiscarded` and this one all
    // existed as operations the fold reduced and as events nothing wrote; this is the one that says
    // a line was a mistake rather than that a bottle changed.
    test('a retracted bottle leaves the shelf entirely', () {
      final ledger = StockLedger.of([
        StockEvents.bottleAdded(hlc: at('a', 1), bottleId: 'typo', sku: 'gin', volume: ml(700)),
        StockEvents.bottleAdded(hlc: at('a', 2), bottleId: 'real', sku: 'rye', volume: ml(750)),
        StockEvents.bottleRemoved(hlc: at('a', 3), bottleId: 'typo'),
      ]);

      expect(ledger.bottle('typo'), isNull);
      expect(ledger.bottleCount, 1);
      expect(ledger.remainingTotal, ml(750),
          reason: 'the retracted bottle contributed no volume before or after');
      expect(ledger.removedBottleIds, {'typo'});
      expect(ledger.unknownBottles, isEmpty,
          reason: 'retracting a bottle that exists is a success, not an orphaned operation');
    });

    test('the clock decides, not the order the events arrive in', () {
      // **Both events stay, and the order that matters is the clock's.** The log is append-only, so
      // a correction is a later event rather than a rewrite of an earlier one, and the fold sorts by
      // HLC before it reduces anything.
      //
      // **My first version of this test asserted the opposite and was wrong twice.** It claimed that
      // folding `[removed, added]` would leave the bottle standing, on the reasoning that a second
      // device might send the pair the other way round -- but the list order is ignored on purpose,
      // and in that fixture the removal was the later event, so it won either way. The assertions
      // below are the version that says what the fold actually does.
      final add = StockEvents.bottleAdded(
        hlc: at('a', 5),
        bottleId: 'typo',
        sku: 'gin',
        volume: ml(700),
      );

      // A removal earlier on the clock: the entry stands, in either list order.
      final early = StockEvents.bottleRemoved(hlc: at('a', 2), bottleId: 'typo');
      expect(StockLedger.of([add, early]).bottleCount, 1);
      expect(StockLedger.of([early, add]).bottleCount, 1);

      // A removal later on the clock: the retraction wins, in either list order.
      final late = StockEvents.bottleRemoved(hlc: at('a', 9), bottleId: 'typo');
      expect(StockLedger.of([add, late]).bottleCount, 0);
      expect(StockLedger.of([late, add]).bottleCount, 0);
    });

    test('a removal carries no volume, and the parser does not demand one', () {
      // Reading `volumeMicrolitres` was `tryParse`'s second line and a requirement, because every
      // other stock op carries an amount. A retraction has nothing to put there, so a parser that
      // required it would drop every removal silently and the bottle would come back on the fold.
      final event = StockEvents.bottleRemoved(hlc: at('a', 1), bottleId: 'b1');
      expect(event.data.containsKey('volumeMicrolitres'), isFalse);

      final op = StockOp.tryParse(event);
      expect(op, isA<BottleRemoved>());
      expect((op! as BottleRemoved).bottleId, 'b1');
    });

    test('retracting a bottle that was never added is surfaced', () {
      // The same rule the ledger applies to every other operation naming a bottle it has not seen:
      // either the log is missing an event and a sync will fix it, or something wrote nonsense.
      final ledger = StockLedger.of([
        StockEvents.bottleRemoved(hlc: at('a', 1), bottleId: 'ghost'),
      ]);

      expect(ledger.bottleCount, 0);
      expect(ledger.unknownBottles.single, isA<BottleRemoved>());
      expect(ledger.removedBottleIds, {'ghost'},
          reason: 'the price fold is told about it either way -- there is nothing to keep');
    });

    test('a retracted bottle takes its price with it', () {
      // **The two folds have to agree**, and they read different things: the shelf is built from
      // operations in clock order, the price series walks events and knows nothing about the ledger.
      // Without the removed set the chart would keep a purchase that no longer exists, which is
      // worse than an empty chart because it looks like data.
      final events = <Event>[
        StockEvents.bottleAdded(
          hlc: at('a', 1),
          bottleId: 'typo',
          sku: 'gin',
          volume: ml(700),
          priceMinor: 12000,
          currency: 'CNY',
        ),
        StockEvents.bottleRemoved(hlc: at('a', 2), bottleId: 'typo'),
      ];

      final ledger = StockLedger.of(events);
      expect(pricePointsOf(events, removedBottles: ledger.removedBottleIds), isEmpty);
      expect(pricePointsOf(events), hasLength(1),
          reason: 'and without being told, the fold keeps it -- which is why the caller passes it');
    });
  });

  test('an empty log is an empty cellar', () {
    final ledger = StockLedger.of(const []);
    expect(ledger.bottleCount, 0);
    expect(ledger.remainingTotal, Volume.zero);
    expect(ledger.unknownBottles, isEmpty);
  });
}
