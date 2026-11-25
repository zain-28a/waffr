// Report-scope insight rules: where the money goes. Each rule checks one
// pattern in the numbers and, when it applies, writes one insight card.
//
// Every rule states only what the recorded data shows, and stays quiet
// until there is enough of it: a trend needs both spans to hold several
// expenses, a monthly comparison needs a month the user actually tracked
// from its start. Longer-range patterns live in report_patterns.dart and
// income-based ones in cashflow_insights.dart; this file runs them all.

import 'package:waffr/core/theme/app_icons.dart';
import 'package:waffr/core/insights/smart/arabic_text.dart';
import 'package:waffr/core/insights/smart/cashflow_insights.dart';
import 'package:waffr/core/insights/smart/insight_phrasing.dart';
import 'package:waffr/core/insights/smart/report_patterns.dart';
import 'package:waffr/core/insights/smart/smart_facts.dart';
import 'package:waffr/core/insights/smart/smart_insight.dart';
import 'package:waffr/data/models/transaction.dart';

/// The category with the largest total in [totals], or null when empty.
/// Equal totals resolve by label, so the answer never depends on map order.
MapEntry<String, double>? largestCategory(Map<String, double> totals) {
  if (totals.isEmpty) return null;
  return totals.entries.reduce((a, b) {
    if (a.value != b.value) return a.value > b.value ? a : b;
    return a.key.compareTo(b.key) <= 0 ? a : b;
  });
}

/// The category label of [expense]; none counts as «أخرى».
String categoryOf(WaffrTransaction expense) => expense.category ?? 'أخرى';

/// Rules for the reports screen: trends, categories, pace and bills.
class ReportInsights {
  /// Rules over [facts], worded through the run's shared phrasing.
  ReportInsights(this.facts, this._p);

  /// The numbers of this run.
  final SmartFacts facts;

  final InsightPhrasing _p;

  /// Least expenses in a span before its total is compared with another.
  static const int minSpanExpenses = 3;

  /// Every report rule that applies, in a fixed order (the order keeps
  /// seeded runs stable). With no expenses only the "start logging" card.
  List<SmartInsight> all() {
    if (!facts.hasExpenses) return [_noExpensesYet()];
    return [
      ?_earlyData(),
      ?_monthTrend(),
      ?_weekTrend(),
      ?_topCategory(),
      ?_categorySpike(),
      ?_categoryDrop(),
      ?_projection(),
      ?_runway(),
      ?_weekdayPeak(),
      ?_smallExpenses(),
      ?_largestExpense(),
      ?_noSpendDays(),
      ?_paymentMix(),
      ?_nightSpending(),
      ?_uncategorized(),
      ?_obligationsSoon(),
      ?_obligationsShare(),
      ...ReportPatterns(facts, _p).all(),
      ...CashflowInsights(facts, _p).forReports(),
    ];
  }

  // Expenses of this month so far.
  late final List<WaffrTransaction> _month = facts.expensesBetween(
    facts.monthStart,
    facts.today.add(const Duration(days: 1)),
  );

  // Nothing logged yet: invite the first expense.
  SmartInsight _noExpensesYet() => SmartInsight(
    id: 'no-expenses',
    tone: InsightTone.tip,
    icon: AppIcons.editNote,
    title: _p.pick([
      'ابدأ بأول مصروف',
      'التحليل بانتظار بياناتك',
      'سجّل مصروفاتك لتظهر القراءة',
    ]),
    body: _p.pick([
      'لا توجد مصروفات مسجّلة بعد. سجّل ما تصرفه يومياً، وستظهر هنا وجهة أموالك ومواضع التوفير.',
      'كل مصروف تسجّله يجعل التحليل أدق. ابدأ اليوم ولو بمصروف صغير.',
      'بعد أسبوعين من التسجيل المنتظم تظهر هنا المقارنات والاتجاهات.',
    ]),
    priority: 100,
    action: InsightAction.addExpense,
  );

