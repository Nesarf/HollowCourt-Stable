import 'dart:io';

import 'package:hollow_court/data/event_log.dart';
import 'package:hollow_court/data/sync/courtpack_service.dart';
import 'package:hollow_court/domain/events/event.dart';
import 'package:hollow_court/domain/events/hlc.dart';
import 'package:hollow_court/domain/sync/courtpack.dart';
import 'package:test/test.dart';

/// **The carrier that needs no network: a file.**
///
/// `courtpack.dart` was written, tested by nobody and called from nowhere. These are the tests that make it a
/// feature: a pack written from one cellar, read into another, and refused in each of the five ways a file can
/// arrive wrong.
void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('hollow-pack'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<EventLog> logNamed(String node) async => EventLog.open(
    file: File('${dir.path}${Platform.pathSeparator}$node.ndjson'),
    nodeId: node,
    nowMillis: () => 1000,
  );

  Event bottle(String sku, int at) => Event(
    hlc: Hlc(physicalMillis: at, counter: 0, nodeId: 'laptop'),
    type: 'stock.bottle.added',
    data: <String, Object?>{
      'bottleId': 'bottle-$sku-$at',
      'sku': sku,
      'volumeMicrolitres': 700000,
    },
  );

  const service = CourtPackService();

  test('**a pack written from one cellar lands in another**', () async {
    final source = await logNamed('laptop');
    await source.record((hlc) => bottle('gin', 1000));
    await source.record((hlc) => bottle('campari', 2000));

    final pack = await service.write(
      source,
      directory: dir.path,
      source: 'laptop',
      fingerprint: 'aaaa',
      now: DateTime(2026, 9, 22, 15, 30),
    );
    expect(pack.existsSync(), isTrue);
    expect(pack.path, endsWith(CourtPackService.extension));
    expect(pack.path, contains('20260922-1530'), reason: 'the name sorts by time');

    final phone = await logNamed('phone');
    expect(phone.stock.bottleCount, 0);

    final imported = await service.read(pack, phone);
    expect(imported.ok, isTrue);
    expect(imported.header!.source, 'laptop');
    expect(imported.header!.fingerprint, 'aaaa');
    expect(imported.offered, 2);
    expect(imported.applied, 2);
    expect(phone.stock.bottleCount, 2);
  });

  test('**importing the same pack twice applies nothing the second time**', () async {
    // The property that makes a pack safe to hand to somebody who cannot remember whether they already
    // imported it: a merge is keyed on the clocks the log already holds.
    final source = await logNamed('laptop');
    await source.record((hlc) => bottle('gin', 1000));
    final pack = await service.write(source, directory: dir.path, source: 'laptop');

    final phone = await logNamed('phone');
    final first = await service.read(pack, phone);
    final second = await service.read(pack, phone);
    expect(first.applied, 1);
    expect(second.applied, 0);
    expect(second.offered, 1, reason: 'the pack still carries its event; nothing was new to this log');
    expect(phone.stock.bottleCount, 1, reason: 'and the cellar did not grow a second bottle');
  });

  test('**a pack that arrived damaged is refused rather than half-imported**', () async {
    final source = await logNamed('laptop');
    await source.record((hlc) => bottle('gin', 1000));
    await source.record((hlc) => bottle('campari', 2000));
    final pack = await service.write(source, directory: dir.path, source: 'laptop');

    // **Two kinds of truncation, and the domain tells them apart.** Losing whole lines leaves every line
    // readable and the count short -- `truncated`, and the screen says the pack lost its end. Losing the last
    // line *halfway* leaves a line that cannot be parsed -- `damaged`. Both happen in transit and both must
    // refuse, so both are tested rather than one standing in for the other.
    final lines = pack.readAsLinesSync();
    pack.writeAsStringSync('${lines.take(lines.length - 1).join('\n')}\n');

    final phone = await logNamed('phone');
    final refused = await service.read(pack, phone);
    expect(refused.ok, isFalse);
    expect(refused.problem, CourtPackProblem.truncated);
    expect(refused.offered, 0, reason: 'nothing partial comes through');
    expect(phone.stock.bottleCount, 0, reason: 'a refusal imports nothing at all');
    expect(describePackProblem(refused.problem!), contains('cut short'));

    // And the halfway cut, on a fresh pack.
    final second = await service.write(source, directory: dir.path, source: 'laptop');
    final text = second.readAsStringSync();
    second.writeAsStringSync(text.substring(0, text.length - 12));
    final halved = await service.read(second, phone);
    expect(halved.ok, isFalse);
    expect(halved.problem, CourtPackProblem.damaged);
    expect(describePackProblem(halved.problem!), contains('damaged'));
  });

  test('an altered pack is refused, which is what the hash is for', () async {
    final source = await logNamed('laptop');
    await source.record((hlc) => bottle('gin', 1000));
    final pack = await service.write(source, directory: dir.path, source: 'laptop');

    // A hand edit that changes one volume: the count still matches, so only the hash can catch it.
    final text = pack.readAsStringSync().replaceAll('700000', '999999');
    pack.writeAsStringSync(text);

    final phone = await logNamed('phone');
    final refused = await service.read(pack, phone);
    expect(refused.ok, isFalse);
    expect(refused.problem, isNotNull);
    expect(phone.stock.bottleCount, 0);
  });

  test('a file that is not a pack says so, in the reader\'s words', () async {
    final other = File('${dir.path}${Platform.pathSeparator}notes.courtpack');
    await other.writeAsString('this is a shopping list, not a cellar');
    final phone = await logNamed('phone');
    final refused = await service.read(other, phone);
    expect(refused.problem, CourtPackProblem.notAPack);
    expect(describePackProblem(refused.problem!), contains('not a 空庭 pack'));
  });

  test('the directory scan finds packs and nothing else, newest first', () async {
    final source = await logNamed('laptop');
    await source.record((hlc) => bottle('gin', 1000));
    final older = await service.write(
      source,
      directory: dir.path,
      source: 'laptop',
      now: DateTime(2026, 9, 20, 10),
    );
    final newer = await service.write(
      source,
      directory: dir.path,
      source: 'laptop',
      now: DateTime(2026, 9, 22, 10),
    );
    File('${dir.path}${Platform.pathSeparator}readme.txt').writeAsStringSync('not a pack');

    final found = service.find(dir.path);
    expect(found.map((f) => f.path), [newer.path, older.path]);
    expect(service.find('${dir.path}${Platform.pathSeparator}nowhere'), isEmpty);
  });
}
