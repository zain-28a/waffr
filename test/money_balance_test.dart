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

  test('the heavier pan looks full and the lighter one partly', () {
    final balance = balanceOf([
      tx(TransactionType.savingsIn, 100, 2),
      tx(TransactionType.expense, 400, 2),
    ]);
    expect(balance.spentLoad, 1);
    expect(balance.savedLoad, closeTo(0.25, 1e-9));
    expect(balanceOf([]).savedLoad, 0);
  });

  test('every state has a verdict and a line without numbers', () {
    for (final balance in [
      balanceOf([]),
      balanceOf([tx(TransactionType.expense, 100, 1)]),
      balanceOf([
        tx(TransactionType.savingsIn, 10, 1),
        tx(TransactionType.expense, 90, 1),
      ]),
      balanceOf([
        tx(TransactionType.savingsIn, 20, 1),
        tx(TransactionType.expense, 80, 1),
      ]),
      balanceOf([tx(TransactionType.savingsIn, 100, 1)]),
    ]) {
      expect(balance.verdict, isNotEmpty);
      expect(balance.message, isNot(matches(RegExp(r'[0-9٠-٩%]'))));
    }
  });
}
