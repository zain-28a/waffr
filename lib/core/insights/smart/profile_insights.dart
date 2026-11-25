// Profile-scope insight rules: the health score, a money personality,
// habits, and the strongest report and savings findings.

import 'package:waffr/core/theme/app_icons.dart';
import 'package:waffr/core/insights/smart/arabic_text.dart';
import 'package:waffr/core/insights/smart/cashflow_insights.dart';
import 'package:waffr/core/insights/smart/insight_phrasing.dart';
import 'package:waffr/core/insights/smart/smart_facts.dart';
import 'package:waffr/core/insights/smart/smart_insight.dart';
import 'package:waffr/core/insights/smart/report_insights.dart';
import 'package:waffr/core/insights/smart/savings_insights.dart';

/// The Arabic name of the [HealthBand] that [score] falls in.
String healthLabel(int score) => switch (HealthBand.of(score)) {
  HealthBand.excellent => 'ممتازة',
  HealthBand.good => 'جيدة',
  HealthBand.fair => 'مقبولة',
  HealthBand.low => 'تحتاج إلى اهتمام',
};

/// Rules for the profile's overall analysis.
class ProfileInsights {
  /// Rules over [facts], worded through the run's shared phrasing.
  ProfileInsights(this.facts, this._p);

  /// The numbers of this run.
  final SmartFacts facts;

  final InsightPhrasing _p;

  /// The health score, persona and habits, then the two strongest report
  /// and savings insights.
  List<SmartInsight> all() {
    // Report and savings rules run first, as they always have, so a seed
    // keeps giving the same wording.
    final reports = ReportInsights(facts, _p).all()
      ..sort((a, b) => b.priority.compareTo(a.priority));
    final savings = SavingsInsights(facts, _p).all()
      ..sort((a, b) => b.priority.compareTo(a.priority));
    return [
      _healthInsight(),
      ?_persona(),
      ?_streak(),
      ?_usageDuration(),
      ?_loggingHabit(),
      ?_loggingImproved(),
      ...CashflowInsights(facts, _p).forProfile(),
      ...reports.take(2),
      ...savings.take(2),
    ];
  }

  /// Weighted 0-100 score from the parts the data can support.
  int healthScore() => _healthParts().score;

  // Points per part, and the lines shown in the score card's details.
  ({int score, List<String> lines}) _healthParts() {
    var earned = 0.0;
    var possible = 0.0;
    final lines = <String>[];
    final income = facts.effectiveMonthlyIncome;

    // Saving rate (30) and the weight of bills (15) need a known income.
    if (income != null && income > 0) {
      // A new user's first month is not three months of missed saving.
      // The 20% target is a share of income, never of expenses.
      final rate = facts.averageMonthlySaving / income;
      final points = (rate / 0.2).clamp(0.0, 1.0) * 30;
      earned += points;
      possible += 30;
      lines.add('التوفير: ${points.round()}/30');

      // Full points up to 30% of income in bills, none from 60%.
      final obligationShare = facts.obligationsMonthly / income;
      final obligationPoints =
          (1 - ((obligationShare - 0.3) / 0.3).clamp(0.0, 1.0)) * 15;
      earned += obligationPoints;
      possible += 15;
      lines.add('الالتزامات: ${obligationPoints.round()}/15');
    }

    // Whether the balance lasts until the next income (25). Without a pace
    // or an income date, any balance earns a neutral 15.
    final runway = facts.runwayDays;
    final untilIncome = facts.daysUntilIncome;
    if (runway != null && untilIncome != null && untilIncome > 0) {
      final points = (runway / untilIncome).clamp(0.0, 1.0) * 25;
      earned += points;
      possible += 25;
      lines.add('كفاية الرصيد: ${points.round()}/25');
    } else if (facts.balance > 0) {
      earned += 15;
      possible += 25;
      lines.add('كفاية الرصيد: 15/25');
    }

    // Spending trend against last month (15): full points from a 10% drop,
    // none from a 30% rise.
    if (facts.prevMonthSpentSameSpan > 0 && facts.monthSpent > 0) {
      final change =
          (facts.monthSpent - facts.prevMonthSpentSameSpan) /
          facts.prevMonthSpentSameSpan;
      final points = (1 - ((change + 0.1) / 0.4).clamp(0.0, 1.0)) * 15;
      earned += points;
      possible += 15;
      lines.add('اتجاه الصرف: ${points.round()}/15');
    }

    // Logging on 15 of the last 30 days earns all 15 points.
    final consistency = (facts.activeDaysLast30 / 15).clamp(0.0, 1.0) * 15;
    earned += consistency;
    possible += 15;
    lines.add('انتظام التسجيل: ${consistency.round()}/15');

    // Scale to 0-100 over the parts that applied.
    final score = possible <= 0 ? 50 : (earned / possible * 100).round();
    return (score: score.clamp(0, 100), lines: lines);
  }

