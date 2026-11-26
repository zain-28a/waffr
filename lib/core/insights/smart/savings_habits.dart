// Saving habits over months: a run of months with savings, a month that
// fell short of the ones before, the first saving, money left idle in the
// balance late in the month, the yearly total at the current rate, a large
// withdrawal, no saving at all, and more goals than the saving pace can
// carry.

import 'dart:math' as math;

import 'package:waffr/core/insights/smart/arabic_text.dart';
import 'package:waffr/core/insights/smart/insight_phrasing.dart';
import 'package:waffr/core/insights/smart/smart_facts.dart';
import 'package:waffr/core/insights/smart/smart_insight.dart';
import 'package:waffr/core/theme/app_icons.dart';
import 'package:waffr/data/models/transaction.dart';

/// Month-by-month saving rules for the savings scope.
class SavingsHabits {
  /// Rules over [facts], worded through the run's shared phrasing.
  SavingsHabits(this.facts, this._p);

  /// The numbers of this run.
  final SmartFacts facts;

  final InsightPhrasing _p;

  /// Every habit rule that applies, in a fixed order.
  List<SmartInsight> all() => [
    ?_streak(),
    ?_dropped(),
    ?_firstSaving(),
    ?_idleBalance(),
    ?_yearAhead(),
    ?_largeWithdrawal(),
    ?_neverSaved(),
    ?_goalsOverloaded(),
  ];

  double _savedInMonth(int back) => facts.savedBetween(
    facts.monthStartBack(back),
    facts.monthStartBack(back - 1),
  );

  // Something saved in each of the last three tracked months.
  SmartInsight? _streak() {
    if (!facts.coversMonth(3)) return null;
    final months = [for (var back = 1; back <= 3; back++) _savedInMonth(back)];
    if (months.any((v) => v <= 0)) return null;
    final total = months.reduce((a, b) => a + b);
    return SmartInsight(
      id: 'savings-streak',
      topic: 'savings-habit',
      tone: InsightTone.positive,
      icon: AppIcons.calendarCheck,
      title: 'ثلاثة أشهر من التوفير المتواصل',
      body:
          'وفّرت في كل شهر من الأشهر الثلاثة الأخيرة، بمجموع ${_p.money(total)}. الانتظام أهم من حجم المبلغ.',
      priority: 52,
    );
  }

  // Last month saved under half of the average of the two before.
  SmartInsight? _dropped() {
    if (!facts.coversMonth(3)) return null;
    final last = _savedInMonth(1);
    final a = _savedInMonth(2);
    final b = _savedInMonth(3);
    if (a <= 0 || b <= 0) return null;
    final before = (a + b) / 2;
    if (last >= before * 0.5) return null;
    return SmartInsight(
      id: 'savings-dropped',
      topic: 'savings-habit',
      tone: InsightTone.info,
      icon: AppIcons.trendingDown,
      title: 'توفير الشهر الماضي أقل من المعتاد',
      body:
          'وفّرت الشهر الماضي ${_p.money(math.max(0, last))} مقابل متوسط ${_p.money(before)} في الشهرين اللذين قبله.',
      priority: 57,
      action: InsightAction.manualSave,
    );
  }

  // The very first saving happened in the last 30 days.
  SmartInsight? _firstSaving() {
    final ins = facts.savingsTransfers.where((e) => e.isSavingsIn).toList();
    if (ins.isEmpty) return null;
    final first = ins
        .map((e) => e.dateTime)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    if (facts.today.difference(first).inDays > 30) return null;
    final total = ins.fold(0.0, (sum, e) => sum + e.amount);
    return SmartInsight(
      id: 'first-saving',
      tone: InsightTone.positive,
      icon: AppIcons.savings,
      title: 'بداية التوفير',
      body:
          'بدأت التوفير هذا الشهر وجمعت حتى الآن ${_p.money(total)}. تحويل مبلغ صغير مع كل دخل يحوّل البداية إلى عادة.',
      priority: 53,
    );
  }

