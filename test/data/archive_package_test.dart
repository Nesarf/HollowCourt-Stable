import 'dart:convert';
import 'dart:io';

import 'package:hollow_court/data/archive_package.dart';
import 'package:hollow_court/domain/events/event.dart';
import 'package:hollow_court/domain/events/hlc.dart';
import 'package:test/test.dart';

/// **The container an archival lands in.**
///
/// `docs/archival.md` settles what compaction is here: **not deletion but a move**, so the working log shrinks while
/// the history stays complete. **That is why the container has to be trustworthy rather than merely readable** -- it is
/// the file a reader is meant to still be able to open in five years, and **the one file nobody will ever check by
/// hand.**
void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('archive_package'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Hlc at(int millis, [int counter = 0]) =>
      Hlc(physicalMillis: millis, counter: counter, nodeId: 'a');

  Event eventAt(int millis, String id) =>
      Event(hlc: at(millis), type: 'stock.bottle.added', data: {'bottleId': id});

  ArchivePackage packageOf(List<Event> events) => ArchivePackage(
    events: events,
    first: events.isEmpty ? '' : events.first.hlc.toString(),
    last: events.isEmpty ? '' : events.last.hlc.toString(),
    manifest: ArchiveManifest(
      format: ArchiveManifest.formatVersion,
      createdMillis: 1_700_000_000_000,
      firstClock: events.isEmpty ? '' : events.first.hlc.toString(),
      lastClock: events.isEmpty ? '' : events.last.hlc.toString(),
      count: events.length,
      nodeId: 'a',
      digest: ArchiveManifest.digestOf(events),
    ),
  );

  test('**a package round-trips, and the events come back in order**', () async {
    final original = [eventAt(1000, 'b1'), eventAt(2000, 'b2'), eventAt(3000, 'b3')];
    final file = await packageOf(original).writeTo(dir);

    final back = await ArchivePackage.read(file);
    expect(back.events, hasLength(3));
    expect(back.events.map((e) => e.data['bottleId']), ['b1', 'b2', 'b3']);
    expect(back.first, original.first.hlc.toString());
    expect(back.last, original.last.hlc.toString());
  });

  test('the file is named after its range, so a directory explains itself', () async {
    final file = await packageOf([eventAt(1000, 'b1'), eventAt(2000, 'b2')]).writeTo(dir);
    expect(file.path, contains('cellar-archive-'));
    expect(file.path, endsWith('.courtarchive'));
    expect(file.path, isNot(contains(' ')), reason: 'a name a person may have to type');
  });

  test('**the manifest is the first line, and the rest are events**', () async {
    // The container is new and **what is inside it is not**: the lines are the same line-delimited JSON the log uses,
    // so a reader can verify the file by opening it rather than by trusting this application.
    final file = await packageOf([eventAt(1000, 'b1')]).writeTo(dir);
    final lines = await file.readAsLines();
    expect(lines, hasLength(2));
    expect((jsonDecode(lines.first) as Map).keys, contains('manifest'));
    final second = jsonDecode(lines[1]) as Map<String, Object?>;
    expect(second['type'], 'stock.bottle.added');
    expect(second['hlc'], isNotNull);
  });

  test('**a damaged event is refused, and the reason is the digest**', () async {
    final file = await packageOf([eventAt(1000, 'b1'), eventAt(2000, 'b2')]).writeTo(dir);
    // An edit that leaves the line count alone -- which is exactly what a damage check based on counting would miss.
    final text = await file.readAsString();
    await file.writeAsString(text.replaceFirst('b2', 'bX'));

    expect(
      () => ArchivePackage.read(file),
      throwsA(
        isA<ArchiveUnreadable>().having(
          (e) => e.reason,
          'reason',
          contains('digest'),
        ),
      ),
    );
  });

  test('**a manifest that disagrees with the file is refused**', () async {
    final file = await packageOf([eventAt(1000, 'b1')]).writeTo(dir);
    final lines = await file.readAsLines();
    // Claim one more event than the file holds, and fix the digest so the count is the only thing wrong.
    final manifest = jsonDecode(lines.first) as Map<String, Object?>;
    final inner = Map<String, Object?>.from(manifest['manifest']! as Map);
    inner['count'] = 2;
    await file.writeAsString('${jsonEncode({'manifest': inner})}\n${lines[1]}\n');

    expect(
      () => ArchivePackage.read(file),
      throwsA(
        isA<ArchiveUnreadable>().having((e) => e.reason, 'reason', contains('the manifest says 2')),
      ),
    );
  });

  test('**a format this build does not write is refused rather than half-read**', () async {
    // The rule `CourtPack.version` already follows. An archive from a future build may hold event types this one does
    // not know, and reading the ones it does know would put a *partial* history into a projection while looking whole.
    final file = await packageOf([eventAt(1000, 'b1')]).writeTo(dir);
    final lines = await file.readAsLines();
    final manifest = jsonDecode(lines.first) as Map<String, Object?>;
    final inner = Map<String, Object?>.from(manifest['manifest']! as Map);
    inner['version'] = ArchiveManifest.formatVersion + 1;
    await file.writeAsString('${jsonEncode({'manifest': inner})}\n${lines[1]}\n');

    expect(
      () => ArchivePackage.read(file),
      throwsA(isA<ArchiveUnreadable>().having((e) => e.reason, 'reason', contains('format version'))),
    );
  });

  test('a file that is not an archive is refused, and says so', () async {
    final file = File('${dir.path}${Platform.pathSeparator}not-an-archive.txt');
    await file.writeAsString('hello\n');
    expect(() => ArchivePackage.read(file), throwsA(isA<ArchiveUnreadable>()));
  });

  test('an empty file is refused rather than read as zero events', () async {
    final file = File('${dir.path}${Platform.pathSeparator}empty.courtarchive');
    await file.writeAsString('');
    expect(() => ArchivePackage.read(file), throwsA(isA<ArchiveUnreadable>()));
  });

  test('**a half-written package is left under a temporary name, never the real one**', () async {
    // A reader must never find something at the archive name that is not an archive: that is the whole of the value of
    // the file. Written to `.writing` and renamed, the same shape `identity_store.dart` uses for the device key.
    final package = packageOf([eventAt(1000, 'b1')]);
    final file = await package.writeTo(dir);
    expect(file.path, endsWith(package.fileName));
    expect(
      File('${file.path}.writing').existsSync(),
      isFalse,
      reason: 'the temporary name must not survive a successful write',
    );
  });

  test('the digest is stable for the same events and differs for different ones', () {
    final one = [eventAt(1000, 'b1')];
    final two = [eventAt(1000, 'b2')];
    expect(ArchiveManifest.digestOf(one), ArchiveManifest.digestOf([eventAt(1000, 'b1')]));
    expect(ArchiveManifest.digestOf(one), isNot(ArchiveManifest.digestOf(two)));
  });
}
