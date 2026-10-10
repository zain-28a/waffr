// Turns SmartFacts into a SmartReport. Everything runs on the device.
//
// Each rule checks one pattern in the numbers and, when it applies, writes
// an insight. Titles and sentences come in several phrasings, and bodies
// may gain an opening phrase and a closing remark, so the seed changes the
// wording each time while the findings stay the same.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:waffr/core/insights/smart/arabic_text.dart';
import 'package:waffr/core/insights/smart/smart_facts.dart';
import 'package:waffr/core/insights/smart/smart_insight.dart';
import 'package:waffr/core/utils/money.dart';

class InsightEngine {
  final SmartFacts facts;
  final math.Random _random;

  InsightEngine(this.facts, {int? seed}) : _random = math.Random(seed);

  static const Map<InsightScope, int> _limits = {
    InsightScope.reports: 7,
    InsightScope.savings: 7,
    InsightScope.profile: 8,
  };

  SmartReport analyze(InsightScope scope) {
    final found = switch (scope) {
      InsightScope.reports => _reportsInsights(),
      InsightScope.savings => _savingsInsights(),
      InsightScope.profile => _profileInsights(),
    };

    // The cut is by priority alone so the findings stay the same; inside
    // it, near-equal priorities trade places between runs for variety.
    found.sort((a, b) => b.priority.compareTo(a.priority));
    final limited = found.take(_limits[scope]!).toList();
    final jitter = {for (final item in limited) item.id: _random.nextInt(8)};
    limited.sort(
      (a, b) => (b.priority + jitter[b.id]!).compareTo(a.priority + jitter[a.id]!),
    );
    limited.add(_tip(scope));

    final score = scope == InsightScope.profile ? healthScore() : null;
    return SmartReport(
      scope: scope,
      headline: _headline(scope, limited, score),
      summary: _summary(scope),
      insights: limited,
      healthScore: score,
    );
  }

  // ---------------------------------------------------------------------
  // Phrasing helpers
  // ---------------------------------------------------------------------

  T _pick<T>(List<T> options) => options[_random.nextInt(options.length)];

  String _m(double value) => '${formatMoney(value)} ${facts.currencySymbol}';

  // Isolated left-to-right so "20%" never flips inside Arabic text.
  String _pct(double ratio) => '\u2066${(ratio * 100).abs().round()}%\u2069';

  String _days(int n) => Ar.days.of(n);

  static const List<String> _openers = [
    'بحسب أرقامك،',
    'بعد مراجعة بياناتك،',
    'من خلال ما سجّلته،',
    'بالنظر إلى مصاريفك الأخيرة،',
    'وفق ما لاحظته،',
  ];

  static const Map<InsightTone, List<String>> _closers = {
    InsightTone.warning: [
      'تعديل بسيط الآن يوفّر عليك الكثير لاحقاً.',
      'يستحق هذا البند مراقبة أدق في الأيام القادمة.',
      'الانتباه المبكر يجعل التصحيح أسهل.',
      'ضع لهذا البند حدّاً واضحاً والتزم به.',
    ],
    InsightTone.positive: [
      'استمرّ على هذا النهج.',
      'تقدّم يستحق الإشادة.',
      'عادة ممتازة، حافظ عليها.',
      'خطوة في الاتجاه الصحيح.',
    ],
    InsightTone.tip: [
      'جرّبها هذا الأسبوع ولاحظ الفرق.',
      'خطوة صغيرة لكن أثرها كبير.',
      'يمكنك البدء بها اليوم.',
    ],
    InsightTone.info: [
      'معلومة تفيدك في التخطيط للشهر القادم.',
      'ضعها في حسابك عند التخطيط.',
    ],
  };

  // A body built from one core sentence, sometimes with an opener and a
  // closing remark, so repeated runs read like newly written text.
  // Openers and closers are used at most once per report, so two cards
  // never end with the same remark.
  String _say(InsightTone tone, List<String> cores) {
    final core = _pick(cores);
    final parts = <String>[];
    final opener = _fresh(_openers);
    if (opener != null && _random.nextDouble() < 0.35) {
      parts.add(opener);
      _usedPhrases.add(opener);
    }
    parts.add(core);
    final closer = _fresh(_closers[tone]!);
    if (closer != null && core.length < 110 && _random.nextDouble() < 0.5) {
      parts.add(closer);
      _usedPhrases.add(closer);
    }
    return parts.join(' ');
  }

  final Set<String> _usedPhrases = {};

  String? _fresh(List<String> options) {
    final unused = [
      for (final item in options)
        if (!_usedPhrases.contains(item)) item,
    ];
    return unused.isEmpty ? null : _pick(unused);
  }

  // ---------------------------------------------------------------------
  // Reports: where the money goes
  // ---------------------------------------------------------------------

  List<SmartInsight> _reportsInsights() {
    if (!facts.hasExpenses) return [_noExpensesYet()];
    return [
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
    ];
  }

  SmartInsight _noExpensesYet() => SmartInsight(
        id: 'no-expenses',
        tone: InsightTone.tip,
        icon: Icons.edit_note_rounded,
        title: _pick([
          'ابدأ بأول مصروف',
          'التحليل بانتظار بياناتك',
          'سجّل مصاريفك لأفهم عاداتك',
        ]),
        body: _pick([
          'لا توجد مصاريف مسجّلة بعد. سجّل ما تصرفه يومياً، وسأبدأ بإظهار وجهة أموالك وطرق التوفير.',
          'كل مصروف تسجّله يجعل التحليل أدق. ابدأ اليوم ولو بمصروف صغير.',
          'بعد أسبوع من التسجيل ستظهر هنا مقارنات واتجاهات ونصائح مصمّمة لك.',
        ]),
        priority: 100,
        action: InsightAction.addExpense,
      );

  SmartInsight? _monthTrend() {
    final now = facts.monthSpent;
    final before = facts.prevMonthSpentSameSpan;
    if (now <= 0 || before <= 0 || facts.dayOfMonth < 3) return null;
    final change = (now - before) / before;
    final detail =
        'هذا الشهر حتى اليوم: ${_m(now)}\nالشهر الماضي في الفترة نفسها: ${_m(before)}';

    if (change > 0.10) {
      return SmartInsight(
        id: 'month-trend',
        tone: InsightTone.warning,
        icon: Icons.trending_up_rounded,
        title: _pick([
          'صرفك أعلى من الشهر الماضي',
          'الصرف في ارتفاع',
          'زيادة بنسبة ${_pct(change)} عن الشهر الماضي',
          'وتيرة صرف أسرع من المعتاد',
        ]),
        body: _say(InsightTone.warning, [
          'صرفت ${_m(now)} حتى الآن، أي أكثر بنسبة ${_pct(change)} من الفترة نفسها في الشهر الماضي.',
          'مقارنةً بالأيام نفسها من الشهر الماضي، ارتفع صرفك بنسبة ${_pct(change)}. راجع أكبر تصنيفاتك لتعرف السبب.',
          'تسير مصاريفك هذا الشهر أسرع من المعتاد بنسبة ${_pct(change)}، والفارق حتى الآن ${_m(now - before)}.',
          'ارتفع إجمالي صرفك من ${_m(before)} إلى ${_m(now)} مقارنةً بالفترة نفسها من الشهر الماضي.',
        ]),
        detail: detail,
        priority: 80 + (change * 20).clamp(0, 15).round(),
      );
    }
    if (change < -0.10) {
      return SmartInsight(
        id: 'month-trend',
        tone: InsightTone.positive,
        icon: Icons.trending_down_rounded,
        title: _pick([
          'أحسنت! صرفك أقل',
          'انخفاض بنسبة ${_pct(change)} في الصرف',
          'شهر أوفر من سابقه',
          'مصاريفك في تراجع',
        ]),
        body: _say(InsightTone.positive, [
          'صرفت ${_m(now)} حتى الآن، أي أقل بنسبة ${_pct(change)} من الفترة نفسها في الشهر الماضي.',
          'تحسّن واضح: وفّرت ${_m(before - now)} مقارنةً بالأيام نفسها من الشهر الماضي.',
          'انخفض صرفك هذا الشهر بنسبة ${_pct(change)}، ويمكنك تحويل الفارق إلى التوفير.',
          'تراجع إجمالي صرفك من ${_m(before)} إلى ${_m(now)} في الفترة المماثلة.',
        ]),
        detail: detail,
        priority: 70,
      );
    }
    return SmartInsight(
      id: 'month-trend',
      tone: InsightTone.info,
      icon: Icons.drag_handle_rounded,
      title: _pick([
        'صرف مستقر',
        'الوتيرة نفسها كالشهر الماضي',
        'لا تغيير يُذكر',
      ]),
      body: _say(InsightTone.info, [
        'صرفك هذا الشهر قريب من الشهر الماضي: ${_m(now)} مقابل ${_m(before)}.',
        'وتيرتك ثابتة تقريباً مقارنةً بالشهر الماضي. الثبات جيد، والخطوة التالية خفض تصنيف واحد.',
        'لا فرق كبير بين هذا الشهر والذي قبله في الفترة نفسها.',
      ]),
      detail: detail,
      priority: 40,
    );
  }

