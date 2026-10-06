/// **Releases every cellar a test opened, so the test can delete its temporary directory.**
///
/// ## Why a shared registry rather than a call at each site
///
/// `CellarLock` holds an exclusive lock on `<log>.lock` while its handle is open, and the operating system drops it
/// only when the *process* ends -- right for the application, wrong for a test that removes its directory
/// afterwards. A test that does not release finds the directory will not delete, with **`errno = 32` and a message
/// naming a directory**, which is why the first attempt at this work looked in the wrong place for an hour.
///
/// Fifteen test files open a log and eleven of them delete a directory. **Making every open go through a wrapper
/// would mean editing every call site in all fifteen**; recording it here instead means each file needs one line in
/// its `tearDown`, which is the difference between a change that can be finished and one that cannot.
///
/// ## How a test uses it
///
/// ```dart
/// tearDown(() async {
///   await releaseCellars();
///   if (dir.existsSync()) dir.deleteSync(recursive: true);
/// });
/// ```
///
/// **Awaiting is not optional.** `EventLog.close` returns a `Future`, and the first version of this fired the
/// releases off and deleted immediately -- a race the file system lost.
library;

import 'package:hollow_court/data/event_log.dart';

final _opened = <EventLog>[];

/// Records a log so [releaseCellars] can release it.
///
/// Returns the log unchanged, so a call site can be wrapped without being restructured:
/// `final log = await track(await EventLog.open(...))`.
Future<EventLog> track(EventLog log) async {
  _opened.add(log);
  return log;
}

/// Releases every claim recorded so far, and forgets them.
///
/// Safe to call when nothing was recorded, and safe to call from a synchronous `tearDown` -- but **await it**, or
/// whatever deletes the directory next is racing a release that has not finished.
Future<void> releaseCellars() async {
  for (final log in _opened) {
    await log.close();
  }
  _opened.clear();
}

/// Opens a log and records it, so [releaseCellars] can release its claim.
///
/// **The call site keeps its shape**: every argument `EventLog.open` takes is passed straight through, so replacing
/// `EventLog.open(` with `openTracked(` is the whole edit.
Future<EventLog> openTracked({
  required dynamic file,
  required String nodeId,
  required int Function() nowMillis,
}) async {
  final log = await EventLog.open(file: file, nodeId: nodeId, nowMillis: nowMillis);
  _opened.add(log);
  return log;
}
