// Income against spending. Waffr has no per-category budgets, so the
// income is the limit: the share of it spent so far against the share of
// the month gone, what was left of last month's income, and over 90 days
// how much of the income the spending takes.
//
// Rules that compare with income use SmartFacts.effectiveMonthlyIncome
// (the configured monthly income, else the recent recorded average);
// month-by-month rules use income actually recorded in that month.

import 'dart:math' as math;

import 'package:waffr/core/insights/smart/arabic_text.dart';
import 'package:waffr/core/insights/smart/insight_phrasing.dart';
import 'package:waffr/core/insights/smart/report_insights.dart';
import 'package:waffr/core/insights/smart/smart_facts.dart';
import 'package:waffr/core/insights/smart/smart_insight.dart';
import 'package:waffr/core/theme/app_icons.dart';
import 'package:waffr/data/models/calendar_period.dart';

/// Income-based rules, for the reports and the overall view.
class CashflowInsights {
  /// Rules over [facts], worded through the run's shared phrasing.
  CashflowInsights(this.facts, this._p);

  /// The numbers of this run.
  final SmartFacts facts;

  final InsightPhrasing _p;

  /// The rules shown with the spending analysis.
  List<SmartInsight> forReports() => [
    ?_budgetPace(),
    ?_categoryVsIncome(),
    ?_weeklyCap(),
    ?_lastMonthIncome(),
    ?_noIncomeKnown(),
    ?_dailyAllowance(),
  ];

  /// The rules shown in the overall view.
  List<SmartInsight> forProfile() => [
    ?_spendToIncome(),
    ?_incomeVariable(),
    ?_incomeUp(),
    ?_fixedCosts(),
  ];

  // Share of the monthly income spent so far against the share of the
  // month gone: well ahead of the calendar is a warning, well behind it a
  // good sign. From the 5th (the 10th for the good sign).
  SmartInsight? _budgetPace() {
    final income = facts.effectiveMonthlyIncome;
    if (income == null || income <= 0 || facts.dayOfMonth < 5) return null;
    if (facts.monthSpent <= 0 || !facts.tracksThisMonth) return null;
    final spentShare = facts.monthSpent / income;
    final elapsed = facts.dayOfMonth / facts.daysInMonth;
    final detail =
        'المصروف هذا الشهر: ${_p.money(facts.monthSpent)}\n'
        'الدخل الشهري: ${_p.money(income)}\n'
        'مضى من الشهر: ${_p.percent(elapsed)}';
    if (spentShare >= elapsed + 0.15) {
      return SmartInsight(
        id: 'budget-pace',
        topic: 'projection',
        tone: InsightTone.warning,
        icon: AppIcons.gauge,
        title: 'صرفك يسبق الشهر',
        body: _p.pick([
          'صرفت ${_p.percent(spentShare)} من دخلك الشهري، ولم يمضِ من الشهر إلا ${_p.percent(elapsed)}.',
          'ذهب ${_p.percent(spentShare)} من الدخل ومضى ${_p.percent(elapsed)} من الشهر. بقي من الدخل ${_p.money(math.max(0, income - facts.monthSpent))}، وأمامك ${_p.days(facts.daysLeftInMonth + 1)} حتى آخر الشهر.',
        ]),
        detail: detail,
        priority: 83,
      );
    }
    if (facts.dayOfMonth >= 10 && spentShare <= elapsed - 0.2) {
      return SmartInsight(
        id: 'budget-pace',
        topic: 'projection',
        tone: InsightTone.positive,
        icon: AppIcons.gauge,
        title: 'صرفك أبطأ من الشهر',
        body:
            'مضى ${_p.percent(elapsed)} من الشهر وصرفت ${_p.percent(spentShare)} فقط من دخلك الشهري.',
        detail: detail,
        priority: 45,
      );
    }
    return null;
  }

  // This month's biggest category taking 30% of the monthly income.
  SmartInsight? _categoryVsIncome() {
    final income = facts.effectiveMonthlyIncome;
    if (income == null || income <= 0 || facts.dayOfMonth < 7) return null;
    final top = largestCategory(facts.monthCategories);
    if (top == null || top.key == 'أخرى') return null;
    final share = top.value / income;
    if (share < 0.3) return null;
    final name = Ar.category(top.key);
    return SmartInsight(
      id: 'category-vs-income',
      topic: 'top-category',
      tone: InsightTone.warning,
      icon: AppIcons.chartPie,
      title: '$name يأخذ ${_p.percent(share)} من دخلك',
      body:
          'صرفت على $name هذا الشهر ${_p.money(top.value)}، أي ${_p.percent(share)} من دخلك الشهري. بند واحد بهذا الحجم يضيّق هامش التوفير.',
      priority: 74,
      action: InsightAction.expenseHistory,
    );
  }

