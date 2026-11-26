// Longer-range spending patterns for the report scope: full-month
// comparisons, multi-month trends, recurring purchases found in the
// history, habits by day and amount, and month-end estimates measured
// against past months.
//
// Each rule needs the months it reads to be tracked from their start
// (SmartFacts.coversMonth) and enough expenses to tell a pattern from
// chance. Cards that tell the same story as a rule in report_insights.dart
// share its topic, so the engine keeps only the stronger one.

import 'dart:math' as math;

import 'package:waffr/core/insights/smart/arabic_text.dart';
import 'package:waffr/core/insights/smart/insight_phrasing.dart';
import 'package:waffr/core/insights/smart/report_insights.dart';
import 'package:waffr/core/insights/smart/smart_facts.dart';
import 'package:waffr/core/insights/smart/smart_insight.dart';
import 'package:waffr/core/theme/app_icons.dart';
import 'package:waffr/data/models/calendar_period.dart';
import 'package:waffr/data/models/recurring_expense.dart';
import 'package:waffr/data/models/transaction.dart';

/// A note reduced to the form two spellings of the same purchase share:
/// trimmed, single-spaced, lower case, and with the common Arabic letter
/// variants folded (أ إ آ → ا, ة → ه, ى → ي).
String normalizedNote(String? note) {
  final text = (note ?? '').trim().toLowerCase().replaceAll(
    RegExp(r'\s+'),
    ' ',
  );
  return text
      .replaceAll(RegExp('[أإآ]'), 'ا')
      .replaceAll('ة', 'ه')
      .replaceAll('ى', 'ي');
}

/// Spending patterns over weeks and months.
class ReportPatterns {
  /// Rules over [facts], worded through the run's shared phrasing.
  ReportPatterns(this.facts, this._p);

  /// The numbers of this run.
  final SmartFacts facts;

  final InsightPhrasing _p;

  late final DateTime _tomorrow = facts.today.add(const Duration(days: 1));

  /// Every pattern rule that applies, in a fixed order.
  List<SmartInsight> all() => [
    ?_lastMonthCompare(),
    ?_longTrend(),
    ?_newCategory(),
    ?_concentration(),
    ?_recurringFound(),
    ?_weekendHeavy(),
    ?_averageTicket(),
    ?_frequencyUp(),
    ?_paydaySpike(),
    ?_forecastVsLastMonth(),
    ?_frontLoaded(),
    ?_obligationsRestOfMonth(),
    ?_habitCost(),
    ?_noSpendStreak(),
    ?_steadyCategory(),
    ?_bestMonth(),
  ];

  int _countBetween(DateTime start, DateTime end) =>
      facts.expensesBetween(start, end).length;

  // Last full month against the one before it. It carries the comparison
  // in the first days of a month, before this month says anything.
  SmartInsight? _lastMonthCompare() {
    if (!facts.coversMonth(2)) return null;
    final last = facts.fullMonthSpent(1);
    final before = facts.fullMonthSpent(2);
    if (last <= 0 || before <= 0) return null;
    if (_countBetween(facts.monthStartBack(1), facts.monthStart) < 5) {
      return null;
    }
    final change = (last - before) / before;
    final lastName = CalendarPeriod.monthName(facts.monthStartBack(1).month);
    final beforeName = CalendarPeriod.monthName(facts.monthStartBack(2).month);
    final detail =
        '$lastName: ${_p.money(last)}\n$beforeName: ${_p.money(before)}';
    if (change.abs() < 0.08) {
      return SmartInsight(
        id: 'last-month-compare',
        topic: 'month-trend',
        tone: InsightTone.info,
        icon: AppIcons.dragHandle,
        title: 'شهران متقاربان',
        body:
            'أنهيت $lastName بصرف ${_p.money(last)}، قريباً من $beforeName (${_p.money(before)}).',
        detail: detail,
        priority: 34,
      );
    }
    final up = change > 0;
    return SmartInsight(
      id: 'last-month-compare',
      topic: 'month-trend',
      tone: up ? InsightTone.warning : InsightTone.positive,
      icon: up ? AppIcons.trendingUp : AppIcons.trendingDown,
      title: up
          ? 'كان $lastName أغلى من $beforeName'
          : 'كان $lastName أوفر من $beforeName',
      body: up
          ? _p.pick([
              'صرفت في $lastName ${_p.money(last)}، أي أكثر بنسبة ${_p.percent(change)} من $beforeName.',
              'زاد صرف $lastName بمقدار ${_p.money(last - before)} عن $beforeName. أبقِ عينك على هذا الشهر من بدايته.',
            ])
          : _p.pick([
              'صرفت في $lastName ${_p.money(last)}، أي أقل بنسبة ${_p.percent(change)} من $beforeName.',
              'أنهيت $lastName بصرف أقل بمقدار ${_p.money(before - last)} من $beforeName.',
            ]),
      detail: detail,
      priority: up ? 56 : 50,
    );
  }

