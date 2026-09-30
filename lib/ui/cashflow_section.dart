import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/pricing/cashflow.dart';
import '../domain/pricing/price.dart';
import 'cashflow_providers.dart';
import 'cash_settings.dart';
import 'l10n/dual_copy.dart';
import 'l10n/dual_copy_text.dart';
import 'money_text.dart';
import 'prism.dart';
import 'theme.dart';

/// What the bar took and what it spent, over the four windows it asks the question in.
///
/// **This is where the feature landed, and the placement was a recorded open question.** `cashflow.dart` was
/// written on 2026-09-21 with four windows, the arithmetic, the unattributed list, `CashReconciliation` and ten
/// tests, and no screen read any of it; `docs/TODO.md` section 十 says why -- *its problem was never behaviour
/// but where it belonged*, and the two candidates were 记录 and 酒窖. The assistant chose 记录 on 2026-09-30 by
/// the screen's own logic: that page's headline facts are already the reader's money (what the cellar is worth,
/// what has been drunk, what is running out), and the shelf that used to sit in this slot is off the interface.
///
/// **Two facts from outside the log are needed, so they are asked for rather than invented.** The event log
/// knows everything that was spent and nothing about what was in the till to begin with, so the starting float
/// and the counted amount are stored per currency -- see `cash_settings.dart`. `CashReconciliation` is the
/// domain's own type for that comparison; this builds one rather than repeating its arithmetic.
///
/// **The income side is named, not zeroed.** There is no event that says a drink was sold, so a figure of zero
/// would be read as "nothing came in" rather than "nothing can be recorded yet". [Copy.cashflowNoIncome] says
/// which it is, in every voice.
class CashflowSection extends ConsumerWidget {
  const CashflowSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final windows = ref.watch(cashflowsProvider);
    final currency = ref.watch(cashflowCurrencyProvider);
    final settings = ref.watch(cashSettingsProvider);
    final notifier = ref.read(cashSettingsProvider.notifier);

    // **The heading is drawn either way; the four rows are not.** A section that vanished while the log opened
    // would make the page jump, and a heading is not a claim about anything. The rows are: until there is
    // something to fold they would each read as "nothing was spent", which is four false statements about the
    // reader's money, held for one frame -- long enough to be seen and never long enough to be reported.
    if (!windows.hasValue) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DualCopyText(Copy.cellarCashflow, style: HollowType.heading),
          const SizedBox(height: 8),
          Text('…', style: HollowType.body.copyWith(color: HollowPalette.inkFaint)),
        ],
      );
    }

    final folded = windows.requireValue;
    // The widest window is the one the comparison is made over: a till counted tonight should be explained by
    // everything the log knows, not by the last seven days of it.
    final quarter = folded.last;
    final deposit = settings.depositIn(currency);
    final counted = settings.countedIn(currency);

    // **The comparison is drawn only once the reader has said what the till started with.** A reconciliation
    // against a deposit nobody entered would compare their count against all recorded history and call the
    // difference a discrepancy.
    final reconciliation = deposit == null
        ? null
        : CashReconciliation(
            deposit: deposit,
            implied: deposit + quarter.net,
            counted: counted,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DualCopyText(Copy.cellarCashflow, style: HollowType.heading),
        const SizedBox(height: 8),
        for (final cashflow in folded) _window(cashflow),
        const SizedBox(height: 20),
        const PrismDivider(),
        const SizedBox(height: 16),
        DualCopyText(Copy.cashflowNoIncome, style: HollowType.caption),
        const SizedBox(height: 20),
        _MoneyRow(
          key: const ValueKey('cash-deposit'),
          label: Copy.cashflowDeposit,
          value: deposit,
          currency: currency,
          onChanged: (minor) => notifier.setDeposit(currency, minor),
        ),
        const SizedBox(height: 10),
        _MoneyRow(
          key: const ValueKey('cash-counted'),
          label: Copy.cashflowCounted,
          value: counted,
          currency: currency,
          onChanged: (minor) => notifier.setCounted(
            currency,
            minor,
            DateTime.now().millisecondsSinceEpoch,
          ),
        ),
        if (reconciliation != null) ...[
          const SizedBox(height: 14),
          _plainRow(Copy.cashflowImplied, moneyText(reconciliation.implied)),
          if (reconciliation.difference case final gap?) ...[
            _plainRow(
              Copy.cashflowDifference,
              moneyText(gap),
              // **Coloured, and only the difference is.** A gap between the till and the log is the one figure
              // on this screen that is a question rather than a fact, and the palette has a colour for that.
              colour: reconciliation.balances ? HollowPalette.gold : HollowPalette.rose,
            ),
            const SizedBox(height: 4),
            DualCopyText(
              reconciliation.balances ? Copy.cashflowBalances : Copy.cashflowDifferenceNote,
              style: HollowType.caption,
            ),
          ],
        ],
      ],
    );
  }

  /// One window: its name, what it cost, and anything that could not be counted.
  Widget _window(Cashflow cashflow) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(_windowLabel(cashflow.window), style: HollowType.body)),
            Text(
              // An em dash rather than a zero: nothing was spent, which is not the same as a total of nothing
              // having been arrived at, and the two read identically as `0.00`.
              cashflow.expense.isZero ? '—' : moneyText(cashflow.expense),
              style: HollowType.body,
            ),
          ],
        ),
        if (cashflow.unattributed.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '${Copy.cashflowUnattributed.primary.text} ${cashflow.unattributed.length}',
              style: HollowType.caption.copyWith(color: HollowPalette.rose),
            ),
          ),
      ],
    ),
  );

  Widget _plainRow(CopyLine label, String value, {Color? colour}) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      children: [
        Expanded(child: Text(label.primary.text, style: HollowType.body)),
        Text(
          value,
          style: HollowType.body.copyWith(color: colour ?? HollowPalette.inkFaint),
        ),
      ],
    ),
  );

  static String _windowLabel(CashflowWindow window) => switch (window) {
    CashflowWindow.today => Copy.cashflowToday,
    CashflowWindow.week => Copy.cashflowWeek,
    CashflowWindow.month => Copy.cashflowMonth,
    CashflowWindow.quarter => Copy.cashflowQuarter,
  };
}