  SmartInsight? _weekTrend() {
    final now = facts.weekSpent;
    final before = facts.prevWeekSpentSameSpan;
    if (now <= 0 || before <= 0) return null;
    final change = (now - before) / before;
    if (change.abs() < 0.25) return null;
    final up = change > 0;
    final tone = up ? InsightTone.warning : InsightTone.positive;
    return SmartInsight(
      id: 'week-trend',
      tone: tone,
      icon: up ? Icons.north_east_rounded : Icons.south_east_rounded,
      title: up
          ? _pick(['أسبوع أغلى من سابقه', 'ارتفاع في صرف هذا الأسبوع', 'الأسبوع الحالي مكلف'])
          : _pick(['أسبوع أوفر', 'هذا الأسبوع أهدأ', 'صرف أسبوعي أقل']),
      body: up
          ? _say(tone, [
              'صرفت هذا الأسبوع ${_m(now)}، أي أكثر بنسبة ${_pct(change)} من الأيام نفسها في الأسبوع الماضي.',
              'يسير هذا الأسبوع أسرع بنسبة ${_pct(change)} من الأسبوع الماضي، وما زال أمامك وقت لتعديل المسار.',
            ])
          : _say(tone, [
              'صرفت هذا الأسبوع ${_m(now)}، أي أقل بنسبة ${_pct(change)} من الأسبوع الماضي.',
              'أسبوع جيد! انخفض صرفك بنسبة ${_pct(change)} مقارنةً بالأسبوع الماضي.',
            ]),
      detail: 'هذا الأسبوع: ${_m(now)}\nالأسبوع الماضي في الأيام نفسها: ${_m(before)}',
      priority: up ? 62 : 48,
    );
  }

  MapEntry<String, double>? _largestCategory(Map<String, double> totals) {
    if (totals.isEmpty) return null;
    return totals.entries.reduce((a, b) => a.value >= b.value ? a : b);
  }