  // Three tracked months in a row, each 5% or more above (or below) the
  // one before.
  SmartInsight? _longTrend() {
    if (!facts.coversMonth(3)) return null;
    final months = [
      for (var back = 3; back >= 1; back--) facts.fullMonthSpent(back),
    ];
    if (months.any((value) => value <= 0)) return null;
    final steps = [
      for (var i = 1; i < months.length; i++)
        (months[i] - months[i - 1]) / months[i - 1],
    ];
    final rising = steps.every((step) => step >= 0.05);
    final falling = steps.every((step) => step <= -0.05);
    if (!rising && !falling) return null;
    final total = (months.last - months.first) / months.first;
    final detail = [
      for (var back = 3; back >= 1; back--)
        '${CalendarPeriod.monthName(facts.monthStartBack(back).month)}: ${_p.money(facts.fullMonthSpent(back))}',
    ].join('\n');
    return SmartInsight(
      id: 'long-trend',
      tone: rising ? InsightTone.warning : InsightTone.positive,
      icon: rising ? AppIcons.chartLine : AppIcons.trendingDown,
      title: rising ? 'صرفك يرتفع منذ ثلاثة أشهر' : 'صرفك ينخفض منذ ثلاثة أشهر',
      body: rising
          ? 'ارتفع صرفك الشهري ثلاثة أشهر متتالية، من ${_p.money(months.first)} إلى ${_p.money(months.last)} (${_p.percent(total)}). ارتفاع متواصل كهذا يستحق مراجعة التزاماتك وأكبر تصنيفاتك.'
          : 'انخفض صرفك الشهري ثلاثة أشهر متتالية، من ${_p.money(months.first)} إلى ${_p.money(months.last)} (${_p.percent(total)}).',
      detail: detail,
      priority: rising ? 78 : 60,
    );
  }

  // A category this month that did not appear in the three months before
  // and already takes a tenth of the month.
  SmartInsight? _newCategory() {
    if (facts.dayOfMonth < 7 || !facts.coversMonth(2)) return null;
    if (facts.monthSpent <= 0) return null;
    final earlier = facts
        .categoryTotals(facts.monthStartBack(3), facts.monthStart)
        .keys
        .toSet();
    if (earlier.isEmpty) return null;
    MapEntry<String, double>? found;
    for (final entry in facts.monthCategories.entries) {
      if (earlier.contains(entry.key) || entry.key == 'أخرى') continue;
      if (entry.value < facts.monthSpent * 0.1) continue;
      if (found == null || entry.value > found.value) found = entry;
    }
    if (found == null) return null;
    final name = Ar.category(found.key);
    return SmartInsight(
      id: 'new-category',
      tone: InsightTone.info,
      icon: AppIcons.shapes,
      title: 'بند جديد هذا الشهر: $name',
      body:
          'صرفت على $name ${_p.money(found.value)} هذا الشهر (${_p.percent(found.value / facts.monthSpent)} من صرفك)، ولم يظهر في الأشهر الثلاثة السابقة.',
      priority: 47,
    );
  }