  // The health score card.
  SmartInsight _healthInsight() {
    final parts = _healthParts();
    final label = healthLabel(parts.score);
    final good = parts.score >= 65;
    return SmartInsight(
      id: 'health-score',
      // A weighted reading of several parts, not a recorded number.
      kind: InsightKind.estimate,
      tone: good
          ? InsightTone.positive
          : (parts.score >= 45 ? InsightTone.info : InsightTone.warning),
      icon: AppIcons.heart,
      title: _p.pick([
        'صحتك المالية $label',
        'مؤشرك المالي \u2066${parts.score}/100\u2069',
        'تقييمك العام: $label',
      ]),
      body: good
          ? _p.pick([
              'مؤشرك ${parts.score} من 100، وهو توازن جيد بين الصرف والتوفير.',
              'وضعك المالي صحي، وأقوى نقاطك تظهر في التفاصيل.',
            ])
          : _p.pick([
              'مؤشرك ${parts.score} من 100. افتح التفاصيل لترى الجانب الذي يحتاج إلى تحسين أولاً.',
              'هناك مساحة للتحسّن، وتحسين جانب واحد يرفع المؤشر بسرعة.',
            ]),
      detail: parts.lines.join('\n'),
      priority: 100,
    );
  }

  // A money personality, named only from measured habits: a month of
  // history and fifteen expenses first, then the saving rate over the
  // months saved, plans, the share of fun spending and logging regularity.
  SmartInsight? _persona() {
    if (facts.historyDays < 30 || facts.expenses.length < 15) return null;
    final income = facts.effectiveMonthlyIncome;
    final rate = income == null || income <= 0
        ? null
        : facts.averageMonthlySaving / income;
    final recent = facts.categoryTotals(
      facts.today.subtract(const Duration(days: 59)),
      facts.today.add(const Duration(days: 1)),
    );
    final recentTotal = recent.values.fold(0.0, (sum, v) => sum + v);
    final top = largestCategory(recent);
    final topShare = top == null || recentTotal <= 0
        ? 0.0
        : top.value / recentTotal;

    final String name;
    final String body;
    if (rate != null && rate >= 0.2) {
      name = 'المدّخر المنضبط';
      body =
          'توفّر في المتوسط ${_p.percent(rate)} من دخلك شهرياً، أي فوق نسبة ${_p.percent(0.2)} الشائعة. التوفير عندك عادة لا استثناء.';
    } else if (rate != null &&
        rate >= 0.05 &&
        facts.goals.isNotEmpty &&
        facts.obligations.isNotEmpty) {
      name = 'المخطّط';
      body =
          'لديك ${Ar.activeGoals.of(facts.goals.length)} والتزامات مسجّلة، وتوفّر ${_p.percent(rate)} من دخلك. الخطوة التالية رفع هذه النسبة تدريجياً.';
    } else if (rate != null && rate >= 0.05) {
      name = 'المتوازن';
      body =
          'توفّر ${_p.percent(rate)} من دخلك في المتوسط وتصرف الباقي بانتظام. هدف توفير واضح يمنح هذا التوازن وجهة.';
    } else if (top != null &&
        topShare >= 0.35 &&
        (top.key == 'ترفيه' || top.key == 'طعام')) {
      final category = Ar.category(top.key);
      name = 'محبّ التجارب';
      body =
          '$category يأخذ ${_p.percent(topShare)} من صرفك في آخر شهرين. الاستمتاع مهم، وتحديد مبلغ شهري له يحميه من استنزاف الميزانية.';
    } else if (facts.activeDaysLast30 >= 15) {
      name = 'المتابع الدقيق';
      body =
          'سجّلت مصروفات في ${_p.days(facts.activeDaysLast30)} من آخر 30 يوماً، وهذا ما يجعل الأرقام هنا موثوقة. حوّل هذه المتابعة الآن إلى هدف توفير.';
    } else {
      name = 'في بداية الطريق';
      body = 'عاداتك المالية ما زالت تتشكّل. التسجيل اليومي وتحويل مبلغ صغير إلى التوفير مع كل دخل يكشفان لك الكثير خلال شهر.';
    }
    return SmartInsight(
      id: 'persona',
      tone: InsightTone.info,
      icon: AppIcons.brain,
      title: _p.pick(['شخصيتك المالية: $name', 'أنت «$name»']),
      body: body,
      priority: 90,
    );
  }

