import 'dart:io';

import 'package:hollow_court/data/event_log.dart';
import 'package:hollow_court/domain/events/event.dart';
import 'package:test/test.dart';

/// **The persistence smoke test: does a real platform keep a real write across a real restart?**
///
/// ## Why this is not one of the existing tests
///
/// `event_log_test` and `overlay_persistence_test` already prove that reopening a log brings back what was written --
/// **but both reopen inside the same process, and both write to a temporary directory.** Neither says anything about
/// the platform the application actually runs on: whether the path it picks is writable, whether the file survives the
/// process ending, whether a lock left behind blocks the next start.
///
/// **That is the gap the review called a QA gap**, and its own description of the fix is this one: *install, open,
/// create a bottle, mutate, restart, read the persisted state.*
///
/// ## How it runs, and why it is two processes
///
/// A restart cannot be faked inside one process, so the test is driven in two phases by the command that runs it --
/// **`SMOKE_PHASE=write` in one process, `SMOKE_PHASE=read` in a second, both pointed at `SMOKE_DIR`.** The second
/// process shares nothing with the first but the disk, which is the whole point.
///
/// It is skipped unless `SMOKE_DIR` is set, so `flutter test` stays a test suite and this stays something a release
/// step runs deliberately. **A test that silently depends on a directory outside the repository is a test that fails
/// on somebody else's machine for a reason that is not about the code.**
void main() {
  final dir = Platform.environment['SMOKE_DIR'];
  final phase = Platform.environment['SMOKE_PHASE'] ?? 'write';

  test('persistence smoke: $phase', () async {
    if (dir == null || dir.isEmpty) {
      markTestSkipped('SMOKE_DIR is not set, so this is not a smoke run');
      return;
    }
    final file = File('$dir${Platform.pathSeparator}cellar.ndjson');
    await file.parent.create(recursive: true);

    // **The application's own code, on the application's own kind of path.** Nothing here is a stand-in for the real
    // writer: `EventLog.open` takes the cross-process lock, reads whatever is there, and `record` appends through the
    // same serialised path every screen uses.
    final log = await EventLog.open(file: file, nodeId: 'smoke', nowMillis: () => DateTime.now().millisecondsSinceEpoch);

    if (phase == 'write') {
      final before = log.events.length;
      await log.record(
        (hlc) => Event(
          hlc: hlc,
          type: 'stock.bottle.added',
          data: {'bottleId': 'smoke-${DateTime.now().millisecondsSinceEpoch}'},
        ),
      );
      // The same process sees it, which is necessary and not sufficient -- see the read phase.
      expect(log.events.length, before + 1, reason: 'the write did not reach the in-memory log');
      await log.close();
      stdout.writeln('SMOKE write: $before -> ${before + 1} events in ${file.path}');
      return;
    }

    // ---- the read phase: a different process, the same file ----
    final types = log.events.map((e) => e.type).toList();
    await log.close();
    expect(
      types.where((t) => t == 'stock.bottle.added'),
      isNotEmpty,
      reason: 'the event the write phase appended is not in the file this process read -- '
          'the platform did not keep it, or the path differs between the two runs',
    );
    stdout.writeln('SMOKE read: ${types.length} events survived, '
        '${types.where((t) => t == 'stock.bottle.added').length} of them bottle additions');
  });
}