  // Under two weeks of records: say what the analysis can and cannot tell
  // yet, so a short report is not mistaken for a verdict.
  SmartInsight? _earlyData() {
    final days = facts.historyDays;
    if (days >= 14) return null;
    final left = 14 - days;
    return SmartInsight(
      id: 'early-data',
      tone: InsightTone.info,
      icon: AppIcons.hourglass,
      title: _p.pick(['التحليل في بدايته', 'المقارنات بعد أسبوعين']),
      body: _p.pick([
        'سجّلت حتى الآن ${Ar.expenses.of(facts.expenses.length)} خلال ${_p.days(days)}. المقارنات والاتجاهات تظهر بعد ${_p.days(left)} أخرى من التسجيل.',
        'ما زالت بياناتك قليلة للحكم على عاداتك، لذلك تظهر الآن الأرقام المؤكدة فقط. تابع التسجيل ${_p.days(left)} أخرى.',
      ]),
      priority: 64,
    );
  }

  // This month so far against the same days of last month. From the 5th,
  // when last month was tracked from its start and both spans hold a few
  // expenses.
  SmartInsight? _monthTrend() {
    final now = facts.monthSpent;
    final before = facts.prevMonthSpentSameSpan;
    if (now <= 0 || before <= 0 || facts.dayOfMonth < 5) return null;
    if (!facts.coversMonth(1)) return null;
    final prevCount = facts
        .expensesBetween(facts.prevMonthStart, facts.prevMonthSameDay)
        .length;
    if (_month.length < minSpanExpenses || prevCount < minSpanExpenses) {
      return null;
    }
    final change = (now - before) / before;
    final detail =
        'هذا الشهر حتى اليوم: ${_p.money(now)}\nالفترة نفسها من الشهر الماضي: ${_p.money(before)}';

    if (change > 0.10) {
      return SmartInsight(
        id: 'month-trend',
        topic: 'month-trend',
        tone: InsightTone.warning,
        icon: AppIcons.trendingUp,
        title: _p.pick([
          'صرفك أعلى من الشهر الماضي',
          'زيادة ${_p.percent(change)} عن الشهر الماضي',
          'وتيرة صرف أسرع من الشهر الماضي',
        ]),
        body: _p.pick([
          'صرفت ${_p.money(now)} حتى اليوم ${facts.dayOfMonth} من الشهر، أي أكثر بنسبة ${_p.percent(change)} من الأيام نفسها في الشهر الماضي.',
          'الفارق عن الفترة نفسها من الشهر الماضي ${_p.money(now - before)}. راجع أكبر تصنيفاتك لتعرف مصدر الزيادة.',
          'ارتفع صرفك من ${_p.money(before)} إلى ${_p.money(now)} مقارنةً بالأيام نفسها من الشهر الماضي.',
        ]),
        detail: detail,
        priority: 80 + (change * 20).clamp(0, 15).round(),
        action: InsightAction.expenseHistory,
      );
    }
    if (change < -0.10) {
      return SmartInsight(
        id: 'month-trend',
        topic: 'month-trend',
        tone: InsightTone.positive,
        icon: AppIcons.trendingDown,
        title: _p.pick([
          'صرفك أقل من الشهر الماضي',
          'انخفاض ${_p.percent(change)} في الصرف',
          'شهر أهدأ من سابقه',
        ]),
        body: _p.pick([
          'صرفت ${_p.money(now)} حتى الآن، أي أقل بنسبة ${_p.percent(change)} من الأيام نفسها في الشهر الماضي.',
          'صرفك أقل بمقدار ${_p.money(before - now)} من الفترة نفسها في الشهر الماضي. إن بقي هذا الفارق حتى آخر الشهر فيمكنك نقله إلى التوفير.',
          'تراجع صرفك من ${_p.money(before)} إلى ${_p.money(now)} في الأيام نفسها.',
        ]),
        detail: detail,
        priority: 70,
      );
    }
    return SmartInsight(
      id: 'month-trend',
      topic: 'month-trend',
      tone: InsightTone.info,
      icon: AppIcons.dragHandle,
      title: _p.pick(['صرف مستقر', 'الوتيرة نفسها كالشهر الماضي']),
      body: _p.pick([
        'صرفك هذا الشهر قريب من الشهر الماضي: ${_p.money(now)} مقابل ${_p.money(before)} في الأيام نفسها.',
        'لا فرق يُذكر بين هذا الشهر والذي قبله في الفترة نفسها (${_p.money(now)} و${_p.money(before)}).',
      ]),
      detail: detail,
      priority: 40,
    );
  }

