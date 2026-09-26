import 'dart:io';

import 'package:hollow_court/data/event_log.dart';
import 'package:hollow_court/domain/events/event.dart';
import 'package:hollow_court/domain/events/stock.dart';
import 'package:hollow_court/domain/units/quantity.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('hollow_court_log'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  File fileFor(String name) =>
      File('${dir.path}${Platform.pathSeparator}$name.ndjson');

  /// Opens a device whose wall clock starts at [startMillis].
  Future<EventLog> device(String name, {int startMillis = 1000}) {
    var now = startMillis;
    return EventLog.open(
      file: fileFor(name),
      nodeId: name,
      nowMillis: () => now,
    );
  }

  StockLedger stockOf(EventLog log) => log.stock;

  Future<Event> addBottle(EventLog log, {int millilitres = 1000}) => log.record(
    (hlc) => StockEvents.bottleAdded(
      hlc: hlc,
      bottleId: 'b1',
      sku: 'gin',
      volume: Volume.fromMillilitres(millilitres),
    ),
  );

  Future<void> pour(EventLog log, int millilitres) => log.record(
    (hlc) => StockEvents.bottleConsumed(
      hlc: hlc,
      bottleId: 'b1',
      volume: Volume.fromMillilitres(millilitres),
    ),
  );

  group('opening', () {
    test('a cellar that has never been opened is empty', () async {
      final log = await device('a');
      expect(log.events, isEmpty);
      expect(log.latest, isNull);
      expect(log.openReport.events, 0);
      expect(log.openReport.duplicates, 0);
      expect(log.openReport.defects, isEmpty);
    });

    test('records, and the state is whatever the operations add up to', () async {
      final log = await device('a');
      await addBottle(log);
      await pour(log, 250);

      expect(log.events, hasLength(2));
      expect(stockOf(log).bottle('b1')!.remaining, Volume.fromMillilitres(750));
    });

    test('reopening restores the same cellar', () async {
      final first = await device('a');
      await addBottle(first);
      await pour(first, 250);

      final second = await device('a');
      expect(second.events, hasLength(2));
      expect(stockOf(second).bottle('b1')!.remaining, Volume.fromMillilitres(750));
    });

    test('the clock resumes past everything already in the log', () async {
      final first = await device('a', startMillis: 5_000_000);
      await addBottle(first);

      // Same device, but its wall clock has been moved backwards since -- a
      // wrong timezone, a corrected clock, a dead CMOS battery.
      final second = await EventLog.open(
        file: fileFor('a'),
        nodeId: 'a',
        nowMillis: () => 1000,
      );
      final next = second.clock.next();

      expect(
        next > first.events.single.hlc,
        isTrue,
        reason: 'a new local event must not look older than one already written',
      );
    });

    test('a reading written twice is reported and kept once', () async {
      final log = await device('a');
      final event = await addBottle(log);

      // Simulate a buggy writer, or a hand-edit.
      final store = EventStoreAdapter(fileFor('a'));
      await store.appendAgain(event);

      final reopened = await device('a');
      expect(reopened.events, hasLength(1));
      expect(reopened.openReport.duplicates, 1);
    });
  });

  group('two devices', () {
    test('each pours while apart, and the merge sums both', () async {
      // The case section 6 is written about. Both devices hold the same bottle;
      // each pours a drink without hearing about the other; then they meet.
      // Last-write-wins would keep one pour and lose the other.
      final a = await device('a', startMillis: 1000);
      await addBottle(a);

      // B starts from a copy of A's log -- the state after their last sync.
      File(fileFor('b').path).writeAsStringSync(
        File(fileFor('a').path).readAsStringSync(),
      );
      final b = await device('b', startMillis: 1000);
      expect(stockOf(b).bottle('b1')!.remaining, Volume.fromMillilitres(1000));

      await pour(a, 400);
      await pour(b, 200);

      // They meet, in both directions.
      await a.merge(b.events);
      await b.merge(a.events);

      expect(stockOf(a).bottle('b1')!.remaining, Volume.fromMillilitres(400));
      expect(stockOf(b).bottle('b1')!.remaining, Volume.fromMillilitres(400));
      expect(stockOf(a).bottle('b1')!.consumed, Volume.fromMillilitres(600));
    });

    test('a merge writes only what was missing', () async {
      final a = await device('a');
      await addBottle(a);
      final b = await device('b');
      await b.merge(a.events);

      final fresh = await b.merge(a.events);
      expect(fresh, isEmpty, reason: 'a second handshake must not grow the file');

      final before = fileFor('b').lengthSync();
      await b.merge(a.events);
      expect(fileFor('b').lengthSync(), before);
    });

    test('a merge is idempotent however many times it runs', () async {
      final a = await device('a');
      await addBottle(a);
      await pour(a, 100);

      final b = await device('b');
      for (var i = 0; i < 5; i++) {
        await b.merge(a.events);
      }
      expect(b.events, hasLength(2));
      expect(stockOf(b).bottle('b1')!.remaining, Volume.fromMillilitres(900));
    });

    test('a peer ahead pulls the local clock forward', () async {
      final a = await device('a', startMillis: 1000);
      await addBottle(a);

      // B's clock is far ahead of A's.
      final b = await device('b', startMillis: 9_000_000);
      await addBottle(b);
      await pour(b, 100);

      await a.merge(b.events);
      final local = a.clock.next();

      expect(
        local > b.events.last.hlc,
        isTrue,
        reason: 'after hearing a peer, a local event must sort after it',
      );
    });

    test('missingFrom is the exact complement of what a peer holds', () async {
      final a = await device('a');
      await addBottle(a);
      final snapshot = a.clocks;

      await pour(a, 100);
      await pour(a, 100);

      final missing = a.missingFrom(snapshot);
      expect(missing, hasLength(2));
      expect(a.missingFrom(a.clocks), isEmpty);
    });

    test('a three-way sync converges on the same cellar', () async {
      final a = await device('a', startMillis: 1000);
      await addBottle(a);

      final b = await device('b', startMillis: 1000);
      await b.merge(a.events);
      final c = await device('c', startMillis: 1000);
      await c.merge(a.events);

      await pour(a, 100);
      await pour(b, 200);
      await pour(c, 300);

      // Everyone tells everyone, twice, in an arbitrary order.
      for (final log in [a, b, c]) {
        for (final other in [a, b, c]) {
          if (!identical(log, other)) await log.merge(other.events);
        }
      }
      for (final log in [a, b, c]) {
        for (final other in [a, b, c]) {
          if (!identical(log, other)) await log.merge(other.events);
        }
      }

      for (final log in [a, b, c]) {
        expect(log.events, hasLength(4), reason: 'one add and three pours');
        expect(
          stockOf(log).bottle('b1')!.remaining,
          Volume.fromMillilitres(400),
        );
      }
    });
  });

  group('the handshake digest, which decides whether to sync at all', () {
    test('two logs holding the same events agree, whatever order they arrived', () async {
      // The property the handshake rests on. `b` receives `a`'s events in reverse, so the two
      // logs hold the same readings and did not arrive that way -- which is the whole reason
      // the digest hashes a SORTED list.
      final a = await device('laptop');
      final b = await device('phone');

      await addBottle(a);
      await pour(a, 50);
      await b.merge(a.events.reversed);

      expect(b.digest.likelyInSyncWith(a.digest), isTrue);
      expect(b.digest.count, a.digest.count);
    });

    test('a log that is behind does not claim to agree', () async {
      final a = await device('laptop');
      final b = await device('phone');

      await addBottle(a);
      await pour(a, 50);
      await b.merge([a.events.first]);

      expect(b.digest.likelyInSyncWith(a.digest), isFalse);
    });

    test('a fresh log has an empty digest, and two of them agree', () async {
      final a = await device('laptop');
      final b = await device('phone');

      expect(a.digest.isEmpty, isTrue);
      expect(a.digest.likelyInSyncWith(b.digest), isTrue);
    });
  });
}

/// A thin helper so a test can append a duplicate without going through the
/// log, which would refuse to write one.
final class EventStoreAdapter {
  EventStoreAdapter(this.file);
  final File file;

  Future<void> appendAgain(dynamic event) async {
    final sink = file.openWrite(mode: FileMode.append);
    try {
      sink.writeln(event.encode());
      await sink.flush();
    } finally {
      await sink.close();
    }
  }
}