  SmartInsight? _topCategory() {
    final top = _largestCategory(facts.monthCategories);
    if (top == null || facts.monthSpent <= 0) return null;
    final share = top.value / facts.monthSpent;
    if (share < 0.3 || facts.monthCategories.length < 2) return null;
    final name = Ar.category(top.key);
    final tone = share > 0.5 ? InsightTone.warning : InsightTone.info;
    return SmartInsight(
      id: 'top-category',
      tone: tone,
      icon: Icons.pie_chart_outline_rounded,
      title: _pick([
        '$name يستحوذ على الحصة الأكبر',
        '${_pct(share)} من صرفك على $name',
        'أكبر تصنيف هذا الشهر: $name',
      ]),
      body: _say(tone, [
        'أنفقت ${_m(top.value)} على $name هذا الشهر، أي ${_pct(share)} من إجمالي صرفك.',
        '$name وحده يمثّل ${_pct(share)} من مصاريفك، وخفضه بنسبة ${_pct(0.1)} يوفّر ${_m(top.value * 0.1)}.',
        'إن أردت أثراً سريعاً في ميزانيتك فابدأ ب$name، إذ صرفت عليه ${_m(top.value)} حتى الآن.',
      ]),
      detail: [
        for (final entry in (facts.monthCategories.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value)))
            .take(4))
          '${entry.key}: ${_m(entry.value)} (${_pct(entry.value / facts.monthSpent)})',
      ].join('\n'),
      priority: share > 0.5 ? 72 : 55,
    );
  }

  SmartInsight? _categorySpike() {
    MapEntry<String, double>? worst;
    var worstGrowth = 0.0;
    for (final entry in facts.monthCategories.entries) {
      final before = facts.prevMonthCategories[entry.key] ?? 0;
      if (before <= 0) continue;
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
      icon: Icons.warning_amber_rounded,
      title: _pick([
        'ارتفاع الصرف على $name بنسبة ${_pct(worstGrowth)}',
        'قفزة في $name',
        'انتبه للصرف على $name',
        '$name أعلى بكثير من المعتاد',
      ]),
      body: _say(InsightTone.warning, [
        'صرفت على $name ${_m(worst.value)} مقابل ${_m(before)} في الفترة نفسها من الشهر الماضي.',
        'زاد صرفك على $name بمقدار ${_m(worst.value - before)} عن الشهر الماضي. هل هو مصروف طارئ أم عادة جديدة؟',
        'سجّل $name أكبر زيادة هذا الشهر بنسبة ${_pct(worstGrowth)}، فحدّد له سقفاً أسبوعياً.',
      ]),
      detail: 'هذا الشهر: ${_m(worst.value)}\nالشهر الماضي في الفترة نفسها: ${_m(before)}',
      priority: 85,
      action: InsightAction.expenseHistory,
    );
  }

  SmartInsight? _categoryDrop() {
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
      icon: Icons.thumb_up_alt_outlined,
      title: _pick([
        'تحسّن في $name',
        'وفّرت على $name',
        'صرف أقل على $name',
      ]),
      body: _say(InsightTone.positive, [
        'صرفك على $name أقل بمقدار ${_m(bestSaving)} من الفترة نفسها في الشهر الماضي.',
        'نجحت في خفض الصرف على $name، والفارق حتى الآن ${_m(bestSaving)}.',
        'وفّر عليك تراجع $name مبلغ ${_m(bestSaving)}، ففكّر في تحويله إلى التوفير.',
      ]),
      priority: 58,
      action: InsightAction.manualSave,
    );
  }

  SmartInsight? _projection() {
    if (facts.dayOfMonth < 5 || facts.monthSpent <= 0) return null;
    final projected = facts.projectedMonthSpend;
    final income = facts.effectiveMonthlyIncome;
    final detail = 'متوسطك اليومي الأخير: ${_m(facts.dailyAverageRecent)}\n'
        'المتبقي من الشهر: ${_days(facts.daysLeftInMonth)}\n'
        'التوقع لنهاية الشهر: ${_m(projected)}';

    if (income != null && projected > income) {
      return SmartInsight(
        id: 'projection',
        tone: InsightTone.warning,
        icon: Icons.insights_rounded,
        title: _pick([
          'التوقع يتجاوز دخلك',
          'بهذه الوتيرة ستتخطى دخلك',
          'نهاية الشهر تحتاج إلى انتباه',
        ]),
        body: _say(InsightTone.warning, [
          'إذا استمر صرفك بالوتيرة نفسها فسيبلغ ${_m(projected)} في نهاية الشهر، بينما دخلك ${_m(income)}.',
          'أتوقع أن يصل صرفك إلى ${_m(projected)} في نهاية الشهر، أي أكثر من دخلك بمقدار ${_m(projected - income)}.',
        ]),
        detail: detail,
        priority: 88,
      );
    }
    final tone = income != null && projected < income * 0.8
        ? InsightTone.positive
        : InsightTone.info;
    return SmartInsight(
      id: 'projection',
      tone: tone,
      icon: Icons.insights_rounded,
      title: _pick([
        'توقّع نهاية الشهر',
        'إلى أين يتجه صرفك؟',
        'نظرة على بقية الشهر',
      ]),
      body: income != null
          ? _say(tone, [
              'بهذه الوتيرة سيكون صرفك نحو ${_m(projected)} من أصل دخل قدره ${_m(income)}.',
              'من المتوقع أن تنهي الشهر بصرف ${_m(projected)}، ويبقى لك تقريباً ${_m(income - projected)}.',
            ])
          : _say(tone, [
              'بهذه الوتيرة سيبلغ صرفك نحو ${_m(projected)} مع نهاية الشهر.',
              'متوسطك اليومي ${_m(facts.dailyAverageRecent)}، أي قرابة ${_m(projected)} للشهر كاملاً.',
            ]),
      detail: detail,
      priority: 52,
    );
  }

  SmartInsight? _runway() {
    final runway = facts.runwayDays;
    final untilIncome = facts.daysUntilIncome;
    if (runway == null || untilIncome == null || untilIncome <= 0) return null;
    if (facts.balance <= 0) {
      return SmartInsight(
        id: 'runway',
        tone: InsightTone.warning,
        icon: Icons.account_balance_wallet_outlined,
        title: _pick(['نفد رصيدك', 'الرصيد صفر']),
        body: 'لم يبقَ رصيد حتى الدخل القادم بعد ${_days(untilIncome)}، فأجّل غير الضروري إن استطعت.',
        priority: 95,
      );
    }
    final dailyLimit = facts.balance / untilIncome;
    final detail = 'الرصيد الحالي: ${_m(facts.balance)}\n'
        'متوسطك اليومي الأخير: ${_m(facts.dailyAverageRecent)}\n'
        'الدخل القادم بعد: ${_days(untilIncome)}';
    if (runway < untilIncome) {
      final gap = (untilIncome - runway).ceil();
      return SmartInsight(
        id: 'runway',
        tone: InsightTone.warning,
        icon: Icons.hourglass_bottom_rounded,
        title: _pick([
          'قد ينفد الرصيد قبل الدخل',
          'انتبه: ${_days(gap)} بلا رصيد',
          'وتيرتك أسرع من رصيدك',
        ]),
        body: _say(InsightTone.warning, [
          'بهذه الوتيرة سينفد رصيدك قبل الدخل القادم بنحو ${_days(gap)}، فحاول ألا تتجاوز ${_m(dailyLimit)} يومياً.',
          'يكفي رصيدك قرابة ${_days(runway.floor())} فقط، والدخل بعد ${_days(untilIncome)}. حدّك اليومي الآمن ${_m(dailyLimit)}.',
          'لتصل إلى الدخل القادم بأمان، اجعل صرفك اليومي نحو ${_m(dailyLimit)} بدلاً من ${_m(facts.dailyAverageRecent)}.',
        ]),
        detail: detail,
        priority: 92,
      );
    }
    return SmartInsight(
      id: 'runway',
      tone: InsightTone.positive,
      icon: Icons.verified_outlined,
      title: _pick([
        'رصيدك يكفي حتى الدخل',
        'وضعك آمن حتى الدخل القادم',
        'أنت على المسار الصحيح',
      ]),
      body: _say(InsightTone.positive, [
        'بوتيرتك الحالية يكفي رصيدك حتى الدخل القادم بعد ${_days(untilIncome)}، ويمكنك صرف ما يصل إلى ${_m(dailyLimit)} يومياً.',
        'يغطي رصيدك قرابة ${_days(runway.floor())}، والدخل بعد ${_days(untilIncome)}، وما يزيد يمكنك توفيره.',
      ]),
      detail: detail,
      priority: 50,
    );
  }

  SmartInsight? _weekdayPeak() {
    if (facts.weeksOfHistory < 3) return null;
    final totals = facts.weekdayTotals;
    if (totals.length < 4) return null;
    final average = totals.values.reduce((a, b) => a + b) / 7;
    final peak = totals.entries.reduce((a, b) => a.value >= b.value ? a : b);
    if (average <= 0 || peak.value < average * 1.6) return null;
    final day = Ar.weekdays[peak.key]!;
    final ratio = (peak.value / average).toStringAsFixed(1);
    return SmartInsight(
      id: 'weekday-peak',
      tone: InsightTone.tip,
      icon: Icons.calendar_month_outlined,
      title: _pick([
        'يوم $day هو الأغلى',
        'نمط أسبوعي: يوم $day',
        'تصرف أكثر أيام $day',
      ]),
      body: _say(InsightTone.tip, [
        'خلال الأسابيع الماضية كان يوم $day الأعلى صرفاً بفارق واضح عن بقية الأيام.',
        'يقارب صرفك يوم $day \u2066$ratio\u2069 أضعاف متوسط اليوم، فخطّط له مسبقاً.',
        'لاحظت أن يوم $day يتكرر بوصفه أغلى أيام أسبوعك، وميزانية صغيرة لهذا اليوم قد تُحدث فرقاً.',
      ]),
      priority: 45,
    );
  }

  SmartInsight? _smallExpenses() {
    final month = facts.expensesBetween(
      facts.monthStart,
      facts.today.add(const Duration(days: 1)),
    );
    if (month.length < 6) return null;
    final average = facts.monthSpent / month.length;
    final small = month.where((e) => e.amount <= average * 0.4).toList();
    final sum = small.fold(0.0, (total, e) => total + e.amount);
    if (small.length < 5 || sum < facts.monthSpent * 0.12) return null;
    final counted = Ar.smallExpenses.of(small.length);
    return SmartInsight(
      id: 'small-expenses',
      tone: InsightTone.tip,
      icon: Icons.local_cafe_outlined,
      title: _pick([
        'المصاريف الصغيرة تتراكم',
        '$counted هذا الشهر',
        'انتبه للمبالغ الصغيرة',
      ]),
      body: _say(InsightTone.tip, [
        'سجّلت $counted مجموعها ${_m(sum)}، أي ${_pct(sum / facts.monthSpent)} من صرفك.',
        'بلغت المبالغ الصغيرة المتكررة ${_m(sum)} هذا الشهر، وقد تكون أسهل مكان للتوفير.',
        'يبدو كل مصروف صغير بسيطاً، لكن $counted صنعت معاً ${_m(sum)}.',
      ]),
      priority: 54,
    );
  }

  SmartInsight? _largestExpense() {
    final month = facts.expensesBetween(
      facts.monthStart,
      facts.today.add(const Duration(days: 1)),
    );
    if (month.length < 3) return null;
    final biggest = month.reduce((a, b) => a.amount >= b.amount ? a : b);
    final share = biggest.amount / facts.monthSpent;
    if (share < 0.25) return null;
    final note = biggest.note?.trim() ?? '';
    final label = note.isNotEmpty
        ? Ar.quote(note)
        : 'في ${Ar.category(biggest.category ?? 'أخرى')}';
    return SmartInsight(
      id: 'largest-expense',
      tone: InsightTone.info,
      icon: Icons.receipt_long_outlined,
      title: _pick([
        'مصروف كبير واحد',
        'أكبر مصروف هذا الشهر',
      ]),
      body: _say(InsightTone.info, [
        'يمثّل مصروفك $label بقيمة ${_m(biggest.amount)} نسبة ${_pct(share)} من صرفك هذا الشهر.',
        'استحوذ مصروف واحد ($label، ${_m(biggest.amount)}) على ${_pct(share)} من صرف الشهر. إن كان متوقعاً فخطّط له في الأشهر القادمة.',
      ]),
      priority: 44,
      action: InsightAction.expenseHistory,
    );
  }

  SmartInsight? _noSpendDays() {
    if (facts.dayOfMonth < 7) return null;
    final days = facts.noSpendDaysThisMonth;
    if (days < 3) return null;
    return SmartInsight(
      id: 'no-spend-days',
      tone: InsightTone.positive,
      icon: Icons.celebration_outlined,
      title: _pick([
        '${_days(days)} بلا صرف',
        'أيام خالية من الصرف',
        'تحدٍّ ناجح',
      ]),
      body: _say(InsightTone.positive, [
        'مرّت ${_days(days)} هذا الشهر دون أي مصروف، وهذه الأيام أسرع طريق إلى التوفير.',
        'لديك ${_days(days)} بلا صرف حتى الآن. جرّب أن تضيف يوماً واحداً كل أسبوع.',
      ]),
      priority: 42,
    );
  }

  SmartInsight? _paymentMix() {
    final month = facts.expensesBetween(
      facts.monthStart,
      facts.today.add(const Duration(days: 1)),
    );
    if (month.length < 6) return null;
    final card = month
        .where((e) => e.paymentMethod == 'بطاقة')
        .fold(0.0, (total, e) => total + e.amount);
    final share = facts.monthSpent <= 0 ? 0.0 : card / facts.monthSpent;
    if (share < 0.7) return null;
    return SmartInsight(
      id: 'payment-mix',
      tone: InsightTone.tip,
      icon: Icons.credit_card_rounded,
      title: _pick([
        'معظم صرفك بالبطاقة',
        '${_pct(share)} من صرفك بالبطاقة',
      ]),
      body: _say(InsightTone.tip, [
        'الدفع بالبطاقة يجعل الصرف أسهل وأقل إحساساً، فراجع مصاريف البطاقة أسبوعياً.',
        'دفعت ${_pct(share)} من صرفك هذا الشهر بالبطاقة، وقد يخفّض الدفع النقدي المصاريف الصغيرة.',
      ]),
      priority: 35,
    );
  }

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
      icon: Icons.nightlight_round,
      title: _pick([
        'صرف ليلي ملحوظ',
        'السهر مكلف',
      ]),
      body: _say(InsightTone.tip, [
        'كان ${Ar.expenses.of(night.length)} من مصاريفك الأخيرة في وقت متأخر ليلاً، بمجموع ${_m(sum)}.',
        'جزء واضح من صرفك يحدث بعد العاشرة مساءً، وقرارات الليل غالباً أقل تخطيطاً.',
      ]),
      priority: 38,
    );
  }

  SmartInsight? _uncategorized() {
    final other = facts.monthCategories['أخرى'] ?? 0;
    if (facts.monthSpent <= 0 || other / facts.monthSpent < 0.25) return null;
    return SmartInsight(
      id: 'uncategorized',
      tone: InsightTone.tip,
      icon: Icons.label_outline_rounded,
      title: _pick([
        'الكثير تحت «أخرى»',
        'صنّف مصاريفك بدقة',
      ]),
      body: _say(InsightTone.tip, [
        'يقع ${_pct(other / facts.monthSpent)} من صرفك تحت تصنيف «أخرى»، وتصنيفه بدقة يجعل التحليل أوضح.',
        'كلما قلّ ما تضعه تحت «أخرى» كانت نصائحي أدق، فجرّب إنشاء تصنيف خاص لما يتكرر.',
      ]),
      priority: 40,
      action: InsightAction.expenseHistory,
    );
  }

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
    final tone = short ? InsightTone.warning : InsightTone.info;
    return SmartInsight(
      id: 'obligations-soon',
      tone: tone,
      icon: Icons.event_repeat_rounded,
      title: _pick([
        'التزامات خلال أيام',
        'دفعات قادمة قريباً',
      ]),
      body: _say(tone, [
        'تستحق خلال الأيام القليلة القادمة: $names، بمجموع ${_m(total)}.',
        'جهّز ${_m(total)} لالتزامات قريبة: $names.',
      ]),
      priority: short ? 90 : 60,
      action: InsightAction.obligations,
    );
  }

  SmartInsight? _obligationsShare() {
    final monthly = facts.obligationsMonthly;
    final income = facts.effectiveMonthlyIncome;
    if (monthly <= 0 || income == null || income <= 0) return null;
    final share = monthly / income;
    if (share < 0.15) return null;
    final heavy = share >= 0.4;
    final tone = heavy ? InsightTone.warning : InsightTone.info;
    return SmartInsight(
      id: 'obligations-share',
      tone: tone,
      icon: Icons.repeat_rounded,
      title: heavy
          ? _pick(['الالتزامات ثقيلة', 'التزاماتك تستهلك الكثير'])
          : _pick(['التزاماتك الشهرية', 'حصة الالتزامات من الدخل']),
      body: heavy
          ? _say(tone, [
              'تستهلك التزاماتك المتكررة (${_m(monthly)} شهرياً) ${_pct(share)} من دخلك، فراجع ما يمكن إلغاؤه أو تخفيضه.',
              'يذهب ${_pct(share)} من دخلك إلى التزامات ثابتة، وحتى اشتراك واحد أقل يصنع فرقاً.',
            ])
          : _say(tone, [
              'تبلغ التزاماتك المتكررة نحو ${_m(monthly)} شهرياً، أي ${_pct(share)} من دخلك.',
              'تدفع شهرياً قرابة ${_m(monthly)} التزامات ثابتة، وهي ${_pct(share)} من الدخل.',
            ]),
      priority: heavy ? 75 : 36,
      action: InsightAction.obligations,
    );
  }

  // ---------------------------------------------------------------------
  // Savings: goals and habits
  // ---------------------------------------------------------------------

  List<SmartInsight> _savingsInsights() {
    return [
      ?_noGoals(),
      ..._goalInsights(),
      ?_stalledGoal(),
      ?_savingsRate(),
      ?_savingSuggestion(),
      ?_withdrawals(),
      ?_leftoverHabit(),
      ?_completedGoals(),
      ?_emergencyFund(),
      ?_shoppingList(),
    ];
  }

  SmartInsight? _noGoals() {
    if (facts.goals.isNotEmpty) return null;
    return SmartInsight(
      id: 'no-goals',
      tone: InsightTone.tip,
      icon: Icons.flag_outlined,
      title: _pick([
        'لا يوجد هدف بعد',
        'حدّد هدفك الأول',
        'التوفير أسهل مع هدف',
      ]),
      body: _say(InsightTone.tip, [
        'الأهداف تحوّل التوفير من نيّة إلى خطة، فابدأ بهدف صغير لشهر واحد.',
        'من يوفّر لهدف واضح يوفّر أكثر. ما الشيء الذي تريده خلال الأشهر القادمة؟',
        'أنشئ هدفاً، وسأتابع تقدّمك وأخبرك إن كنت على المسار.',
      ]),
      priority: 80,
      action: InsightAction.createGoal,
    );
  }

  List<SmartInsight> _goalInsights() {
    final results = <SmartInsight>[];
    final pace = facts.goals.isEmpty
        ? 0.0
        : facts.averageMonthlySaving / facts.goals.length;
    for (final goal in facts.goals.take(3)) {
      if (goal.ratio >= 1) continue;
      final name = Ar.quote(goal.name);
      final detail = 'الهدف: ${_m(goal.target)}\nتم توفير: ${_m(goal.saved)}\n'
          'المتبقي: ${_m(goal.remaining)}';

      if (goal.ratio >= 0.8) {
        results.add(SmartInsight(
          id: 'goal-near-${goal.id}',
          tone: InsightTone.positive,
          icon: Icons.emoji_events_outlined,
          title: _pick([
            'اقتربت من $name',
            '$name على وشك الاكتمال',
            'أنجزت ${_pct(goal.ratio)} من $name',
          ]),
          body: _say(InsightTone.positive, [
            'بقي ${_m(goal.remaining)} فقط لتحقيق $name. دفعة أخيرة!',
            'أنجزت ${_pct(goal.ratio)} من $name، وخطوة صغيرة تفصلك عن الوصول.',
          ]),
          detail: detail,
          priority: 74,
          action: InsightAction.manualSave,
        ));
        continue;
      }

      final monthsToDeadline =
          goal.deadline.difference(facts.today).inDays / 30;
      if (monthsToDeadline <= 0) {
        results.add(SmartInsight(
          id: 'goal-late-${goal.id}',
          tone: InsightTone.warning,
          icon: Icons.event_busy_outlined,
          title: _pick([
            'انتهى موعد $name',
            '$name تجاوز موعده',
          ]),
          body: _say(InsightTone.warning, [
            'انتهت المدة التي حدّدتها لـ$name وما زال ينقصه ${_m(goal.remaining)}، فمدّد المدة أو زِد المبلغ الشهري.',
            'بلغ $name ${_pct(goal.ratio)} بعد انتهاء موعده. لا بأس، عدّل الخطة وتابع.',
          ]),
          detail: detail,
          priority: 70,
        ));
        continue;
      }

      final needed = goal.remaining / math.max(0.25, monthsToDeadline);
      if (pace <= 0 || goal.remaining / pace > monthsToDeadline + 0.25) {
        results.add(SmartInsight(
          id: 'goal-behind-${goal.id}',
          tone: InsightTone.warning,
          icon: Icons.speed_rounded,
          title: _pick([
            '$name يحتاج إلى تسريع',
            'وتيرة $name بطيئة',
          ]),
          body: _say(InsightTone.warning, [
            'لتحقيق $name في موعده تحتاج إلى قرابة ${_m(needed)} شهرياً.',
            'بوتيرتك الحالية لن يكتمل $name في موعده، فخصّص له ${_m(needed)} شهرياً.',
          ]),
          detail: '$detail\nالمطلوب شهرياً: ${_m(needed)}',
          priority: 68,
          action: InsightAction.manualSave,
        ));
      } else {
        results.add(SmartInsight(
          id: 'goal-ontrack-${goal.id}',
          tone: InsightTone.positive,
          icon: Icons.track_changes_rounded,
          title: _pick([
            '$name على المسار',
            'تقدّم جيد في $name',
          ]),
          body: _say(InsightTone.positive, [
            'وصلت إلى ${_pct(goal.ratio)} من $name، وبهذه الوتيرة ستحققه في موعده.',
            'يسير $name كما خطّطت (${_pct(goal.ratio)}).',
          ]),
          detail: detail,
          priority: 46,
        ));
      }
    }
    return results;
  }

  SmartInsight? _stalledGoal() {
    for (final goal in facts.goals) {
      if (goal.ratio >= 1) continue;
      if (facts.today.difference(goal.createdAt).inDays < 14) continue;
      final last = facts.lastSavedFor(goal.id);
      if (last != null && facts.today.difference(last).inDays < 30) continue;
      final name = Ar.quote(goal.name);
      return SmartInsight(
        id: 'goal-stalled-${goal.id}',
        tone: InsightTone.tip,
        icon: Icons.pause_circle_outline_rounded,
        title: _pick([
          '$name متوقف',
          'لم توفّر لـ$name مؤخراً',
        ]),
        body: _say(InsightTone.tip, [
          'مرّ أكثر من شهر دون إضافة إلى $name، وحتى مبلغ صغير يعيد الزخم.',
          '$name بانتظارك. جرّب تحويل مبلغ ثابت مع كل دخل.',
        ]),
        priority: 64,
        action: InsightAction.manualSave,
      );
    }
    return null;
  }

  SmartInsight? _savingsRate() {
    final income = facts.effectiveMonthlyIncome;
    if (income == null || income <= 0) return null;
    final rate = facts.savedLast30 / income;
    if (rate >= 0.2) {
      return SmartInsight(
        id: 'savings-rate',
        tone: InsightTone.positive,
        icon: Icons.savings_outlined,
        title: _pick([
          'نسبة توفير ممتازة',
          'توفّر ${_pct(rate)} من دخلك',
        ]),
        body: _say(InsightTone.positive, [
          'وفّرت ${_m(facts.savedLast30)} خلال آخر 30 يوماً، أي ${_pct(rate)} من دخلك، وهذا فوق نسبة ${_pct(0.2)} الموصى بها.',
          'نسبة توفيرك ${_pct(rate)}، وأنت تبني أماناً مالياً حقيقياً.',
        ]),
        priority: 60,
      );
    }
    if (rate < 0.05) {
      return SmartInsight(
        id: 'savings-rate',
        tone: InsightTone.tip,
        icon: Icons.savings_outlined,
        title: _pick([
          'التوفير منخفض هذا الشهر',
          'ابدأ بنسبة ${_pct(0.05)} فقط',
        ]),
        body: _say(InsightTone.tip, [
          'وفّرت ${_m(math.max(0, facts.savedLast30))} خلال آخر 30 يوماً. ابدأ بنسبة ${_pct(0.05)} من الدخل (${_m(income * 0.05)}) ثم زِدها تدريجياً.',
          'القاعدة الشائعة أن تخصّص ${_pct(0.2)} من الدخل للتوفير، وإن كان ذلك صعباً فابدأ بـ${_m(income * 0.05)} شهرياً.',
        ]),
        priority: 66,
        action: InsightAction.manualSave,
      );
    }
    return SmartInsight(
      id: 'savings-rate',
      tone: InsightTone.info,
      icon: Icons.savings_outlined,
      title: _pick(['نسبة توفيرك', 'أنت في منتصف الطريق']),
      body: _say(InsightTone.info, [
        'وفّرت ${_pct(rate)} من دخلك خلال آخر 30 يوماً، والوصول إلى ${_pct(0.2)} يعني ${_m(income * 0.2)} شهرياً.',
      ]),
      priority: 40,
    );
  }

  // A realistic monthly amount: what is left after obligations and normal
  // spending, kept below the 20% rule so it stays sustainable.
  double? suggestedMonthlySaving() {
    final income = facts.effectiveMonthlyIncome;
    if (income == null || income <= 0) return null;
    final spare = income - facts.obligationsMonthly - facts.averageMonthlySpend;
    if (spare <= 0) return null;
    final amount = math.min(spare * 0.7, income * 0.2);
    if (amount <= 0) return null;
    // Round to a friendly figure.
    final step = amount >= 1000 ? 100.0 : (amount >= 100 ? 10.0 : 1.0);
    return (amount / step).floor() * step;
  }

  SmartInsight? _savingSuggestion() {
    final amount = suggestedMonthlySaving();
    final income = facts.effectiveMonthlyIncome;
    if (amount == null || income == null) return null;
    return SmartInsight(
      id: 'saving-suggestion',
      tone: InsightTone.tip,
      icon: Icons.lightbulb_outline_rounded,
      title: _pick([
        'اقتراح: وفّر ${_m(amount)} شهرياً',
        'مبلغ توفير واقعي لك',
        'كم يمكنك أن توفّر؟',
      ]),
      body: _say(InsightTone.tip, [
        'بعد الالتزامات ومتوسط صرفك، يمكنك توفير نحو ${_m(amount)} شهرياً دون ضغط على ميزانيتك.',
        'بحسب دخلك وصرفك المعتاد، يُعدّ ${_m(amount)} شهرياً مبلغاً مريحاً للتوفير، أي ${_m(amount * 12)} في السنة.',
        'جرّب تحويل ${_m(amount)} إلى التوفير فور وصول دخلك، قبل أن تبدأ بالصرف.',
      ]),
      detail: 'الدخل الشهري: ${_m(income)}\n'
          'الالتزامات: ${_m(facts.obligationsMonthly)}\n'
          'متوسط الصرف: ${_m(facts.averageMonthlySpend)}',
      priority: 62,
      action: facts.goals.isEmpty
          ? InsightAction.createGoal
          : InsightAction.manualSave,
    );
  }

  SmartInsight? _withdrawals() {
    final count = facts.withdrawalsLast30;
    if (count < 2) return null;
    final times = Ar.times.of(count);
    return SmartInsight(
      id: 'withdrawals',
      tone: InsightTone.warning,
      icon: Icons.output_rounded,
      title: _pick([
        'سحوبات متكررة من التوفير',
        'سحبت من التوفير $times',
      ]),
      body: _say(InsightTone.warning, [
        'سحبت من التوفير $times خلال آخر 30 يوماً، والتوفير ينجح أكثر حين يبقى بعيداً عن الصرف اليومي.',
        'قد يعني السحب المتكرر أن الميزانية الشهرية ضيقة، فراجع أكبر تصنيفاتك قبل السحب القادم.',
      ]),
      priority: 72,
    );
  }

  SmartInsight? _leftoverHabit() {
    final count = facts.leftoverTransfers;
    if (count < 1) return null;
    return SmartInsight(
      id: 'leftover-habit',
      tone: InsightTone.positive,
      icon: Icons.move_down_rounded,
      title: _pick([
        'عادة ذكية',
        'تنقل الفائض إلى التوفير',
      ]),
      body: _say(InsightTone.positive, [
        'نقلت باقي رصيدك إلى التوفير ${Ar.times.of(count)}، وهذه من أفضل العادات المالية.',
        'كل مرة تنقل فيها ما تبقّى إلى التوفير تبني رصيداً دون جهد إضافي.',
      ]),
      priority: 34,
    );
  }

  SmartInsight? _completedGoals() {
    final count = facts.completedGoals;
    if (count < 1) return null;
    final counted = Ar.goals.of(count);
    return SmartInsight(
      id: 'completed-goals',
      tone: InsightTone.positive,
      icon: Icons.workspace_premium_outlined,
      title: _pick([
        count == 1 ? 'حققت هدفاً!' : 'حققت $counted',
        'إنجازاتك في التوفير',
      ]),
      body: _say(InsightTone.positive, [
        'أكملت $counted حتى الآن، وهذا دليل على قدرتك. فما الهدف التالي؟',
        'إنجاز الأهداف السابقة يعني أن خطتك تعمل، فارفع سقف الهدف القادم قليلاً.',
      ]),
      priority: 33,
      action: facts.goals.isEmpty ? InsightAction.createGoal : null,
    );
  }

  SmartInsight? _emergencyFund() {
    final monthly = facts.averageMonthlySpend;
    if (monthly <= 0) return null;
    final months = facts.savingsBalance / monthly;
    final covered = months.toStringAsFixed(1);
    if (months >= 3) {
      return SmartInsight(
        id: 'emergency-fund',
        tone: InsightTone.positive,
        icon: Icons.shield_outlined,
        title: _pick([
          'صندوق طوارئ متين',
          'أمان يكفي ${Ar.months.of(months.floor())}',
        ]),
        body: _say(InsightTone.positive, [
          'يغطي توفيرك (${_m(facts.savingsBalance)}) صرفك المعتاد لمدة \u2066$covered\u2069 شهر تقريباً.',
        ]),
        priority: 38,
      );
    }
    return SmartInsight(
      id: 'emergency-fund',
      tone: InsightTone.tip,
      icon: Icons.shield_outlined,
      title: _pick([
        'ابنِ صندوق طوارئ',
        'كم يغطي توفيرك؟',
      ]),
      body: _say(InsightTone.tip, [
        'يغطي توفيرك صرفك المعتاد لمدة \u2066$covered\u2069 شهر فقط، والحدّ الآمن ثلاثة أشهر، أي ${_m(monthly * 3)}.',
        'يحميك صندوق الطوارئ من المفاجآت، فاجعل هدفك الأول ${_m(monthly * 3)}، أي صرف ثلاثة أشهر.',
      ]),
      priority: 44,
      action: facts.goals.isEmpty
          ? InsightAction.createGoal
          : InsightAction.manualSave,
    );
  }

  SmartInsight? _shoppingList() {
    final count = facts.pendingShopping;
    if (count < 3) return null;
    final counted = Ar.items.of(count);
    return SmartInsight(
      id: 'shopping-list',
      tone: InsightTone.tip,
      icon: Icons.checklist_rounded,
      title: _pick([
        '$counted في قائمة المشتريات',
        'قائمتك بانتظارك',
      ]),
      body: _say(InsightTone.tip, [
        'لديك $counted لم تشترِها بعد، فحدّد ميزانية للقائمة قبل الخروج للتسوق.',
        'التسوق من قائمة يقلّل الشراء العشوائي، فراجع العناصر واحذف غير الضروري منها.',
      ]),
      priority: 30,
      action: InsightAction.shoppingList,
    );
  }

  // ---------------------------------------------------------------------
  // Profile: the whole picture
  // ---------------------------------------------------------------------

  List<SmartInsight> _profileInsights() {
    final reports = _reportsInsights()
      ..sort((a, b) => b.priority.compareTo(a.priority));
    final savings = _savingsInsights()
      ..sort((a, b) => b.priority.compareTo(a.priority));
    return [
      _healthInsight(),
      ?_persona(),
      ?_streak(),
      ?_usageDuration(),
      ?_loggingHabit(),
      ...reports.take(2),
      ...savings.take(2),
    ];
  }

  // Weighted 0-100 score from the parts the data can support.
  int healthScore() => _healthParts().score;

  ({int score, List<String> lines}) _healthParts() {
    var earned = 0.0;
    var possible = 0.0;
    final lines = <String>[];
    final income = facts.effectiveMonthlyIncome;

    if (income != null && income > 0) {
      final rate = (facts.savedLast90 / 3) / income;
      final points = (rate / 0.2).clamp(0.0, 1.0) * 30;
      earned += points;
      possible += 30;
      lines.add('التوفير: ${points.round()}/30');

      final obligationShare = facts.obligationsMonthly / income;
      final obligationPoints =
          (1 - ((obligationShare - 0.3) / 0.3).clamp(0.0, 1.0)) * 15;
      earned += obligationPoints;
      possible += 15;
      lines.add('الالتزامات: ${obligationPoints.round()}/15');
    }

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

    if (facts.prevMonthSpentSameSpan > 0 && facts.monthSpent > 0) {
      final change = (facts.monthSpent - facts.prevMonthSpentSameSpan) /
          facts.prevMonthSpentSameSpan;
      final points = (1 - ((change + 0.1) / 0.4).clamp(0.0, 1.0)) * 15;
      earned += points;
      possible += 15;
      lines.add('اتجاه الصرف: ${points.round()}/15');
    }

    final consistency = (facts.activeDaysLast30 / 15).clamp(0.0, 1.0) * 15;
    earned += consistency;
    possible += 15;
    lines.add('انتظام التسجيل: ${consistency.round()}/15');

    final score = possible <= 0 ? 50 : (earned / possible * 100).round();
    return (score: score.clamp(0, 100), lines: lines);
  }

  String _healthLabel(int score) {
    if (score >= 80) return 'ممتازة';
    if (score >= 65) return 'جيدة';
    if (score >= 45) return 'مقبولة';
    return 'تحتاج إلى اهتمام';
  }

  SmartInsight _healthInsight() {
    final parts = _healthParts();
    final label = _healthLabel(parts.score);
    final good = parts.score >= 65;
    return SmartInsight(
      id: 'health-score',
      tone: good
          ? InsightTone.positive
          : (parts.score >= 45 ? InsightTone.info : InsightTone.warning),
      icon: Icons.favorite_outline_rounded,
      title: _pick([
        'صحتك المالية $label',
        'مؤشرك المالي \u2066${parts.score}/100\u2069',
        'تقييمك العام: $label',
      ]),
      body: good
          ? _pick([
              'مؤشرك ${parts.score} من 100، وهو توازن جيد بين الصرف والتوفير.',
              'وضعك المالي صحي، وأقوى نقاطك تظهر في التفاصيل.',
            ])
          : _pick([
              'مؤشرك ${parts.score} من 100. افتح التفاصيل لترى الجانب الذي يحتاج إلى تحسين أولاً.',
              'هناك مساحة للتحسّن، وتحسين جانب واحد يرفع المؤشر بسرعة.',
            ]),
      detail: parts.lines.join('\n'),
      priority: 100,
    );
  }

  SmartInsight? _persona() {
    if (!facts.hasExpenses) return null;
    final income = facts.effectiveMonthlyIncome;
    final rate = income == null || income <= 0
        ? null
        : (facts.savedLast90 / 3) / income;
    final top = _largestCategory(facts.categoryTotals(
      facts.today.subtract(const Duration(days: 60)),
      facts.today.add(const Duration(days: 1)),
    ));

    final String name;
    final String body;
    if (rate != null && rate >= 0.2) {
      name = _pick(['المدّخر المنضبط', 'صاحب الخطة']);
      body = _pick([
        'توفّر جزءاً ثابتاً من دخلك وتتحكم في صرفك، وأنت من القلة الذين يبنون ثروتهم بهدوء.',
        'التوفير عندك عادة لا استثناء، وهذا أساس كل استقرار مالي.',
      ]);
    } else if (facts.goals.isNotEmpty && facts.obligations.isNotEmpty) {
      name = _pick(['المخطّط', 'المنظّم']);
      body = _pick([
        'لديك أهداف والتزامات واضحة، والخطوة التالية رفع نسبة التوفير تدريجياً.',
        'تعرف التزاماتك وتخطّط لأهدافك، وهذا يضعك في موقع قوي.',
      ]);
    } else if (top != null && (top.key == 'ترفيه' || top.key == 'طعام')) {
      final category = Ar.category(top.key);
      name = _pick(['محبّ التجارب', 'الاجتماعي']);
      body = _pick([
        'يذهب معظم صرفك إلى $category. الاستمتاع مهم، وتحديد سقف شهري له يحميه من استنزاف الميزانية.',
        'تحب الاستمتاع، و$category أكبر بنودك. ميزانية واضحة له تجعلك تستمتع دون قلق.',
      ]);
    } else if (facts.activeDaysLast30 >= 15) {
      name = _pick(['المتابع الدقيق', 'العين الساهرة']);
      body = _pick([
        'تسجّل مصاريفك بانتظام، وهذه أهم خطوة، فحوّل هذه المعرفة الآن إلى أهداف.',
        'بياناتك دقيقة ومنتظمة، وهذا ما يجعل كل تحليل هنا موثوقاً.',
      ]);
    } else {
      name = _pick(['في بداية الطريق', 'المستكشف']);
      body = _pick([
        'ما زلت تبني عاداتك المالية، والتسجيل اليومي لأسبوعين سيكشف لك الكثير.',
        'كل يوم تسجّل فيه مصاريفك يقرّبك من صورة أوضح عن وضعك.',
      ]);
    }
    return SmartInsight(
      id: 'persona',
      tone: InsightTone.info,
      icon: Icons.psychology_outlined,
      title: _pick(['شخصيتك المالية: $name', 'أنت «$name»']),
      body: body,
      priority: 90,
    );
  }

  SmartInsight? _streak() {
    final count = facts.streakCount;
    if (count <= 0) return null;
    final run = Ar.consecutiveDays.of(count);
    if (count >= 7) {
      return SmartInsight(
        id: 'streak',
        tone: InsightTone.positive,
        icon: Icons.local_fire_department_outlined,
        title: _pick(['سلسلة من $run!', 'التزام رائع']),
        body: _say(InsightTone.positive, [
          'تفتح وفّر منذ $run، والاستمرار هو سرّ النتائج.',
          'أكملت $run من المتابعة، فلا تكسر السلسلة!',
        ]),
        priority: 58,
      );
    }
    return SmartInsight(
      id: 'streak',
      tone: InsightTone.tip,
      icon: Icons.local_fire_department_outlined,
      title: _pick(['ابنِ سلسلتك', 'سلسلتك الحالية: ${_days(count)}']),
      body: _say(InsightTone.tip, [
        'سلسلتك الحالية ${_days(count)}. افتح التطبيق يومياً ولو لدقيقة لتصل إلى أسبوع كامل.',
        'تُبنى العادات بالتكرار، وهدفك القادم ${Ar.consecutiveDays.of(7)}.',
      ]),
      priority: 36,
    );
  }

  SmartInsight? _usageDuration() {
    final started = facts.usageStartedAt;
    if (started == null) return null;
    final days = facts.today.difference(started).inDays + 1;
    if (days < 7) return null;
    return SmartInsight(
      id: 'usage-duration',
      tone: InsightTone.info,
      icon: Icons.history_rounded,
      title: _pick([
        '${_days(days)} مع وفّر',
        'رحلتك مستمرة',
      ]),
      body: _pick([
        'بدأت قبل ${_days(days)}، وسجّلت ${Ar.expenses.of(facts.expenses.length)} منذ ذلك الحين.',
        'خلال ${_days(days)} جمعت بيانات تكفي لفهم عاداتك، وكل يوم إضافي يجعل التحليل أدق.',
      ]),
      priority: 28,
    );
  }

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
        icon: Icons.edit_calendar_outlined,
        title: _pick([
          'آخر مصروف قبل ${_days(idle)}',
          'هل نسيت التسجيل؟',
        ]),
        body: _say(InsightTone.tip, [
          'لم تسجّل أي مصروف منذ ${_days(idle)}، والتحليل أدق حين تكون البيانات كاملة.',
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
        icon: Icons.edit_calendar_outlined,
        title: _pick(['تسجيل منتظم', 'بياناتك دقيقة']),
        body: 'سجّلت مصاريف في ${_days(facts.activeDaysLast30)} من آخر 30 يوماً، وهذا ما يجعل الأرقام هنا موثوقة.',
        priority: 32,
      );
    }
    return null;
  }

  // ---------------------------------------------------------------------
  // Tips, headline and summary
  // ---------------------------------------------------------------------

  static const List<String> _generalTips = [
    'ادفع لنفسك أولاً: حوّل مبلغ التوفير فور وصول الدخل.',
    'قاعدة الـ24 ساعة: انتظر يوماً كاملاً قبل أي شراء غير ضروري.',
    'راجع اشتراكاتك الشهرية مرة كل ثلاثة أشهر، وألغِ ما لا تستخدمه.',
    'حدّد سقفاً أسبوعياً للمطاعم بدلاً من سقف شهري، فهو أسهل في المتابعة.',
    'سجّل المصروف لحظة دفعه، فالتأجيل يعني النسيان.',
    'قاعدة 50/30/20: نصف الدخل للضروريات، وثلاثة أعشاره للرغبات، وخُمسه للتوفير.',
    'التسوق بقائمة وبعد تناول الطعام يقلّل الشراء العشوائي بوضوح.',
    'امنح هدف التوفير اسماً واضحاً، فالأهداف المسمّاة تتحقق أسرع.',
    'المبالغ الصغيرة اليومية تصنع فرقاً كبيراً في نهاية السنة.',
    'قبل أي شراء كبير، احسب عدد أيام العمل التي يكلّفك إياها.',
    'خصّص يوماً في الأسبوع بلا صرف، وراقب أثره في الشهر.',
    'ابدأ صندوق طوارئ يغطي ثلاثة أشهر من مصاريفك الأساسية.',
    'قارن الأسعار قبل الشراء، خصوصاً في المشتريات المتكررة.',
    'كافئ نفسك عند تحقيق هدف، لكن بمبلغ محدد مسبقاً.',
    'راجع تقريرك الأسبوعي كل جمعة، فالمراجعة الدورية تمنع المفاجآت.',
    'العروض ليست توفيراً إن لم تكن بحاجة إلى الشيء أصلاً.',
  ];

  SmartInsight _tip(InsightScope scope) {
    final scoped = switch (scope) {
      InsightScope.reports => [
          'تقسيم الميزانية على الأسابيع يجعل التحكم في الصرف أسهل من متابعة الشهر كاملاً.',
          'راجع أكبر ثلاثة مصاريف كل أسبوع واسأل نفسك: هل كانت ضرورية؟',
        ],
      InsightScope.savings => [
          'التوفير التلقائي مع كل دخل أسهل من التوفير مما يتبقّى آخر الشهر.',
          'قسّم الهدف الكبير إلى مراحل شهرية صغيرة.',
        ],
      InsightScope.profile => [
          'أفضل وقت لمراجعة وضعك المالي بداية كل شهر.',
        ],
    };
    return SmartInsight(
      id: 'tip',
      tone: InsightTone.tip,
      icon: Icons.tips_and_updates_outlined,
      title: _pick(['نصيحة سريعة', 'فكرة لك', 'هل تعلم؟', 'من خبرة المدّخرين']),
      body: _pick([..._generalTips, ...scoped]),
      priority: 0,
    );
  }

  String _headline(InsightScope scope, List<SmartInsight> insights, int? score) {
    final warnings =
        insights.where((item) => item.tone == InsightTone.warning).length;
    final positives =
        insights.where((item) => item.tone == InsightTone.positive).length;

    if (scope == InsightScope.profile && score != null) {
      final label = _healthLabel(score);
      return _pick([
        'صحتك المالية $label، وإليك الصورة الكاملة.',
        'مؤشرك \u2066$score/100\u2069، وهذا ما لاحظته عنك.',
        'نظرة شاملة على وضعك: $label.',
        'جمعت لك أهم ما في مصاريفك وتوفيرك وعاداتك.',
      ]);
    }
    if (!facts.hasExpenses && scope == InsightScope.reports) {
      return _pick([
        'لنبدأ معاً: سجّل مصاريفك لأحلّلها لك.',
        'التحليل جاهز حالما تبدأ بالتسجيل.',
      ]);
    }
    if (warnings >= 2) {
      return _pick([
        warnings == 2
            ? 'هناك نقطتان تحتاجان إلى انتباهك.'
            : 'هناك $warnings نقاط تحتاج إلى انتباهك.',
        'لاحظت أموراً تستحق التوقف عندها.',
        'وضعك جيد، لكن انتبه لهذه النقاط.',
        'إليك ما يحتاج إلى متابعة أدق.',
      ]);
    }
    if (warnings == 1) {
      return _pick([
        'نقطة واحدة تحتاج إلى انتباهك، والباقي جيد.',
        'أغلب المؤشرات جيدة مع ملاحظة مهمة.',
        'الصورة إيجابية في معظمها، باستثناء أمر واحد.',
      ]);
    }
    if (positives >= 2) {
      return _pick([
        'أداء رائع! إليك ما يسير على ما يرام.',
        'أخبار جيدة: أنت تتحسّن.',
        'استمرّ، فالمؤشرات في صالحك.',
      ]);
    }
    return switch (scope) {
      InsightScope.savings => _pick([
          'هذه قراءتي لتوفيرك وأهدافك.',
          'إليك وضع توفيرك واقتراحاتي.',
        ]),
      _ => _pick([
          'هذه قراءتي لمصاريفك.',
          'إليك أهم ما لاحظته في صرفك.',
        ]),
    };
  }

  String _summary(InsightScope scope) {
    final parts = <String>[];
    switch (scope) {
      case InsightScope.reports:
        if (facts.monthSpent > 0) {
          parts.add(_pick([
            'صرفت هذا الشهر ${_m(facts.monthSpent)} بمعدل ${_m(facts.dailyAverageThisMonth)} يومياً.',
            'حتى اليوم ${facts.dayOfMonth} من الشهر بلغ صرفك ${_m(facts.monthSpent)}.',
            'إجمالي صرفك منذ بداية الشهر ${_m(facts.monthSpent)}.',
          ]));
        }
        final top = _largestCategory(facts.monthCategories);
        if (top != null) {
          final name = Ar.category(top.key);
          parts.add(_pick([
            'أكبر تصنيف هو $name.',
            'ذهب معظم الصرف إلى $name.',
            'يتصدّر $name قائمة مصاريفك.',
          ]));
        }
      case InsightScope.savings:
        parts.add(_pick([
          'رصيد توفيرك ${_m(facts.savingsBalance)}.',
          'لديك ${_m(facts.savingsBalance)} في التوفير.',
        ]));
        if (facts.goals.isNotEmpty) {
          parts.add('لديك ${Ar.activeGoals.of(facts.goals.length)}.');
        }
      case InsightScope.profile:
        parts.add(_pick([
          'جمعت هنا أهم ما في مصاريفك وتوفيرك وعاداتك.',
          'قراءة شاملة مبنية على كل ما سجّلته.',
          'هذه خلاصة ما تقوله أرقامك.',
        ]));
    }
    return parts.join(' ');
  }
}
