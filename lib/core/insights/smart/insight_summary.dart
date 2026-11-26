// The parts of a report around the cards: the closing tip, the headline
// and the short summary.
//
// The closing tip is picked from tips whose condition the user's own data
// meets (bills recorded, a heavy food category, many small expenses, no
// goal yet...). With none that fits, the report simply ends without one.

import 'package:waffr/core/theme/app_icons.dart';
import 'package:waffr/core/insights/smart/arabic_text.dart';
import 'package:waffr/core/insights/smart/insight_phrasing.dart';
import 'package:waffr/core/insights/smart/smart_facts.dart';
import 'package:waffr/core/insights/smart/smart_insight.dart';
import 'package:waffr/core/insights/smart/profile_insights.dart';
import 'package:waffr/core/insights/smart/report_insights.dart';

/// Writes the tip, headline and summary of a report.
class InsightSummary {
  /// Text over [facts], worded through the run's shared phrasing.
  InsightSummary(this.facts, this._p);

  /// The numbers of this run.
  final SmartFacts facts;

  final InsightPhrasing _p;

  // Expenses of the last 30 days.
  late final _recent = facts.expensesBetween(
    facts.today.subtract(const Duration(days: 29)),
    facts.today.add(const Duration(days: 1)),
  );

  /// The tips that fit the data for [scope]. Their order is fixed so a seed
  /// always picks the same one.
  List<String> _fittingTips(InsightScope scope) {
    final income = facts.effectiveMonthlyIncome;
    final top = largestCategory(facts.monthCategories);
    final topShare = top == null || facts.monthSpent <= 0
        ? 0.0
        : top.value / facts.monthSpent;
    final average = _recent.isEmpty
        ? 0.0
        : _recent.fold(0.0, (sum, e) => sum + e.amount) / _recent.length;
    final small = _recent.where((e) => e.amount <= average * 0.4).length;
    final spending = scope != InsightScope.savings;
    final saving = scope != InsightScope.reports;

    return [
      if (spending && facts.obligations.length >= 2)
        'لديك ${Ar.payments.of(facts.obligations.length)} متكررة. راجعها مرة كل ثلاثة أشهر وألغِ ما لم تعد تستخدمه.',
      if (spending && top != null && top.key == 'طعام' && topShare >= 0.3) 'الطعام أكبر بنودك هذا الشهر. سقف أسبوعي للمطاعم والوجبات الجاهزة أسهل في المتابعة من سقف شهري.',
      if (spending && top != null && top.key == 'تسوق' && topShare >= 0.3) 'التسوق أكبر بنودك هذا الشهر. قاعدة الأربع والعشرين ساعة تساعد: انتظر يوماً كاملاً قبل أي شراء غير ضروري.',
      if (spending && _recent.length >= 10 && small >= 6)
        'سجّلت ${Ar.smallExpenses.of(small)} في آخر 30 يوماً. اجمعها في مشتريات أسبوعية أقل عدداً لتلاحظ أثرها.',
      if (spending && facts.pendingShopping >= 1)
        'في قائمة مشترياتك ${Ar.items.of(facts.pendingShopping)}. التسوق من القائمة وحدها يقلّل الشراء العشوائي.',
      if (spending && facts.loggedLast30 > 0 && facts.loggedLast30 < 10)
        'سجّلت ${Ar.expenses.of(facts.loggedLast30)} فقط في آخر 30 يوماً. تسجيل المصروف لحظة دفعه يمنع نسيانه ويجعل الأرقام أدق.',
      if (saving && income != null && facts.averageMonthlySaving < income * 0.1) 'حوّل مبلغ التوفير فور وصول الدخل، قبل أن تبدأ بالصرف؛ التوفير مما يتبقّى آخر الشهر أصعب.',
      if (saving && facts.goals.isEmpty) 'الأهداف المسمّاة تُنجز أسرع. سمِّ هدفك وحدّد مبلغه ومدته في قسم التوفير.',
      if (saving && facts.goals.isNotEmpty)
        'قسّم كل هدف كبير إلى دفعات شهرية صغيرة، وحوّل الدفعة مع كل دخل.',
      if (saving && facts.withdrawalsLast30 >= 1) 'قبل أي سحب من التوفير، اسأل: هل هو طارئ فعلاً أم يمكن تأجيله إلى الدخل القادم؟',
      if (scope == InsightScope.profile && facts.dayOfMonth <= 5) 'بداية الشهر أنسب وقت لمراجعة وضعك المالي: قارن صرف الشهر الماضي بدخلك، وحدّد مبلغ التوفير لهذا الشهر.',
    ];
  }

