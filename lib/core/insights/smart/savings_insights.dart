// Savings-scope insight rules: goals, saving rate and habits. Month-by-month
// saving habits live in savings_habits.dart; this file runs them too.

import 'package:waffr/core/theme/app_icons.dart';

import 'dart:math' as math;

import 'package:waffr/core/insights/smart/arabic_text.dart';
import 'package:waffr/core/insights/smart/insight_phrasing.dart';
import 'package:waffr/core/insights/smart/savings_habits.dart';
import 'package:waffr/data/models/calendar_period.dart';
import 'package:waffr/core/insights/smart/smart_facts.dart';
import 'package:waffr/core/insights/smart/smart_insight.dart';

/// Rules for the savings screen.
class SavingsInsights {
  /// Rules over [facts], worded through the run's shared phrasing.
  SavingsInsights(this.facts, this._p);

  /// The numbers of this run.
  final SmartFacts facts;

  final InsightPhrasing _p;

  /// Every savings rule that applies, in a fixed order.
  List<SmartInsight> all() {
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
      ...SavingsHabits(facts, _p).all(),
    ];
  }

  // No goal yet: suggest creating one.
  SmartInsight? _noGoals() {
    if (facts.goals.isNotEmpty) return null;
    return SmartInsight(
      id: 'no-goals',
      tone: InsightTone.tip,
      icon: AppIcons.flag,
      title: _p.pick([
        'لا يوجد هدف بعد',
        'حدّد هدفك الأول',
        'التوفير أسهل مع هدف',
      ]),
      body: _p.pick([
        'الأهداف تحوّل التوفير من نيّة إلى خطة، فابدأ بهدف صغير لشهر واحد.',
        'من يوفّر لهدف واضح يوفّر أكثر. ما الشيء الذي تريده خلال الأشهر القادمة؟',
        'أنشئ هدفاً، وسأتابع تقدّمك وأخبرك إن كنت على المسار.',
      ]),
      priority: 80,
      action: InsightAction.createGoal,
    );
  }

  // Up to three goals: nearly done, past due, due within two weeks, just
  // created, behind pace, ahead of plan, or on track. One card per goal.
  List<SmartInsight> _goalInsights() {
    final results = <SmartInsight>[];
    final pace = facts.goals.isEmpty
        ? 0.0
        : facts.averageMonthlySaving / facts.goals.length;
    for (final goal in facts.goals.take(3)) {
      if (goal.ratio >= 1) continue;
      final name = Ar.quote(goal.name);
      final topic = 'goal-${goal.id}';
      final detail =
          'الهدف: ${_p.money(goal.target)}\nتم توفير: ${_p.money(goal.saved)}\n'
          'المتبقي: ${_p.money(goal.remaining)}';

      if (goal.ratio >= 0.8) {
        results.add(
          SmartInsight(
            id: 'goal-near-${goal.id}',
            topic: topic,
            tone: InsightTone.positive,
            icon: AppIcons.trophy,
            title: _p.pick([
              'اقتربت من $name',
              '$name على وشك الاكتمال',
              'أنجزت ${_p.percent(goal.ratio)} من $name',
            ]),
            body: _p.pick([
              'بقي ${_p.money(goal.remaining)} فقط لتحقيق $name.',
              'أنجزت ${_p.percent(goal.ratio)} من $name، ويفصلك عنه ${_p.money(goal.remaining)}.',
            ]),
            detail: detail,
            priority: 74,
            action: InsightAction.manualSave,
          ),
        );
        continue;
      }

      final daysLeft = goal.deadline.difference(facts.today).inDays;
      final monthsToDeadline = daysLeft / 30;
      if (daysLeft <= 0) {
        results.add(
          SmartInsight(
            id: 'goal-late-${goal.id}',
            topic: topic,
            tone: InsightTone.warning,
            icon: AppIcons.calendarX,
            title: _p.pick(['انتهى موعد $name', '$name تجاوز موعده']),
            body: _p.pick([
              'انتهت المدة التي حدّدتها لـ$name وما زال ينقصه ${_p.money(goal.remaining)}. مدّد المدة أو زِد المبلغ الذي تخصّصه له.',
              'بلغ $name ${_p.percent(goal.ratio)} عند انتهاء موعده. عدّل خطته لتكمله.',
            ]),
            detail: detail,
            priority: 70,
          ),
        );
        continue;
      }

      if (daysLeft <= 14) {
        final perDay = goal.remaining / daysLeft;
        results.add(
          SmartInsight(
            id: 'goal-deadline-${goal.id}',
            topic: topic,
            tone: InsightTone.warning,
            icon: AppIcons.hourglass,
            title: 'موعد $name بعد ${_p.days(daysLeft)}',
            body:
                'ينقص $name ${_p.money(goal.remaining)}، أي نحو ${_p.money(perDay)} يومياً حتى موعده.',
            detail: detail,
            priority: 73,
            action: InsightAction.manualSave,
          ),
        );
        continue;
      }

      final age = facts.today.difference(goal.createdAt).inDays;
      final needed = goal.remaining / math.max(0.25, monthsToDeadline);
      if (age < 14 && goal.saved <= 0) {
        results.add(
          SmartInsight(
            id: 'goal-new-${goal.id}',
            topic: topic,
            tone: InsightTone.tip,
            icon: AppIcons.flag,
            title: 'ابدأ $name بدفعة أولى',
            body:
                'لتحقيق $name في موعده تحتاج إلى نحو ${_p.money(needed)} شهرياً. دفعة أولى الآن تجعل البداية أسهل.',
            detail: '$detail\nالمطلوب شهرياً: ${_p.money(needed)}',
            priority: 61,
            action: InsightAction.manualSave,
          ),
        );
        continue;
      }

      if (pace <= 0 || goal.remaining / pace > monthsToDeadline + 0.25) {
        results.add(
          SmartInsight(
            id: 'goal-behind-${goal.id}',
            topic: topic,
            tone: InsightTone.warning,
            icon: AppIcons.gauge,
            title: _p.pick(['$name يحتاج إلى تسريع', 'وتيرة $name بطيئة']),
            body: _p.pick([
              'لتحقيق $name في موعده تحتاج إلى قرابة ${_p.money(needed)} شهرياً.',
              'بوتيرة توفيرك الحالية لن يكتمل $name في موعده. خصّص له ${_p.money(needed)} شهرياً.',
            ]),
            detail: '$detail\nالمطلوب شهرياً: ${_p.money(needed)}',
            priority: 68,
            action: InsightAction.manualSave,
          ),
        );
        continue;
      }

      // At the current pace: the month the goal would be reached.
      final eta = facts.today.add(
        Duration(days: (goal.remaining / pace * 30).ceil()),
      );
      final etaLabel = '${CalendarPeriod.monthName(eta.month)} ${eta.year}';
      final ahead = monthsToDeadline - goal.remaining / pace >= 1;
      results.add(
        SmartInsight(
          id: ahead ? 'goal-ahead-${goal.id}' : 'goal-ontrack-${goal.id}',
          topic: topic,
          kind: InsightKind.estimate,
          tone: InsightTone.positive,
          icon: AppIcons.target,
          title: ahead
              ? '$name يسبق خطته'
              : _p.pick(['$name على المسار', 'تقدّم جيد في $name']),
          body: ahead
              ? 'بوتيرة توفيرك الحالية يكتمل $name في $etaLabel تقريباً، قبل موعده بشهر أو أكثر.'
              : _p.pick([
                  'وصلت إلى ${_p.percent(goal.ratio)} من $name، وبوتيرتك الحالية يكتمل في موعده.',
                  'يسير $name كما خطّطت (${_p.percent(goal.ratio)})، والتقدير أن يكتمل في $etaLabel.',
                ]),
          detail: '$detail\nالاكتمال المتوقع: $etaLabel',
          priority: ahead ? 47 : 46,
        ),
      );
    }
    return results;
  }

  // The first goal (two weeks old or more) with nothing saved for 30 days.
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
        icon: AppIcons.pause,
        title: _p.pick(['$name متوقف', 'لم توفّر لـ$name مؤخراً']),
        body: _p.pick([
          'مرّ أكثر من شهر دون إضافة إلى $name، وحتى مبلغ صغير يعيد الزخم.',
          '$name بانتظارك. جرّب تحويل مبلغ ثابت مع كل دخل.',
        ]),
        priority: 64,
        action: InsightAction.manualSave,
      );
    }
    return null;
  }

  // Net saving over 30 days as a share of income, against the 20% rule.
  SmartInsight? _savingsRate() {
    final income = facts.effectiveMonthlyIncome;
    if (income == null || income <= 0) return null;
    // A month of history first, so a new user is not "saving nothing".
    if (facts.historyDays < 30) return null;
    final rate = facts.savedLast30 / income;
    if (rate >= 0.2) {
      return SmartInsight(
        id: 'savings-rate',
        topic: 'savings-rate',
        tone: InsightTone.positive,
        icon: AppIcons.savings,
        title: _p.pick([
          'نسبة توفير ممتازة',
          'توفّر ${_p.percent(rate)} من دخلك',
        ]),
        body: _p.pick([
          'وفّرت ${_p.money(facts.savedLast30)} خلال آخر 30 يوماً، أي ${_p.percent(rate)} من دخلك، وهذا فوق نسبة ${_p.percent(0.2)} الموصى بها.',
          'نسبة توفيرك ${_p.percent(rate)}، وأنت تبني أماناً مالياً حقيقياً.',
        ]),
        priority: 60,
      );
    }
    if (rate < 0.05) {
      return SmartInsight(
        id: 'savings-rate',
        topic: 'savings-rate',
        tone: InsightTone.tip,
        icon: AppIcons.savings,
        title: _p.pick([
          'التوفير منخفض هذا الشهر',
          'ابدأ بنسبة ${_p.percent(0.05)} فقط',
        ]),
        body: _p.pick([
          'وفّرت ${_p.money(math.max(0, facts.savedLast30))} خلال آخر 30 يوماً. ابدأ بنسبة ${_p.percent(0.05)} من الدخل (${_p.money(income * 0.05)}) ثم زِدها تدريجياً.',
          'القاعدة الشائعة أن تخصّص ${_p.percent(0.2)} من الدخل للتوفير، وإن كان ذلك صعباً فابدأ بـ${_p.money(income * 0.05)} شهرياً.',
        ]),
        priority: 66,
        action: InsightAction.manualSave,
      );
    }
    return SmartInsight(
      id: 'savings-rate',
      topic: 'savings-rate',
      tone: InsightTone.info,
      icon: AppIcons.savings,
      title: _p.pick(['نسبة توفيرك', 'أنت في منتصف الطريق']),
      body: _p.pick([
        'وفّرت ${_p.percent(rate)} من دخلك خلال آخر 30 يوماً، والوصول إلى ${_p.percent(0.2)} يعني ${_p.money(income * 0.2)} شهرياً.',
      ]),
      priority: 40,
    );
  }

  /// A realistic monthly amount: what is left after obligations and normal
  /// spending, kept below the 20% rule so it stays sustainable. Null when
  /// income is unknown, the history is under two weeks, or nothing is left.
  double? suggestedMonthlySaving() {
    final income = facts.effectiveMonthlyIncome;
    if (income == null || income <= 0) return null;
    // "Normal spending" needs two weeks of history behind it.
    if (facts.historyDays < 14) return null;
    final spare = income - facts.obligationsMonthly - facts.averageMonthlySpend;
    if (spare <= 0) return null;
    final amount = math.min(spare * 0.7, income * 0.2);
    if (amount <= 0) return null;
    // Round to a friendly figure.
    final step = amount >= 1000 ? 100.0 : (amount >= 100 ? 10.0 : 1.0);
    return (amount / step).floor() * step;
  }

  // A concrete monthly amount from [suggestedMonthlySaving].
  SmartInsight? _savingSuggestion() {
    final amount = suggestedMonthlySaving();
    final income = facts.effectiveMonthlyIncome;
    if (amount == null || income == null) return null;
    return SmartInsight(
      id: 'saving-suggestion',
      tone: InsightTone.tip,
      icon: AppIcons.lightbulb,
      title: _p.pick([
        'اقتراح: وفّر ${_p.money(amount)} شهرياً',
        'مبلغ توفير واقعي لك',
        'كم يمكنك أن توفّر؟',
      ]),
      body: _p.pick([
        'بعد الالتزامات ومتوسط صرفك، يمكنك توفير نحو ${_p.money(amount)} شهرياً دون ضغط على ميزانيتك.',
        'بحسب دخلك وصرفك المعتاد، يُعدّ ${_p.money(amount)} شهرياً مبلغاً مريحاً للتوفير، أي ${_p.money(amount * 12)} في السنة.',
        'جرّب تحويل ${_p.money(amount)} إلى التوفير فور وصول دخلك، قبل أن تبدأ بالصرف.',
      ]),
      detail:
          'الدخل الشهري: ${_p.money(income)}\n'
          'الالتزامات: ${_p.money(facts.obligationsMonthly)}\n'
          'متوسط الصرف: ${_p.money(facts.averageMonthlySpend)}',
      priority: 62,
      action: facts.goals.isEmpty
          ? InsightAction.createGoal
          : InsightAction.manualSave,
    );
  }

  // Two withdrawals from savings or more in 30 days.
  SmartInsight? _withdrawals() {
    final count = facts.withdrawalsLast30;
    if (count < 2) return null;
    final times = Ar.times.of(count);
    return SmartInsight(
      id: 'withdrawals',
      topic: 'withdrawals',
      tone: InsightTone.warning,
      icon: AppIcons.withdraw,
      title: _p.pick(['سحوبات متكررة من التوفير', 'سحبت من التوفير $times']),
      body: _p.pick([
        'سحبت من التوفير $times خلال آخر 30 يوماً، والتوفير ينجح أكثر حين يبقى بعيداً عن الصرف اليومي.',
        'قد يعني السحب المتكرر أن الميزانية الشهرية ضيقة، فراجع أكبر تصنيفاتك قبل السحب القادم.',
      ]),
      priority: 72,
    );
  }

  // Praise for moving period leftovers to savings.
  SmartInsight? _leftoverHabit() {
    final count = facts.leftoverTransfers;
    if (count < 1) return null;
    return SmartInsight(
      id: 'leftover-habit',
      tone: InsightTone.positive,
      icon: AppIcons.deposit,
      title: _p.pick(['عادة ذكية', 'تنقل الفائض إلى التوفير']),
      body: _p.pick([
        'نقلت باقي رصيدك إلى التوفير ${Ar.times.of(count)}، وهذه من أفضل العادات المالية.',
        'كل مرة تنقل فيها ما تبقّى إلى التوفير تبني رصيداً دون جهد إضافي.',
      ]),
      priority: 34,
    );
  }

  // Goals completed so far.
  SmartInsight? _completedGoals() {
    final count = facts.completedGoals;
    if (count < 1) return null;
    final counted = Ar.goals.of(count);
    return SmartInsight(
      id: 'completed-goals',
      tone: InsightTone.positive,
      icon: AppIcons.award,
      title: _p.pick([
        count == 1 ? 'حققت هدفاً!' : 'حققت $counted',
        'إنجازاتك في التوفير',
      ]),
      body: _p.pick([
        'أكملت $counted حتى الآن، وهذا دليل على قدرتك. فما الهدف التالي؟',
        'إنجاز الأهداف السابقة يعني أن خطتك تعمل، فارفع سقف الهدف القادم قليلاً.',
      ]),
      priority: 33,
      action: facts.goals.isEmpty ? InsightAction.createGoal : null,
    );
  }

  // Months of normal spending the savings cover: three or more is solid,
  // one to three is under way, below one is a start. A month of history
  // first, so the "normal spending" is real.
  SmartInsight? _emergencyFund() {
    final monthly = facts.averageMonthlySpend;
    if (monthly <= 0 || facts.historyDays < 30) return null;
    final months = facts.savingsBalance / monthly;
    final covered = '\u2066${months.toStringAsFixed(1)}\u2069';
    final target = monthly * 3;
    if (months >= 3) {
      return SmartInsight(
        id: 'emergency-fund',
        topic: 'emergency',
        tone: InsightTone.positive,
        icon: AppIcons.shield,
        title: _p.pick([
          'صندوق طوارئ متين',
          'أمان يكفي ${Ar.months.of(months.floor())}',
        ]),
        body:
            'يغطي توفيرك (${_p.money(facts.savingsBalance)}) صرفك المعتاد لمدة $covered شهر تقريباً، وهذا فوق حدّ الأمان المعتاد (ثلاثة أشهر).',
        priority: 38,
      );
    }
    if (months >= 1) {
      return SmartInsight(
        id: 'emergency-fund',
        topic: 'emergency',
        tone: InsightTone.info,
        icon: AppIcons.shield,
        title: 'صندوق الطوارئ في منتصف الطريق',
        body:
            'يغطي توفيرك صرفك المعتاد لمدة $covered شهر. يبقى ${_p.money(target - facts.savingsBalance)} لتصل إلى ثلاثة أشهر (${_p.money(target)}).',
        priority: 42,
        action: InsightAction.manualSave,
      );
    }
    return SmartInsight(
      id: 'emergency-fund',
      topic: 'emergency',
      tone: InsightTone.tip,
      icon: AppIcons.shield,
      title: _p.pick(['ابنِ صندوق طوارئ', 'كم يغطي توفيرك؟']),
      body: _p.pick([
        'يغطي توفيرك صرفك المعتاد لأقل من شهر. الحدّ الآمن المعتاد ثلاثة أشهر، أي ${_p.money(target)}.',
        'صندوق الطوارئ يحميك من المفاجآت. ابدأ بهدف يعادل صرف شهر واحد (${_p.money(monthly)})، ثم وسّعه إلى ثلاثة أشهر (${_p.money(target)}).',
      ]),
      priority: 44,
      action: facts.goals.isEmpty
          ? InsightAction.createGoal
          : InsightAction.manualSave,
    );
  }

  // Three items or more still on the shopping list.
  SmartInsight? _shoppingList() {
    final count = facts.pendingShopping;
    if (count < 3) return null;
    final counted = Ar.items.of(count);
    return SmartInsight(
      id: 'shopping-list',
      tone: InsightTone.tip,
      icon: AppIcons.listChecks,
      title: _p.pick(['$counted في قائمة المشتريات', 'قائمتك بانتظارك']),
      body: _p.pick([
        'لديك $counted لم تشترِها بعد، فحدّد ميزانية للقائمة قبل الخروج للتسوق.',
        'التسوق من قائمة يقلّل الشراء العشوائي، فراجع العناصر واحذف غير الضروري منها.',
      ]),
      priority: 30,
      action: InsightAction.shoppingList,
    );
  }
}
