// How the user's saving weighs against their spending lately. Drives the
// balance scale on the profile, which shows only the overall state (good or
// not), never amounts. Pure: no Flutter, no I/O.

import 'package:waffr/data/models/transaction.dart';

/// Where the scale settles, from most spending-heavy to most saving-heavy.
enum BalanceState { empty, spendingHeavy, leaningSpending, balanced, savingHeavy }

class MoneyBalance {
  /// Days looked back. Long enough that one big purchase does not swing the
  /// scale, short enough that a change in habits shows within weeks.
  static const int windowDays = 30;

  /// Share of money moved that went to savings at which the beam is level.
  static const double target = 0.2;

  final double saved;
  final double spent;

  const MoneyBalance({required this.saved, required this.spent});

  /// Sums [transactions] in [currencyCode] over the last [windowDays] up to
  /// [now]. Withdrawals from savings count against what was saved.
  factory MoneyBalance.fromTransactions(
    Iterable<WaffrTransaction> transactions, {
    required String currencyCode,
    required DateTime now,
  }) {
    final start = now.subtract(const Duration(days: windowDays));
    var saved = 0.0;
    var spent = 0.0;

    for (final item in transactions) {
      if (item.currencyCode != currencyCode) continue;
      final at = item.dateTime;
      if (at.isBefore(start) || at.isAfter(now)) continue;

      if (item.isSavingsIn) {
        saved += item.amount;
      } else if (item.isSavingsOut) {
        saved -= item.amount;
      } else if (item.isExpense) {
        spent += item.amount;
      }
    }

    return MoneyBalance(saved: saved < 0 ? 0 : saved, spent: spent);
  }

  bool get isEmpty => saved + spent <= 0;

  /// Part of the money moved that went to savings, 0..1.
  double get share => isEmpty ? 0 : saved / (saved + spent);

  /// Beam tilt, -1 (spending pan down) to 1 (saving pan down); 0 is level
  /// at [target].
  double get tilt {
    if (isEmpty) return 0;
    return ((share - target) / target).clamp(-1.0, 1.0);
  }

  /// How full each pan looks, 0..1, relative to the heavier one.
  double get savedLoad => _load(saved);
  double get spentLoad => _load(spent);

  double _load(double amount) {
    final heavier = saved > spent ? saved : spent;
    if (heavier <= 0 || amount <= 0) return 0;
    return (amount / heavier).clamp(0.15, 1.0);
  }

  BalanceState get state {
    if (isEmpty) return BalanceState.empty;
    if (share < 0.05) return BalanceState.spendingHeavy;
    if (share < 0.15) return BalanceState.leaningSpending;
    if (share <= 0.3) return BalanceState.balanced;
    return BalanceState.savingHeavy;
  }

  /// One word for the chip: how the user is doing overall.
  String get verdict => switch (state) {
        BalanceState.empty => 'لا بيانات بعد',
        BalanceState.spendingHeavy => 'يحتاج انتباهاً',
        BalanceState.leaningSpending => 'مقبول',
        BalanceState.balanced => 'جيد',
        BalanceState.savingHeavy => 'ممتاز',
      };

  /// One short line under the scale, without numbers.
  String get message => switch (state) {
        BalanceState.empty => 'سجّل مصروفك وتوفيرك ليظهر ميزانك',
        BalanceState.spendingHeavy => 'الصرف يغلب على التوفير مؤخراً',
        BalanceState.leaningSpending => 'قريب من التوازن، خطوة توفير صغيرة تعدّله',
        BalanceState.balanced => 'توفيرك وصرفك في توازن جيد',
        BalanceState.savingHeavy => 'توفيرك قوي، أحسنت',
      };
}
