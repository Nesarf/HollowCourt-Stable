import '../units/rational.dart';
import 'price.dart';

/// The four spans the bar's takings are looked at over.
///
/// **Fixed spans rather than a date picker**, because these are the four questions a bar actually asks: what
/// happened tonight, this week, this month, this quarter. A picker would be more general and would make the
/// common question take three taps.
enum CashflowWindow {
  today('today', 1),
  week('week', 7),
  month('month', 30),
  quarter('quarter', 90);

  const CashflowWindow(this.name, this.days);

  final String name;
  final int days;

  /// The first instant the window covers, counted back from [now].
  ///
  /// **Calendar days, not 24-hour blocks.** "Today" means since midnight, which is what a person means by it;
  /// subtracting one day from the current time would make the morning's takings vanish at lunchtime.
  DateTime startFrom(DateTime now) {
    final midnight = DateTime(now.year, now.month, now.day);
    return midnight.subtract(Duration(days: days - 1));
  }
}

/// One amount that moved, as the fold needs to see it.
///
/// Deliberately smaller than the event it comes from: a cashflow only needs to know what, how much, and when.
/// Keeping it this way means the arithmetic can be tested without an event log, a clock or a sync layer.
final class CashflowEntry {
  const CashflowEntry({
    required this.minorUnits,
    required this.currency,
    required this.at,
    this.label,
  });

  final int minorUnits;
  final Currency currency;
  final DateTime at;

  /// What it was for -- an ingredient, or a recipe. Carried so a gap can be *named* rather than counted.
  final String? label;
}

/// What the bar took and what it spent in one window, and what could not be counted.
final class Cashflow {
  const Cashflow({
    required this.window,
    required this.from,
    required this.until,
    required this.currency,
    required this.income,
    required this.expense,
    required this.unattributed,
  });

  final CashflowWindow window;
  final DateTime from;
  final DateTime until;

  /// Null when nothing in the window carried a currency, which is different from a balance of zero.
  final Currency? currency;

  final Money income;
  final Money expense;

  /// Money that moved in a currency other than the window's, or without a price to attribute.
  ///
  /// **Named, not folded in.** The same rule the recipe costing follows: a figure that silently drops or silently
  /// absorbs a line it could not understand is worse than no figure, because somebody will make a decision on it.
  final List<String> unattributed;

  Money get net => income - expense;

  /// Income as a fraction of expense -- how many times over the bar paid for what it sold. Null when nothing was
  /// spent, because "infinitely profitable" is not an answer.
  Rational? get cover => expense.isZero ? null : income.toRational() * Rational.of(1, expense.minorUnits);
}

/// Folds [income] and [expense] entries into a window ending at [now].
///
/// **Income is a separate list because the application has no way to record it yet.** Nothing in the event log
/// says a drink was *sold* -- `BottleConsumed` says a bottle is lighter, which is a fact about stock and not about
/// money. So the income side is a parameter rather than something this fold can find, and callers pass an empty
/// list until sales exist. That is stated here rather than hidden, because a takings screen that quietly counts
/// nothing as income would show a bar that only ever loses money.
Cashflow cashflowOf({
  required CashflowWindow window,
  required DateTime now,
  Iterable<CashflowEntry> expense = const [],
  Iterable<CashflowEntry> income = const [],
}) {
  final from = window.startFrom(now);
  final until = now;
  final unattributed = <String>[];

  bool inWindow(CashflowEntry entry) =>
      !entry.at.isBefore(from) && !entry.at.isAfter(until);

  Currency? currency;
  for (final entry in [...expense, ...income]) {
    if (!inWindow(entry)) continue;
    if (currency == null) {
      currency = entry.currency;
    } else if (entry.currency != currency) {
      unattributed.add(entry.label ?? entry.currency.code);
    }
  }

  var incomeMinor = 0;
  var expenseMinor = 0;
  for (final entry in expense) {
    if (!inWindow(entry)) continue;
    if (currency == null || entry.currency != currency) continue;
    expenseMinor += entry.minorUnits;
  }
  for (final entry in income) {
    if (!inWindow(entry)) continue;
    if (currency == null || entry.currency != currency) continue;
    incomeMinor += entry.minorUnits;
  }

  return Cashflow(
    window: window,
    from: from,
    until: until,
    // **The field gets the fallback as well as the amounts.** A screen should never have to answer "which
    // currency is this zero in" with "none" -- an empty window is a zero of some denomination, not a null.
    currency: currency ?? _fallback,
    income: Money.fromMinorUnits(incomeMinor, currency ?? _fallback),
    expense: Money.fromMinorUnits(expenseMinor, currency ?? _fallback),
    unattributed: unattributed,
  );
}

/// Used only when a window is empty of everything with a currency, so that a screen has a zero of *some*
/// denomination to draw rather than a null it has to special-case everywhere.
const Currency _fallback = Currency('XXX', 2);

/// The bar's own money, and what the events say should be in it.
///
/// **The comparison is the point of the deposit.** A reader counts the till and enters what is there; this says
/// what the log implies should be there. The difference is either takings nobody recorded, a purchase nobody
/// entered, or a mistake -- and the application's job is to show the difference, not to decide which.
final class CashReconciliation {
  const CashReconciliation({required this.deposit, required this.implied, required this.counted});

  /// What the reader said the bar started with. Stored, not derived.
  final Money deposit;

  /// Deposit plus income minus expense, over the window.
  final Money implied;

  /// What the reader actually counted, when they have said. Null means the comparison has not been made.
  final Money? counted;

  /// How far the till is from the log, or null when nothing was counted. Positive means more money than the
  /// events explain, which usually means a sale nobody recorded.
  Money? get difference => counted == null ? null : counted! - implied;

  bool get balances => difference?.isZero ?? false;
}
