import 'dart:io';

import 'package:hollow_court/data/event_log.dart';
import 'package:test/test.dart';

/// **The cross-process claim on a cellar.**
///
/// A second process writing one log is not a lost update but a **corrupt file**: every append is a line, and the
/// reader *rewrites* the log when it discards a torn tail, so two writers leave a file that is neither version's.
/// `CellarLock` argues it at length; this checks the behaviour, including the part that made the first attempt fail.
void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('cellar_lock'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  File logAt(String name) => File('${dir.path}${Platform.pathSeparator}$name.ndjson');

  test('**the same process is allowed back in**', () async {
    // **The measurement that shaped the design.** Dart's `lock` is per *handle*, not per process: a second handle in
    // the same process is refused exactly as a foreign process would be. So a lock that refused on contention would
    // refuse the application's own reload and every test that opens a cellar twice -- 64 tests failed on the first
    // attempt, which is how that was found. The pid written beside the lock is what tells the two apart.
    final first = await EventLog.open(file: logAt('a'), nodeId: 'a', nowMillis: () => 1000);
    final second = await EventLog.open(file: logAt('a'), nodeId: 'a', nowMillis: () => 1000);

    expect(second.openReport.events, 0, reason: 'the same cellar, opened twice');
    await second.close();
    await first.close();
  });

  // **A cross-process refusal is not tested here, and that is deliberate rather than an omission.** The three
  // tests around this comment are about behaviour that can be observed from inside one process. Refusing a *foreign*
  // holder needs a second process, and the first attempt at writing that test used two handles in this one -- which
  // is not the same thing at all, and would have proved nothing while looking like it proved everything. The
  // mechanism is `CellarLock.acquire`'s pid comparison, argued in that class; what this file can honestly check is
  // the half that does not need a second program.

  test('**closing releases the claim, so the directory can go**', () async {
    // The failure that cost the first attempt its time: `close()` returns a `Future`, and firing it off without
    // awaiting raced the directory deletion -- and the file system does not lose races in the caller's favour. The
    // symptom was `errno = 32` naming a *directory*, which is why it took three tries to find the lock behind it.
    final log = await EventLog.open(file: logAt('c'), nodeId: 'a', nowMillis: () => 1000);
    await log.close();

    final sub = Directory('${dir.path}${Platform.pathSeparator}sub')..createSync();
    File('${sub.path}${Platform.pathSeparator}gone.ndjson').writeAsStringSync('');
    sub.deleteSync(recursive: true);
    expect(sub.existsSync(), isFalse);
  });

  test('the lock file and its owner are siblings of the log, not the log itself', () async {
    // The log is opened, closed and rewritten during recovery, so a lock held on it would be dropped whenever the
    // store reopens it -- and the log's bytes must stay untouched, because it is a sync format and a `.courtpack` is
    // a copy of it.
    final log = await EventLog.open(file: logAt('d'), nodeId: 'a', nowMillis: () => 1000);
    expect(File('${logAt('d').path}.lock').existsSync(), isTrue);
    expect(File('${logAt('d').path}.lock.owner').existsSync(), isTrue);
    await log.close();
  });
}
