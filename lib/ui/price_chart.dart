import 'package:flutter/material.dart';

import '../domain/pricing/ohlc.dart';
import '../domain/units/rational.dart';
import 'theme.dart';

/// A run of [PriceCandle]s, drawn as a candlestick chart.
///
/// **The one place a price becomes a `double`.** `rational.dart` says `toDouble` is
/// "for showing a number to a person and for nothing else", and a chart is precisely
/// that: a pixel is not a quantity, and nothing downstream of here computes with the
/// result. So [Rational.toDouble] is called in the painter and nowhere else, and the
/// candles that arrive are still exact.
///
/// **Colour is the project's own vocabulary rather than a charting convention.** The
/// palette already means something -- `dual_copy_text.dart` writes that "a rose error
/// line and a gold verdict keep their colour in the second language" -- so a rise is
/// [HollowPalette.gold] and a fall is [HollowPalette.rose], and a period that opened
/// and closed alike is [HollowPalette.inkFaint] rather than green. Painting a flat
/// period green would claim a movement that did not happen.
///
/// **An empty chart draws a baseline and no text.** Section 12.4's rule is that a
/// string a person reads is a `CopyLine` and goes through the dual-copy machinery, so
/// inventing an empty-state sentence inside a painter would put unwritten copy in the
/// wrong layer. The caller owns the words; this widget owns the marks.
class PriceChart extends StatelessWidget {
  const PriceChart({
    super.key,
    required this.candles,
    this.height = 168,
  });

  /// Oldest first, as [candlesOf] returns them.
  final List<PriceCandle> candles;

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _CandlePainter(candles),
        // The chart is a picture of numbers that are already on the screen beside it,
        // so it carries no semantics of its own; a screen reader gets the values from
        // the text, not from a description of a drawing.
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _CandlePainter extends CustomPainter {
  _CandlePainter(this.candles);

  final List<PriceCandle> candles;

  static const double _pad = 6;

  @override
  void paint(Canvas canvas, Size size) {
    final baseline = Paint()
      ..color = HollowPalette.hairline
      ..strokeWidth = 1;

    if (candles.isEmpty || size.height <= _pad * 2 || size.width <= _pad * 2) {
      // Nothing to plot. A line where the data would have been, rather than a blank
      // box, so "no prices recorded" and "the chart failed to draw" do not look alike.
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        baseline,
      );
      return;
    }

    // The band is taken from the wicks and not from the bodies: a chart scaled to the
    // open/close range alone would draw every wick off the top and bottom of the box.
    var lowest = candles.first.low.toDouble();
    var highest = candles.first.high.toDouble();
    for (final candle in candles) {
      final low = candle.low.toDouble();
      final high = candle.high.toDouble();
      if (low < lowest) lowest = low;
      if (high > highest) highest = high;
    }

    // A single price, or a series where nothing moved, gives a band of zero height and
    // a division by zero on the way to a pixel. Widening it to the value's own size
    // (with a floor, so a price of zero does not produce a zero band) draws that series
    // as the flat line it is instead of as a crash.
    var span = highest - lowest;
    if (span <= 0) {
      final magnitude = highest.abs() > 0 ? highest.abs() : 1.0;
      span = magnitude * 0.02;
      lowest -= span / 2;
      highest += span / 2;
      span = highest - lowest;
    }

    final usableHeight = size.height - _pad * 2;
    double yFor(double value) =>
        _pad + usableHeight * (1 - (value - lowest) / span);

    final slot = size.width / candles.length;
    // A body has to stay visible when it is thin; a candle with no width reads as
    // missing data rather than as a small move.
    final bodyWidth = (slot * 0.62).clamp(1.5, 26.0);

    for (var i = 0; i < candles.length; i++) {
      final candle = candles[i];
      final colour = candle.isRising
          ? HollowPalette.gold
          : candle.isFalling
              ? HollowPalette.rose
              : HollowPalette.inkFaint;
      final centre = slot * (i + 0.5);
      final open = yFor(candle.open.toDouble());
      final close = yFor(candle.close.toDouble());

      final wick = Paint()
        ..color = colour.withValues(alpha: 0.75)
        ..strokeWidth = 1;
      canvas.drawLine(
        Offset(centre, yFor(candle.high.toDouble())),
        Offset(centre, yFor(candle.low.toDouble())),
        wick,
      );

      final body = Paint()..color = colour;
      final top = open < close ? open : close;
      final bottom = open < close ? close : open;
      // A doji: open and close are the same price, so the rectangle has no height and
      // would draw nothing at all. One pixel is the smallest visible statement that a
      // period exists and did not move.
      final bodyHeight = (bottom - top) < 1 ? 1.0 : bottom - top;
      canvas.drawRect(
        Rect.fromLTWH(centre - bodyWidth / 2, top, bodyWidth, bodyHeight),
        body,
      );
    }
  }

  @override
  bool shouldRepaint(_CandlePainter old) =>
      old.candles.length != candles.length ||
      // Identity is enough for the elements: a new series is a new list of candles, and
      // comparing every Rational in every candle on every frame would cost more than
      // the redraw it avoids.
      (candles.isNotEmpty && old.candles.isNotEmpty && !identical(old.candles.first, candles.first)) ||
      !identical(old.candles.lastOrNull, candles.lastOrNull);
}
