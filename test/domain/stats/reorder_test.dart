import 'package:flutter_test/flutter_test.dart';

import 'package:hollow_court/domain/events/event.dart';
import 'package:hollow_court/domain/events/hlc.dart';
import 'package:hollow_court/domain/events/stock.dart';
import 'package:hollow_court/domain/stats/reorder.dart';
import 'package:hollow_court/domain/units/quantity.dart';

/// **What is worth buying again** -- stage ④ of `docs/catalogue-and-stock.md`, as arithmetic.
///
/// The thing being held to here is that three signals are combined and that each of them catches a case the others
/// miss. A test that only checked "a nearly empty bottle is listed" would pass with one rule and no combination at
/// all, so every case below is built to be reachable by exactly one of them.
void main() {
  Hlc at(int millis) => Hlc(physicalMillis: millis, counter: 0, nodeId: 'test');

  const day = 86400000;

  /// **[millis] is not decoration.** Two helper-built events carrying the same `Hlc` are the same event as far as
  /// any device can tell, so a fixture that adds three bottles at `at(1)` folds to **one** bottle -- the trap
  /// `cellar_page_test` and `shelf_test` each record, and it cost this file a failing assertion about ordering that
  /// looked like a sort bug.
  Event added(String bottleId, String sku, int millilitres, {int millis = 1}) => StockEvents.bottleAdded(
    hlc: at(millis),
    bottleId: bottleId,
    sku: sku,
    volume: Volume.fromMillilitres(millilitres),
  );

  Event poured(String bottleId, int millilitres, int millis) => StockEvents.bottleConsumed(
    hlc: at(millis),
    bottleId: bottleId,
    volume: Volume.fromMillilitres(millilitres),
  );

  StockLedger ledgerOf(List<Event> events) => StockLedger.of(events);

  ReorderList listOf(List<Event> events, {ReorderPoint? point}) => ReorderList.of(
    stock: ledgerOf(events),
    events: events,
    thresholds: point ?? ReorderPoint.defaults,
  );

  group('the three signals, one at a time', () {
    test('**the fraction alone lists a bottle that is nearly empty**', () {
      // 700 ml in, 630 poured away: a tenth left, which is under the default fifth. The remainder is 70 ml, which is
      // under the default 100 -- so this case is caught by *both* and is not the isolated one. The next test is.
      final list = listOf([added('b1', 'gin', 700), poured('b1', 630, day)]);

      expect(list.entries, hasLength(1));
      expect(list.entries.single.reasons, contains(LowReason.nearlyEmpty));
    });

    test('**the remainder alone lists a big bottle with a small amount left**', () {
      // A litre at 8%: 80 ml left. The fraction rule also fires, so this isolates the *remainder* by asking for the
      // one thing the fraction cannot say -- that 80 ml is under the absolute floor whatever the bottle held.
      final list = listOf([added('b1', 'vermouth', 1000), poured('b1', 920, day)]);

      expect(list.entries.single.reasons, contains(LowReason.smallRemainder));
    });

    test('**the fraction alone catches what the remainder cannot: a small bottle at a quarter**', () {
      // 200 ml in, 150 poured: 50 ml left. That is under 100 ml, so both fire -- which is the point of the pair
      // rather than a problem: the two rules are meant to overlap, and what matters is that neither is a subset.
      // This case is the one the *remainder* misses when the numbers move: see the next test.
      // 200 ml in, 165 poured: 35 ml left, which is 17.5% and under the default fifth *and* under 100 ml. **The
      // first version of this test poured 150 and claimed both fired** -- 50 ml of 200 is a quarter, and a quarter is
      // above the 20% the defaults ask for. The arithmetic was mine and the fold was right.
      final list = listOf([added('b1', 'bitters', 200), poured('b1', 165, day)]);

      expect(list.entries.single.reasons, containsAll([LowReason.nearlyEmpty, LowReason.smallRemainder]));
    });

    test('**and the remainder alone catches what the fraction cannot: plenty left, in a small bottle**', () {
      // 150 ml in, 60 poured: 90 ml left, which is 60% of the bottle and completely healthy by the fraction rule --
      // and under 100 ml, so a reader about to make the one drink it is for wants to know. **This is the case that
      // proves neither rule subsumes the other**, and it is the one the design note means by "half".
      final list = listOf([added('b1', 'bitters', 150), poured('b1', 60, day)]);

      expect(list.entries, hasLength(1));
      expect(list.entries.single.reasons, {LowReason.smallRemainder});
      expect(list.entries.single.fraction, closeTo(0.6, 0.001));
    });

    test('**the horizon alone lists a bottle that is still mostly full**', () {
      // A litre, half gone over ten days: 500 ml left, which is 50% and nowhere near the floor of 100 ml. At that
      // speed it runs out in ten more days, which is inside the default thirty.
      // **Two pours, because one is not a speed** -- and the first version of this test wrote one, so the horizon
      // rule correctly refused to fire and the test failed for the reason the rule exists. 250 ml on day one and
      // 250 ml on day ten: 500 ml drunk over nine days, and the 500 ml left lasts nine more.
      final list = listOf([
        added('b1', 'gin', 1000),
        poured('b1', 250, day),
        poured('b1', 250, day * 10),
      ]);

      expect(list.entries, hasLength(1));
      final entry = list.entries.single;
      expect(entry.reasons, {LowReason.runningOutSoon});
      expect(entry.lastsFor, isNotNull);
      expect(entry.lastsFor!.inDays, closeTo(9, 1));
    });

    test('a healthy bottle is not listed at all', () {
      final list = listOf([added('b1', 'gin', 1000), poured('b1', 100, day)]);

      expect(list.isEmpty, isTrue);
    });

    test('**a finished bottle is listed, because zero is under every threshold there is**', () {
      final list = listOf([added('b1', 'gin', 700), poured('b1', 700, day)]);

      expect(list.entries.single.remaining.microlitres, 0);
      expect(list.entries.single.reasons, contains(LowReason.nearlyEmpty));
    });
  });

  group('the speed, and when it refuses to speak', () {
    test('**one pour is not a speed**', () {
      // The log was 1.6 KB after three weeks when this was written. A rate fitted to a single pour is a number rather
      // than evidence, and the horizon rule must simply not fire.
      final history = PourHistory.of([added('b1', 'gin', 1000), poured('b1', 400, day * 5)]);

      expect(history.of('b1').count, 1);
      expect(history.of('b1').lastsFor(600000), isNull);
    });

    test('**two pours in the same minute are not a speed either**', () {
      // Under a day apart, the speed is an artefact of two events landing together -- and it comes out enormous,
      // which would fire the horizon rule on every bottle a reader pours twice while unpacking their shopping.
      final history = PourHistory.of([
        added('b1', 'gin', 1000),
        poured('b1', 100, day),
        poured('b1', 100, day + 60000),
      ]);

      expect(history.of('b1').count, 2);
      expect(history.of('b1').lastsFor(800000), isNull);
    });

    test('a bottle nobody has poured from has no history, and that is not an error', () {
      final history = PourHistory.of([added('b1', 'gin', 1000)]);

      expect(history.of('b1').count, 0);
      expect(history.of('b1').lastsFor(1000000), isNull);
      expect(history.of('nobody').count, 0);
    });

    test('**a discard is not evidence about how fast somebody drinks**', () {
      // Watering a plant with the last of the vermouth is not drinking it. Counting it would make the bottle look
      // like it was going faster exactly when it was thrown away.
      final thrown = StockEvents.bottleDiscarded(
        hlc: at(day * 5),
        bottleId: 'b1',
        volume: Volume.fromMillilitres(400),
      );
      final history = PourHistory.of([added('b1', 'gin', 1000), thrown]);

      expect(history.of('b1').count, 0);
    });

    test('**the pours are read in clock order, not file order**', () {
      // A merged log holds a peer's events interleaved with local ones, and "the first pour" has to mean the same
      // thing on both devices. Fed backwards on purpose.
      final history = PourHistory.of([
        poured('b1', 100, day * 10),
        added('b1', 'gin', 1000),
        poured('b1', 100, day),
      ]);

      expect(history.of('b1').first, at(day));
      expect(history.of('b1').last, at(day * 10));
      expect(history.of('b1').consumedMicrolitres, 200000);
    });
  });

  group('the thresholds are the reader\'s', () {
    test('**a threshold nothing reaches turns its own signal off without turning the others off**', () {
      // The reason there are no switches: a reader who does not want the remainder rule sets it to a millilitre
      // count nothing falls under, and the fraction rule goes on working.
      final events = [added('b1', 'bitters', 150), poured('b1', 60, day)];

      expect(listOf(events).entries, hasLength(1));
      expect(
        listOf(events, point: const ReorderPoint(millilitres: 0)).isEmpty,
        isTrue,
        reason: 'nothing is under zero millilitres, and the fraction here is healthy',
      );
    });

    test('**raising the fraction lists more, and the same bottle is the same bottle**', () {
      final events = [added('b1', 'gin', 1000), poured('b1', 500, day)];

      expect(listOf(events).isEmpty, isTrue, reason: 'half a litre is not low by the defaults');
      final strict = listOf(events, point: const ReorderPoint(fillPercent: 60));
      expect(strict.entries.single.ingredientId, 'gin');
    });

    test('the defaults are the three the design note chose', () {
      expect(ReorderPoint.defaults.fillPercent, 20);
      expect(ReorderPoint.defaults.millilitres, 100);
      expect(ReorderPoint.defaults.horizonDays, 30);
      expect(ReorderPoint.defaults.isDefault, isTrue);
      expect(const ReorderPoint(fillPercent: 25).isDefault, isFalse);
    });

    test('copyWith replaces one and keeps the rest', () {
      final moved = ReorderPoint.defaults.copyWith(horizonDays: 7);
      expect(moved.horizonDays, 7);
      expect(moved.fillPercent, ReorderPoint.defaults.fillPercent);
      expect(moved.millilitres, ReorderPoint.defaults.millilitres);
    });
  });

  group('the list itself', () {
    test('**least left first, so the top of it is what to deal with tonight**', () {
      final list = listOf([
        added('b1', 'gin', 1000, millis: 1),
        added('b2', 'vermouth', 1000, millis: 2),
        added('b3', 'campari', 1000, millis: 3),
        poured('b1', 950, day),
        poured('b2', 830, day + 1),
        poured('b3', 990, day + 2),
      ]);

      expect(
        [for (final entry in list.entries) entry.ingredientId],
        ['campari', 'gin', 'vermouth'],
      );
    });

    test('**an ingredient and a bottle are not the same thing**', () {
      // Two bottles of one thing, and only one of them low: a list keyed by ingredient id would say *the gin is low*
      // while a full bottle stands beside the empty one.
      final list = listOf([
        added('b1', 'gin', 700),
        added('b2', 'gin', 700),
        poured('b1', 690, day),
      ]);

      expect(list.entries, hasLength(1));
      expect(list.entries.single.bottleId, 'b1');
    });

    test('the thresholds the list was built against come back with it', () {
      final point = ReorderPoint.defaults.copyWith(horizonDays: 7);
      expect(listOf(const [], point: point).thresholds, point);
    });
  });
}
