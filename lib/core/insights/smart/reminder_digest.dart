// Short, factual notification texts built from SmartFacts. Each one states
// something true and useful (a bill coming up, how far the balance goes,
// a category that grew, goal progress, the week's total) and never asks
// the user to open the app; the fact itself is the reason to come back.
//
// Texts are written when the app is open and shown days later. Nothing
// changes in the ledger meanwhile (it only changes inside the app), so the
// amounts stay true; dates are counted from [fireAt].

import 'package:waffr/core/insights/smart/arabic_text.dart';
import 'package:waffr/core/insights/smart/smart_facts.dart';
import 'package:waffr/core/utils/money.dart';

typedef ReminderText = ({String kind, String title, String body});

class ReminderDigest {
  final SmartFacts facts;

  const ReminderDigest(this.facts);

  String _m(double value) => '${formatMoney(value)} ${facts.currencySymbol}';

  String _pct(double ratio) => '\u2066${(ratio * 100).abs().round()}%\u2069';

  DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);

  /// Facts worth a notification at [fireAt], most useful first.
  List<ReminderText> candidates(DateTime fireAt) {
    return [
      ?_obligation(fireAt),
      ?_balance(fireAt),
      ?_categoryChange(),
      ?_goal(),
      ?_monthTotal(),
    ];
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
    final due = _day(next.nextDueAt).difference(day).inDays;
    final when = switch (due) {
      0 => 'مستحق اليوم',
      1 => 'مستحق غداً',
      _ => 'مستحق بعد ${Ar.days.of(due)}',
    };
    return (
      kind: 'obligation',
      title: '${Ar.quote(next.name)} $when',
      body: next.amount > facts.balance
          ? 'المبلغ ${_m(next.amount)}، ورصيدك الحالي ${_m(facts.balance)}.'
          : 'المبلغ ${_m(next.amount)}.',
    );
  }

  ReminderText? _balance(DateTime fireAt) {
    final income = facts.daysUntilIncome;
    if (income == null || facts.balance <= 0) return null;
    final left = income - _day(fireAt).difference(facts.today).inDays;
    if (left < 2) return null;
    return (
      kind: 'balance',
      title: 'متبقٍّ في رصيدك ${_m(facts.balance)}',
      body: 'والدخل القادم بعد ${Ar.days.of(left)}، '
          'أي نحو ${_m(facts.balance / left)} لكل يوم.',
    );
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
    return (
      kind: 'category',
      title: 'صرفك على $name أعلى بنسبة ${_pct(growth)}',
      body: '${_m(top.value)} هذا الشهر مقابل '
          '${_m(facts.prevMonthCategories[top.key]!)} في الفترة نفسها من الشهر الماضي.',
    );
  }

  ReminderText? _goal() {
    final active = facts.goals.where((goal) => goal.ratio < 1).toList()
      ..sort((a, b) => b.ratio.compareTo(a.ratio));
    if (active.isEmpty) return null;
    final goal = active.first;
    return (
      kind: 'goal',
      title: '${Ar.quote(goal.name)} وصل إلى ${_pct(goal.ratio)}',
      body: 'بقي ${_m(goal.remaining)} على الهدف.',
    );
  }

  ReminderText? _monthTotal() {
    if (facts.monthSpent <= 0) return null;
    final top = facts.monthCategories.entries.isEmpty
        ? null
        : facts.monthCategories.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return (
      kind: 'month',
      title: 'صرفك هذا الشهر ${_m(facts.monthSpent)}',
      body: top == null
          ? 'بمعدل ${_m(facts.dailyAverageThisMonth)} يومياً.'
          : 'أكبر بند ${Ar.category(top.key)} بنسبة ${_pct(top.value / facts.monthSpent)}.',
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
          ? 'أكثر بنسبة ${_pct(change)} من الأسبوع الماضي.'
          : 'أقل بنسبة ${_pct(change)} من الأسبوع الماضي.';
    } else {
      body = 'قريب من الأسبوع الماضي.';
    }
    return (kind: 'weekly', title: 'صرفك هذا الأسبوع ${_m(now)}', body: body);
  }
}
