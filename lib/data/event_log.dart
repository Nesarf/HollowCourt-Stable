import 'dart:io';

import '../domain/events/event.dart';
import '../domain/events/hlc.dart';
import '../domain/events/shelf.dart';
import '../domain/events/stock.dart';
import '../domain/overlay/overlay.dart';
import '../domain/sync/exchange.dart';
import '../domain/sync/pairing.dart';
import 'event_store.dart';

/// What happened when the log was opened.
final class OpenReport {
  const OpenReport({required this.events, required this.duplicates, required this.defects});

  final int events;

  /// Readings that appeared more than once in the file. Harmless -- the ledger
  /// applies each reading once -- but it means something wrote an event twice,
  /// and that is worth being able to see.
  final int duplicates;

  final List<LogDefect> defects;

  bool get hasCorruption => defects.any((d) => d.kind == LogDefectKind.unreadable);
}

/// The event log, in memory and on disk.
///
/// This is the seam the rest of the app talks to. It owns three things that
/// have to agree with each other -- the file, the clock, and the folded state
/// -- and it is the only place that knows how they relate.
///
/// Section 6 asks for operations rather than state, and the consequence is
/// visible here: there is no `setStock` method. A caller appends an operation
/// and the state is whatever the operations add up to. That is what makes two
/// devices able to merge without a diff layer, and it is what makes a mistake
/// recoverable by reading the log rather than by trusting the app.
final class EventLog implements SyncSource {
  EventLog._({
    required this.store,
    required this.clock,
    required List<Event> events,
    required this.openReport,
  }) : _events = events,
       _byClock = {for (final event in events) event.hlc: event};

  final EventStore store;
  final HlcClock clock;

  /// What the last open found, including anything it could not read.
  final OpenReport openReport;

  final List<Event> _events;
  final Map<Hlc, Event> _byClock;

  /// Reads [file], restores the clock, and folds whatever is there.
  ///
  /// [nowMillis] is injected rather than read from the system clock so that a
  /// test can decide what "now" means; production passes
  /// `DateTime.now().millisecondsSinceEpoch`.
  static Future<EventLog> open({
    required File file,
    required String nodeId,
    required int Function() nowMillis,
  }) async {
    final store = EventStore(file);
    final result = await store.read();

    // Dedupe on the way in. The ledger would tolerate a repeated reading
    // anyway, but two copies in the log means two copies to send on every sync
    // for the rest of the cellar's life.
    final seen = <Hlc>{};
    final events = <Event>[];
    var duplicates = 0;
    for (final event in result.events) {
      if (seen.add(event.hlc)) {
        events.add(event);
      } else {
        duplicates++;
      }
    }

    events.sort((a, b) => a.hlc.compareTo(b.hlc));

    // Replaying the readings through the clock is what restores it: the device
    // resumes issuing readings past everything already written, even if its own
    // wall clock has since gone backwards.
    final clock = HlcClock(nodeId: nodeId, nowMillis: nowMillis);
    for (final event in events) {
      clock.observe(event.hlc);
    }

    return EventLog._(
      store: store,
      clock: clock,
      events: events,
      openReport: OpenReport(
        events: events.length,
        duplicates: duplicates,
        defects: result.defects,
      ),
    );
  }

  /// Every event, in clock order.
  List<Event> get events => List.unmodifiable(_events);

  /// The clock readings held here, for asking a peer what it is missing.
  @override
  Set<Hlc> get clocks => Set.unmodifiable(_byClock.keys);

  /// A small summary of what this log holds, for the first message of a handshake.
  ///
  /// **The wiring `ClockDigest` needed to be worth having.** Two devices exchange this before
  /// either sends an event; equal digests mean there is nothing to do, and on a phone that is
  /// the difference between a sync that costs nothing and one that uploads a clock set per
  /// event. The full set is what [missingFrom] wants -- this is only the question of whether
  /// to ask for it.
  ClockDigest get digest => ClockDigest.of(_byClock.keys);

