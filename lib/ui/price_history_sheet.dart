import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/pricing/ohlc.dart';
import '../domain/pricing/price.dart';
import '../domain/units/rational.dart';
import 'library.dart';
import 'l10n/dual_copy.dart';
import 'l10n/dual_copy_text.dart';
import 'money_text.dart';
import 'price_chart.dart';
import 'price_period.dart';
import 'theme.dart';

/// One ingredient's price over time, and what it means for a glass.
///
/// **This is where section 7 becomes something a person can look at.** The series, the
/// fold and the candles are all domain work with tests behind them; a sheet is what
/// turns them into an answer to "has this got more expensive".
///
/// **The chart is per ingredient and the sheet is opened from a bottle**, which is the
/// join section 12.3 describes when it puts prices on the Stock tab: a bottle carries a
/// sku, a price is about a sku, and tapping the bottle is how somebody asks about it.
///
/// **The period is a choice and the chart is redrawn from the same observations.** Nothing
/// is stored per period: a candle is a fold of the observations over a different boundary,
/// so switching from day to month loses no resolution and can be switched back. That is
/// only true because the boundary is applied at read time, which is why [PricePeriod]
/// supplies a function rather than the series holding candles.
Future<void> showPriceHistory(
  BuildContext context, {
  required String sku,
  required String name,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: HollowPalette.surface,
  builder: (_) => PriceHistorySheet(sku: sku, name: name),
);

class PriceHistorySheet extends ConsumerStatefulWidget {
  const PriceHistorySheet({super.key, required this.sku, required this.name});

  final String sku;
  final String name;

  @override
  ConsumerState<PriceHistorySheet> createState() => _PriceHistorySheetState();
}

class _PriceHistorySheetState extends ConsumerState<PriceHistorySheet> {
  /// Days first, because that is the resolution a person means when they ask whether
  /// something got more expensive this week.
  PricePeriod _period = PricePeriod.day;

  @override
  Widget build(BuildContext context) {
    final series = ref.watch(priceSeriesForProvider(widget.sku));
    final insets = MediaQuery.viewInsetsOf(context);
    final systemPadding = MediaQuery.paddingOf(context);

    // Already exact: the candles keep their Rationals and the one conversion to a double
    // happens inside the painter, where a pixel is finally wanted.
    final candles = series.usable.isEmpty
        ? const <PriceCandle>[]
        : candlesBy(series, bucketOf: _period.bucketOf);

    final latest = series.perMicrolitre;
    final perGlass = series.costOf(standardPour);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + insets.bottom + systemPadding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.name, style: HollowType.title),
          const SizedBox(height: 2),
          Text(widget.sku, style: HollowType.caption),
          const SizedBox(height: 14),
          DualCopyText(Copy.priceHistory, style: HollowType.heading),
          const SizedBox(height: 10),
          if (candles.isEmpty)
            // **The chart still draws**, as a bare baseline, and the sentence beside it
            // says which of the two silences this is. A blank box would leave a person
            // unable to tell "no prices yet" from "the chart broke". The period control
            // is absent because there is nothing to re-resolve into.
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PriceChart(candles: <PriceCandle>[], height: 96),
                const SizedBox(height: 10),
                DualCopyText(Copy.priceNone, style: HollowType.caption),
              ],
            )
          else ...[
            PriceChart(candles: _windowed(candles)),
            const SizedBox(height: 12),
            SegmentedButton<PricePeriod>(
              segments: [
                for (final period in PricePeriod.values)
                  ButtonSegment<PricePeriod>(
                    value: period,
                    // A segmented button has one line per option, so the pair cannot be
                    // drawn here -- the same wall as the four tab labels and the add
                    // button, and it says which reason rather than passing `false`.
                    label: Text(
                      period.label
                          .present(
                            dualCopy: ref.watch(dualCopyProvider),
                            roomForSecondary: false,
                          )
                          .primary,
                    ),
                  ),
              ],
              selected: <PricePeriod>{_period},
              showSelectedIcon: false,
              onSelectionChanged: (selection) =>
                  setState(() => _period = selection.first),
            ),
            const SizedBox(height: 14),
            _Reading(
              label: Copy.priceLatest,
              // A unit price and not a bottle total, because the two observations it
              // may be comparing were not the same size. `PricePoint.perMicrolitre` is
              // the only figure in a price series that is comparable across purchases.
              value: latest == null ? '—' : _perLitre(latest),
              emphasis: true,
            ),
            const SizedBox(height: 6),
            _Reading(
              label: Copy.pricePerGlass,
              value: perGlass == null ? '—' : moneyText(perGlass),
              // The pour is shown as a number beside the label rather than inside a
              // translated sentence, so that changing `standardPour` cannot leave a
              // string lying about it in fourteen locales.
              note: '${standardPour.microlitres ~/ 1000} ml',
            ),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  /// The tail of the series, so a cellar recorded over years does not squeeze today into
  /// a single pixel. The window is in candles rather than in days, so that changing the
  /// period changes the resolution instead of the amount of history on screen.
  List<PriceCandle> _windowed(List<PriceCandle> candles) {
    final window = _period.windowCandles;
    if (candles.length <= window) return candles;
    return candles.sublist(candles.length - window);
  }

  static String _perLitre(Rational perMicrolitre) {
    // A litre is a million microlitres, so this is exact arithmetic and one rounding.
    final perLitre = (perMicrolitre * Rational.fromInt(1000000)).toDouble();
    return '${perLitre.toStringAsFixed(2)} / L';
  }
}

class _Reading extends StatelessWidget {
  const _Reading({
    required this.label,
    required this.value,
    this.note,
    this.emphasis = false,
  });

  final CopyLine label;
  final String value;
  final String? note;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(child: DualCopyText(label, style: HollowType.caption)),
        Text(
          value,
          style: emphasis
              ? HollowType.numeric.copyWith(color: HollowPalette.gold)
              : HollowType.numeric,
        ),
        if (note != null) ...[
          const SizedBox(width: 6),
          Text(note!, style: HollowType.caption),
        ],
      ],
    );
  }
}
