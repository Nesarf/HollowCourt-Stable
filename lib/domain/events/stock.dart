import '../units/quantity.dart';
import 'event.dart';
import 'hlc.dart';

/// The stock events, and the payload keys they use.
///
/// The keys are written down once, here, because they are a wire format: two
/// devices agree about a consumed bottle only because they spell the field the
/// same way. A string literal repeated at every call site is a rename waiting
/// to happen in one place and not the other.
abstract final class StockEvent {
  /// A bottle entered the cellar.
  static const bottleAdded = 'stock.bottle.added';

  /// Some of a bottle was poured into drinks.
  static const bottleConsumed = 'stock.bottle.consumed';

  /// The rest of a bottle left the cellar without being drunk: broken, poured
  /// away, or given away. Separate from [bottleConsumed] on purpose -- both
  /// reduce the stock, but only one of them was a drink, and a consumption
  /// curve that cannot tell them apart is not a consumption curve.
  static const bottleDiscarded = 'stock.bottle.discarded';

  /// Someone counted what is actually in the bottle.
  ///
  /// An absolute reading rather than a delta, because that is what looking at a
  /// bottle gives you. It is the one stock event that does not commute with its
  /// neighbours, which is why the ledger folds in clock order rather than in
  /// arrival order.
  static const bottleRecounted = 'stock.bottle.recounted';

  /// A line that should never have been written, retracted.
  ///
  /// **Not an undo, and not a rewrite of history.** The log is append-only, so the only way for a
  /// mistake to stop being in the cellar is for a later event to say so -- and this is that event.
  /// The bottle leaves the shelf, its price observation leaves the chart, and a reader who scrolls
  /// the log still finds both the entry and the retraction in order, which is the difference between
  /// correcting a record and editing one.
  ///
  /// **It carries no volume, on purpose.** Every other stock op says how much moved; this one says
  /// the line was never true, so there is no amount to name. That is why [StockOp.tryParse] has to
  /// handle it *before* it looks for `volumeMicrolitres` -- reading that key was the parser's second
  /// line and a requirement, and a removal has nothing to put there.
  ///
  /// **[decision] The writer refuses it when anything has been poured or discarded against the
  /// bottle**, and that guard lives in the notifier rather than here. A fold cannot refuse: a
  /// removal may arrive from another device *after* a pour this one recorded, and the fold's job is
  /// to reduce what it is given rather than to argue with it. What the writer's guard buys is that
  /// the consumption curve cannot be made to lie by deleting the bottle a drink came from -- the
  /// pours stay in the log with nothing left to belong to.
  static const bottleRemoved = 'stock.bottle.removed';

  /// Every type this build knows how to reduce.
  static const all = {
    bottleAdded,
    bottleConsumed,
    bottleDiscarded,
    bottleRecounted,
    bottleRemoved,
  };
}

/// Builders for the stock events.
///
/// Each takes the clock reading the caller obtained from [HlcClock]. Nothing
/// here reads the system clock: where a timestamp is wanted in the payload
/// (a purchase date, say) it is passed in, so that an event's contents can be
/// asserted exactly in a test.
abstract final class StockEvents {
  static Event bottleAdded({
    required Hlc hlc,
    required String bottleId,
    required String sku,
    required Volume volume,
    int? priceMinor,
    String? currency,
    int? purchasedAtMillis,
    String? note,
  }) => Event(
    hlc: hlc,
    type: StockEvent.bottleAdded,
    data: {
      'bottleId': bottleId,
      'sku': sku,
      'volumeMicrolitres': volume.microlitres,
      'priceMinor': ?priceMinor,
      'currency': ?currency,
      'purchasedAtMillis': ?purchasedAtMillis,
      'note': ?note,
    },
  );

  static Event bottleConsumed({
    required Hlc hlc,
    required String bottleId,
    required Volume volume,
    String? batchId,
  }) => Event(
    hlc: hlc,
    type: StockEvent.bottleConsumed,
    data: {
      'bottleId': bottleId,
      'volumeMicrolitres': volume.microlitres,
      'batchId': ?batchId,
    },
  );

  static Event bottleDiscarded({
    required Hlc hlc,
    required String bottleId,
    required Volume volume,
    String? reason,
  }) => Event(
    hlc: hlc,
    type: StockEvent.bottleDiscarded,
    data: {
      'bottleId': bottleId,
      'volumeMicrolitres': volume.microlitres,
      'reason': ?reason,
    },
  );

  static Event bottleRecounted({
    required Hlc hlc,
    required String bottleId,
    required Volume volume,
    String? reason,
  }) => Event(
    hlc: hlc,
    type: StockEvent.bottleRecounted,
    data: {
      'bottleId': bottleId,
      'volumeMicrolitres': volume.microlitres,
      'reason': ?reason,
    },
  );

