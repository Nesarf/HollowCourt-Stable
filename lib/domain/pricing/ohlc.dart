/// Section 7's time series, folded into candles.
///
/// **A candle is what a price series looks like when it is asked about a period
/// rather than about a moment.** Section 7's `Change` compares the first observation
/// with the last and answers one question; a candle answers the same question per
/// period, which is what makes a run of them readable as a chart rather than as a
/// single number.
///
/// **The candle carries a rate and not a total, and that is the whole design.** Two
/// observations in one bucket may be a 700 ml bottle and a 50 ml miniature; their
/// `paid` amounts are not comparable and their difference is meaningless, while their
/// prices per microlitre are exactly comparable. So [PriceCandle] holds
/// `price per microlitre`, taken from [PricePoint.perMicrolitre], and an open of
/// 0.002 against a close of 0.0025 means what a person reading a chart expects it to
/// mean. A candle built from totals would show a spike every time somebody bought a
/// bigger bottle, and no screen could tell that from a real price move.
///
/// **Nothing here is a `double`.** Open, high, low and close are [Rational], because
/// they are still quantities and the conversion to a pixel is the caller's last step.
/// `rational.dart` is explicit that [Rational.toDouble] is for showing a number to a
/// person and for nothing else; a chart is exactly that place, and it is the only one
/// in this file.
///
/// **Time zones are deliberately absent.** A bucket is cut by integer arithmetic on
/// `Hlc.physicalMillis`, and the caller supplies the width and the alignment. The
/// domain layer has no business knowing when local midnight is -- that is a display
/// fact, section 3 keeps display facts in the UI layer, and a domain that hardcoded a
/// day as 86400000 would be silently wrong twice a year in any zone with daylight
/// saving.
library;

import '../events/hlc.dart';
import '../units/rational.dart';
import 'price.dart';

/// One period's opening price, highest, lowest and closing price.
final class PriceCandle {
  const PriceCandle({
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.observations,
    required this.openHlc,
    required this.closeHlc,
  });

  /// The first observation's rate in the period.
  final Rational open;

  /// The highest rate in the period.
  final Rational high;

  /// The lowest rate in the period.
  final Rational low;

  /// The last observation's rate in the period.
  final Rational close;

  /// How many observations the period actually contains, so a one-point candle can be
  /// drawn or described differently from a settled one.
  final int observations;

  final Hlc openHlc;
  final Hlc closeHlc;

  /// Which way the period went, which is the only thing a candle's colour means.
  ///
  /// Undirected rather than "rising when not falling": a period that opened and closed
  /// at the same rate is neither, and a chart that painted it green would be claiming a
  /// movement that did not happen. The same distinction `PriceChange.isUnchanged`
  /// makes one layer up.
  bool get isRising => close > open;
  bool get isFalling => close < open;
  bool get isFlat => close == open;

  /// Close minus open, exact. Negative when the period got cheaper.
  Rational get change => close - open;

  /// High minus low: how much the period moved, which is what the candle's height
  /// draws.
  Rational get range => high - low;

  @override
  String toString() =>
      'PriceCandle($open/$high/$low/$close x$observations)';
}

/// Cuts [series] into candles of [widthMillis], oldest first.
///
/// Only observations that can be divided by take part: [PriceSeries.usable] is the
/// input, because a purchase with no recorded volume has no rate and a bucket
/// containing one would otherwise have to invent a number for it. Such an observation
/// is still a fact and is still in the series -- it is simply not a price *movement*.
///
/// [alignMillis] shifts where the buckets are cut, so a caller in a zone at UTC+8 can
/// align them to its own midnight by passing its offset. The default cuts on the epoch,
/// which is a defensible answer and not a claim about anybody's clock.
///
/// A trailing partial period is included, and [PriceCandle.observations] is how a
/// caller finds out that it is partial -- dropping it would hide the most recent price,
/// which is the one a person is looking at the chart for.
List<PriceCandle> candlesOf(
  PriceSeries series, {
  required int widthMillis,
  int alignMillis = 0,
}) {
  if (widthMillis <= 0) {
    throw ArgumentError.value(widthMillis, 'widthMillis', 'a period has to have a width');
  }
  return _candles(
    series,
    (int millis) => _bucketOf(millis, widthMillis, alignMillis),
  );
}