  Hlc? get latest => _events.isEmpty ? null : _events.last.hlc;

  /// The cellar, folded from the log.
  ///
  /// Recomputed per call rather than cached. It is a pure fold over a few
  /// thousand events, and a cached copy is a second source of truth that can
  /// disagree with the first.
  StockLedger get stock => StockLedger.of(_events);

  /// Section 8's overlay, folded from the same events.
  ///
  /// **The same list, not a second store.** Section 8's dividend is that the
  /// event log is already an overlay layer; a separate file for the user's notes
  /// would be a second clock, a second merge and a second thing to lose. So this
  /// is a second *fold* of one log, and the two folds are pure functions of the
  /// same bytes.
  ///
  /// Recomputed per call rather than cached, for the same reason [stock] is: a
  /// cached copy is a second source of truth that can disagree with the first.
  Overlay get overlay => Overlay.of(_events);

  /// Where the bottles stand, folded from the same events.
  ///
  /// **The third fold of one log, and the reason placement needed no store of
  /// its own.** A separate file for positions would be a second clock, a second
  /// merge and a second thing to lose -- the argument section 8 makes for the
  /// overlay, applied to the arrangement of the cupboard.
  ///
  /// Recomputed per call rather than cached, for the same reason [stock] is.
  ShelfLayout get shelf => ShelfLayout.of(_events);

  /// Appends one operation, minting its clock reading.
  ///
  /// The builder receives the reading rather than supplying one, so no caller
  /// can invent a clock and no two operations can accidentally share one.
  Future<Event> record(Event Function(Hlc hlc) build) async {
    final event = build(clock.next());
    await store.append([event]);
    _insert(event);
    return event;
  }

  /// Appends several operations atomically with respect to the clock.
  Future<List<Event>> recordAll(Iterable<Event Function(Hlc hlc)> builders) async {
    final events = [for (final build in builders) build(clock.next())];
    if (events.isEmpty) return events;
    await store.append(events);
    for (final event in events) {
      _insert(event);
    }
    return events;
  }

  /// Takes in events from a peer, keeping only the ones not already held.
  ///
  /// Returns the events that were new. Section 10.4 reduces a sync to
  /// exchanging what the other side is missing, and this is the receiving half
  /// of that: the sending half is [missingFrom].
  ///
  /// Only the new ones are written. Re-appending events already in the log
  /// would grow the file on every sync without changing the cellar, and an
  /// append-only log that doubles itself on each handshake is not a log anyone
  /// will keep.
  @override
  Future<List<Event>> merge(Iterable<Event> incoming) async {
    final fresh = <Event>[];
    for (final event in incoming) {
      if (_byClock.containsKey(event.hlc)) continue;
      fresh.add(event);
    }
    if (fresh.isEmpty) return const [];

    fresh.sort((a, b) => a.hlc.compareTo(b.hlc));
    await store.append(fresh);
    for (final event in fresh) {
      // Fold the peer's readings into the clock before inserting, so a local
      // operation recorded immediately afterwards sorts after everything just
      // received rather than racing it.
      clock.observe(event.hlc);
      _insert(event);
    }
    return fresh;
  }

  /// The events a peer holding [theirClocks] does not have.
  @override
  List<Event> missingFrom(Set<Hlc> theirClocks) =>
      [for (final event in _events) if (!theirClocks.contains(event.hlc)) event];

  void _insert(Event event) {
    if (_byClock.containsKey(event.hlc)) return;
    _byClock[event.hlc] = event;
    // Insert in clock order. A peer's event can legitimately land before one
    // already held, so appending to the end would leave the list unsorted and
    // the fold would silently use the wrong order.
    final at = _events.indexWhere((e) => e.hlc.compareTo(event.hlc) > 0);
    if (at < 0) {
      _events.add(event);
    } else {
      _events.insert(at, event);
    }
  }
}