/// One editable amount, kept as text while it is being typed.
///
/// **A `TextEditingController` and not a controlled `Text` value.** Parsing on every keystroke would fight the
/// reader -- `0.` is not a number yet, and a field that erased it would make a two-digit amount impossible to
/// type. The value is read on submit instead, which is how the price sheets in this application already work.
class _MoneyRow extends StatefulWidget {
  const _MoneyRow({
    super.key,
    required this.label,
    required this.value,
    required this.currency,
    required this.onChanged,
  });

  final CopyLine label;
  final Money? value;
  final Currency currency;
  final ValueChanged<int> onChanged;

  @override
  State<_MoneyRow> createState() => _MoneyRowState();
}

class _MoneyRowState extends State<_MoneyRow> {
  late final TextEditingController _controller =
      TextEditingController(text: _editable(widget.value));

  /// The amount as a person would type it: **the number alone, without the currency code.**
  ///
  /// `moneyText` renders `45.00 CNY`, and seeding the field with that would make it unreadable back --
  /// `minorUnitsTyped` expects what it produces, and a round trip through a formatted string is exactly how a
  /// currency code ends up parsed as part of the number.
  static String _editable(Money? amount) {
    if (amount == null) return '';
    final digits = amount.currency.minorUnitDigits;
    return (amount.minorUnits / _pow10(digits)).toStringAsFixed(digits);
  }

  static int _pow10(int digits) {
    var out = 1;
    for (var i = 0; i < digits; i++) {
      out *= 10;
    }
    return out;
  }

  @override
  void didUpdateWidget(_MoneyRow old) {
    super.didUpdateWidget(old);
    // **The field follows the amount, and this is a fix rather than housekeeping.** The controller is created in
    // `initState` with the value it was handed then, and a rebuild with a different amount reuses this State --
    // so without this the box keeps showing the old figure. On the handset that is not a test artefact: changing
    // the currency resolves a different deposit, and the reader would see the previous currency's number sitting
    // in a box labelled with the new one. Found because a test asserted an empty field when a value had been
    // supplied, and the first reading of that was "the override did not reach the widget".
    final incoming = _editable(widget.value);
    if (incoming != _controller.text) _controller.text = incoming;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: DualCopyText(widget.label, style: HollowType.body)),
      SizedBox(
        width: 132,
        child: TextField(
          controller: _controller,
          textAlign: TextAlign.end,
          style: HollowType.body,
          decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
          // **Read on submit, and a string that cannot be read leaves the field as typed.** Clearing it would
          // discard an entry the reader can still see and fix, which is the behaviour that makes a numeric
          // field feel broken when it is the field's parsing that failed.
          onSubmitted: (text) {
            final minor = minorUnitsTyped(text, widget.currency);
            if (minor == null) return;
            widget.onChanged(minor);
          },
        ),
      ),
    ],
  );
}