  // A weekly amount from the income after recurring bills, against this
  // week so far (from the third day of the week).
  SmartInsight? _weeklyCap() {
    final income = facts.effectiveMonthlyIncome;
    if (income == null || income <= 0 || facts.weekDaysElapsed < 3) {
      return null;
    }
    if (!facts.tracksThisWeek) return null;
    final free = income - facts.obligationsMonthly;
    if (free <= 0 || facts.weekSpent <= 0) return null;
    final cap = free * 7 / 30.4;
    final used = facts.weekSpent / cap;
    final detail =
        'الدخل بعد الالتزامات: ${_p.money(free)} شهرياً\n'
        'ما يعادله أسبوعياً: ${_p.money(cap)}\n'
        'صرف هذا الأسبوع: ${_p.money(facts.weekSpent)}';
    if (used >= 1) {
      return SmartInsight(
        id: 'weekly-cap',
        topic: 'week-trend',
        tone: InsightTone.warning,
        icon: AppIcons.calendarRange,
        title: 'تجاوزت حصة الأسبوع من دخلك',
        body:
            'حصة الأسبوع من دخلك بعد الالتزامات نحو ${_p.money(cap)}، وصرفت هذا الأسبوع ${_p.money(facts.weekSpent)}.',
        detail: detail,
        priority: 65,
      );
    }
    if (used < 0.5 || facts.weekDaysElapsed < 5) return null;
    return SmartInsight(
      id: 'weekly-cap',
      topic: 'week-trend',
      kind: InsightKind.suggestion,
      tone: InsightTone.info,
      icon: AppIcons.calendarRange,
      title: 'ما بقي من حصة الأسبوع',
      body:
          'من حصة الأسبوع (${_p.money(cap)}) بقي ${_p.money(cap - facts.weekSpent)}، وأمامك ${_p.days(8 - facts.weekDaysElapsed)} حتى نهاية الأسبوع.',
      detail: detail,
      priority: 43,
    );
  }

  // Last month: did the recorded income cover the spending, and what was
  // left of it.
  SmartInsight? _lastMonthIncome() {
    if (!facts.coversMonth(1)) return null;
    final income = facts.fullMonthIncome(1);
    final spent = facts.fullMonthSpent(1);
    if (income <= 0 || spent <= 0) return null;
    final name = CalendarPeriod.monthName(facts.monthStartBack(1).month);
    final detail =
        'دخل $name: ${_p.money(income)}\nمصروفات $name: ${_p.money(spent)}';
    if (spent > income) {
      return SmartInsight(
        id: 'last-month-income',
        topic: 'cashflow',
        tone: InsightTone.warning,
        icon: AppIcons.scale,
        title: 'صرفت في $name أكثر من دخلك',
        body:
            'سجّلت في $name دخلاً بقيمة ${_p.money(income)} ومصروفات بقيمة ${_p.money(spent)}، أي بفارق ${_p.money(spent - income)} غُطّي من رصيد سابق.',
        detail: detail,
        priority: 76,
      );
    }
    final kept = (income - spent) / income;
    if (kept < 0.1) return null;
    return SmartInsight(
      id: 'last-month-income',
      topic: 'cashflow',
      tone: InsightTone.positive,
      icon: AppIcons.scale,
      title: 'بقي من دخل $name ${_p.percent(kept)}',
      body:
          'من دخل $name (${_p.money(income)}) صرفت ${_p.money(spent)}، وبقي ${_p.money(income - spent)}.',
      detail: detail,
      priority: 48,
    );
  }

  // Regular logging but no income anywhere: comparisons with income are
  // impossible until one is added.
  SmartInsight? _noIncomeKnown() {
    if (facts.effectiveMonthlyIncome != null) return null;
    if (facts.loggedLast30 < 8) return null;
    return SmartInsight(
      id: 'no-income',
      tone: InsightTone.tip,
      icon: AppIcons.banknote,
      title: 'أضف دخلك لقراءة أدق',
      body: 'لا يوجد دخل مسجّل في آخر 90 يوماً ولا دخل شهري محدد. بعد إضافته تظهر هنا نسبة صرفك من الدخل وكفاية رصيدك حتى آخر الشهر.',
      priority: 63,
      action: InsightAction.addIncome,
    );
  }

  // Without a recurring income date: what the balance allows per day to
  // the end of the month.
  SmartInsight? _dailyAllowance() {
    if (facts.daysUntilIncome != null || facts.balance <= 0) return null;
    if (facts.effectiveMonthlyIncome == null) return null;
    final days = facts.daysLeftInMonth + 1;
    if (days < 3) return null;
    return SmartInsight(
      id: 'daily-allowance',
      topic: 'runway',
      kind: InsightKind.suggestion,
      tone: InsightTone.info,
      icon: AppIcons.wallet,
      title: 'حدّك اليومي حتى آخر الشهر',
      body:
          'رصيدك ${_p.money(facts.balance)} و${_p.days(days)} باقية من الشهر، أي نحو ${_p.money(facts.balance / days)} لكل يوم إن أردت أن يكفيك حتى آخره.',
      priority: 47,
    );
  }

