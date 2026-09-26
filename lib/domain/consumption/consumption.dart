import '../events/event.dart';
import '../events/stock.dart';
import '../units/quantity.dart';

/// Section 12.3's consumption curve, folded from the same log as everything else.
///
/// **Two columns, and they are never added together here.** The stock event family
/// already separates a pour from a bottle that was broken, poured away or given
/// away, and says why: both reduce the stock, but only one of them was a drink, and
/// *a consumption curve that cannot tell them apart is not a consumption curve*. So
/// a bucket holds [drunk] and [discarded], and [ConsumptionBucket.total] exists but
/// is a named choice a caller has to make rather than the default reading.
///
/// **Nothing here is a `double`.** A volume is whole microlitres from end to end,
/// exactly as the rest of the quantity family is; turning litres into a pixel is the
/// chart's last step and not this layer's business.
///
/// **Time zones are deliberately absent**, for the reason `ohlc.dart` gives: a bucket
/// is cut by calling [bucketOf] on `Hlc.physicalMillis`, and the caller owns the
/// calendar. A domain that hardcoded a day as 86400000 would be silently wrong twice
/// a year in any zone with daylight saving, and it would be wrong in a way that a
/// curve cannot show.
final class ConsumptionCurve {
  const ConsumptionCurve._(
    this._buckets, {
    required int pours,
    required int discards,
    required int ignoredVolume,
    required int ignoredType,
  }) : pourEvents = pours,
       discardEvents = discards,
       ignoredVolumeEvents = ignoredVolume,
       ignoredTypeEvents = ignoredType;

  /// Folds a log into a curve.
  ///
  /// Buckets are **filled in across the whole span**, including the empty ones. A
  /// run with nothing in it and a run that was never measured are different
  /// readings, and a chart that closed the gap would draw them the same way. The
  /// same distinction `ohlc_test` records when it insists a flat period still has a
  /// candle.
  factory ConsumptionCurve.of(
    Iterable<Event> events, {
    required int Function(int millis) bucketOf,
  }) {
    final drunk = <int, Volume>{};
    final discarded = <int, Volume>{};
    final pours = <int, int>{};
    final discards = <int, int>{};
    var ignoredVolume = 0;
    var ignoredType = 0;

    for (final event in events) {
      final isPour = event.type == StockEvent.bottleConsumed;
      final isDiscard = event.type == StockEvent.bottleDiscarded;
      if (!isPour && !isDiscard) {
        ignoredType++;
        continue;
      }
      final microlitres = event.optional<int>('volumeMicrolitres');
      // A pour of nothing is a no-op, and a negative one is a defect. Neither is
      // a quantity and neither is added; both are counted so that a log which
      // contains them can be seen to contain them.
      if (microlitres == null || microlitres <= 0) {
        ignoredVolume++;
        continue;
      }
      final key = bucketOf(event.hlc.physicalMillis);
      final volume = Volume.fromMicrolitres(microlitres);
      if (isPour) {
        drunk[key] = (drunk[key] ?? Volume.zero) + volume;
        pours[key] = (pours[key] ?? 0) + 1;
      } else {
        discarded[key] = (discarded[key] ?? Volume.zero) + volume;
        discards[key] = (discards[key] ?? 0) + 1;
      }
    }

    final keys = {...drunk.keys, ...discarded.keys}.toList()..sort();
    final buckets = <ConsumptionBucket>[];
    if (keys.isNotEmpty) {
      // One bucket after the last one is not added: the span is the span of what
      // happened, and inventing a trailing empty period would make every curve end
      // in a fall to zero.
      for (var key = keys.first; key <= keys.last; key++) {
        buckets.add(
          ConsumptionBucket(
            bucket: key,
            drunk: drunk[key] ?? Volume.zero,
            discarded: discarded[key] ?? Volume.zero,
            pours: pours[key] ?? 0,
            discards: discards[key] ?? 0,
          ),
        );
      }
    }

    return ConsumptionCurve._(
      List.unmodifiable(buckets),
      pours: pours.values.fold(0, (a, b) => a + b),
      discards: discards.values.fold(0, (a, b) => a + b),
      ignoredVolume: ignoredVolume,
      ignoredType: ignoredType,
    );
  }

  final List<ConsumptionBucket> _buckets;

  /// Every bucket from the first with something in it to the last, gaps included.
  List<ConsumptionBucket> get buckets => _buckets;

  /// How many pour events were folded.
  final int pourEvents;

  /// How many discard events were folded.
  final int discardEvents;

  /// Events of this family whose volume was missing, zero or negative.
  final int ignoredVolumeEvents;

  /// Events of other families, which this fold does not reduce.
  final int ignoredTypeEvents;

  /// Everything poured into drinks, summed.
  Volume get drunkTotal =>
      _buckets.fold(Volume.zero, (sum, b) => sum + b.drunk);

  /// Everything that left without being drunk, summed.
  Volume get discardedTotal =>
      _buckets.fold(Volume.zero, (sum, b) => sum + b.discarded);

  /// True when nothing was drunk.
  ///
  /// **Deliberately not "the curve is empty".** A cellar where everything was
  /// discarded has a curve and has no drinks in it, and a screen that treated the
  /// two as one state would say nothing has happened.
  bool get hasNoDrinks => _buckets.every((b) => b.drunk.isZero);

  /// True when the log holds no consumption at all.
  bool get isEmpty => _buckets.isEmpty;

  /// The largest single-column figure, for scaling a chart.
  ///
  /// Taken over both columns rather than over the drinks alone, so that a discarded
  /// bottle cannot draw outside the plot.
  Volume get peak {
    var high = Volume.zero;
    for (final bucket in _buckets) {
      if (bucket.drunk > high) high = bucket.drunk;
      if (bucket.discarded > high) high = bucket.discarded;
    }
    return high;
  }
}

/// One period's consumption.
final class ConsumptionBucket {
  const ConsumptionBucket({
    required this.bucket,
    required this.drunk,
    required this.discarded,
    required this.pours,
    required this.discards,
  });

  /// The bucket index [ConsumptionCurve.of]'s `bucketOf` produced.
  ///
  /// An opaque integer: this layer does not know whether it counts days, weeks or
  /// something else, which is what lets the caller cut on a local midnight.
  final int bucket;

  /// Poured into drinks.
  final Volume drunk;

  /// Left the cellar without being drunk.
  final Volume discarded;

  final int pours;
  final int discards;

  /// Both columns added.
  ///
  /// A named choice rather than the default reading. It is the right number for
  /// "how much left the cellar" and the wrong one for "how much was drunk", and the
  /// two questions look identical on a screen that shows only this.
  Volume get total => drunk + discarded;

  /// Nothing happened in this period.
  bool get isEmpty => drunk.isZero && discarded.isZero;

  @override
  String toString() =>
      'ConsumptionBucket($bucket: ${drunk.microlitres} in drinks, '
      '${discarded.microlitres} discarded)';
}
