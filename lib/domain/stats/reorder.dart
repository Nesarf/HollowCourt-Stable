import '../events/event.dart';
import '../events/hlc.dart';
import '../events/stock.dart';
import '../units/quantity.dart';

/// What is worth buying again -- stage ④ of `docs/catalogue-and-stock.md`.
///
/// **The shopping list answers a different question**, and the design note calls the difference "half": it is derived
/// from *the plan*, so it lists what the drinks a reader intends to make are missing. A bottle with five percent left
/// counts as *had*, and the negroni is planned, and the list is empty -- on the evening the gin runs out.
///
/// ## Three signals rather than one, and none of them is sufficient
///
/// A home bar is not a warehouse and a single rule gets it wrong in both directions. The owner's instruction was to
/// combine all three, and the reason each is needed is a case the others miss:
///
///   * **A fraction** -- `remaining / added` under [ReorderPoint.fillPercent]. This is what a person actually
///     notices: *the bottle is nearly empty*. It is also the one that catches a bottle that has been finished,
///     because zero is under every threshold there is.
///   * **A remainder** -- under [ReorderPoint]. A quarter of a litre of bitters is a quarter of a litre of bitters,
///     and the fraction rule cannot see it: a small bottle at twenty percent may be one drink, and a litre at twenty
///     percent is an evening. **Neither rule subsumes the other.**
///   * **A horizon** -- at the speed it is going, it runs out within [ReorderPoint.horizonDays]. This is the only one
///     that is a *reorder point* in the warehouse's sense rather than a level, and **it is the one that usually
///     cannot speak**: see [ReorderEntry.lastsFor].
///
/// ## What this fold refuses to do
///
/// **It does not guess a speed from one pour.** The log was 1.6 KB after three weeks when this was written -- eight
/// events -- and a rate fitted to two pours a minute apart is a number, not evidence. So [ReorderEntry.lastsFor] is
/// null unless the pours span at least [shortestSpan] and there are at least [fewestPours] of them, and the horizon
/// rule simply does not fire when it is null. **A warning that cannot be trusted is worse than no warning**, which is
/// the same rule `liquid_visual.dart` follows when it draws an empty glass rather than a guessed colour.
final class ReorderList {
  const ReorderList._(this.entries, {required this.thresholds});

  /// Builds the list from the shelf and the log's own pours.
  ///
  /// **The pours are read from the events rather than from the ledger**, because the ledger keeps quantities and
  /// throws the clock readings away: `BottleState` has `added` and `remaining`, and neither says *when*. The events
  /// are the only place the times are, and a speed needs two of them.
  factory ReorderList.of({
    required StockLedger stock,
    required Iterable<Event> events,
    required ReorderPoint thresholds,
    Hlc? now,
  }) {
    final pours = PourHistory.of(events, now: now);
    final entries = <ReorderEntry>[];

    for (final bottle in stock.bottles) {
      final added = bottle.added.microlitres;
      final remaining = bottle.remaining.microlitres;
      // A bottle whose added volume is nothing cannot have a fraction, and a record like that is a defect rather
      // than a bottle. Skipped rather than divided by.
      if (added <= 0) continue;

      final fraction = remaining / added;
      final history = pours.of(bottle.bottleId);
      final reasons = <LowReason>{
        if (remaining * 100 <= added * thresholds.fillPercent) LowReason.nearlyEmpty,
        if (remaining <= thresholds.millilitres * 1000) LowReason.smallRemainder,
        if (history.lastsFor(remaining) case final lasts?
            when lasts <= Duration(days: thresholds.horizonDays))
          LowReason.runningOutSoon,
      };
      if (reasons.isEmpty) continue;

      entries.add(
        ReorderEntry(
          ingredientId: bottle.sku,
          bottleId: bottle.bottleId,
          added: bottle.added,
          remaining: bottle.remaining,
          fraction: fraction,
          lastsFor: history.lastsFor(remaining),
          reasons: reasons,
        ),
      );
    }

    // **Least left first**, so the top of the list is the thing to deal with tonight, and ties broken by id so that
    // two identical reads do not reshuffle -- the rule the shelf, the statistics fold and the shopping list all keep.
    entries.sort((a, b) {
      final byFraction = a.fraction.compareTo(b.fraction);
      if (byFraction != 0) return byFraction;
      final byRemaining = a.remaining.microlitres.compareTo(b.remaining.microlitres);
      if (byRemaining != 0) return byRemaining;
      return a.bottleId.compareTo(b.bottleId);
    });

    return ReorderList._(List.unmodifiable(entries), thresholds: thresholds);
  }

