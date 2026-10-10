// The totals sent to /ai/insights. Only sums per category, goal and
// obligation leave the phone; single transactions and notes never do.

import 'package:waffr/data/models/ai_insights.dart';
import 'package:waffr/data/models/calendar_period.dart';
import 'package:waffr/data/models/recurring_expense.dart';
import 'package:waffr/data/models/transaction.dart';

class GoalTotal {
  final String name;
  final double target;
  final double saved;

  const GoalTotal({required this.name, required this.target, required this.saved});
}

// Builds the /ai/insights body for [kind]: the current week or month
// against the one before it.
Map<String, Object?> buildSpendingSummary({
  required AiInsightsKind kind,
  required String currencyCode,
  required DateTime now,
  required List<WaffrTransaction> expenses,
  required double balance,
  required double cycleSpent,
  required double maxBalance,
  required double? monthlyIncome,
  required RecurringFrequency incomeFrequency,
  required bool hasRecurringIncome,
  required double totalSaved,
  required List<GoalTotal> goals,
  required List<RecurringExpense> obligations,
}) {
  final frequency = kind == AiInsightsKind.weekly
      ? RecurringFrequency.weekly
      : RecurringFrequency.monthly;
  final current = CalendarPeriod.ofFrequency(frequency, now);
  final previous = CalendarPeriod.ofFrequency(
    frequency,
    current.start.subtract(const Duration(days: 1)),
  );

  final currentTotals = <String, double>{};
  final previousTotals = <String, double>{};
  for (final expense in expenses) {
    if (!expense.isExpense) continue;
    final category = expense.category ?? 'أخرى';
    if (current.contains(expense.dateTime)) {
      currentTotals[category] = (currentTotals[category] ?? 0) + expense.amount;
    } else if (previous.contains(expense.dateTime)) {
      previousTotals[category] =
          (previousTotals[category] ?? 0) + expense.amount;
    }
  }
  final names = {...currentTotals.keys, ...previousTotals.keys}.toList()
    ..sort(
      (a, b) => (currentTotals[b] ?? 0).compareTo(currentTotals[a] ?? 0),
    );

  final today = DateTime(now.year, now.month, now.day);
  final daysTotal = current.end.difference(current.start).inDays;
  final daysElapsed =
      (today.difference(current.start).inDays + 1).clamp(1, daysTotal);

  int? daysUntilIncome;
  if (hasRecurringIncome && incomeFrequency != RecurringFrequency.none) {
    final next = CalendarPeriod.ofFrequency(incomeFrequency, now).end;
    daysUntilIncome = next.difference(today).inDays.clamp(0, 62);
  }

  return {
    'kind': kind.name,
    'currency': currencyCode,
    'period_label': kind == AiInsightsKind.weekly ? 'هذا الأسبوع' : 'هذا الشهر',
    'days_elapsed': daysElapsed,
    'days_total': daysTotal,
    'monthly_income': (monthlyIncome ?? 0) > 0 ? _round(monthlyIncome!) : null,
    'balance': _round(balance),
    'cycle_spent': _round(cycleSpent),
    'max_balance': _round(maxBalance),
    'days_until_income': daysUntilIncome,
    'total_saved': _round(totalSaved < 0 ? 0 : totalSaved),
    'categories': [
      for (final name in names.take(40))
        {
          'name': _clip(name, 60),
          'current': _round(currentTotals[name] ?? 0),
          'previous': _round(previousTotals[name] ?? 0),
        },
    ],
    'goals': [
      for (final goal in goals.take(20))
        {
          'name': _clip(goal.name, 80),
          'target': _round(goal.target),
          'saved': _round(goal.saved),
        },
    ],
    'obligations': [
      for (final item in obligations.where((item) => item.enabled).take(30))
        {
          'name': _clip(item.category, 80),
          'amount': _round(item.amount),
          'frequency': _clip(item.intervalDescription, 20),
        },
    ],
  };
}

double _round(double value) => (value * 100).roundToDouble() / 100;

// The backend rejects longer strings; custom names can run long.
String _clip(String value, int max) =>
    value.length <= max ? value : value.substring(0, max);
