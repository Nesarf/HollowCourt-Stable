import 'dart:io';

import 'package:hollow_court/data/event_store.dart';
import 'package:hollow_court/domain/events/event.dart';
import 'package:hollow_court/domain/events/hlc.dart';
import 'package:hollow_court/domain/events/stock.dart';
import 'package:hollow_court/domain/units/quantity.dart';
import 'package:test/test.dart';

/// **The durability contract, as far as it can be tested from inside the process.**
///
/// `docs/durability.md` states what an append guarantees and what it does not. **What it does not guarantee -- that
/// the bytes reached the platter -- cannot be tested here**, because Dart exposes no `fsync` and a test cannot cut
/// the power. What *can* be tested is the bound the design actually rests on: **an append that returned is in the
/// file, so a restart finds it**, and **a crash mid-append costs at most the tail and never the file**.
///
/// Writing the contract down and then asserting the half of it that is assertable is the point; the other half is
/// stated as a limit in that document rather than left for a reader to assume.
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

    test('**an append that returned is in the file, not in a buffer**', () async {
      // **Half of the durability contract, and the half that is assertable** (`docs/durability.md`). What this can
      // show is that `flush()` really did push the bytes out of Dart: a *second handle* over the same path, which
      // shares no buffer with the appender, sees the line. What it cannot show is that the bytes reached the
      // platter -- Dart exposes no `fsync`, and a test cannot cut the power.
      await store.append([added('b1', 1)]);

      // A fresh read through a different handle, which is what a restart does.
      final reread = await EventStore(file).read();
      expect(reread.events, hasLength(1));
      expect(
        file.readAsStringSync().endsWith('\n'),
        isTrue,
        reason: 'a complete line ends in a newline, which is what tells the next open nothing was torn',
      );
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

  group('**how a log ends decides whether the last line is torn or broken**', () {
    // The reader became a byte stream on 2026-10-01, and the four shapes below are every way a log can end.
    // They exist because the old implementation and the new one had to agree about all four, and because the
    // distinction is the difference between *a write was interrupted* and *a line somebody has to look at* --
    // different causes, and the screen says different things about them.
    //
    // **The judgement is deferred by one line on purpose**: whether an unparseable final line is a torn write or
    // corruption depends on whether the *file* ends with a newline, and that is only known once the stream has
    // ended. An implementation that decided as it went would have to keep the whole file in order to change its
    // mind.
    String lineFor(int i) => Event(
          hlc: Hlc(physicalMillis: 1000 + i, counter: 0, nodeId: 't'),
          type: 'stock.bottle.added',
          data: {'i': i},
        ).encode();

    test('a file that ends with a newline has no torn tail', () async {
      final file = File('${dir.path}/clean.ndjson');
      await file.writeAsString([lineFor(1), lineFor(2), ''].join('\n'));
      final result = await EventStore(file).read();
      expect(result.events, hasLength(2));
      expect(result.defects, isEmpty);
    });

    test('a final line cut mid-write is a torn tail', () async {
      final file = File('${dir.path}/torn.ndjson');
      // No trailing newline, and the last line is half a record: a write that stopped.
      await file.writeAsString('${[lineFor(1), lineFor(2)].join('\n')}\n{"hlc":');
      final result = await EventStore(file).read();
      expect(result.events, hasLength(2));
      expect(result.defects.single.kind, LogDefectKind.tornTail);
    });

    test('garbage in the middle is unreadable, whatever the file does at the end', () async {
      final file = File('${dir.path}/middle.ndjson');
      await file.writeAsString([lineFor(1), '{not json}', lineFor(2), ''].join('\n'));
      final result = await EventStore(file).read();
      expect(result.events, hasLength(2), reason: 'a bad line must not cost the good ones after it');
      expect(result.defects.single.kind, LogDefectKind.unreadable);
      expect(result.defects.single.lineNumber, 2);
    });

    test('**an unparseable last line followed by a newline is not a torn tail**', () async {
      // The case the streaming reader could most easily get wrong, and the reason the judgement is deferred: the
      // line cannot be parsed *and* it is the last one, but the file ended cleanly, so nothing was cut mid-write.
      final file = File('${dir.path}/broken.ndjson');
      await file.writeAsString([lineFor(1), '{broken}', ''].join('\n'));
      final result = await EventStore(file).read();
      expect(result.events, hasLength(1));
      expect(result.defects.single.kind, LogDefectKind.unreadable);
    });
  });
}
