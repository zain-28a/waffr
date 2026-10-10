// Counts and lifetime spending/saving for the profile. One pass, no charts.

import 'package:waffr/data/stores/currency_store.dart';
import 'package:waffr/data/stores/transaction_store.dart';

class ProfileSnapshot {
  final int expenseCount;
  final int incomeCount;
  final int goalCount;
  final int savingsCount;
  final double spent;
  final double saved;

  const ProfileSnapshot({
    required this.expenseCount,
    required this.incomeCount,
    required this.goalCount,
    required this.savingsCount,
    required this.spent,
    required this.saved,
  });

  bool get hasMoneyMovement => spent > 0 || saved > 0;

  factory ProfileSnapshot.fromStore(TransactionStore store) {
    final code = CurrencyStore.instance.activeCode;
    var expenseCount = 0;
    var incomeCount = 0;
    var savingsCount = 0;
    var spent = 0.0;
    var saved = 0.0;

    for (final item in store.transactions) {
      if (item.isExpense) {
        expenseCount++;
      } else if (item.isIncome) {
        incomeCount++;
      } else if (item.isSavingsIn) {
        savingsCount++;
      }

      if (item.currencyCode != code) continue;
      if (item.isExpense) {
        spent += item.amount;
      } else if (item.isSavingsIn) {
        saved += item.amount;
      }
    }

    return ProfileSnapshot(
      expenseCount: expenseCount,
      incomeCount: incomeCount,
      goalCount: store.goals.length,
      savingsCount: savingsCount,
      spent: spent,
      saved: saved,
    );
  }
}

/// Earliest ledger or goal date, used when usage start was never stored.
DateTime? earliestUsageDate(TransactionStore store) {
  DateTime? earliest;
  for (final item in store.transactions) {
    final local = item.dateTime.toLocal();
    if (earliest == null || local.isBefore(earliest)) earliest = local;
  }
  for (final goal in store.goals) {
    final local = goal.createdAt.toLocal();
    if (earliest == null || local.isBefore(earliest)) earliest = local;
  }
  return earliest;
}
