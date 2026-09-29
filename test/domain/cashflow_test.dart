import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/domain/pricing/cashflow.dart';
import 'package:hollow_court/domain/pricing/price.dart';

/// The bar's takings, over the four spans a bar actually asks about.
void main() {
  const cny = Currency('CNY', 2);
  const usd = Currency('USD', 2);
  final now = DateTime(2026, 9, 25, 22, 30); // a Friday night, after service

  CashflowEntry entry(int yuan, DateTime at, {Currency currency = cny, String? label}) =>
      CashflowEntry(minorUnits: yuan * 100, currency: currency, at: at, label: label);

  group('the windows', () {
    test('**today means since midnight, not the last twenty-four hours**', () {
      // The morning's takings must not vanish at lunchtime, which is what subtracting a day from `now` does.
      final window = CashflowWindow.today.startFrom(now);
      expect(window, DateTime(2026, 9, 25), reason: 'midnight this morning');
    });

    test('each span counts its own days, inclusive of today', () {
      expect(CashflowWindow.week.startFrom(now), DateTime(2026, 9, 19));
      expect(CashflowWindow.month.startFrom(now), DateTime(2026, 8, 27));
      expect(CashflowWindow.quarter.startFrom(now), DateTime(2026, 6, 28));
    });

    test('a payment this morning is inside today and a payment last night is not', () {
      final morning = entry(48, DateTime(2026, 9, 25, 9));
      final lastNight = entry(52, DateTime(2026, 9, 24, 23, 59));

      final today = cashflowOf(window: CashflowWindow.today, now: now, income: [morning, lastNight]);
      expect(today.income.minorUnits, 4800, reason: 'nine o\'clock this morning is today');
      expect(today.currency!.code, 'CNY');

      final week = cashflowOf(window: CashflowWindow.week, now: now, income: [morning, lastNight]);
      expect(week.income.minorUnits, 4800 + 5200);
    });
  });

  group('the two sides', () {
    test('expense is what was paid for bottles, and net is the difference', () {
      final result = cashflowOf(
        window: CashflowWindow.month,
        now: now,
        expense: [entry(120, DateTime(2026, 9, 20)), entry(80, DateTime(2026, 9, 22))],
        income: [entry(48, DateTime(2026, 9, 24)), entry(96, DateTime(2026, 9, 25, 21))],
      );
      expect(result.expense.minorUnits, 20000);
      expect(result.income.minorUnits, 14400);
      expect(result.net.minorUnits, -5600);
      expect(result.cover!.toDouble(), closeTo(14400 / 20000, 1e-9));
    });

    test('nothing spent means no cover figure rather than an infinite one', () {
      final result = cashflowOf(window: CashflowWindow.today, now: now, income: [entry(48, now)]);
      expect(result.cover, isNull);
    });

    test('**a second currency is named, not folded in**', () {
      final result = cashflowOf(
        window: CashflowWindow.month,
        now: now,
        expense: [
          entry(120, DateTime(2026, 9, 20), label: 'gin'),
          entry(30, DateTime(2026, 9, 21), currency: usd, label: 'whiskey'),
        ],
      );
      expect(result.currency!.code, 'CNY', reason: 'the first currency seen is the window\'s');
      expect(result.expense.minorUnits, 12000, reason: 'the dollar line is not added to the yuan total');
      expect(result.unattributed, ['whiskey'], reason: 'and it is named, so somebody can act on it');
    });

    test('an empty window is a zero with a currency, not a null a screen must special-case', () {
      final result = cashflowOf(window: CashflowWindow.today, now: now);
      expect(result.currency, isNotNull);
      expect(result.income.isZero, isTrue);
      expect(result.expense.isZero, isTrue);
      expect(result.unattributed, isEmpty);
    });
  });

  group('the deposit', () {
    test('**the till is compared with what the log implies**, and the gap is the answer', () {
      final flow = cashflowOf(
        window: CashflowWindow.today,
        now: now,
        expense: [entry(120, DateTime(2026, 9, 25, 11))],
        income: [entry(200, DateTime(2026, 9, 25, 21))],
      );
      final deposit = Money.fromMinorUnits(50000, cny); // 500 yuan in the tin this morning

      final reconciled = CashReconciliation(
        deposit: deposit,
        implied: deposit + flow.net,
        counted: Money.fromMinorUnits(58000, cny), // 580 counted, 580 expected
      );
      expect(reconciled.implied.minorUnits, 50000 + 20000 - 12000);
      expect(reconciled.difference!.minorUnits, 0);
      expect(reconciled.balances, isTrue);
    });

    test('an uncounted till has no difference at all', () {
      final reconciled = CashReconciliation(
        deposit: Money.fromMinorUnits(50000, cny),
        implied: Money.fromMinorUnits(58000, cny),
        counted: null,
      );
      expect(reconciled.difference, isNull, reason: 'not balanced is not the same as not counted');
      expect(reconciled.balances, isFalse);
    });

    test('takings nobody recorded show up as the till holding more than the log explains', () {
      final reconciled = CashReconciliation(
        deposit: Money.fromMinorUnits(50000, cny),
        implied: Money.fromMinorUnits(58000, cny),
        counted: Money.fromMinorUnits(64000, cny),
      );
      expect(reconciled.difference!.minorUnits, 6000);
      expect(reconciled.difference!.isNegative, isFalse);
    });
  });
}