  // Spending against recorded income over 90 days (60 days of history).
  SmartInsight? _spendToIncome() {
    if (facts.historyDays < 60) return null;
    final from = facts.today.subtract(const Duration(days: 89));
    final income = facts.incomeLast90;
    final spent = facts.spentBetween(
      from,
      facts.today.add(const Duration(days: 1)),
    );
    if (income <= 0 || spent <= 0) return null;
    final ratio = spent / income;
    final detail =
        'الدخل في 90 يوماً: ${_p.money(income)}\nالمصروفات في 90 يوماً: ${_p.money(spent)}';
    if (ratio > 1) {
      return SmartInsight(
        id: 'spend-to-income',
        topic: 'cashflow',
        tone: InsightTone.warning,
        icon: AppIcons.scale,
        title: 'مصروفاتك أكبر من دخلك',
        body:
            'في آخر 90 يوماً صرفت ${_p.percent(ratio)} من دخلك المسجّل. الفارق (${_p.money(spent - income)}) جاء من رصيد سابق أو من دخل لم يُسجَّل.',
        detail: detail,
        priority: 82,
      );
    }
    if (ratio >= 0.85) {
      return SmartInsight(
        id: 'spend-to-income',
        topic: 'cashflow',
        tone: InsightTone.info,
        icon: AppIcons.scale,
        title: 'الدخل يكاد يُصرف كله',
        body:
            'في آخر 90 يوماً ذهب ${_p.percent(ratio)} من دخلك إلى المصروفات، فبقي هامش صغير للتوفير.',
        detail: detail,
        priority: 54,
      );
    }
    if (ratio <= 0.7) {
      return SmartInsight(
        id: 'spend-to-income',
        topic: 'cashflow',
        tone: InsightTone.positive,
        icon: AppIcons.scale,
        title: 'هامش جيد بين الدخل والصرف',
        body:
            'في آخر 90 يوماً صرفت ${_p.percent(ratio)} من دخلك، وبقي ${_p.money(income - spent)}.',
        detail: detail,
        priority: 46,
      );
    }
    return null;
  }

  // Monthly income varying by a quarter or more over three tracked months.
  SmartInsight? _incomeVariable() {
    if (!facts.coversMonth(3)) return null;
    final months = [
      for (var back = 1; back <= 3; back++) facts.fullMonthIncome(back),
    ];
    if (months.any((v) => v <= 0)) return null;
    final low = months.reduce(math.min);
    final high = months.reduce(math.max);
    if ((high - low) / high < 0.25) return null;
    return SmartInsight(
      id: 'income-variable',
      kind: InsightKind.suggestion,
      tone: InsightTone.tip,
      icon: AppIcons.chartStacked,
      title: 'دخلك يتغير من شهر لآخر',
      body:
          'تراوح دخلك المسجّل في الأشهر الثلاثة الأخيرة بين ${_p.money(low)} و${_p.money(high)}. خطّط لمصروفاتك على أساس الشهر الأقل، وادّخر الزيادة في الأشهر الأعلى.',
      priority: 52,
    );
  }

  // Last month's recorded income 15% above the two months before it.
  SmartInsight? _incomeUp() {
    if (!facts.coversMonth(3)) return null;
    final last = facts.fullMonthIncome(1);
    final before = (facts.fullMonthIncome(2) + facts.fullMonthIncome(3)) / 2;
    if (last <= 0 ||
        facts.fullMonthIncome(2) <= 0 ||
        facts.fullMonthIncome(3) <= 0) {
      return null;
    }
    if (last < before * 1.15) return null;
    return SmartInsight(
      id: 'income-up',
      kind: InsightKind.suggestion,
      tone: InsightTone.positive,
      icon: AppIcons.trendingUp,
      title: 'ارتفع دخلك الشهر الماضي',
      body:
          'سجّلت الشهر الماضي دخلاً بقيمة ${_p.money(last)}، أعلى بنحو ${_p.money(last - before)} من متوسط الشهرين السابقين. توفير الزيادة كلها أو بعضها يمنع ارتفاع الصرف معها.',
      priority: 51,
      action: InsightAction.manualSave,
    );
  }

  // Recurring bills making up half of normal monthly spending.
  SmartInsight? _fixedCosts() {
    final monthly = facts.obligationsMonthly;
    final average = facts.averageMonthlySpend;
    if (monthly <= 0 || average <= 0 || facts.historyDays < 30) return null;
    final share = monthly / average;
    if (share < 0.5) return null;
    return SmartInsight(
      id: 'fixed-costs',
      tone: InsightTone.info,
      icon: AppIcons.calendarRepeat,
      title: 'معظم صرفك ثابت',
      body:
          'التزاماتك المتكررة (${_p.money(monthly)} شهرياً) تعادل ${_p.percent(math.min(share, 1))} من صرفك الشهري المعتاد. التوفير الأكبر عندك يأتي من مراجعة هذه الالتزامات، لا من المصروفات اليومية.',
      priority: 49,
      action: InsightAction.obligations,
    );
  }
}
