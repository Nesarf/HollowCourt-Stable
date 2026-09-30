import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/events/price.dart';
import '../domain/pricing/cashflow.dart';
import '../domain/pricing/price.dart';
import 'library.dart';
import 'preferences_providers.dart';

/// The four windows' takings, folded from the log the rest of the screen is already reading.
///
/// **This is the fold `cashflow.dart` has been waiting for since it was written.** The domain has carried four
/// windows, the arithmetic, the unattributed list and `CashReconciliation` with ten tests behind them, and no
/// screen read any of it -- see `docs/TODO.md` section 十, which recorded that the feature's problem was never
/// its behaviour but where it belonged. It belongs on 记录: that screen's headline facts are already the
/// reader's money, and the shelf that used to sit in this slot is off the interface.
///
/// **Income is empty, and that is a finding rather than a shortcut.** Nothing in the event log says a drink was
/// *sold*: `BottleConsumed` records that a bottle is lighter, which is a fact about stock, not about money, and
/// there is no event that records taking payment. `cashflowOf` takes income as a parameter precisely so this
/// could be honest about it, and its own comment says why it matters -- *a takings screen that quietly counts
/// nothing as income would show a bar that only ever loses money*. The view states the gap in words rather than
/// drawing a zero that reads as an answer.
///
/// **A retracted price is still an expense.** `priceSeriesOf` subtracts withdrawn purchases, because a chart of
/// what a bottle cost must not count one that was entered by mistake. Cash is not the same question: money that
/// left the account left it whether or not the line was later removed, and a total that shrank when a mistyped
/// line was corrected would be a worse lie than the one the retraction was fixing. So the two folds read the
/// same log and disagree on purpose, and this comment is here because that disagreement looks like a bug.
final cashflowsProvider = Provider<AsyncValue<List<Cashflow>>>((ref) {
  final cellar = ref.watch(cellarProvider);
  // **Loading and empty are different answers and the type says so.** The log is opened asynchronously, so the
  // first frame has no cellar at all; folding that into four zero-filled windows draws "nothing was spent" --
  // a false statement about the reader's money, held for exactly one frame, which is long enough to be seen and
  // never long enough to be reported. The loading state travels out to the screen instead.
  return cellar.when(
    loading: () => const AsyncValue.loading(),
    error: (error, stack) => AsyncValue.error(error, stack),
    data: (cellar) => AsyncValue.data(_fold(cellar, DateTime.now())),
  );
});

List<Cashflow> _fold(Cellar cellar, DateTime now) {
  final expenses = <CashflowEntry>[];
  for (final event in cellar.log.events) {
    // **`PriceOp.tryParse`, not a look at `event.type`.** The log is an open set of dotted names on purpose --
    // an older build has to carry a newer one's events across a sync -- so reading the payload directly would
    // mean this screen understanding a wire format it does not own. The op layer knows which strings are its
    // own, and returns null for the rest rather than throwing.
    final op = PriceOp.tryParse(event);
    if (op is! PricePaid) continue;
    expenses.add(
      CashflowEntry(
        minorUnits: op.minorUnits,
        currency: op.currency,
        // **`atMillis`, the same accessor the price chart uses.** It prefers the date the reader said they paid
        // over the moment they typed it, which is the difference between a receipt entered a month late landing
        // in the right window and landing in this one.
        at: DateTime.fromMillisecondsSinceEpoch(op.atMillis),
        label: op.sku,
      ),
    );
  }

  return [
    for (final window in CashflowWindow.values)
      cashflowOf(window: window, now: now, expense: expenses),
  ];
}

/// Which currency the cashflow view is drawn in.
///
/// **The window's own currency when it has one, and the reader's primary otherwise.** `cashflowOf` already
/// picks the first currency it sees in the window and reports everything else as unattributed, so asking the
/// preferences first would be a second answer to a question the fold has answered. The preference is needed
/// only for a window with nothing in it, where the fold has nothing to read and returns its own placeholder --
/// and an empty total in the reader's own money is more useful than one in `XXX`.
///
/// It is declared here rather than beside the preferences because this is the only reader: `stock_page.dart`
/// resolves its currency from the price being edited, not from a global default.
final cashflowCurrencyProvider = Provider<Currency>((ref) {
  final windows = ref.watch(cashflowsProvider).value;
  for (final window in windows ?? const <Cashflow>[]) {
    if (!window.expense.isZero || !window.income.isZero) return window.currency!;
  }
  return ref.watch(preferencesProvider).currencies.primary;
});
