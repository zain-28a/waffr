// The numbers the smart analysis reasons over, gathered once per run.
// Pure data plus derived figures, so the engine can be tested without
// stores or prefs.

import 'dart:math' as math;

import 'package:waffr/data/models/calendar_period.dart';
import 'package:waffr/data/models/transaction.dart';

class GoalFact {
  final String id;
  final String name;
  final double target;
  final double saved;
  final DateTime createdAt;

  // Planned length in months (a week counts as a quarter month).
  final double plannedMonths;

  const GoalFact({
    required this.id,
    required this.name,
    required this.target,
    required this.saved,
    required this.createdAt,
    required this.plannedMonths,
  });

  double get ratio => target <= 0 ? 0 : (saved / target).clamp(0.0, 1.0);
  double get remaining => math.max(0, target - saved);
  DateTime get deadline =>
      createdAt.add(Duration(days: (plannedMonths * 30).round()));
}

class ObligationFact {
  final String name;
  final double amount;
  final double monthlyEquivalent;
  final DateTime nextDueAt;

  const ObligationFact({
    required this.name,
    required this.amount,
    required this.monthlyEquivalent,
    required this.nextDueAt,
  });
}

class SmartFacts {
  final DateTime now;
  final String currencySymbol;

  // Active currency only, any date.
  final List<WaffrTransaction> expenses;
  final List<WaffrTransaction> incomes;
  final List<WaffrTransaction> savingsTransfers;

  final double balance;
  final double maxBalance;
  final double? monthlyIncome;
  final RecurringFrequency incomeFrequency;
  final bool hasRecurringIncome;
  final double savingsBalance;
  final List<GoalFact> goals;
  final int completedGoals;
  final List<ObligationFact> obligations;
  final int pendingShopping;
  final int streakCount;
  final DateTime? usageStartedAt;

  SmartFacts({
    required this.now,
    required this.currencySymbol,
    required this.expenses,
    required this.incomes,
    required this.savingsTransfers,
    required this.balance,
    required this.maxBalance,
    required this.monthlyIncome,
    required this.incomeFrequency,
    required this.hasRecurringIncome,
    required this.savingsBalance,
    required this.goals,
    required this.completedGoals,
    required this.obligations,
    required this.pendingShopping,
    required this.streakCount,
    required this.usageStartedAt,
  });

  DateTime get today => DateTime(now.year, now.month, now.day);
  DateTime get monthStart => DateTime(now.year, now.month);
  int get daysInMonth => DateTime(now.year, now.month + 1, 0).day;
  int get dayOfMonth => now.day;
  int get daysLeftInMonth => daysInMonth - dayOfMonth;

  bool get hasExpenses => expenses.isNotEmpty;

  double spentBetween(DateTime start, DateTime end) {
    var total = 0.0;
    for (final item in expenses) {
      if (!item.dateTime.isBefore(start) && item.dateTime.isBefore(end)) {
        total += item.amount;
      }
    }
    return total;
  }

  List<WaffrTransaction> expensesBetween(DateTime start, DateTime end) => [
    for (final item in expenses)
      if (!item.dateTime.isBefore(start) && item.dateTime.isBefore(end)) item,
  ];

  Map<String, double> categoryTotals(DateTime start, DateTime end) {
    final totals = <String, double>{};
    for (final item in expensesBetween(start, end)) {
      final key = item.category ?? 'أخرى';
      totals[key] = (totals[key] ?? 0) + item.amount;
    }
    return totals;
  }

  // Month to date, and the same number of days of last month, so a
  // comparison on the 10th is not against a full month.
  late final DateTime _tomorrow = today.add(const Duration(days: 1));
  late final DateTime prevMonthStart = DateTime(now.year, now.month - 1);
  late final DateTime prevMonthSameDay = () {
    final prevDays = DateTime(now.year, now.month, 0).day;
    final day = math.min(dayOfMonth, prevDays);
    return DateTime(prevMonthStart.year, prevMonthStart.month, day + 1);
  }();

  late final double monthSpent = spentBetween(monthStart, _tomorrow);
  late final double prevMonthSpentSameSpan = spentBetween(
    prevMonthStart,
    prevMonthSameDay,
  );
  late final double prevMonthSpentFull = spentBetween(
    prevMonthStart,
    monthStart,
  );

  late final Map<String, double> monthCategories = categoryTotals(
    monthStart,
    _tomorrow,
  );
  late final Map<String, double> prevMonthCategories = categoryTotals(
    prevMonthStart,
    prevMonthSameDay,
  );

  late final DateTime weekStart = CalendarPeriod.weekStart(now);
  late final double weekSpent = spentBetween(weekStart, _tomorrow);
  late final double prevWeekSpentSameSpan = spentBetween(
    weekStart.subtract(const Duration(days: 7)),
    _tomorrow.subtract(const Duration(days: 7)),
  );

  double get dailyAverageThisMonth =>
      dayOfMonth <= 0 ? 0 : monthSpent / dayOfMonth;

  // Recent pace, steadier than month to date early in the month.
  late final double dailyAverageRecent = () {
    final start = today.subtract(const Duration(days: 13));
    final first = expenses.isEmpty
        ? today
        : expenses
              .map((e) => e.dateTime)
              .reduce((a, b) => a.isBefore(b) ? a : b);
    final from = first.isAfter(start)
        ? DateTime(first.year, first.month, first.day)
        : start;
    final days = math.max(1, _tomorrow.difference(from).inDays);
    return spentBetween(from, _tomorrow) / days;
  }();