  // Two categories taking 80% of the month, with three or more in use.
  SmartInsight? _concentration() {
    if (facts.dayOfMonth < 10 || facts.monthSpent <= 0) return null;
    final sorted = facts.monthCategories.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (sorted.length < 3) return null;
    final top2 = sorted[0].value + sorted[1].value;
    final share = top2 / facts.monthSpent;
    if (share < 0.8) return null;
    final a = Ar.category(sorted[0].key);
    final b = Ar.category(sorted[1].key);
    return SmartInsight(
      id: 'concentration',
      topic: 'top-category',
      tone: InsightTone.info,
      icon: AppIcons.chartPie,
      title: 'صرفك مركّز في بندين',
      body:
          '$a و$b معاً يمثّلان ${_p.percent(share)} من صرفك هذا الشهر. أي خفض فيهما يظهر أثره مباشرة في الرصيد.',
      priority: 50,
    );
  }

  // The same purchase (same note) in three of the last four months at a
  // steady amount, not yet saved as a recurring bill.
  SmartInsight? _recurringFound() {
    if (!facts.coversMonth(2)) return null;
    final known = {
      for (final item in facts.obligations) normalizedNote(item.name),
    };
    final byNote = <String, Map<int, double>>{};
    final labels = <String, String>{};
    for (var back = 0; back <= 3; back++) {
      final start = facts.monthStartBack(back);
      final end = back == 0 ? _tomorrow : facts.monthStartBack(back - 1);
      for (final e in facts.expensesBetween(start, end)) {
        if (RecurringExpense.isRecurringSource(e.sourceId)) continue;
        final key = normalizedNote(e.note);
        if (key.length < 2 || known.contains(key)) continue;
        labels[key] ??= e.note!.trim();
        final months = byNote.putIfAbsent(key, () => {});
        months[back] = (months[back] ?? 0) + e.amount;
      }
    }
    String? best;
    double bestAmount = 0;
    for (final entry in byNote.entries) {
      final months = entry.value;
      if (months.length < 3) continue;
      final amounts = months.values.toList()..sort();
      final median = amounts[amounts.length ~/ 2];
      if (median <= 0) continue;
      final steady = amounts.every((a) => (a - median).abs() <= median * 0.2);
      if (steady && median > bestAmount) {
        best = entry.key;
        bestAmount = median;
      }
    }
    if (best == null) return null;
    final name = Ar.quote(labels[best]!);
    return SmartInsight(
      id: 'recurring-found',
      tone: InsightTone.tip,
      icon: AppIcons.calendarRepeat,
      title: 'مصروف يتكرر كل شهر: $name',
      body:
          'سجّلت $name في ${Ar.months.of(byNote[best]!.length)} مختلفة بمبلغ قريب من ${_p.money(bestAmount)}. أضفه إلى الالتزامات ليُذكّرك وفّر بموعده ويحسبه في تقديراتك.',
      priority: 57,
      action: InsightAction.obligations,
    );
  }

  // Friday and Saturday costing half again as much per day as the rest of
  // the week, over the last eight weeks (four weeks of history needed).
  SmartInsight? _weekendHeavy() {
    if (facts.weeksOfHistory < 4) return null;
    final totals = facts.weekdayTotals;
    final weekend =
        (totals[DateTime.friday] ?? 0) + (totals[DateTime.saturday] ?? 0);
    final weekdays = totals.entries
        .where((e) => e.key != DateTime.friday && e.key != DateTime.saturday)
        .fold(0.0, (sum, e) => sum + e.value);
    if (weekend <= 0 || weekdays <= 0) return null;
    final ratio = (weekend / 2) / (weekdays / 5);
    if (ratio < 1.5) return null;
    return SmartInsight(
      id: 'weekend-heavy',
      topic: 'weekday',
      tone: InsightTone.tip,
      icon: AppIcons.calendarDays,
      title: 'عطلة نهاية الأسبوع مكلفة',
      body:
          'يومَي الجمعة والسبت يكلّفانك في المتوسط ${_p.percent(ratio - 1)} أكثر من باقي أيام الأسبوع، بحسب الأسابيع الثمانية الأخيرة. حدّد مبلغاً للعطلة قبل أن تبدأ.',
      priority: 46,
    );
  }