  /// A tip that fits the data for [scope], or null when none fits.
  SmartInsight? tip(InsightScope scope) {
    final options = _fittingTips(scope);
    if (options.isEmpty) return null;
    return SmartInsight(
      id: 'tip',
      tone: InsightTone.tip,
      icon: AppIcons.tips,
      title: _p.pick(['نصيحة لك', 'فكرة تناسب أرقامك']),
      body: _p.pick(options),
      priority: 0,
    );
  }

  /// One line above the cards: health for the profile, else what the
  /// warnings and positives add up to.
  String headline(InsightScope scope, List<SmartInsight> insights, int? score) {
    final warnings = insights
        .where((item) => item.tone == InsightTone.warning)
        .length;
    final positives = insights
        .where((item) => item.tone == InsightTone.positive)
        .length;

    if (scope == InsightScope.profile && score != null) {
      final label = healthLabel(score);
      return _p.pick([
        'صحتك المالية $label، وإليك الصورة الكاملة.',
        'مؤشرك \u2066$score/100\u2069، وهذا ما وراءه.',
        'نظرة شاملة على وضعك: $label.',
        'وضعك المالي هذه الفترة: $label.',
      ]);
    }
    if (!facts.hasExpenses && scope == InsightScope.reports) {
      return _p.pick([
        'سجّل مصروفاتك لتظهر القراءة.',
        'التحليل جاهز حالما تبدأ بالتسجيل.',
        'سجّل أول مصروف لتبدأ القراءة.',
      ]);
    }
    if (warnings >= 2) {
      return _p.pick([
        warnings == 2
            ? 'هناك نقطتان تحتاجان إلى انتباهك.'
            : 'هناك $warnings نقاط تحتاج إلى انتباهك.',
        'بعض المؤشرات تطلب انتباهك.',
        'إليك ما يحتاج إلى متابعة أدق.',
      ]);
    }
    if (warnings == 1) {
      return _p.pick([
        'نقطة واحدة تحتاج إلى انتباهك.',
        'ملاحظة مهمة واحدة، وإليك الباقي.',
      ]);
    }
    if (positives >= 2) {
      return _p.pick([
        'المؤشرات في صالحك هذه الفترة.',
        'أخبار جيدة عن أرقامك هذه الفترة.',
      ]);
    }
    return switch (scope) {
      InsightScope.savings => _p.pick([
        'هذا وضع توفيرك وأهدافك.',
        'نظرة على أهدافك وتقدّمك.',
      ]),
      _ => _p.pick(['إليك أهم ما في صرفك.', 'نظرة على صرفك هذه الفترة.']),
    };
  }

  /// The short summary under the headline.
  String summary(InsightScope scope) {
    final parts = <String>[];
    switch (scope) {
      case InsightScope.reports:
        if (facts.monthSpent > 0) {
          parts.add(
            _p.pick([
              'صرفت هذا الشهر ${_p.money(facts.monthSpent)} بمعدل ${_p.money(facts.dailyAverageThisMonth)} يومياً.',
              'حتى اليوم ${facts.dayOfMonth} من الشهر بلغ صرفك ${_p.money(facts.monthSpent)}.',
            ]),
          );
        }
        final top = largestCategory(facts.monthCategories);
        if (top != null && facts.monthSpent > 0) {
          final name = Ar.category(top.key);
          final share = _p.percent(top.value / facts.monthSpent);
          parts.add(
            _p.pick([
              'أكبر تصنيف هو $name بنسبة $share.',
              'يتصدّر $name مصروفاتك بنسبة $share.',
            ]),
          );
        }
      case InsightScope.savings:
        parts.add(
          _p.pick([
            'رصيد توفيرك ${_p.money(facts.savingsBalance)}.',
            'لديك ${_p.money(facts.savingsBalance)} في التوفير.',
          ]),
        );
        if (facts.goals.isNotEmpty) {
          parts.add('لديك ${Ar.activeGoals.of(facts.goals.length)}.');
        }
      case InsightScope.profile:
        parts.add(
          _p.pick([
            'أهم ما في مصروفاتك وتوفيرك وعاداتك، من أرقامك المسجّلة.',
            'خلاصة مبنية على كل ما سجّلته.',
          ]),
        );
    }
    return parts.join(' ');
  }
}
