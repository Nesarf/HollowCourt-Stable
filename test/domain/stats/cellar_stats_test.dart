import 'package:hollow_court/domain/events/event.dart';
import 'package:hollow_court/domain/events/hlc.dart';
import 'package:hollow_court/domain/events/stock.dart';
import 'package:hollow_court/domain/stats/cellar_stats.dart';
import 'package:hollow_court/domain/units/quantity.dart';
import 'package:test/test.dart';

Hlc at(int millis) => Hlc(physicalMillis: millis, counter: 0, nodeId: 'test');

Volume ml(num millilitres) => Volume.fromMicrolitres((millilitres * 1000).round());

final List<Event> _log = [];

/// Adds a bottle and returns its id, so a test can pour from it.
String add(String sku, num millilitres, {String? id}) {
  final bottleId = id ?? 'b${_log.length}';
  _log.add(
    StockEvents.bottleAdded(
      hlc: at(_log.length + 1),
      bottleId: bottleId,
      sku: sku,
      volume: ml(millilitres),
    ),
  );
  return bottleId;
}

void pour(String bottleId, num millilitres) => _log.add(
  StockEvents.bottleConsumed(
    hlc: at(_log.length + 1),
    bottleId: bottleId,
    volume: ml(millilitres),
  ),
);

void discard(String bottleId, num millilitres) => _log.add(
  StockEvents.bottleDiscarded(
    hlc: at(_log.length + 1),
    bottleId: bottleId,
    volume: ml(millilitres),
  ),
);

CellarStats stats() =>
    CellarStats.of(stock: StockLedger.of(_log), events: _log);

void main() {
  // Inside `main`, and not beside the helpers: Dart allows only declarations at the top
  // level, so a bare `setUp(...)` there is parsed as a function declaration and fails with
  // a complaint about the argument list.
  setUp(() => _log.clear());

  group('the counts come from the ledger and not from a second fold', () {
    test('bottles, standing, empty and overdrawn are four different numbers', () {
      final gin = add('gin', 700);
      add('rum', 700);
      final finished = add('vodka', 700);
      pour(finished, 700);
      final over = add('whisky', 500);
      pour(over, 800);

      final s = stats();

      expect(s.bottles, 4);
      expect(s.standing, 3, reason: 'vodka is finished, so it is not standing');
      expect(s.emptyBottles, 1);
      expect(
        s.overdrawn,
        1,
        reason: 'a bottle emptier than it was ever full is a defect, not a finish',
      );
      expect(gin, isNotEmpty);
    });

    test('a sku nobody can pour from is not a sku the shelf holds', () {
      add('gin', 700);
      final finished = add('gin', 700);
      pour(finished, 700);
      add('rum', 700);

      final s = stats();

      expect(s.bottles, 3);
      expect(
        s.distinctSkus,
        2,
        reason: 'the second gin is empty, and an empty bottle holds nothing',
      );
    });

    test('what is on hand is the sum of what is standing, split by sku', () {
      final a = add('gin', 700);
      add('rum', 750);
      pour(a, 100);

      final s = stats();

      expect(s.onHand, ml(1350));
      expect(s.onHandBySku['gin'], ml(600));
      expect(s.onHandBySku['rum'], ml(750));
    });
  });

  group('the history is the curve’s answer, not a second sum', () {
    test('drunk, discarded and the pour count are over the whole log', () {
      final gin = add('gin', 700);
      pour(gin, 45);
      pour(gin, 45);
      discard(gin, 100);

      final s = stats();

      expect(s.drunk, ml(90));
      expect(s.discarded, ml(100));
      expect(s.pours, 2, reason: 'a discard is not a pour');
      // And not added together anywhere: the two columns exist because a broken bottle is
      // not a busy evening.
      expect(s.drunk, isNot(s.discarded));
    });

    test('the most-poured sku is the top by volume, and ties break by name', () {
      // The tie-break is the part worth testing: without it the answer would come from
      // map iteration order, which is stable for one run and not a promise -- the same
      // rule `ShelfLayout.onShelf` applies to two bottles in one place.
      final gin = add('gin', 700);
      final rum = add('rum', 700);
      pour(gin, 50);
      pour(rum, 50);

      expect(stats().mostPouredSku, 'gin', reason: 'gin sorts before rum');
    });

    test('nothing poured means no most-poured sku, and not an empty name', () {
      add('gin', 700);

      final s = stats();

      expect(s.mostPouredSku, isNull);
      expect(s.mostPoured, Volume.zero);
    });

    test('a pour from a bottle the ledger does not hold is not attributed', () {
      // Rather than attributed to a made-up sku. It is the same gap `ConsumptionCurve`
      // reports as an ignored event: the pour happened but nothing here can name what it
      // came out of.
      add('gin', 700);
      pour('a-bottle-that-is-not-in-the-log', 45);

      final s = stats();

      expect(s.drunk, ml(45), reason: 'the volume is still drunk');
      expect(s.mostPouredSku, isNull, reason: 'but no sku can be credited with it');
    });
  });

  group('an empty cellar and a bare shelf are different readings', () {
    test('a log with nothing in it is empty and bare', () {
      final s = stats();

      expect(s.isEmpty, isTrue);
      expect(s.isBare, isTrue);
      expect(s.bottles, 0);
      expect(s.onHand, Volume.zero);
      expect(s.mostPouredSku, isNull);
    });

    test('a shelf that has been drunk dry is bare and not empty', () {
      // The distinction the whole screen turns on: a cellar with a history and nothing left
      // is a different thing from a cellar nobody has used, and a screen that reported one
      // for the other would be lying about which.
      final gin = add('gin', 700);
      pour(gin, 700);

      final s = stats();

      expect(s.isEmpty, isFalse);
      expect(s.isBare, isTrue);
      expect(s.drunk, ml(700));
      expect(s.mostPouredSku, 'gin');
    });
  });
}