  // The average expense this month 30% above the tracked months before.
  SmartInsight? _averageTicket() {
    if (facts.dayOfMonth < 10) return null;
    final month = facts.expensesBetween(facts.monthStart, _tomorrow);
    if (month.length < 8) return null;
    var count = 0;
    var total = 0.0;
    for (var back = 1; back <= 3; back++) {
      if (!facts.coversMonth(back)) continue;
      final rows = facts.expensesBetween(
        facts.monthStartBack(back),
        facts.monthStartBack(back - 1),
      );
      count += rows.length;
      total += rows.fold(0.0, (sum, e) => sum + e.amount);
    }
    if (count < 15) return null;
    final before = total / count;
    final now = facts.monthSpent / month.length;
    final change = (now - before) / before;
    if (change < 0.3) return null;
    return SmartInsight(
      id: 'average-ticket',
      tone: InsightTone.info,
      icon: AppIcons.receipt,
      title: 'مصروفاتك أكبر من المعتاد',
      body:
          'متوسط المصروف الواحد هذا الشهر ${_p.money(now)}، مقابل ${_p.money(before)} في الأشهر السابقة. عدد المشتريات ليس السبب؛ قيمتها هي التي ارتفعت.',
      priority: 43,
    );
  }

  // Many more purchases than the same days of last month (40% more, ten or
  // more this month).
  SmartInsight? _frequencyUp() {
    if (facts.dayOfMonth < 10 || !facts.coversMonth(1)) return null;
    final now = _countBetween(facts.monthStart, _tomorrow);
    final before = _countBetween(facts.prevMonthStart, facts.prevMonthSameDay);
    if (now < 10 || before < 5) return null;
    final change = (now - before) / before;
    if (change < 0.4) return null;
    return SmartInsight(
      id: 'frequency-up',
      tone: InsightTone.info,
      icon: AppIcons.listChecks,
      title: 'مشتريات أكثر من الشهر الماضي',
      body:
          'سجّلت ${Ar.expenses.of(now)} حتى الآن هذا الشهر مقابل ${Ar.expenses.of(before)} في الأيام نفسها من الشهر الماضي. كثرة المشتريات الصغيرة ترفع الصرف دون أن تلاحظ.',
      priority: 41,
    );
  }

  // Two incomes or more in 90 days after which 40% of the period's spending
  // happened in the first three days.
  SmartInsight? _paydaySpike() {
    final from = facts.today.subtract(const Duration(days: 89));
    final incomes =
        facts.incomes.where((e) => !e.dateTime.isBefore(from)).toList()
          ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
    if (incomes.length < 2) return null;
    final shares = <double>[];
    for (var i = 0; i < incomes.length; i++) {
      final start = incomes[i].dateTime;
      final nextIncome = i + 1 < incomes.length
          ? incomes[i + 1].dateTime
          : start.add(const Duration(days: 30));
      final end = nextIncome.isBefore(_tomorrow) ? nextIncome : _tomorrow;
      if (end.difference(start).inDays < 10) continue;
      final total = facts.spentBetween(start, end);
      if (total <= 0) continue;
      final first = facts.spentBetween(
        start,
        start.add(const Duration(days: 3)),
      );
      shares.add(first / total);
    }
    if (shares.length < 2) return null;
    final average = shares.reduce((a, b) => a + b) / shares.length;
    if (average < 0.4) return null;
    return SmartInsight(
      id: 'payday-spike',
      tone: InsightTone.tip,
      icon: AppIcons.banknote,
      title: 'صرف كبير بعد وصول الدخل',
      body:
          'في المتوسط ${_p.percent(average)} من صرف كل فترة يحدث في الأيام الثلاثة الأولى بعد وصول الدخل. حوّل مبلغ التوفير فور وصول الدخل، قبل أن تبدأ المشتريات.',
      priority: 53,
      action: InsightAction.manualSave,
    );
  }