  // This week against the same days of last week; swings of 25% or more,
  // from the third day of the week and with a few expenses in each span.
  SmartInsight? _weekTrend() {
    final now = facts.weekSpent;
    final before = facts.prevWeekSpentSameSpan;
    if (now <= 0 || before <= 0) return null;
    if (facts.weekDaysElapsed < 3 || facts.historyDays < 14) return null;
    final tomorrow = facts.today.add(const Duration(days: 1));
    final thisCount = facts.expensesBetween(facts.weekStart, tomorrow).length;
    final prevCount = facts
        .expensesBetween(
          facts.weekStart.subtract(const Duration(days: 7)),
          tomorrow.subtract(const Duration(days: 7)),
        )
        .length;
    if (thisCount < minSpanExpenses || prevCount < minSpanExpenses) {
      return null;
    }
    final change = (now - before) / before;
    if (change.abs() < 0.25) return null;
    final up = change > 0;
    final daysLeft = 7 - facts.weekDaysElapsed;
    return SmartInsight(
      id: 'week-trend',
      topic: 'week-trend',
      tone: up ? InsightTone.warning : InsightTone.positive,
      icon: up ? AppIcons.arrowUpRight : AppIcons.arrowDownRight,
      title: up
          ? _p.pick(['أسبوع أغلى من سابقه', 'ارتفاع في صرف هذا الأسبوع'])
          : _p.pick(['أسبوع أوفر من سابقه', 'صرف أسبوعي أقل']),
      body: up
          ? _p.pick([
              'صرفت هذا الأسبوع ${_p.money(now)}، أي أكثر بنسبة ${_p.percent(change)} من الأيام نفسها في الأسبوع الماضي.',
              daysLeft > 0
                  ? 'يسير هذا الأسبوع أسرع بنسبة ${_p.percent(change)} من الأسبوع الماضي، وما زالت أمامك ${_p.days(daysLeft)} لتعديل المسار.'
                  : 'كان هذا الأسبوع أسرع بنسبة ${_p.percent(change)} من الأسبوع الماضي.',
            ])
          : _p.pick([
              'صرفت هذا الأسبوع ${_p.money(now)}، أي أقل بنسبة ${_p.percent(change)} من الأيام نفسها في الأسبوع الماضي.',
              'انخفض صرفك هذا الأسبوع بمقدار ${_p.money(before - now)} مقارنةً بالأيام نفسها من الأسبوع الماضي.',
            ]),
      detail:
          'هذا الأسبوع: ${_p.money(now)}\nالأيام نفسها من الأسبوع الماضي: ${_p.money(before)}',
      priority: up ? 62 : 48,
    );
  }