  final List<ReorderEntry> entries;

  /// The thresholds this list was built against, kept so that a screen can say what it was asked for rather than
  /// leaving a reader to guess why something is on the list.
  final ReorderPoint thresholds;

  bool get isEmpty => entries.isEmpty;

  /// The fewest pours a speed may be fitted to.
  static const fewestPours = 2;

  /// The shortest span those pours may cover.
  ///
  /// **A day, and the number is the point rather than a detail.** Under it, the speed is computed from a clock
  /// difference measured in minutes and comes out enormous -- which fires the horizon rule on every bottle a reader
  /// pours twice while unpacking their shopping. A day is short enough that a reader who has genuinely been drinking
  /// for a week gets an answer and long enough that an afternoon does not produce one.
  static const shortestSpan = Duration(days: 1);
}

/// What is low about a bottle, and there may be more than one answer.
enum LowReason {
  /// Under [ReorderPoint.fillPercent] of what the bottle held. Includes a bottle that has been finished.
  nearlyEmpty,

  /// Under [ReorderPoint.millilitres] left, whatever the bottle's size.
  smallRemainder,

  /// At the observed speed, it runs out within [ReorderPoint.horizonDays].
  runningOutSoon,
}

/// The three thresholds, as the reader has them.
///
/// **All three are always in force.** There is no mode that turns one off, because each one exists for a case the
/// others miss and a set of three switches would be three ways to build a list that quietly stops warning about
/// something. A reader who does not want one of them sets it to a value nothing reaches.
final class ReorderPoint {
  const ReorderPoint({
    this.fillPercent = 20,
    this.millilitres = 100,
    this.horizonDays = 30,
  });

  final int fillPercent;
  final int millilitres;
  final int horizonDays;

  static const ReorderPoint defaults = ReorderPoint();

  /// Whether these are the values a fresh cellar starts with.
  bool get isDefault => this == defaults;

  ReorderPoint copyWith({int? fillPercent, int? millilitres, int? horizonDays}) =>
      ReorderPoint(
        fillPercent: fillPercent ?? this.fillPercent,
        millilitres: millilitres ?? this.millilitres,
        horizonDays: horizonDays ?? this.horizonDays,
      );

  @override
  bool operator ==(Object other) =>
      other is ReorderPoint &&
      other.fillPercent == fillPercent &&
      other.millilitres == millilitres &&
      other.horizonDays == horizonDays;

  @override
  int get hashCode => Object.hash(fillPercent, millilitres, horizonDays);

  @override
  String toString() =>
      'ReorderPoint($fillPercent%, ${millilitres}ml, ${horizonDays}d)';
}

/// One bottle worth buying again.
final class ReorderEntry {
  const ReorderEntry({
    required this.ingredientId,
    required this.bottleId,
    required this.added,
    required this.remaining,
    required this.fraction,
    required this.lastsFor,
    required this.reasons,
  });

  /// The sku a recipe names and a bottle matches on.
  final String ingredientId;

  /// **Which bottle**, because a cellar may hold two of one thing and only one of them may be low. The ingredient id
  /// alone would make the list say *the gin is low* when one bottle is full.
  final String bottleId;

  final Volume added;
  final Volume remaining;

  /// What is left, as a fraction of what the bottle held. 1.0 is untouched, 0.0 is finished.
  final double fraction;

  /// **How long it lasts at the speed it has been going, or null when there is not enough evidence to say.**
  ///
  /// Null is the ordinary answer for a young cellar rather than a failure: a speed needs two pours a day apart, and
  /// the horizon rule cannot fire without one. A screen must therefore show the other two reasons rather than
  /// treating a missing speed as "not low".
  final Duration? lastsFor;