  // From the 22nd with a monthly income: much of the income still sits in
  // the balance, after the bills left this month.
  SmartInsight? _idleBalance() {
    if (facts.dayOfMonth < 22 || !facts.hasRecurringIncome) return null;
    if (facts.incomeFrequency != RecurringFrequency.monthly) return null;
    final income = facts.effectiveMonthlyIncome;
    if (income == null || income <= 0) return null;
    final monthEnd = DateTime(facts.now.year, facts.now.month + 1);
    final billsLeft = facts.obligations
        .where(
          (item) =>
              !item.nextDueAt.isBefore(facts.today) &&
              item.nextDueAt.isBefore(monthEnd),
        )
        .fold(0.0, (sum, item) => sum + item.amount);
    final daysLeft = facts.daysLeftInMonth + 1;
    final spare =
        facts.balance - billsLeft - facts.dailyAverageRecent * daysLeft;
    if (spare < income * 0.2) return null;
    final suggestion = spare * 0.5;
    return SmartInsight(
      id: 'idle-balance',
      kind: InsightKind.suggestion,
      tone: InsightTone.tip,
      icon: AppIcons.deposit,
      title: 'رصيد يمكن نقل جزء منه',
      body:
          'بعد الالتزامات الباقية وصرفك المعتاد حتى آخر الشهر يبقى في رصيدك نحو ${_p.money(spare)}. نقل نصفه (${_p.money(suggestion)}) إلى التوفير الآن يحفظه من الصرف.',
      detail:
          'الرصيد: ${_p.money(facts.balance)}\n'
          'التزامات باقية هذا الشهر: ${_p.money(billsLeft)}\n'
          'صرف متوقع حتى آخر الشهر: ${_p.money(facts.dailyAverageRecent * daysLeft)}',
      priority: 59,
      action: InsightAction.manualSave,
    );
  }

  // The yearly total at the average monthly saving (two months of savings
  // history).
  SmartInsight? _yearAhead() {
    if (facts.savingsMonthsCovered < 2) return null;
    final monthly = facts.averageMonthlySaving;
    if (monthly <= 0) return null;
    return SmartInsight(
      id: 'year-ahead',
      kind: InsightKind.estimate,
      tone: InsightTone.info,
      icon: AppIcons.calendarRange,
      title: 'توفيرك في سنة',
      body:
          'متوسط توفيرك ${_p.money(monthly)} شهرياً. إن استمر فسيصبح لديك ${_p.money(monthly * 12)} إضافية بعد سنة.',
      priority: 37,
    );
  }

  // One withdrawal in 30 days taking 30% of what savings held before it.
  SmartInsight? _largeWithdrawal() {
    final from = facts.today.subtract(const Duration(days: 30));
    WaffrTransaction? largest;
    for (final e in facts.savingsTransfers) {
      if (!e.isSavingsOut || e.dateTime.isBefore(from)) continue;
      if (largest == null || e.amount > largest.amount) largest = e;
    }
    if (largest == null) return null;
    final before = facts.savingsBalance + largest.amount;
    if (before <= 0 || largest.amount / before < 0.3) return null;
    return SmartInsight(
      id: 'large-withdrawal',
      topic: 'withdrawals',
      tone: InsightTone.warning,
      icon: AppIcons.withdraw,
      title: 'سحب كبير من التوفير',
      body:
          'سحبت ${_p.money(largest.amount)} من التوفير خلال آخر 30 يوماً، أي ${_p.percent(largest.amount / before)} مما كان فيه. أعِد بناءه تدريجياً بمبلغ ثابت مع كل دخل.',
      priority: 69,
      action: InsightAction.manualSave,
    );
  }

  // A month of history and an income, but nothing ever saved.
  SmartInsight? _neverSaved() {
    if (facts.savingsTransfers.isNotEmpty || facts.historyDays < 30) {
      return null;
    }
    final income = facts.effectiveMonthlyIncome;
    if (income == null || income <= 0) return null;
    return SmartInsight(
      id: 'never-saved',
      topic: 'savings-rate',
      tone: InsightTone.tip,
      icon: AppIcons.savings,
      title: 'لم تبدأ التوفير بعد',
      body:
          'لا يوجد أي تحويل إلى التوفير منذ بدأت. ابدأ بـ${_p.money(income * 0.05)} شهرياً (${_p.percent(0.05)} من دخلك)، ثم زِد المبلغ تدريجياً.',
      priority: 67,
      action: InsightAction.manualSave,
    );
  }

  // Two goals or more whose monthly needs exceed half again the average
  // monthly saving.
  SmartInsight? _goalsOverloaded() {
    final active = facts.goals.where((goal) => goal.ratio < 1).toList();
    if (active.length < 2 || facts.savingsMonthsCovered < 2) return null;
    var needed = 0.0;
    for (final goal in active) {
      final months = goal.deadline.difference(facts.today).inDays / 30;
      needed += goal.remaining / math.max(0.25, months);
    }
    final pace = facts.averageMonthlySaving;
    if (pace <= 0 || needed < pace * 1.5) return null;
    return SmartInsight(
      id: 'goals-overloaded',
      kind: InsightKind.suggestion,
      tone: InsightTone.tip,
      icon: AppIcons.flag,
      title: 'أهدافك أكبر من وتيرة توفيرك',
      body:
          'تحتاج ${Ar.activeGoals.of(active.length)} معاً إلى نحو ${_p.money(needed)} شهرياً، ومتوسط توفيرك ${_p.money(pace)}. رتّب الأهداف حسب الأولوية وركّز على الأقرب أولاً.',
      priority: 63,
    );
  }
}