  // The month-end estimate against last month's full total.
  SmartInsight? _forecastVsLastMonth() {
    if (facts.dayOfMonth < 10 || !facts.coversMonth(1)) return null;
    final last = facts.fullMonthSpent(1);
    if (last <= 0) return null;
    if (_countBetween(facts.monthStart, _tomorrow) < 5) return null;
    final projected = facts.projectedMonthSpend;
    final change = (projected - last) / last;
    if (change.abs() < 0.15) return null;
    final up = change > 0;
    final lastName = CalendarPeriod.monthName(facts.monthStartBack(1).month);
    return SmartInsight(
      id: 'forecast-vs-last',
      topic: 'projection',
      kind: InsightKind.estimate,
      tone: up ? InsightTone.warning : InsightTone.positive,
      icon: AppIcons.chartSpline,
      title: up
          ? 'الشهر يتجه ليكون أغلى من $lastName'
          : 'الشهر يتجه ليكون أوفر من $lastName',
      body: up
          ? 'بوتيرة آخر أسبوعين ينتهي الشهر بصرف نحو ${_p.money(projected)}، مقابل ${_p.money(last)} في $lastName.'
          : 'بوتيرة آخر أسبوعين ينتهي الشهر بصرف نحو ${_p.money(projected)}، أقل من $lastName (${_p.money(last)}) بنحو ${_p.money(last - projected)}.',
      priority: up ? 66 : 49,
    );
  }

  // Half of last month's spending in its first week.
  SmartInsight? _frontLoaded() {
    if (facts.dayOfMonth > 10 || !facts.coversMonth(1)) return null;
    final start = facts.monthStartBack(1);
    final total = facts.fullMonthSpent(1);
    if (total <= 0 || _countBetween(start, facts.monthStart) < 8) return null;
    final firstWeek = facts.spentBetween(
      start,
      start.add(const Duration(days: 7)),
    );
    final share = firstWeek / total;
    if (share < 0.5) return null;
    return SmartInsight(
      id: 'front-loaded',
      tone: InsightTone.tip,
      icon: AppIcons.calendarRange,
      title: 'بداية الشهر تستهلك الكثير',
      body:
          'ذهب ${_p.percent(share)} من صرف الشهر الماضي في أسبوعه الأول. وزّع مشتريات البداية على أسابيع الشهر ليبقى لك هامش في آخره.',
      priority: 52,
    );
  }

  // Bills still due before the month ends, against the balance.
  SmartInsight? _obligationsRestOfMonth() {
    final monthEnd = DateTime(facts.now.year, facts.now.month + 1);
    final due = facts.obligations
        .where(
          (item) =>
              !item.nextDueAt.isBefore(facts.today) &&
              item.nextDueAt.isBefore(monthEnd),
        )
        .toList();
    if (due.length < 2) return null;
    final total = due.fold(0.0, (sum, item) => sum + item.amount);
    final short = total > facts.balance;
    return SmartInsight(
      id: 'obligations-month',
      topic: 'obligations-upcoming',
      tone: short ? InsightTone.warning : InsightTone.info,
      icon: AppIcons.calendarCheck,
      title: short
          ? 'التزامات الشهر أكبر من رصيدك'
          : 'التزامات باقية هذا الشهر',
      body: short
          ? 'تبقى عليك هذا الشهر ${Ar.payments.of(due.length)} بمجموع ${_p.money(total)}، ورصيدك الآن ${_p.money(facts.balance)}.'
          : 'تبقى عليك هذا الشهر ${Ar.payments.of(due.length)} بمجموع ${_p.money(total)}، فيبقى من رصيدك بعدها ${_p.money(facts.balance - total)}.',
      priority: short ? 84 : 39,
      action: InsightAction.obligations,
    );
  }

  // The same small purchase six times or more in 30 days, and what it
  // costs over a year at that rate.
  SmartInsight? _habitCost() {
    final recent = facts.expensesBetween(
      facts.today.subtract(const Duration(days: 29)),
      _tomorrow,
    );
    if (recent.length < 10 || facts.historyDays < 30) return null;
    final average =
        recent.fold(0.0, (sum, e) => sum + e.amount) / recent.length;
    final groups = <String, List<WaffrTransaction>>{};
    for (final e in recent) {
      final key = normalizedNote(e.note);
      if (key.length < 2 || e.amount > average * 0.6) continue;
      groups.putIfAbsent(key, () => []).add(e);
    }
    MapEntry<String, List<WaffrTransaction>>? top;
    for (final entry in groups.entries) {
      if (entry.value.length < 6) continue;
      if (top == null || entry.value.length > top.value.length) top = entry;
    }
    if (top == null) return null;
    final sum = top.value.fold(0.0, (total, e) => total + e.amount);
    final name = Ar.quote(top.value.first.note!.trim());
    return SmartInsight(
      id: 'habit-cost',
      topic: 'small',
      kind: InsightKind.estimate,
      tone: InsightTone.tip,
      icon: AppIcons.coffee,
      title: 'عادة صغيرة: $name',
      body:
          'سجّلت $name ${Ar.times.of(top.value.length)} في آخر 30 يوماً بمجموع ${_p.money(sum)}. بهذا المعدل تكلّفك نحو ${_p.money(sum * 365 / 30)} في السنة.',
      priority: 55,
    );
  }