  final Set<LowReason> reasons;

  /// How much of the bottle is gone, for a screen that wants a bar rather than a fraction.
  double get drunk => 1 - fraction;

  @override
  String toString() =>
      'ReorderEntry($ingredientId $bottleId ${(fraction * 100).round()}%, $reasons)';
}

/// What one bottle's pours add up to.
final class BottlePours {
  const BottlePours({
    required this.count,
    this.first,
    this.last,
    required this.consumedMicrolitres,
  });

  /// A bottle nobody has poured from.
  static const none = BottlePours(count: 0, consumedMicrolitres: 0);

  final int count;

  /// **Nullable, and not for convenience.** A bottle with no pours has no first pour, and the first version stood a
  /// `Hlc(physicalMillis: 0, nodeId: '')` in for it -- which does not compile as a `const` at all, because `Hlc`'s
  /// own assert refuses a reading with no node id. The type was refusing a value the design had no business
  /// inventing: an epoch-zero clock reading is a real reading from a device that does not exist.
  final Hlc? first;
  final Hlc? last;
  final int consumedMicrolitres;

  /// How long [remainingMicrolitres] lasts at the speed these pours describe, or null.
  ///
  /// **Null in three cases and each of them is a refusal rather than a zero**: fewer than [ReorderList.fewestPours]
  /// pours (no speed exists), a span under [ReorderList.shortestSpan] (the speed would be an artefact of two events
  /// landing in the same minute), and nothing consumed (a division by zero that would read as "lasts for ever").
  Duration? lastsFor(int remainingMicrolitres) {
    final from = first;
    final to = last;
    if (count < ReorderList.fewestPours || from == null || to == null) return null;
    final spanMillis = to.physicalMillis - from.physicalMillis;
    if (spanMillis < ReorderList.shortestSpan.inMilliseconds) return null;
    if (consumedMicrolitres <= 0) return null;
    final perMilli = consumedMicrolitres / spanMillis;
    if (perMilli <= 0) return null;
    return Duration(milliseconds: (remainingMicrolitres / perMilli).round());
  }
}

/// Every bottle's pours, folded from the log once.
///
/// **Made once and asked per bottle**, because the alternative is scanning every event for every bottle and a cellar
/// with forty of them would scan the log forty times on one build.
final class PourHistory {
  const PourHistory(this._byBottle);

  final Map<String, BottlePours> _byBottle;

  static const PourHistory none = PourHistory(<String, BottlePours>{});

  /// An empty answer for a bottle nobody has poured from -- not null, so that a caller does not have to decide what
  /// a missing bottle means when the answer is the same as a bottle with no history.
  BottlePours of(String bottleId) => _byBottle[bottleId] ?? BottlePours.none;

  factory PourHistory.of(Iterable<Event> events, {Hlc? now}) {
    // Sorted by clock rather than read in file order, the rule every fold here keeps: a merged log holds a peer's
    // events interleaved with local ones, and "the first pour" has to mean the same thing on both devices.
    final ordered = events.toList()..sort((a, b) => a.hlc.compareTo(b.hlc));

    final first = <String, Hlc>{};
    final last = <String, Hlc>{};
    final count = <String, int>{};
    final consumed = <String, int>{};

    for (final event in ordered) {
      final op = StockOp.tryParse(event);
      // **Only pours, and not discards.** Watering a plant with the last of the vermouth is not evidence about how
      // fast the reader drinks vermouth, and counting it would make a bottle look like it was going faster than it
      // is exactly when it was thrown away.
      if (op is! BottleConsumed) continue;
      final id = op.bottleId;
      first.putIfAbsent(id, () => op.hlc);
      last[id] = op.hlc;
      count[id] = (count[id] ?? 0) + 1;
      consumed[id] = (consumed[id] ?? 0) + op.volume.microlitres;
    }

    return PourHistory({
      for (final id in count.keys)
        id: BottlePours(
          count: count[id]!,
          first: first[id]!,
          last: last[id]!,
          consumedMicrolitres: consumed[id]!,
        ),
    });
  }
}
