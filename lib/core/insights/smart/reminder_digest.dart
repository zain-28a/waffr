// Short, factual notification texts built from SmartFacts. Each one states
// something true and useful (a bill coming up, how far the balance goes,
// a category that grew, goal progress, the week's total) and never asks
// the user to open the app; the fact itself is the reason to come back.
//
// Texts are written when the app is open and shown days later. Nothing
// changes in the ledger meanwhile (it only changes inside the app), so the
// amounts stay true; dates are counted from the time the text will show.
// Every kind has several phrasings; the seed picks one.

import 'dart:math' as math;

import 'package:waffr/core/insights/smart/arabic_text.dart';
import 'package:waffr/core/insights/smart/smart_facts.dart';
import 'package:waffr/core/utils/money.dart';

typedef ReminderText = ({String kind, String title, String body});

class ReminderDigest {
  final SmartFacts facts;
  final math.Random _random;

  ReminderDigest(this.facts, {int? seed}) : _random = math.Random(seed);

  T _pick<T>(List<T> options) => options[_random.nextInt(options.length)];

  String _m(double value) => '${formatMoney(value)} ${facts.currencySymbol}';

  String _pct(double ratio) => '\u2066${(ratio * 100).abs().round()}%\u2069';

  DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);

  // Days from today to [at]'s day.
  int _offset(DateTime at) => _day(at).difference(facts.today).inDays;

  /// Facts worth a notification at [fireAt]. Time-sensitive ones (a bill,
  /// a balance that will not last) come first; the rest in varying order.
  List<ReminderText> candidates(DateTime fireAt) {
    final urgent = [?_obligation(fireAt), ?_shortBalance(fireAt)];
    final rest = [
      ?_paymentsAhead(fireAt),
      ?_balance(fireAt),
      ?_categoryChange(),
      ?_goal(),
      ?_topShare(),
      ?_noSpendDays(),
      ?_savings(),
      ?_monthTotal(),
    ]..shuffle(_random);
    return [...urgent, ...rest];
  }

  ReminderText? _obligation(DateTime fireAt) {
    final day = _day(fireAt);
    final upcoming = facts.obligations
        .where((item) {
          final due = _day(item.nextDueAt).difference(day).inDays;
          return due >= 0 && due <= 4;
        })
        .toList()
      ..sort((a, b) => a.nextDueAt.compareTo(b.nextDueAt));
    if (upcoming.isEmpty) return null;
    final next = upcoming.first;
    final name = Ar.quote(next.name);
    final due = _day(next.nextDueAt).difference(day).inDays;
    final when = switch (due) {
      0 => 'اليوم',
      1 => 'غداً',
      _ => 'بعد ${Ar.days.of(due)}',
    };
    final short = next.amount > facts.balance;
    return (
      kind: 'obligation',
      title: _pick([
        '$name مستحق $when',
        'موعد $name $when',
        '$when: دفعة $name',
      ]),
      body: short
          ? _pick([
              'المبلغ ${_m(next.amount)}، ورصيدك الحالي ${_m(facts.balance)}.',
              'المبلغ ${_m(next.amount)}، وهو أكبر من رصيدك الحالي.',
            ])
          : _pick([
              'المبلغ ${_m(next.amount)}.',
              'قيمة الدفعة ${_m(next.amount)}.',
              'سيُخصم ${_m(next.amount)} من رصيدك.',
            ]),
    );
  }

  ReminderText? _paymentsAhead(DateTime fireAt) {
    final day = _day(fireAt);
    final week = facts.obligations.where((item) {
      final due = _day(item.nextDueAt).difference(day).inDays;
      return due >= 0 && due < 7;
    }).toList();
    if (week.length < 2) return null;
    final total = week.fold(0.0, (sum, item) => sum + item.amount);
    final count = Ar.payments.of(week.length);
    return (
      kind: 'payments',
      title: _pick([
        '$count خلال الأيام السبعة القادمة',
        'أسبوع فيه $count مستحقة',
      ].where((text) => week.length > 2 || text.startsWith(count)).toList()),
      body: _pick([
        'مجموعها ${_m(total)}.',
        'بإجمالي ${_m(total)}.',
      ]),
    );
  }

  ReminderText? _shortBalance(DateTime fireAt) {
    final income = facts.daysUntilIncome;
    final runway = facts.runwayDays;
    if (income == null || runway == null || facts.balance <= 0) return null;
    final passed = _offset(fireAt);
    final incomeLeft = income - passed;
    final runwayLeft = (runway - passed).floor();
    if (incomeLeft < 2 || runwayLeft >= incomeLeft - 1) return null;
    final lasting = runwayLeft <= 0
        ? 'قد يكون نفد الآن'
        : 'يكفي نحو ${Ar.days.of(runwayLeft)}';
    return (
      kind: 'short-balance',
      title: _pick([
        'رصيدك قد لا يكفي حتى الدخل',
        'رصيدك أقصر من المدة المتبقية حتى الدخل',
      ]),
      body: _pick([
        'بالوتيرة الأخيرة $lasting، والدخل بعد ${Ar.days.of(incomeLeft)}.',
        'الحد اليومي الذي يوصلك إلى الدخل ${_m(facts.balance / incomeLeft)}.',
      ]),
    );
  }

  ReminderText? _balance(DateTime fireAt) {
    final income = facts.daysUntilIncome;
    if (income == null || facts.balance <= 0) return null;
    final left = income - _offset(fireAt);
    if (left < 2) return null;
    final perDay = _m(facts.balance / left);
    final balance = _m(facts.balance);
    final days = Ar.days.of(left);
    // Title and body are paired so neither repeats the other.
    final (title, body) = _pick([
      ('متبقٍّ في رصيدك $balance', 'والدخل القادم بعد $days، أي نحو $perDay لكل يوم.'),
      ('رصيدك الحالي $balance', 'ما يعادل $perDay يومياً حتى الدخل القادم.'),
      ('الدخل القادم بعد $days', 'ورصيدك $balance، بمعدل $perDay لليوم.'),
    ]);
    return (kind: 'balance', title: title, body: body);
  }

  ReminderText? _categoryChange() {
    MapEntry<String, double>? top;
    var growth = 0.0;
    for (final entry in facts.monthCategories.entries) {
      final before = facts.prevMonthCategories[entry.key] ?? 0;
      if (before <= 0) continue;
      final change = (entry.value - before) / before;
      if (change > 0.3 && change > growth) {
        top = entry;
        growth = change;
      }
    }
    if (top == null) return null;
    final name = Ar.category(top.key);
    final before = facts.prevMonthCategories[top.key]!;
    return (
      kind: 'category',
      title: _pick([
        'صرفك على $name أعلى بنسبة ${_pct(growth)}',
        'ارتفاع في صرف $name',
        '$name يرتفع بنسبة ${_pct(growth)}',
      ]),
      body: _pick([
        '${_m(top.value)} هذا الشهر مقابل ${_m(before)} في الفترة نفسها من الشهر الماضي.',
        'الفارق عن الشهر الماضي ${_m(top.value - before)} حتى الآن.',
        'بلغ ${_m(top.value)} بعد أن كان ${_m(before)} في الفترة نفسها.',
      ]),
    );
  }

  ReminderText? _goal() {
    final active = facts.goals.where((goal) => goal.ratio < 1).toList()
      ..sort((a, b) => b.ratio.compareTo(a.ratio));
    if (active.isEmpty) return null;
    final goal = active.first;
    final name = Ar.quote(goal.name);
    return (
      kind: 'goal',
      title: _pick([
        '$name وصل إلى ${_pct(goal.ratio)}',
        'هدفك $name: ${_pct(goal.ratio)}',
        goal.ratio >= 0.8
            ? '$name على وشك الاكتمال'
            : 'أنجزت ${_pct(goal.ratio)} من $name',
      ]),
      body: _pick([
        'بقي ${_m(goal.remaining)} على الهدف.',
        'تم توفير ${_m(goal.saved)} من أصل ${_m(goal.target)}.',
        'المتبقي لإكماله ${_m(goal.remaining)}.',
      ]),
    );
  }

  ReminderText? _topShare() {
    if (facts.monthSpent <= 0 || facts.monthCategories.length < 2) return null;
    final top = facts.monthCategories.entries
        .reduce((a, b) => a.value >= b.value ? a : b);
    final share = top.value / facts.monthSpent;
    if (share < 0.3) return null;
    final name = Ar.category(top.key);
    return (
      kind: 'top-share',
      title: _pick([
        '$name يمثّل ${_pct(share)} من صرف الشهر',
        'الحصة الأكبر هذا الشهر ${Ar.li(name)}',
      ]),
      body: _pick([
        'بمبلغ ${_m(top.value)} حتى الآن.',
        'أي ${_m(top.value)} من أصل ${_m(facts.monthSpent)}.',
      ]),
    );
  }

  ReminderText? _noSpendDays() {
    if (facts.dayOfMonth < 7) return null;
    final days = facts.noSpendDaysThisMonth;
    if (days < 3 || facts.dailyAverageThisMonth <= 0) return null;
    final saved = _m(days * facts.dailyAverageThisMonth);
    return (
      kind: 'no-spend',
      title: _pick([
        '${Ar.days.of(days)} بلا صرف هذا الشهر',
        'مرّت ${Ar.days.of(days)} هذا الشهر دون أي مصروف',
      ]),
      body: _pick([
        'وهذا يعادل نحو $saved بحسب متوسطك اليومي.',
        'أي ما يعادل نحو $saved بمتوسط صرفك اليومي.',
      ]),
    );
  }

  ReminderText? _savings() {
    if (facts.savingsBalance <= 0) return null;
    final daily = facts.dailyAverageRecent;
    final String body;
    if (daily > 0) {
      final days = (facts.savingsBalance / daily).floor();
      final cover = days >= 60
          ? Ar.months.of(days ~/ 30)
          : Ar.days.of(math.max(1, days));
      body = _pick([
        'يغطي صرفك المعتاد لمدة $cover تقريباً.',
        'وهو ما يكفي لنحو $cover من صرفك الحالي.',
      ]);
    } else {
      body = _pick([
        'محفوظ بعيداً عن الصرف اليومي.',
        'مبلغ جاهز لأهدافك القادمة.',
      ]);
    }
    return (
      kind: 'savings',
      title: _pick([
        'رصيد توفيرك ${_m(facts.savingsBalance)}',
        'لديك ${_m(facts.savingsBalance)} في التوفير',
      ]),
      body: body,
    );
  }

  ReminderText? _monthTotal() {
    if (facts.monthSpent <= 0) return null;
    final top = facts.monthCategories.entries.isEmpty
        ? null
        : facts.monthCategories.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return (
      kind: 'month',
      title: _pick([
        'صرفك هذا الشهر ${_m(facts.monthSpent)}',
        'إجمالي الشهر حتى الآن ${_m(facts.monthSpent)}',
      ]),
      body: top == null
          ? 'بمعدل ${_m(facts.dailyAverageThisMonth)} يومياً.'
          : _pick([
              'أكبر بند ${Ar.category(top.key)} بنسبة ${_pct(top.value / facts.monthSpent)}.',
              'بمعدل ${_m(facts.dailyAverageThisMonth)} يومياً.',
            ]),
    );
  }

  /// The Friday summary of the current week, or null with nothing spent.
  ReminderText? weekly() {
    final now = facts.weekSpent;
    if (now <= 0) return null;
    final before = facts.prevWeekSpentSameSpan;
    final String body;
    if (before > 0 && (now - before).abs() / before >= 0.1) {
      final change = (now - before) / before;
      body = change > 0
          ? _pick([
              'أكثر بنسبة ${_pct(change)} من الأسبوع الماضي.',
              'بزيادة ${_m(now - before)} عن الأسبوع الماضي.',
            ])
          : _pick([
              'أقل بنسبة ${_pct(change)} من الأسبوع الماضي.',
              'بتوفير ${_m(before - now)} مقارنةً بالأسبوع الماضي.',
            ]);
    } else {
      body = _pick([
        'قريب من صرف الأسبوع الماضي.',
        'في مستوى الأسبوع الماضي تقريباً.',
      ]);
    }
    return (
      kind: 'weekly',
      title: _pick([
        'صرفك هذا الأسبوع ${_m(now)}',
        'حصيلة أسبوعك: ${_m(now)}',
        'أسبوعك في رقم: ${_m(now)}',
      ]),
      body: body,
    );
  }

  /// The evening streak reminder, written as a fact about the streak.
  /// Needs no ledger, so it can be written without SmartFacts.
  static ReminderText streakText(int count, {int? seed}) =>
      _StreakText(math.Random(seed)).text(count);
}

class _StreakText {
  final math.Random _random;

  _StreakText(this._random);

  T _pick<T>(List<T> options) => options[_random.nextInt(options.length)];

  ReminderText text(int count) {
    final run = Ar.consecutiveDays.of(count);
    return (
      kind: 'streak',
      title: _pick([
        'سلسلة من $run في وفّر',
        'سلسلتك مستمرة منذ ${Ar.days.of(count)}',
      ]),
      body: _pick([
        'يوم إضافي يرفعها إلى ${Ar.days.of(count + 1)}.',
        'يوم آخر يجعلها ${Ar.days.of(count + 1)}.',
      ]),
    );
  }
}