  // The longest run of finished days this month without spending (four
  // days or more).
  SmartInsight? _noSpendStreak() {
    if (facts.dayOfMonth < 6) return null;
    final first = facts.firstActivityDay;
    if (first == null) return null;
    final from = first.isAfter(facts.monthStart) ? first : facts.monthStart;
    final spent = {
      for (final e in facts.expensesBetween(from, facts.today))
        DateTime(e.dateTime.year, e.dateTime.month, e.dateTime.day),
    };
    var best = 0;
    var run = 0;
    for (
      var day = from;
      day.isBefore(facts.today);
      day = DateTime(day.year, day.month, day.day + 1)
    ) {
      run = spent.contains(day) ? 0 : run + 1;
      best = math.max(best, run);
    }
    if (best < 4) return null;
    return SmartInsight(
      id: 'no-spend-streak',
      topic: 'no-spend',
      tone: InsightTone.positive,
      icon: AppIcons.flame,
      title: '${Ar.consecutiveDays.of(best)} بلا صرف',
      body:
          'مرّت عليك هذا الشهر ${Ar.consecutiveDays.of(best)} دون أي مصروف مسجّل، وهي أطول سلسلة لك هذا الشهر.',
      priority: 44,
    );
  }

  // The biggest category of the last three tracked months stayed within
  // 10% of its average each month: a fixed cost to plan around.
  SmartInsight? _steadyCategory() {
    if (!facts.coversMonth(3)) return null;
    final perMonth = [
      for (var back = 1; back <= 3; back++)
        facts.categoryTotals(
          facts.monthStartBack(back),
          facts.monthStartBack(back - 1),
        ),
    ];
    final combined = <String, double>{};
    for (final month in perMonth) {
      month.forEach(
        (key, value) => combined[key] = (combined[key] ?? 0) + value,
      );
    }
    final top = largestCategory(combined);
    if (top == null || top.key == 'أخرى') return null;
    final values = [for (final month in perMonth) month[top.key] ?? 0];
    if (values.any((v) => v <= 0)) return null;
    final average = top.value / 3;
    if (values.any((v) => (v - average).abs() > average * 0.1)) return null;
    final name = Ar.category(top.key);
    return SmartInsight(
      id: 'steady-category',
      tone: InsightTone.info,
      icon: AppIcons.gauge,
      title: '$name ثابت كل شهر',
      body:
          'صرفك على $name بقي قرابة ${_p.money(average)} شهرياً في الأشهر الثلاثة الأخيرة. اعتبره مبلغاً ثابتاً في خطتك، وابحث عن التوفير في البنود المتغيرة.',
      priority: 33,
    );
  }

  // From the 20th: the month is heading below each of the three tracked
  // months before it.
  SmartInsight? _bestMonth() {
    if (facts.dayOfMonth < 20 || !facts.coversMonth(3)) return null;
    if (_countBetween(facts.monthStart, _tomorrow) < 8) return null;
    final past = [
      for (var back = 1; back <= 3; back++) facts.fullMonthSpent(back),
    ];
    if (past.any((v) => v <= 0)) return null;
    final projected = facts.projectedMonthSpend;
    final lowest = past.reduce(math.min);
    if (projected >= lowest * 0.97) return null;
    return SmartInsight(
      id: 'best-month',
      kind: InsightKind.estimate,
      tone: InsightTone.positive,
      icon: AppIcons.trophy,
      title: 'قد يكون أوفر شهر لك مؤخراً',
      body:
          'بوتيرة آخر أسبوعين ينتهي الشهر بصرف نحو ${_p.money(projected)}، أقل من كل شهر من الأشهر الثلاثة السابقة (أقلها ${_p.money(lowest)}).',
      priority: 59,
    );
  }
}