  /// Retracts a [bottleAdded]. **The only stock builder with no amount in it**, because the event
  /// is about the line rather than about the liquid -- see [StockEvent.bottleRemoved].
  static Event bottleRemoved({
    required Hlc hlc,
    required String bottleId,
    String? reason,
  }) => Event(
    hlc: hlc,
    type: StockEvent.bottleRemoved,
    data: {'bottleId': bottleId, 'reason': ?reason},
  );
}

/// A stock event, read back as a typed operation.
///
/// [tryParse] returns null for any other event type rather than throwing: the
/// log is shared, and a device will routinely meet events written by a build
/// that knows more than it does. Refusing to read the line would be refusing to
/// carry it, and an op-log that drops what it does not understand loses
/// operations on sync.
sealed class StockOp {
  const StockOp(this.hlc);

  final Hlc hlc;

  /// The bottle this operation is about.
  String get bottleId;

  static StockOp? tryParse(Event event) {
    final id = event.optional<String>('bottleId');
    if (id == null) return null;

    // **The removal is read before the volume is, and it has to be.** The next two lines treat
    // `volumeMicrolitres` as a requirement, because every other stock op carries an amount. A
    // removal carries none -- there is no amount in "this line was never true" -- so a parser that
    // demanded one would drop every retraction on the floor, silently, and the bottle would come
    // back on the next fold.
    if (event.type == StockEvent.bottleRemoved) {
      return BottleRemoved(hlc: event.hlc, bottleId: id);
    }

    final microlitres = event.optional<int>('volumeMicrolitres');
    if (microlitres == null) return null;
    final volume = Volume.fromMicrolitres(microlitres);
    return switch (event.type) {
      StockEvent.bottleAdded => BottleAdded(
        hlc: event.hlc,
        bottleId: id,
        sku: event.require<String>('sku'),
        volume: volume,
        priceMinor: event.optional<int>('priceMinor'),
        currency: event.optional<String>('currency'),
        purchasedAtMillis: event.optional<int>('purchasedAtMillis'),
      ),
      StockEvent.bottleConsumed => BottleConsumed(
        hlc: event.hlc,
        bottleId: id,
        volume: volume,
        batchId: event.optional<String>('batchId'),
      ),
      StockEvent.bottleDiscarded => BottleDiscarded(
        hlc: event.hlc,
        bottleId: id,
        volume: volume,
      ),
      StockEvent.bottleRecounted => BottleRecounted(
        hlc: event.hlc,
        bottleId: id,
        volume: volume,
      ),
      _ => null,
    };
  }
}

final class BottleAdded extends StockOp {
  const BottleAdded({
    required Hlc hlc,
    required this.bottleId,
    required this.sku,
    required this.volume,
    this.priceMinor,
    this.currency,
    this.purchasedAtMillis,
  }) : super(hlc);

  @override
  final String bottleId;
  final String sku;
  final Volume volume;
  final int? priceMinor;

  /// The ISO code [priceMinor] is denominated in, when the writer said.
  ///
  /// **Read back rather than ignored, which it was.** `StockEvents.bottleAdded` has always
  /// accepted a `currency` and written it into the payload, and this class did not read it
  /// -- so a price recorded in USD came back as whatever the price fold assumed, with
  /// nothing anywhere reporting the substitution. A payload key that the writer sets and
  /// the reader drops is worse than a key that does not exist: the first looks like data.
  ///
  /// Null for an event written before this field was read, and that is the case the price
  /// fold's fallback exists for.
  final String? currency;

  final int? purchasedAtMillis;
}

final class BottleConsumed extends StockOp {
  const BottleConsumed({
    required Hlc hlc,
    required this.bottleId,
    required this.volume,
    this.batchId,
  }) : super(hlc);

  @override
  final String bottleId;
  final Volume volume;
  final String? batchId;
}

final class BottleDiscarded extends StockOp {
  const BottleDiscarded({
    required Hlc hlc,
    required this.bottleId,
    required this.volume,
  }) : super(hlc);

  @override
  final String bottleId;
  final Volume volume;
}

final class BottleRecounted extends StockOp {
  const BottleRecounted({
    required Hlc hlc,
    required this.bottleId,
    required this.volume,
  }) : super(hlc);

  @override
  final String bottleId;
  final Volume volume;
}

/// The retraction of an [BottleAdded]: the line was a mistake and never happened.
///
/// No volume, and that is the type saying something rather than an omission -- see
/// [StockEvent.bottleRemoved], which also explains why the writer refuses this for a bottle that
/// has been poured from.
final class BottleRemoved extends StockOp {
  const BottleRemoved({required Hlc hlc, required this.bottleId}) : super(hlc);

