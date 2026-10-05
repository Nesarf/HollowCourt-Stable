import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/data/event_store.dart';
import 'package:hollow_court/domain/events/event.dart';
import 'package:hollow_court/domain/events/hlc.dart';

/// The log file, where it is larger than the window the tail-repair reads.
///
/// **A defect found by review on 2026-10-01, and these are the tests it should have had.** `_startOfTornTail`
/// read from `RandomAccessFile` without seeking, so it examined the file's **first** 64 KiB while computing an
/// offset from the file's **length** -- and `append` then truncated the file to that offset. On a log over 64 KiB
/// with an interrupted write, that deletes everything between the two, silently.
///
/// **Why the existing tests could not see it**: the fault needs a torn tail *and* a file larger than the window.
/// Every test here used a handful of small events, so both conditions were absent. A cellar in use has both the
/// first time a write is interrupted after a few months of use.
///
/// The three cases below are the three that matter, and the third is the one that destroys history.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('event_store_tail');
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  File logFile() => File('${dir.path}/cellar.ndjson');

  /// A real encoded event, so the file holds what the application actually writes.
  String encoded(int i) => Event(
    hlc: Hlc(physicalMillis: 1700000000000 + i, counter: 0, nodeId: 'test'),
    type: 'stock.bottle.added',
    data: {'i': i, 'pad': 'x' * 60},
  ).encode();

  /// Writes [count] whole events, and returns the number of lines written.
  Future<int> seed(File file, int count) async {
    final sink = file.openWrite();
    for (var i = 0; i < count; i++) {
      sink.writeln(encoded(i));
    }
    await sink.flush();
    await sink.close();
    return count;
  }

  test('**a clean log over 64 KiB is left exactly as it was**', () async {
    // The window boundary is where the old code started looking in the wrong place, so a file that crosses it and
    // needs no repair is the first thing to pin down.
    final file = logFile();
    final written = await seed(file, 1200);
    final before = await file.length();
    expect(before, greaterThan(65536), reason: 'the fixture must cross the window to be a test of it');

    final store = EventStore(file);
    await store.append([
      Event(
        hlc: Hlc(physicalMillis: 1800000000000, counter: 0, nodeId: 'test'),
        type: 'stock.bottle.added',
        data: const {'i': 9999},
      ),
    ]);

    final lines = (await file.readAsString()).split('\n').where((l) => l.isNotEmpty).toList();
    expect(lines, hasLength(written + 1), reason: 'a clean file must gain one line and lose none');
    expect(await file.length(), greaterThan(before));
  });

  test('**a torn tail over 64 KiB costs only the torn line**', () async {
    final file = logFile();
    final written = await seed(file, 1200);

    // Tear it: cut into the middle of the final line, the way an interrupted write leaves it.
    final whole = await file.readAsString();
    final torn = whole.substring(0, whole.length - 40);
    await file.writeAsString(torn, flush: true);
    expect(await file.length(), greaterThan(65536));

    final store = EventStore(file);
    await store.append([
      Event(
        hlc: Hlc(physicalMillis: 1800000000001, counter: 0, nodeId: 'test'),
        type: 'stock.bottle.added',
        data: const {'i': 9998},
      ),
    ]);

    final lines = (await file.readAsString()).split('\n').where((l) => l.isNotEmpty).toList();
    // The torn line is gone -- that is the repair working -- and **every whole line before it survives**.
    expect(
      lines,
      hasLength(written),
      reason: 'the torn fragment is replaced by one new line, so the count is the original total: '
          '$written whole events plus the new one minus the torn one. Losing more means the repair '
          'truncated into history, which is the defect this test exists for.',
    );
    expect(lines.last, contains('9998'), reason: 'the newly appended event must be the last line');
  });

  test('**appending after a torn tail keeps the history before it**', () async {
    // **This is the case that destroyed data.** With the read starting at offset 0, the offset handed to
    // `truncate` landed far below the real end -- so this assertion is the one that fails on the old code.
    final file = logFile();
    final written = await seed(file, 1200);
    final whole = await file.readAsString();
    await file.writeAsString(whole.substring(0, whole.length - 40), flush: true);

    final store = EventStore(file);
    await store.append([
      Event(
        hlc: Hlc(physicalMillis: 1800000000002, counter: 0, nodeId: 'test'),
        type: 'stock.bottle.added',
        data: const {'i': 9997},
      ),
    ]);

    final text = await file.readAsString();
    // The first event is the cheapest possible witness that nothing was cut from the beginning.
    expect(
      text,
      contains('"i":0,'),
      reason: 'the first event must still be in the file; its absence means the repair truncated into history',
    );
    expect(text, contains('"i":9997'), reason: 'and the new event must be there');
    final lines = text.split('\n').where((l) => l.isNotEmpty).toList();
    expect(lines, hasLength(written));
  });

  test('a torn tail under the window still behaves as it always did', () async {
    // The small case is not the bug, but a fix that broke it would be a worse trade than the bug.
    final file = logFile();
    await seed(file, 5);
    final whole = await file.readAsString();
    await file.writeAsString(whole.substring(0, whole.length - 20), flush: true);

    final store = EventStore(file);
    await store.append([
      Event(
        hlc: Hlc(physicalMillis: 1800000000003, counter: 0, nodeId: 'test'),
        type: 'stock.bottle.added',
        data: const {'i': 111},
      ),
    ]);

    final lines = (await file.readAsString()).split('\n').where((l) => l.isNotEmpty).toList();
    expect(lines, hasLength(5));
    expect(lines.last, contains('111'));
  });
}