  double get projectedMonthSpend =>
      monthSpent + dailyAverageRecent * daysLeftInMonth;

  // Days of balance left at the recent pace; null when nothing is spent.
  double? get runwayDays =>
      dailyAverageRecent <= 0 ? null : balance / dailyAverageRecent;

  int? get daysUntilIncome {
    if (!hasRecurringIncome || incomeFrequency == RecurringFrequency.none) {
      return null;
    }
    final next = CalendarPeriod.ofFrequency(incomeFrequency, now).end;
    return next.difference(today).inDays;
  }

  double get obligationsMonthly =>
      obligations.fold(0.0, (sum, item) => sum + item.monthlyEquivalent);

  // Average monthly spending over the last three full months that have
  // data, falling back to the projection for new users.
  late final double averageMonthlySpend = () {
    final totals = <double>[];
    for (var back = 1; back <= 3; back++) {
      final start = DateTime(now.year, now.month - back);
      final end = DateTime(now.year, now.month - back + 1);
      final total = spentBetween(start, end);
      if (total > 0) totals.add(total);
    }
    if (totals.isEmpty) return projectedMonthSpend;
    return totals.reduce((a, b) => a + b) / totals.length;
  }();

  double savedBetween(DateTime start, DateTime end) {
    var total = 0.0;
    for (final item in savingsTransfers) {
      if (item.dateTime.isBefore(start) || !item.dateTime.isBefore(end)) {
        continue;
      }
      if (item.isSavingsIn) total += item.amount;
      if (item.isSavingsOut) total -= item.amount;
    }
    return total;
  }

  late final double savedLast30 = savedBetween(
    today.subtract(const Duration(days: 29)),
    _tomorrow,
  );
  late final double savedLast90 = savedBetween(
    today.subtract(const Duration(days: 89)),
    _tomorrow,
  );

  int get withdrawalsLast30 => savingsTransfers
      .where(
        (item) =>
            item.isSavingsOut &&
            item.dateTime.isAfter(today.subtract(const Duration(days: 30))),
      )
      .length;

  int get leftoverTransfers => savingsTransfers
      .where(
        (item) =>
            item.isSavingsIn &&
            item.transferKind == SavingsTransferKind.periodLeftover,
      )
      .length;

  // Months of history covered by savings, capped at three, for averages.
  double get savingsMonthsCovered {
    if (savingsTransfers.isEmpty) return 1;
    final first = savingsTransfers
        .map((e) => e.dateTime)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final days = today.difference(first).inDays + 1;
    return (days / 30).clamp(1.0, 3.0);
  }

  double get averageMonthlySaving =>
      math.max(0, savedLast90) / savingsMonthsCovered;

  DateTime? lastSavedFor(String goalId) {
    DateTime? last;
    for (final item in savingsTransfers) {
      if (item.isSavingsIn && item.goalId == goalId) {
        if (last == null || item.dateTime.isAfter(last)) last = item.dateTime;
      }
    }
    return last;
  }

  DateTime? get lastExpenseAt => expenses.isEmpty
      ? null
      : expenses.map((e) => e.dateTime).reduce((a, b) => a.isAfter(b) ? a : b);

  int get loggedLast30 => expenses
      .where(
        (e) => e.dateTime.isAfter(today.subtract(const Duration(days: 30))),
      )
      .length;

  // Distinct days with at least one expense in the last 30 days.
  int get activeDaysLast30 => {
    for (final e in expenses)
      if (e.dateTime.isAfter(today.subtract(const Duration(days: 30))))
        DateTime(e.dateTime.year, e.dateTime.month, e.dateTime.day),
  }.length;

  int get noSpendDaysThisMonth {
    final spentDays = {
      for (final e in expensesBetween(monthStart, _tomorrow)) e.dateTime.day,
    };
    return dayOfMonth - spentDays.length;
  }

  // Total spent per weekday (DateTime.monday..sunday) over the last 8 weeks.
  Map<int, double> get weekdayTotals {
    final totals = <int, double>{};
    final from = today.subtract(const Duration(days: 55));
    for (final e in expensesBetween(from, _tomorrow)) {
      totals[e.dateTime.weekday] = (totals[e.dateTime.weekday] ?? 0) + e.amount;
    }
    return totals;
  }

  int get weeksOfHistory {
    final first = expenses.isEmpty
        ? today
        : expenses
              .map((e) => e.dateTime)
              .reduce((a, b) => a.isBefore(b) ? a : b);
    return today.difference(first).inDays ~/ 7;
  }

  double get incomeLast90 {
    final from = today.subtract(const Duration(days: 89));
    return incomes
        .where((e) => !e.dateTime.isBefore(from))
        .fold(0.0, (sum, e) => sum + e.amount);
  }

  // Income the analysis can rely on: the configured monthly amount, or
  // the last 90 days averaged per month.
  double? get effectiveMonthlyIncome {
    if ((monthlyIncome ?? 0) > 0) return monthlyIncome;
    final recent = incomeLast90;
    if (recent <= 0) return null;
    final first = incomes
        .map((e) => e.dateTime)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final months = ((today.difference(first).inDays + 1) / 30).clamp(1.0, 3.0);
    return recent / months;
  }
}
