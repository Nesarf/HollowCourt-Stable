import 'package:flutter/material.dart';

import '../domain/consumption/consumption.dart';
import 'price_period.dart';
import 'theme.dart';

/// Section 12.3's consumption curve, drawn.
///
/// **Twin bars rather than a stack.** Stacking the two columns would draw their sum,
/// and the sum is exactly the reading this project went out of its way to avoid: a
/// broken bottle and a busy evening would look the same. Two bars side by side keep
/// them separable at a glance, which is the only thing the chart is for.
///
/// **The calendar is [PricePeriod]'s, and the name is a leftover.** The period type
/// was written for the price chart and is a period, not a price -- reusing it is
/// right and renaming it to `Period` is the honest follow-up, recorded here rather
/// than done, because a rename touches the price chart, its sheet and their tests and
/// is not what this screen needed today.
class ConsumptionChart extends StatelessWidget {
  const ConsumptionChart({super.key, required this.curve, required this.period});

  final ConsumptionCurve curve;
  final PricePeriod period;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 120,
    width: double.infinity,
    child: CustomPaint(painter: _CurvePainter(curve)),
  );
}

class _CurvePainter extends CustomPainter {
  _CurvePainter(this.curve);

  final ConsumptionCurve curve;

  @override
  void paint(Canvas canvas, Size size) {
    if (curve.buckets.isEmpty) return;

    // Scaled on the peak over BOTH columns, because a discarded bottle that drew
    // outside the plot would read as a rendering fault instead of as a fact.
    final peak = curve.peak.microlitres;
    if (peak <= 0) return;

    final slot = size.width / curve.buckets.length;
    // A gap between pairs, so two bars in one period are two bars rather than one
    // bar with a seam.
    final barWidth = (slot * 0.34).clamp(1.0, 14.0);
    final baseline = size.height;

    final drunk = Paint()..color = HollowPalette.gold;
    final discarded = Paint()..color = HollowPalette.absent;

    for (var i = 0; i < curve.buckets.length; i++) {
      final bucket = curve.buckets[i];
      final left = i * slot + slot / 2 - barWidth;
      _bar(canvas, drunk, left, baseline, barWidth,
          bucket.drunk.microlitres / peak * size.height);
      _bar(canvas, discarded, left + barWidth + 1, baseline, barWidth,
          bucket.discarded.microlitres / peak * size.height);
    }

    // The baseline last, so it is not overdrawn by a bar that reaches zero.
    canvas.drawLine(
      Offset(0, baseline),
      Offset(size.width, baseline),
      Paint()
        ..color = HollowPalette.hairline
        ..strokeWidth = 1,
    );
  }

  void _bar(Canvas canvas, Paint paint, double left, double baseline,
      double width, double height) {
    // A period with nothing in it draws nothing, rather than a one-pixel stub that
    // would be indistinguishable from a very small pour.
    if (height <= 0) return;
    final h = height.clamp(1.0, baseline);
    canvas.drawRect(
      Rect.fromLTWH(left, baseline - h, width, h),
      paint,
    );
  }

  @override
  bool shouldRepaint(_CurvePainter old) =>
      old.curve.buckets.length != curve.buckets.length ||
      old.curve.peak != curve.peak;
}