  @override
  final String bottleId;
}

/// What one bottle comes to after every operation on it has been applied.
final class BottleState {
  const BottleState({
    required this.bottleId,
    required this.sku,
    required this.added,
    required this.consumed,
    required this.discarded,
    required this.remaining,
    required this.recounts,
    this.priceMinor,
    this.purchasedAtMillis,
  });

  final String bottleId;
  final String sku;

  /// How much went in when the bottle was recorded.
  final Volume added;

  /// Everything poured into drinks, summed.
  final Volume consumed;

  /// Everything that left without being drunk, summed.
  final Volume discarded;

  /// What is left, counting any recount as the new truth.
  final Volume remaining;

  /// How many times someone physically recounted this bottle.
  final int recounts;

  final int? priceMinor;
  final int? purchasedAtMillis;

  /// True when more has been taken out than the bottle was known to hold.
  ///
  /// Judged against [remaining] alone rather than against `consumed + discarded
  /// > added`, because a recount supersedes the original fill: a bottle
  /// weighed at 300 ml after 800 ml had been recorded as poured is a corrected
  /// bottle, not an overdrawn one.
  ///
  /// Not clamped to zero. A cellar whose ledger says a bottle is emptier than
  /// it ever was full has a real problem -- a missing `added`, a mistyped
  /// measurement, two devices that disagree -- and rounding it away would hide
  /// the only evidence of it.
  bool get isOverdrawn => remaining.isNegative;

  bool get isEmpty => remaining.isZero;
}

/// The fold from stock events to what is on the shelf.
///
/// Built fresh from the log rather than kept in step with it. Section 6 asks
/// for operations rather than state precisely so that this is possible: the
/// ledger is a pure function of the events, so two devices that hold the same
/// events hold the same cellar, whether they arrived in the same order or not.
final class StockLedger {
  StockLedger._(
    this._bottles, {
    required List<StockOp> unknownBottles,
    required List<Event> duplicateAdds,
    required Set<String> removedBottleIds,
    required int applied,
    required int ignored,
  }) : unknownBottles = List.unmodifiable(unknownBottles),
       duplicateAdds = List.unmodifiable(duplicateAdds),
       removedBottleIds = Set.unmodifiable(removedBottleIds),
       appliedEvents = applied,
       ignoredEvents = ignored;

  final Map<String, BottleState> _bottles;

  /// Operations naming a bottle that was never added.
  ///
  /// Surfaced rather than dropped. Either the log is missing an event -- which
  /// a sync will fix -- or something wrote an operation against a bottle that
  /// does not exist, which is a bug worth seeing.
  final List<StockOp> unknownBottles;

  /// A second `added` for a bottle id that already had one.
  ///
  /// Not applied: adding it again would invent stock. Recorded, because two
  /// devices independently recording the same purchase is exactly the kind of
  /// thing an op-log is supposed to make visible.
  final List<Event> duplicateAdds;

  /// Every bottle a [StockEvent.bottleRemoved] has named.
  ///
  /// **Exposed because the shelf is not the only fold that read the entry.** A bottle's price
  /// becomes a point in section 7's series, and that fold walks events without consulting this
  /// ledger -- so a retracted line would keep its price in the chart while the bottle it came from
  /// had already left the shelf. The two folds disagreeing about what happened is the failure the
  /// Cellar type exists to prevent, and the set is how the price side finds out.
  final Set<String> removedBottleIds;

  /// How many events this ledger actually reduced.
  final int appliedEvents;

  /// How many it could not read, which is normal when a log carries events
  /// written by a newer build.
  final int ignoredEvents;

