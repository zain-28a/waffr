// How the user's saving weighs against their spending over a rolling window.
// Drives the balance scale on the profile. Pure: no Flutter, no I/O.

import 'package:waffr/data/models/transaction.dart';

/// Where the scale settles, from most spending-heavy to most saving-heavy.
enum BalanceState { empty, spendingHeavy, leaningSpending, balanced, savingHeavy }

class MoneyBalance {
  /// Days in each window. Long enough that one big purchase does not swing
  /// the scale, short enough that a change in habits shows within weeks.
  static const int windowDays = 30;

  /// Share of money moved that went to savings at which the scale is level.
  static const double target = 0.2;

  final double saved;
  final double spent;

  /// The same figures for the window before, or null when there was no
  /// money movement then.
  final double? previousShare;

  const MoneyBalance({
    required this.saved,
    required this.spent,
    this.previousShare,
  });

  /// Sums [transactions] in [currencyCode] over the last [windowDays] up to
  /// [now], and the window before it for the trend. Withdrawals from
  /// savings count against what was saved.
  factory MoneyBalance.fromTransactions(
    Iterable<WaffrTransaction> transactions, {
    required String currencyCode,
    required DateTime now,
  }) {
    final start = now.subtract(const Duration(days: windowDays));
    final previousStart = start.subtract(const Duration(days: windowDays));
    var saved = 0.0, spent = 0.0, prevSaved = 0.0, prevSpent = 0.0;

    for (final item in transactions) {
      if (item.currencyCode != currencyCode) continue;
      final at = item.dateTime;
      if (at.isAfter(now)) continue;
      final current = !at.isBefore(start);
      if (!current && at.isBefore(previousStart)) continue;

      final double savedDelta = item.isSavingsIn
          ? item.amount
          : item.isSavingsOut
              ? -item.amount
              : 0.0;
      final double spentDelta = item.isExpense ? item.amount : 0.0;
      if (current) {
        saved += savedDelta;
        spent += spentDelta;
      } else {
        prevSaved += savedDelta;
        prevSpent += spentDelta;
      }
    }

    return MoneyBalance(
      saved: saved < 0 ? 0 : saved,
      spent: spent,
      previousShare: _share(prevSaved < 0 ? 0 : prevSaved, prevSpent),
    );
  }

  static double? _share(double saved, double spent) {
    final total = saved + spent;
    if (total <= 0) return null;
    return saved / total;
  }

  bool get isEmpty => saved + spent <= 0;

  /// Part of the money moved that went to savings, 0..1.
  double get share => _share(saved, spent) ?? 0;

  /// Beam tilt, -1 (spending pan down) to 1 (saving pan down); 0 is level
  /// at [target].
  double get tilt {
    if (isEmpty) return 0;
    final raw = (share - target) / target;
    return raw.clamp(-1.0, 1.0);
  }

  BalanceState get state {
    if (isEmpty) return BalanceState.empty;
    if (share < 0.05) return BalanceState.spendingHeavy;
    if (share < 0.15) return BalanceState.leaningSpending;
    if (share <= 0.3) return BalanceState.balanced;
    return BalanceState.savingHeavy;
  }

  String get title => switch (state) {
        BalanceState.empty => 'ميزانك ينتظر',
        BalanceState.spendingHeavy => 'الصرف طاغٍ',
        BalanceState.leaningSpending => 'يميل إلى الصرف',
        BalanceState.balanced => 'متوازن',
        BalanceState.savingHeavy => 'يميل إلى التوفير',
      };

  String get caption => switch (state) {
        BalanceState.empty => 'سجّل مصروفك وتوفيرك ليظهر ميزانك',
        BalanceState.spendingHeavy =>
          'وفّر ولو مبلغاً صغيراً هذا الأسبوع ليبدأ الميزان بالاعتدال',
        BalanceState.leaningSpending =>
          'قريب من التوازن. توفير ${_percent(target)} من حركة مالك يعدّله',
        BalanceState.balanced => 'توفيرك وصرفك في توازن جيد، حافظ عليه',
        BalanceState.savingHeavy => 'توفيرك قوي هذه الفترة، أحسنت',
      };

  /// Compared with the window before: positive when more went to savings.
  double? get trend {
    final previous = previousShare;
    if (previous == null || isEmpty) return null;
    return share - previous;
  }

  String? get trendText {
    final change = trend;
    if (change == null || change.abs() < 0.02) return null;
    return change > 0
        ? 'أفضل من الفترة السابقة'
        : 'أقل توفيراً من الفترة السابقة';
  }

  static String _percent(double value) =>
      '\u2066${(value * 100).round()}%\u2069';

  String get shareText => _percent(share);
}
