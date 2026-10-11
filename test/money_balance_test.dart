import 'package:flutter_test/flutter_test.dart';
import 'package:waffr/core/insights/money_balance.dart';
import 'package:waffr/data/models/transaction.dart';

void main() {
  final now = DateTime(2026, 10, 20, 12);
  var id = 0;

  WaffrTransaction tx(TransactionType type, double amount, int daysAgo,
          {String currency = 'SYP'}) =>
      WaffrTransaction(
        id: '${id++}',
        type: type,
        amount: amount,
        currencyCode: currency,
        dateTime: now.subtract(Duration(days: daysAgo)),
      );

  MoneyBalance balanceOf(List<WaffrTransaction> items) =>
      MoneyBalance.fromTransactions(items, currencyCode: 'SYP', now: now);

  test('nothing moved: empty and level', () {
    final balance = balanceOf([]);
    expect(balance.state, BalanceState.empty);
    expect(balance.tilt, 0);
  });

  test('the target share keeps the beam level', () {
    final balance = balanceOf([
      tx(TransactionType.savingsIn, 200, 3),
      tx(TransactionType.expense, 800, 5),
    ]);
    expect(balance.share, closeTo(0.2, 1e-9));
    expect(balance.tilt, closeTo(0, 1e-9));
    expect(balance.state, BalanceState.balanced);
  });

  test('spending only tips fully to spending; withdrawals count against', () {
    final balance = balanceOf([
      tx(TransactionType.savingsIn, 100, 2),
      tx(TransactionType.savingsOut, 150, 1),
      tx(TransactionType.expense, 500, 4),
    ]);
    expect(balance.saved, 0);
    expect(balance.tilt, -1);
    expect(balance.state, BalanceState.spendingHeavy);
  });

  test('only the last 30 days and the active currency count', () {
    final balance = balanceOf([
      tx(TransactionType.expense, 1000, 40),
      tx(TransactionType.savingsIn, 500, 2, currency: 'USD'),
      tx(TransactionType.savingsIn, 400, 2),
      tx(TransactionType.expense, 600, 2),
    ]);
    expect(balance.saved, 400);
    expect(balance.spent, 600);
    expect(balance.state, BalanceState.savingHeavy);
    expect(balance.tilt, 1);
  });

  test('the trend compares with the 30 days before', () {
    final balance = balanceOf([
      tx(TransactionType.savingsIn, 50, 45),
      tx(TransactionType.expense, 950, 45),
      tx(TransactionType.savingsIn, 300, 5),
      tx(TransactionType.expense, 700, 5),
    ]);
    expect(balance.previousShare, closeTo(0.05, 1e-9));
    expect(balance.trendText, 'أفضل من الفترة السابقة');
  });
}