  // The daily-use streak.
  SmartInsight? _streak() {
    final count = facts.streakCount;
    if (count <= 0) return null;
    final run = Ar.consecutiveDays.of(count);
    if (count >= 7) {
      return SmartInsight(
        id: 'streak',
        tone: InsightTone.positive,
        icon: AppIcons.flame,
        title: _p.pick(['سلسلة من $run!', 'التزام رائع']),
        body: _p.pick([
          'تفتح وفّر منذ $run، والاستمرار هو سرّ النتائج.',
          'أكملت $run من المتابعة، فلا تكسر السلسلة!',
        ]),
        priority: 58,
      );
    }
    return SmartInsight(
      id: 'streak',
      tone: InsightTone.tip,
      icon: AppIcons.flame,
      title: _p.pick(['ابنِ سلسلتك', 'سلسلتك الحالية: ${_p.days(count)}']),
      body: _p.pick([
        'سلسلتك الحالية ${_p.days(count)}. افتح التطبيق يومياً ولو لدقيقة لتصل إلى أسبوع كامل.',
        'تُبنى العادات بالتكرار، وهدفك القادم ${Ar.consecutiveDays.of(7)}.',
      ]),
      priority: 36,
    );
  }

  // How long the app has been used (from a week on).
  SmartInsight? _usageDuration() {
    final started = facts.usageStartedAt;
    if (started == null) return null;
    final days = facts.today.difference(started).inDays + 1;
    if (days < 7) return null;
    return SmartInsight(
      id: 'usage-duration',
      tone: InsightTone.info,
      icon: AppIcons.history,
      title: _p.pick(['${_p.days(days)} مع وفّر', 'رحلتك مستمرة']),
      body: _p.pick([
        'بدأت قبل ${_p.days(days)}، وسجّلت ${Ar.expenses.of(facts.expenses.length)} منذ ذلك الحين.',
        'خلال ${_p.days(days)} جمعت بيانات تكفي لفهم عاداتك، وكل يوم إضافي يجعل التحليل أدق.',
      ]),
      priority: 28,
    );
  }

  // Logging on five days more in the last 30 than in the 30 before.
  SmartInsight? _loggingImproved() {
    if (facts.historyDays < 60) return null;
    final now = facts.activeDaysLast30;
    final before = {
      for (final e in facts.expensesBetween(
        facts.today.subtract(const Duration(days: 60)),
        facts.today.subtract(const Duration(days: 30)),
      ))
        DateTime(e.dateTime.year, e.dateTime.month, e.dateTime.day),
    }.length;
    if (now - before < 5) return null;
    return SmartInsight(
      id: 'logging-improved',
      tone: InsightTone.positive,
      icon: AppIcons.calendarCheck,
      title: 'تسجيلك أكثر انتظاماً',
      body:
          'سجّلت مصروفات في ${_p.days(now)} من آخر 30 يوماً، مقابل ${_p.days(before)} في الثلاثين التي قبلها.',
      priority: 34,
    );
  }

  // A nudge after three idle days, or praise for logging on 20 of the last
  // 30 days.
  SmartInsight? _loggingHabit() {
    final last = facts.lastExpenseAt;
    if (last == null) return null;
    final idle = facts.today
        .difference(DateTime(last.year, last.month, last.day))
        .inDays;
    if (idle >= 3) {
      return SmartInsight(
        id: 'logging-habit',
        tone: InsightTone.tip,
        icon: AppIcons.calendarEdit,
        title: _p.pick(['آخر مصروف قبل ${_p.days(idle)}', 'هل نسيت التسجيل؟']),
        body: _p.pick([
          'لم تسجّل أي مصروف منذ ${_p.days(idle)}، والتحليل أدق حين تكون البيانات كاملة.',
          'سجّل ما صرفته في الأيام الماضية ولو تقريبياً، ليبقى رصيدك واقعياً.',
        ]),
        priority: 76,
        action: InsightAction.addExpense,
      );
    }
    if (facts.activeDaysLast30 >= 20) {
      return SmartInsight(
        id: 'logging-habit',
        tone: InsightTone.positive,
        icon: AppIcons.calendarEdit,
        title: _p.pick(['تسجيل منتظم', 'بياناتك دقيقة']),
        body:
            'سجّلت مصاريف في ${_p.days(facts.activeDaysLast30)} من آخر 30 يوماً، وهذا ما يجعل الأرقام هنا موثوقة.',
        priority: 32,
      );
    }
    return null;
  }
}