  // One category taking 30% or more of this month's spending, once the
  // month holds a handful of expenses.
  SmartInsight? _topCategory() {
    final top = largestCategory(facts.monthCategories);
    if (top == null || facts.monthSpent <= 0) return null;
    if (_month.length < 5 || facts.dayOfMonth < 5) return null;
    final share = top.value / facts.monthSpent;
    if (share < 0.3 || facts.monthCategories.length < 2) return null;
    final name = Ar.category(top.key);
    final heavy = share > 0.5;
    return SmartInsight(
      id: 'top-category',
      topic: 'top-category',
      tone: heavy ? InsightTone.warning : InsightTone.info,
      icon: AppIcons.chartPie,
      title: _p.pick([
        '$name يستحوذ على الحصة الأكبر',
        '${_p.percent(share)} من صرفك على $name',
        'أكبر تصنيف هذا الشهر: $name',
      ]),
      body: _p.pick([
        'صرفت ${_p.money(top.value)} على $name هذا الشهر، أي ${_p.percent(share)} من إجمالي صرفك.',
        heavy
            ? 'أكثر من نصف صرفك هذا الشهر ذهب إلى $name (${_p.money(top.value)}). خفضه بنسبة ${_p.percent(0.1)} وحدها يوفّر ${_p.money(top.value * 0.1)}.'
            : '$name وحده يمثّل ${_p.percent(share)} من صرفك، وخفضه بنسبة ${_p.percent(0.1)} يوفّر ${_p.money(top.value * 0.1)}.',
      ]),
      detail: [
        for (final entry
            in (facts.monthCategories.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value)))
                .take(4))
          '${entry.key}: ${_p.money(entry.value)} (${_p.percent(entry.value / facts.monthSpent)})',
      ].join('\n'),
      priority: heavy ? 72 : 55,
    );
  }

  // The category that grew most against the same days of last month: over
  // 30% and worth a tenth of this month. From the 7th, with last month
  // tracked from its start and two expenses or more in the category.
  SmartInsight? _categorySpike() {
    if (facts.dayOfMonth < 7 || !facts.coversMonth(1)) return null;
    MapEntry<String, double>? worst;
    var worstGrowth = 0.0;
    for (final entry in facts.monthCategories.entries) {
      final before = facts.prevMonthCategories[entry.key] ?? 0;
      if (before <= 0) continue;
      final count = _month.where((e) => categoryOf(e) == entry.key).length;
      if (count < 2) continue;
      final growth = (entry.value - before) / before;
      final significant = entry.value - before >= facts.monthSpent * 0.1;
      if (growth > 0.3 && significant && growth > worstGrowth) {
        worst = entry;
        worstGrowth = growth;
      }
    }
    if (worst == null) return null;
    final before = facts.prevMonthCategories[worst.key]!;
    final name = Ar.category(worst.key);
    return SmartInsight(
      id: 'category-spike',
      tone: InsightTone.warning,
      icon: AppIcons.warning,
      title: _p.pick([
        'ارتفاع الصرف على $name بنسبة ${_p.percent(worstGrowth)}',
        '$name أعلى من المعتاد',
      ]),
      body: _p.pick([
        'صرفت على $name ${_p.money(worst.value)} مقابل ${_p.money(before)} في الفترة نفسها من الشهر الماضي.',
        'زاد صرفك على $name بمقدار ${_p.money(worst.value - before)} عن الشهر الماضي. افتح السجل لترى إن كانت الزيادة مصروفاً طارئاً أم عادة جديدة.',
      ]),
      detail:
          'هذا الشهر: ${_p.money(worst.value)}\nالفترة نفسها من الشهر الماضي: ${_p.money(before)}',
      priority: 85,
      action: InsightAction.expenseHistory,
    );
  }

  // The category that fell most: by a quarter, worth 8% of last month's
  // same span. Same guards as the spike.
  SmartInsight? _categoryDrop() {
    if (facts.dayOfMonth < 7 || !facts.coversMonth(1)) return null;
    MapEntry<String, double>? best;
    var bestSaving = 0.0;
    for (final entry in facts.prevMonthCategories.entries) {
      final now = facts.monthCategories[entry.key] ?? 0;
      final saving = entry.value - now;
      if (now < entry.value * 0.75 &&
          saving > bestSaving &&
          saving >= facts.prevMonthSpentSameSpan * 0.08) {
        best = entry;
        bestSaving = saving;
      }
    }
    if (best == null) return null;
    final name = Ar.category(best.key);
    return SmartInsight(
      id: 'category-drop',
      tone: InsightTone.positive,
      icon: AppIcons.thumbsUp,
      title: _p.pick(['تحسّن في $name', 'صرف أقل على $name']),
      body: _p.pick([
        'صرفك على $name أقل بمقدار ${_p.money(bestSaving)} من الفترة نفسها في الشهر الماضي.',
        'انخفض صرفك على $name بمقدار ${_p.money(bestSaving)} حتى الآن. إن بقي الفارق في رصيدك فانقله إلى التوفير.',
      ]),
      priority: 58,
      action: InsightAction.manualSave,
    );
  }

  // Month-end spending at the recent pace, against income when known. An
  // estimate, so from the 7th, with five expenses this month and a week of
  // history.
  SmartInsight? _projection() {
    if (facts.dayOfMonth < 7 || facts.monthSpent <= 0) return null;
    // The pace behind the estimate needs a week of history.
    if (_month.length < 5 || facts.historyDays < 7) return null;
    final projected = facts.projectedMonthSpend;
    final income = facts.effectiveMonthlyIncome;
    final detail =
        'متوسطك اليومي في آخر أسبوعين: ${_p.money(facts.dailyAverageRecent)}\n'
        'المتبقي من الشهر: ${_p.days(facts.daysLeftInMonth)}\n'
        'التقدير لنهاية الشهر: ${_p.money(projected)}';

    if (income != null && projected > income) {
      final room = income - facts.monthSpent;
      return SmartInsight(
        id: 'projection',
        topic: 'projection',
        kind: InsightKind.estimate,
        tone: InsightTone.warning,
        icon: AppIcons.chartSpline,
        title: _p.pick(['التقدير يتجاوز دخلك', 'بهذه الوتيرة ستتخطى دخلك']),
        body: room > 0 && facts.daysLeftInMonth > 0
            ? _p.pick([
                'إن استمر صرفك بوتيرة آخر أسبوعين فسيبلغ نحو ${_p.money(projected)} مع نهاية الشهر، ودخلك الشهري ${_p.money(income)}.',
                'التقدير لنهاية الشهر ${_p.money(projected)}، أي أكثر من دخلك بنحو ${_p.money(projected - income)}. صرف يومي في حدود ${_p.money(room / facts.daysLeftInMonth)} يبقيك ضمن الدخل.',
              ])
            : 'صرفت حتى الآن ${_p.money(facts.monthSpent)}، وهو أكثر من دخلك الشهري (${_p.money(income)}). بوتيرة آخر أسبوعين يصل الصرف إلى نحو ${_p.money(projected)}.',
        detail: detail,
        priority: 88,
      );
    }
    final comfortable = income != null && projected < income * 0.8;
    return SmartInsight(
      id: 'projection',
      topic: 'projection',
      kind: InsightKind.estimate,
      tone: comfortable ? InsightTone.positive : InsightTone.info,
      icon: AppIcons.chartSpline,
      title: _p.pick(['تقدير نهاية الشهر', 'إلى أين يتجه صرفك؟']),
      body: income != null
          ? _p.pick([
              'بوتيرة آخر أسبوعين سيكون صرفك نحو ${_p.money(projected)} من دخل قدره ${_p.money(income)}.',
              'المتوقع أن تنهي الشهر بصرف نحو ${_p.money(projected)}، فيبقى من دخلك قرابة ${_p.money(income - projected)}.',
            ])
          : _p.pick([
              'بوتيرة آخر أسبوعين سيبلغ صرفك نحو ${_p.money(projected)} مع نهاية الشهر.',
              'متوسطك اليومي الأخير ${_p.money(facts.dailyAverageRecent)}، أي قرابة ${_p.money(projected)} للشهر كاملاً.',
            ]),
      detail: detail,
      priority: comfortable ? 50 : 46,
    );
  }

  // Whether the balance lasts until the next income at the recent pace.
  // The pace needs a week of history and five expenses in 30 days.
  SmartInsight? _runway() {
    final untilIncome = facts.daysUntilIncome;
    if (untilIncome == null || untilIncome <= 0) return null;
    if (facts.balance <= 0) {
      return SmartInsight(
        id: 'runway',
        topic: 'runway',
        tone: InsightTone.warning,
        icon: AppIcons.wallet,
        title: _p.pick(['نفد رصيدك', 'رصيدك صفر']),
        body:
            'لم يبقَ رصيد حتى الدخل القادم بعد ${_p.days(untilIncome)}. أجّل غير الضروري، وسجّل أي دخل إضافي يصلك.',
        priority: 95,
        action: InsightAction.addIncome,
      );
    }
    final runway = facts.runwayDays;
    if (runway == null) return null;
    if (facts.historyDays < 7 || facts.loggedLast30 < 5) return null;
    final dailyLimit = facts.balance / untilIncome;
    final detail =
        'الرصيد الحالي: ${_p.money(facts.balance)}\n'
        'متوسطك اليومي في آخر أسبوعين: ${_p.money(facts.dailyAverageRecent)}\n'
        'الدخل القادم بعد: ${_p.days(untilIncome)}';
    if (runway < untilIncome) {
      final gap = (untilIncome - runway).ceil();
      return SmartInsight(
        id: 'runway',
        topic: 'runway',
        kind: InsightKind.estimate,
        tone: InsightTone.warning,
        icon: AppIcons.hourglass,
        title: _p.pick(['قد ينفد الرصيد قبل الدخل', 'وتيرتك أسرع من رصيدك']),
        body: _p.pick([
          'بوتيرة آخر أسبوعين ينفد رصيدك قبل الدخل القادم بنحو ${_p.days(gap)}. حدّك اليومي الآمن ${_p.money(dailyLimit)}.',
          'يكفي رصيدك ${runway < 1 ? '' : 'قرابة '}${_p.days(runway.floor())} بوتيرتك الحالية، والدخل بعد ${_p.days(untilIncome)}. اجعل صرفك اليومي نحو ${_p.money(dailyLimit)} بدلاً من ${_p.money(facts.dailyAverageRecent)}.',
        ]),
        detail: detail,
        priority: 92,
      );
    }
    return SmartInsight(
      id: 'runway',
      topic: 'runway',
      kind: InsightKind.estimate,
      tone: InsightTone.positive,
      icon: AppIcons.verified,
      title: _p.pick(['رصيدك يكفي حتى الدخل', 'وضعك آمن حتى الدخل القادم']),
      body: _p.pick([
        'بوتيرتك الحالية يكفي رصيدك حتى الدخل القادم بعد ${_p.days(untilIncome)}، ويمكنك صرف ما يصل إلى ${_p.money(dailyLimit)} يومياً.',
        'يغطي رصيدك قرابة ${_p.days(runway.floor())} بوتيرتك الحالية، والدخل بعد ${_p.days(untilIncome)}.',
      ]),
      detail: detail,
      priority: 50,
    );
  }

  // A weekday costing 60% more than the average day (three weeks of history
  // and four active weekdays needed).
  SmartInsight? _weekdayPeak() {
    if (facts.weeksOfHistory < 3) return null;
    final totals = facts.weekdayTotals;
    if (totals.length < 4) return null;
    final average = totals.values.reduce((a, b) => a + b) / 7;
    final peak = totals.entries.reduce(
      (a, b) => a.value != b.value
          ? (a.value > b.value ? a : b)
          : (a.key < b.key ? a : b),
    );
    if (average <= 0 || peak.value < average * 1.6) return null;
    final day = Ar.weekdays[peak.key]!;
    final above = peak.value / average - 1;
    return SmartInsight(
      id: 'weekday-peak',
      topic: 'weekday',
      tone: InsightTone.tip,
      icon: AppIcons.calendarDays,
      title: _p.pick(['يوم $day هو الأغلى', 'نمط أسبوعي: يوم $day']),
      body: _p.pick([
        'في الأسابيع الثمانية الأخيرة كان صرفك يوم $day أعلى بنسبة ${_p.percent(above)} من متوسط أيامك.',
        'يتكرر يوم $day بوصفه أغلى أيام أسبوعك. خطّط لمشترياته مسبقاً، أو حدّد له مبلغاً ثابتاً.',
      ]),
      priority: 45,
    );
  }

  // Small amounts (40% of the average expense or less) adding up to 12% of
  // the month or more.
  SmartInsight? _smallExpenses() {
    if (_month.length < 6) return null;
    final average = facts.monthSpent / _month.length;
    final small = _month.where((e) => e.amount <= average * 0.4).toList();
    final sum = small.fold(0.0, (total, e) => total + e.amount);
    if (small.length < 5 || sum < facts.monthSpent * 0.12) return null;
    final counted = Ar.smallExpenses.of(small.length);
    return SmartInsight(
      id: 'small-expenses',
      topic: 'small',
      tone: InsightTone.tip,
      icon: AppIcons.coffee,
      title: _p.pick(['المصروفات الصغيرة تتراكم', '$counted هذا الشهر']),
      body: _p.pick([
        'سجّلت هذا الشهر $counted مجموعها ${_p.money(sum)}، أي ${_p.percent(sum / facts.monthSpent)} من صرفك.',
        'كل مصروف صغير يبدو بسيطاً، لكن $counted بلغت معاً ${_p.money(sum)} هذا الشهر.',
      ]),
      priority: 54,
    );
  }

  // One expense worth a quarter of the month or more.
  SmartInsight? _largestExpense() {
    if (_month.length < 3) return null;
    final biggest = _month.reduce((a, b) => a.amount >= b.amount ? a : b);
    final share = biggest.amount / facts.monthSpent;
    if (share < 0.25) return null;
    final note = biggest.note?.trim() ?? '';
    final label = note.isNotEmpty
        ? Ar.quote(note)
        : 'في ${Ar.category(categoryOf(biggest))}';
    return SmartInsight(
      id: 'largest-expense',
      topic: 'large-expense',
      tone: InsightTone.info,
      icon: AppIcons.receipt,
      title: _p.pick(['مصروف كبير واحد', 'أكبر مصروف هذا الشهر']),
      body: _p.pick([
        'مصروفك $label بقيمة ${_p.money(biggest.amount)} يعادل ${_p.percent(share)} من صرفك هذا الشهر.',
        'مصروف واحد ($label، ${_p.money(biggest.amount)}) شكّل ${_p.percent(share)} من صرف الشهر. إن كان يتكرر كل فترة فخطّط له مسبقاً.',
      ]),
      priority: 44,
      action: InsightAction.expenseHistory,
    );
  }

  // Finished days without spending this month (from the 7th, three or
  // more).
  SmartInsight? _noSpendDays() {
    if (facts.dayOfMonth < 7) return null;
    final days = facts.noSpendDaysThisMonth;
    if (days < 3) return null;
    return SmartInsight(
      id: 'no-spend-days',
      topic: 'no-spend',
      tone: InsightTone.positive,
      icon: AppIcons.celebration,
      title: _p.pick(['${_p.days(days)} بلا صرف', 'أيام خالية من الصرف']),
      body: _p.pick([
        'مرّت ${_p.days(days)} هذا الشهر دون أي مصروف مسجّل.',
        'لديك ${_p.days(days)} بلا صرف حتى الآن هذا الشهر. يوم إضافي واحد كل أسبوع يخفّض صرفك الشهري بوضوح.',
      ]),
      priority: 42,
    );
  }

  // Card payments making up 70% of the month or more.
  SmartInsight? _paymentMix() {
    if (_month.length < 6 || facts.monthSpent <= 0) return null;
    final card = _month
        .where((e) => e.paymentMethod == 'بطاقة')
        .fold(0.0, (total, e) => total + e.amount);
    final share = card / facts.monthSpent;
    if (share < 0.7) return null;
    return SmartInsight(
      id: 'payment-mix',
      tone: InsightTone.tip,
      icon: AppIcons.creditCard,
      title: _p.pick([
        'معظم صرفك بالبطاقة',
        '${_p.percent(share)} من صرفك بالبطاقة',
      ]),
      body: _p.pick([
        'دفعت ${_p.percent(share)} من صرفك هذا الشهر بالبطاقة. الدفع بالبطاقة أسهل وأقل إحساساً بالمبلغ، فراجع مصروفاتها مرة كل أسبوع.',
        'معظم مصروفاتك هذا الشهر بالبطاقة (${_p.money(card)}). مراجعتها أسبوعياً تكشف المشتريات غير المخطط لها.',
      ]),
      priority: 35,
    );
  }

  // A quarter of recent expenses or more made between 10 pm and 4 am.
  SmartInsight? _nightSpending() {
    final recent = facts.expensesBetween(
      facts.today.subtract(const Duration(days: 30)),
      facts.today.add(const Duration(days: 1)),
    );
    if (recent.length < 8) return null;
    final night = recent
        .where((e) => e.dateTime.hour >= 22 || e.dateTime.hour < 4)
        .toList();
    if (night.length < 4 || night.length / recent.length < 0.25) return null;
    final sum = night.fold(0.0, (total, e) => total + e.amount);
    return SmartInsight(
      id: 'night-spending',
      tone: InsightTone.tip,
      icon: AppIcons.moon,
      title: _p.pick(['صرف ليلي ملحوظ', 'مصروفات بعد العاشرة مساءً']),
      body: _p.pick([
        '${Ar.expenses.of(night.length)} من مصروفاتك في آخر 30 يوماً كانت بعد العاشرة مساءً، بمجموع ${_p.money(sum)}.',
        'جزء واضح من صرفك (${_p.money(sum)}) يحدث في وقت متأخر ليلاً، وقرارات الشراء المتأخرة غالباً أقل تخطيطاً.',
      ]),
      priority: 38,
    );
  }

  // A quarter of the month or more filed under «أخرى».
  SmartInsight? _uncategorized() {
    final other = facts.monthCategories['أخرى'] ?? 0;
    if (_month.length < 4) return null;
    if (facts.monthSpent <= 0 || other / facts.monthSpent < 0.25) return null;
    return SmartInsight(
      id: 'uncategorized',
      tone: InsightTone.tip,
      icon: AppIcons.tag,
      title: _p.pick(['الكثير تحت «أخرى»', 'صنّف مصروفاتك بدقة']),
      body: _p.pick([
        'يقع ${_p.percent(other / facts.monthSpent)} من صرفك هذا الشهر تحت «أخرى». تصنيفه بدقة يجعل المقارنات أوضح.',
        'كلما قلّ ما تضعه تحت «أخرى» صارت القراءة أدق. أنشئ تصنيفاً خاصاً لما يتكرر منه.',
      ]),
      priority: 40,
      action: InsightAction.expenseHistory,
    );
  }

  // Bills due within three days; a warning when they exceed the balance.
  SmartInsight? _obligationsSoon() {
    final soon = facts.obligations
        .where(
          (item) =>
              !item.nextDueAt.isBefore(facts.today) &&
              item.nextDueAt.isBefore(facts.today.add(const Duration(days: 4))),
        )
        .toList();
    if (soon.isEmpty) return null;
    final total = soon.fold(0.0, (sum, item) => sum + item.amount);
    final names = soon.map((item) => Ar.quote(item.name)).take(3).join('، ');
    final short = total > facts.balance;
    return SmartInsight(
      id: 'obligations-soon',
      topic: 'obligations-upcoming',
      tone: short ? InsightTone.warning : InsightTone.info,
      icon: AppIcons.calendarRepeat,
      title: _p.pick(['التزامات خلال أيام', 'دفعات قريبة']),
      body: short
          ? 'تستحق خلال الأيام الثلاثة القادمة: $names، بمجموع ${_p.money(total)}، ورصيدك الحالي ${_p.money(facts.balance)} لا يغطيها.'
          : _p.pick([
              'تستحق خلال الأيام الثلاثة القادمة: $names، بمجموع ${_p.money(total)}.',
              'جهّز ${_p.money(total)} لالتزامات قريبة: $names.',
            ]),
      priority: short ? 90 : 60,
      action: InsightAction.obligations,
    );
  }

  // Recurring bills taking 15% of income or more (heavy from 40%).
  SmartInsight? _obligationsShare() {
    final monthly = facts.obligationsMonthly;
    final income = facts.effectiveMonthlyIncome;
    if (monthly <= 0 || income == null || income <= 0) return null;
    final share = monthly / income;
    if (share < 0.15) return null;
    final heavy = share >= 0.4;
    return SmartInsight(
      id: 'obligations-share',
      tone: heavy ? InsightTone.warning : InsightTone.info,
      icon: AppIcons.repeat,
      title: heavy
          ? _p.pick(['الالتزامات ثقيلة', 'التزاماتك تستهلك الكثير'])
          : _p.pick(['التزاماتك الشهرية', 'حصة الالتزامات من الدخل']),
      body: heavy
          ? _p.pick([
              'تستهلك التزاماتك المتكررة (${_p.money(monthly)} شهرياً) ${_p.percent(share)} من دخلك. راجعها وابحث عمّا يمكن إلغاؤه أو تخفيضه.',
              monthly < income
                  ? 'يذهب ${_p.percent(share)} من دخلك إلى التزامات ثابتة، فيبقى للصرف اليومي والتوفير ${_p.money(income - monthly)} فقط.'
                  : 'التزاماتك المتكررة (${_p.money(monthly)} شهرياً) أكبر من دخلك الشهري (${_p.money(income)}). راجعها قبل أي شيء آخر.',
            ])
          : _p.pick([
              'تبلغ التزاماتك المتكررة نحو ${_p.money(monthly)} شهرياً، أي ${_p.percent(share)} من دخلك.',
              'تدفع شهرياً قرابة ${_p.money(monthly)} التزامات ثابتة، وهي ${_p.percent(share)} من الدخل.',
            ]),
      priority: heavy ? 75 : 36,
      action: InsightAction.obligations,
    );
  }
}