  /// Folds [events] into a ledger.
  ///
  /// Applies them in clock order, and applies each clock reading at most once.
  /// Both matter and neither is optional:
  ///
  /// * Clock order, because [StockEvent.bottleRecounted] replaces the remaining
  ///   volume rather than adjusting it. Its effect depends on which operations
  ///   it sits between, so folding in arrival order would give a different
  ///   cellar depending on how the mail happened to arrive.
  /// * Deduplication, because sync means sending the other device everything it
  ///   is missing, and a device that is missing a stretch of the log rather
  ///   than a single event will happily send one twice.
  ///
  /// The additive operations commute, which is the property section 6 is really
  /// asking for: two devices that each poured a drink produce the same total
  /// whichever order the two pours are applied in, and neither pour overwrites
  /// the other.
  factory StockLedger.of(Iterable<Event> events) {
    final ordered = events.toList()
      ..sort((a, b) => a.hlc.compareTo(b.hlc));

    final accumulators = <String, _BottleAccumulator>{};
    final seen = <Hlc>{};
    final unknown = <StockOp>[];
    final duplicates = <Event>[];
    // Every bottle id a retraction has named, whether or not the bottle was still there. Kept
    // outside the accumulator map because the map is what the shelf is built from and a removed
    // bottle has to be *absent* from it -- the price fold needs the ids, and it reads events
    // rather than the ledger.
    final removed = <String>{};
    var applied = 0;
    var ignored = 0;

    for (final event in ordered) {
      if (!seen.add(event.hlc)) continue; // already applied, or a duplicate
      final op = StockOp.tryParse(event);
      if (op == null) {
        ignored++;
        continue;
      }
      applied++;

      if (op is BottleAdded) {
        if (accumulators.containsKey(op.bottleId)) {
          duplicates.add(event);
          continue;
        }
        accumulators[op.bottleId] = _BottleAccumulator(op);
        continue;
      }

      // **Handled before the lookup, because a removal of a bottle that exists is a success rather
      // than an unknown.** Everything below this point answers "which bottle is this about", and a
      // retraction's answer is "there is no longer one". A removal naming a bottle that was never
      // added *is* unknown, and is surfaced like any other orphaned operation.
      if (op is BottleRemoved) {
        if (accumulators.remove(op.bottleId) == null) unknown.add(op);
        removed.add(op.bottleId);
        continue;
      }

      final accumulator = accumulators[op.bottleId];
      if (accumulator == null) {
        unknown.add(op);
        continue;
      }
      switch (op) {
        case BottleConsumed():
          accumulator.consume(op.volume);
        case BottleDiscarded():
          accumulator.discard(op.volume);
        case BottleRecounted():
          accumulator.recount(op.volume);
        case BottleRemoved():
          // Unreachable, and the switch says so rather than growing a `default` that would hide the
          // next op somebody adds. A retraction has no accumulator to apply to.
          throw StateError('handled above');
        case BottleAdded():
          throw StateError('handled above');
      }
    }

    return StockLedger._(
      {
        for (final entry in accumulators.entries) entry.key: entry.value.build(),
      },
      unknownBottles: unknown,
      duplicateAdds: duplicates,
      removedBottleIds: removed,
      applied: applied,
      ignored: ignored,
    );
  }

  Iterable<BottleState> get bottles => _bottles.values;

  BottleState? bottle(String bottleId) => _bottles[bottleId];

  /// Every distinct sku with at least one bottle on the shelf.
  Iterable<String> get skus =>
      _bottles.values.map((bottle) => bottle.sku).toSet();

  /// What is left of one sku, summed across its bottles.
  Volume remainingOf(String sku) => _bottles.values
      .where((bottle) => bottle.sku == sku)
      .fold(Volume.zero, (sum, bottle) => sum + bottle.remaining);

  Volume get remainingTotal => _bottles.values
      .fold(Volume.zero, (sum, bottle) => sum + bottle.remaining);

  /// Bottles that still hold something.
  Iterable<BottleState> get openBottles =>
      _bottles.values.where((bottle) => !bottle.isEmpty);

  int get bottleCount => _bottles.length;
}

/// Mutable working state for one bottle while the fold runs.
final class _BottleAccumulator {
  _BottleAccumulator(this._added);

  final BottleAdded _added;

  Volume _consumed = Volume.zero;
  Volume _discarded = Volume.zero;
  Volume? _recounted;
  Volume _consumedAtRecount = Volume.zero;
  Volume _discardedAtRecount = Volume.zero;
  int _recounts = 0;

  void consume(Volume volume) => _consumed = _consumed + volume;

  void discard(Volume volume) => _discarded = _discarded + volume;

  void recount(Volume volume) {
    // A recount absorbs everything that happened before it -- the number
    // someone read off the bottle already accounts for those pours. What it
    // must not do is absorb what happens *after* it, so the running totals are
    // remembered here and subtracted from the recount rather than replacing it.
    _recounted = volume;
    _consumedAtRecount = _consumed;
    _discardedAtRecount = _discarded;
    _recounts++;
  }

  BottleState build() {
    final recounted = _recounted;
    final remaining = recounted == null
        ? _added.volume - _consumed - _discarded
        : recounted - (_consumed - _consumedAtRecount) -
              (_discarded - _discardedAtRecount);
    return BottleState(
      bottleId: _added.bottleId,
      sku: _added.sku,
      added: _added.volume,
      consumed: _consumed,
      discarded: _discarded,
      remaining: remaining,
      recounts: _recounts,
      priceMinor: _added.priceMinor,
      purchasedAtMillis: _added.purchasedAtMillis,
    );
  }
}
