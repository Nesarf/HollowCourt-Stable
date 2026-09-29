import 'l10n/dual_copy.dart';
import 'theme.dart';

/// How much time one candle covers, and **where the calendar lives**.
///
/// **This file is in the UI layer on purpose.** `ohlc.dart` was written to take a width
/// in milliseconds and to keep time zones out of the domain, and a calendar month cannot
/// be a width -- months run 28 to 31 days, so every constant is wrong for part of the
/// year. `candlesBy` therefore takes a boundary *function*, and the reader's calendar is
/// supplied from here, where the reader's locale already is. A domain layer that did this
/// arithmetic would have to pick a zone, and picking one is the decision that belongs
/// above it.
///
/// **All three periods cut on the local calendar, including the fixed ones.** Aligning a
/// day to the UTC epoch is the obvious thing and it is quietly wrong: at UTC+8 a purchase
/// at two in the morning belongs to the previous UTC day, so the candle it lands in is not
/// the day the person remembers buying it. The same mistake a day-widening shortcut makes
/// is the one a month-width shortcut makes, one order of magnitude smaller.
enum PricePeriod {
  day,
  week,
  month;

  /// How many candles the chart keeps. Roughly a screen's worth at each density, so that
  /// switching period changes the resolution rather than the amount of history shown.
  int get windowCandles => switch (this) {
    PricePeriod.day => 120,
    PricePeriod.week => 160,
    PricePeriod.month => 120,
  };

  CopyLine get label => switch (this) {
    PricePeriod.day => Copy.periodDay,
    PricePeriod.week => Copy.periodWeek,
    PricePeriod.month => Copy.periodMonth,
  };

  /// Which period an instant belongs to, as one integer that must increase with time.
  ///
  /// The contract `candlesBy` states: the fold emits a candle whenever this changes, so a
  /// function that went backwards would produce one candle per observation. Every branch
  /// below is built from a UTC midnight of the *local* date, which is monotonic even
  /// across a daylight-saving shift -- where the local midnight itself is not.
  int bucketOf(int millis) {
    final local = DateTime.fromMillisecondsSinceEpoch(millis);
    final midnight = DateTime.utc(local.year, local.month, local.day);
    final dayIndex = midnight.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;

    return switch (this) {
      // A week is seven of those days, anchored to the epoch's Thursday. Anchoring to a
      // Monday would be a locale decision, and the reader's week start is not something
      // this build has asked them yet.
      PricePeriod.day => dayIndex,
      PricePeriod.week => dayIndex ~/ 7,
      PricePeriod.month => local.year * 12 + local.month - 1,
    };
  }
}
