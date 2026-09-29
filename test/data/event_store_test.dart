import 'dart:io';

import 'package:hollow_court/data/event_store.dart';
import 'package:hollow_court/domain/events/event.dart';
import 'package:hollow_court/domain/events/hlc.dart';
import 'package:hollow_court/domain/events/stock.dart';
import 'package:hollow_court/domain/units/quantity.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late File file;
  late EventStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('hollow_court_log');
    file = File('${dir.path}${Platform.pathSeparator}events.ndjson');
    store = EventStore(file);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Event added(String bottleId, int millis) => StockEvents.bottleAdded(
    hlc: Hlc(physicalMillis: millis, counter: 0, nodeId: 'a'),
    bottleId: bottleId,
    sku: 'gin',
    volume: Volume.fromMillilitres(700),
  );

  group('append and read', () {
    test('a log that does not exist yet reads as empty, not as an error', () {
      expect(file.existsSync(), isFalse);
      return store.read().then((result) {
        expect(result.events, isEmpty);
        expect(result.defects, isEmpty);
      });
    });

    test('round-trips events', () async {
      await store.append([added('b1', 1), added('b2', 2)]);
      final result = await store.read();

      expect(result.events, hasLength(2));
      expect(result.defects, isEmpty);
      expect(result.events.map((e) => e.data['bottleId']), ['b1', 'b2']);
    });

    test('writes one line per event, each newline-terminated', () async {
      await store.append([added('b1', 1), added('b2', 2)]);
      final raw = await file.readAsString();

      expect(raw.endsWith('\n'), isTrue, reason: 'a clean end is what tells a reader nothing was torn');
      expect(raw.trim().split('\n'), hasLength(2));
    });

    test('appending twice extends the log rather than replacing it', () async {
      await store.append([added('b1', 1)]);
      await store.append([added('b2', 2)]);
      expect((await store.read()).events, hasLength(2));
    });

    test('appending nothing leaves the file untouched', () async {
      await store.append([added('b1', 1)]);
      final before = await file.length();
      await store.append(const []);
      expect(await file.length(), before);
    });

    test('creates missing parent directories', () async {
      final nested = File(
        '${dir.path}${Platform.pathSeparator}deep${Platform.pathSeparator}deeper'
        '${Platform.pathSeparator}events.ndjson',
      );
      await EventStore(nested).append([added('b1', 1)]);
      expect(nested.existsSync(), isTrue);
    });
  });

  group('a crash during an append', () {
    /// Simulates a process that died mid-write by cutting the file short.
    Future<void> tearLastLine() async {
      final raw = await file.readAsString();
      final lines = raw.split('\n')..removeLast(); // drop the empty tail
      final last = lines.removeLast();
      await file.writeAsString('${lines.join('\n')}\n${last.substring(0, last.length ~/ 2)}');
    }

    test('a half-written last line is recognised as a torn tail', () async {
      await store.append([added('b1', 1), added('b2', 2)]);
      await tearLastLine();

      final result = await store.read();
      expect(result.events, hasLength(1), reason: 'the complete line survives');
      expect(result.defects, hasLength(1));
      expect(result.defects.single.kind, LogDefectKind.tornTail);
      expect(result.hasCorruption, isFalse,
          reason: 'a lost append is not corruption');
    });

    test('the next append replaces the torn line instead of fusing with it', () async {
      await store.append([added('b1', 1), added('b2', 2)]);
      await tearLastLine();

      // Without the trim, the fragment would join the new line and destroy an
      // event that was otherwise fine.
      await store.append([added('b3', 3)]);

      final result = await store.read();
      expect(result.defects, isEmpty);
      expect(
        result.events.map((e) => e.data['bottleId']),
        ['b1', 'b3'],
        reason: 'b2 was lost with the crash; b1 and b3 are intact',
      );
    });
  });

  group('damage in the middle of the log', () {
    test('an unreadable complete line is corruption, not a torn tail', () async {
      await store.append([added('b1', 1), added('b2', 2)]);
      final raw = await file.readAsString();
      final lines = raw.trim().split('\n');
      // Keep the newline: the line is complete, it just is not an event.
      await file.writeAsString('${lines[0]}\n{"broken":\n${lines[1]}\n');

      final result = await store.read();
      expect(result.events, hasLength(2));
      expect(result.defects, hasLength(1));
      expect(result.defects.single.kind, LogDefectKind.unreadable);
      expect(result.defects.single.lineNumber, 2);
      expect(result.hasCorruption, isTrue);
    });

    test('one bad line does not cost the rest of the log', () async {
      await store.append([added('b1', 1), added('b2', 2), added('b3', 3)]);
      final lines = (await file.readAsString()).trim().split('\n');
      lines[1] = 'garbage';
      await file.writeAsString('${lines.join('\n')}\n');

      final result = await store.read();
      expect(result.events.map((e) => e.data['bottleId']), ['b1', 'b3']);
      expect(result.corruptions, hasLength(1));
    });

    test('blank lines are skipped without complaint', () async {
      await store.append([added('b1', 1)]);
      await file.writeAsString('\n\n${await file.readAsString()}\n\n');
      final result = await store.read();
      expect(result.events, hasLength(1));
      expect(result.defects, isEmpty);
    });
  });

  group('since', () {
    test('returns only what a peer that stopped at the given clock is missing', () async {
      await store.append([added('b1', 1), added('b2', 2), added('b3', 3)]);

      final missing = await store.since(
        Hlc(physicalMillis: 1, counter: 0, nodeId: 'a'),
      );
      expect(missing.map((e) => e.data['bottleId']), ['b2', 'b3']);
    });

    test('a peer that is fully up to date gets nothing', () async {
      await store.append([added('b1', 1), added('b2', 2)]);
      final missing = await store.since(
        Hlc(physicalMillis: 2, counter: 0, nodeId: 'a'),
      );
      expect(missing, isEmpty);
    });
  });

  test('the log is a file a human can read', () async {
    await store.append([added('b1', 1)]);
    final line = (await file.readAsString()).trim();
    expect(line, startsWith('{"hlc":'));
    expect(line, contains('"type":"stock.bottle.added"'));
    expect(line, contains('"volumeMicrolitres":700000'));
  });
}