/// Cuts [series] into candles using a caller-supplied period boundary.
///
/// **This is the general form, and it exists because a calendar month is not a width.**
/// [candlesOf] takes a number of milliseconds, which is right for a day and a week and
/// cannot express "January": months vary between 28 and 31 days, so no constant is
/// correct and any constant chosen would be wrong for one twelfth of the year while
/// looking entirely plausible on a chart.
///
/// A boundary function can express it, and it also answers the question [candlesOf]'s
/// docstring raises -- where the time zone lives. It stays with the **caller**: the
/// domain asks only "which period does this instant belong to", and a UI layer that
/// already knows the reader's locale answers with its own calendar. A domain that did the
/// calendar arithmetic itself would have to pick a zone, and picking one is exactly the
/// decision that belongs above it.
///
/// The function must be monotonic in `millis`: the fold emits a candle whenever the
/// returned value changes, and a boundary that went backwards would produce a candle per
/// observation. Nothing here can check that, so it is stated as a contract.
List<PriceCandle> candlesBy(
  PriceSeries series, {
  required int Function(int millis) bucketOf,
}) => _candles(series, bucketOf);

List<PriceCandle> _candles(
  PriceSeries series,
  int Function(int millis) bucketOf,
) {
  // Refused at the door rather than partitioned or silently truncated, which is the
  // same move `Money.+` makes when two currencies meet and `Rational` makes on a zero
  // denominator. A candle of two currencies is not a candle that is slightly off; it is
  // a shape drawn from numbers that were never comparable, and nothing about the
  // drawing would say so.
  if (!series.isSingleCurrency) {
    throw ArgumentError.value(
      series.currency?.code,
      'series',
      'a candle cannot compare two currencies: total them separately, or convert first',
    );
  }

  final candles = <PriceCandle>[];
  Rational? open;
  Rational? high;
  Rational? low;
  Rational? close;
  Hlc? openHlc;
  Hlc? closeHlc;
  var observations = 0;
  int? bucket;

  void flush() {
    if (observations == 0) return;
    candles.add(
      PriceCandle(
        open: open!,
        high: high!,
        low: low!,
        close: close!,
        observations: observations,
        openHlc: openHlc!,
        closeHlc: closeHlc!,
      ),
    );
  }

  for (final point in series.usable) {
    final index = bucketOf(point.hlc.physicalMillis);
    if (bucket != index) {
      flush();
      bucket = index;
      open = null;
      high = null;
      low = null;
      close = null;
      // Both clock readings have to be cleared, and forgetting `openHlc` here is a
      // mistake that looks like success: every price in the candle stays correct while
      // every candle claims to have opened at the first observation ever seen. A chart
      // that places candles by their opening time then draws them all at one x, and
      // nothing in the numbers above says so.
      openHlc = null;
      closeHlc = null;
      observations = 0;
    }

    final rate = point.perMicrolitre;
    open ??= rate;
    openHlc ??= point.hlc;
    // `high == null ||` on the first observation of a bucket, because a rate of zero
    // is a legitimate price and `rate > high!` would throw before high was set.
    high = (high == null || rate > high) ? rate : high;
    low = (low == null || rate < low) ? rate : low;
    close = rate;
    closeHlc = point.hlc;
    observations++;
  }
  flush();

  return List<PriceCandle>.unmodifiable(candles);
}

int _bucketOf(int millis, int width, int align) {
  final shifted = millis - align;
  // Floor division rather than `~/`, which truncates toward zero: an observation
  // before the alignment point must land in the bucket before it, not in bucket zero
  // beside the ones after it. Timestamps are positive today, and this is cheaper than
  // being wrong the first time a device reports a clock it has not synced.
  return (shifted >= 0 ? shifted ~/ width : -((-shifted + width - 1) ~/ width));
}
