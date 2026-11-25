// ReportPatterns and CashflowInsights: full-month comparisons, long
// trends, recurring purchases found in the history, habits and income-
// based rules, each with the data it needs before it speaks.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:waffr/core/insights/smart/cashflow_insights.dart';
import 'package:waffr/core/insights/smart/insight_phrasing.dart';
import 'package:waffr/core/insights/smart/report_patterns.dart';
import 'package:waffr/core/insights/smart/smart_facts.dart';
import 'package:waffr/core/insights/smart/smart_insight.dart';
import 'package:waffr/data/models/transaction.dart';

import '../../../helpers/ledger_builders.dart';

final DateTime _now = DateTime(2026, 10, 20, 12);

InsightPhrasing _p() => InsightPhrasing('ل.س', math.Random(2));

Map<String, SmartInsight> _patterns(SmartFacts facts) => {
  for (final item in ReportPatterns(facts, _p()).all()) item.id: item,
};

Map<String, SmartInsight> _cash(SmartFacts facts, {bool profile = false}) => {
  for (final item
      in profile
          ? CashflowInsights(facts, _p()).forProfile()
          : CashflowInsights(facts, _p()).forReports())
    item.id: item,
};

/// [perDay] spent every day of the month starting [start].
List<WaffrTransaction> _month(
  DateTime start,
  double perDay, {
  String category = 'طعام',
  int days = 28,
}) => [
  for (var d = 0; d < days; d++)
    expenseAt(
      perDay,
      DateTime(start.year, start.month, start.day + d, 13),
      category: category,
    ),
];

void main() {
  test('normalized notes fold spelling variants', () {
    expect(normalizedNote('  إشتراك   النت '), normalizedNote('اشتراك النت'));
    expect(normalizedNote('قهوة'), normalizedNote('قهوه'));
    expect(normalizedNote(null), '');
  });

  test('last month against the month before needs both tracked', () {
    final rising = buildFacts(
      now: _now,
      expenses: [
        ..._month(DateTime(2026, 8, 1), 10),
        ..._month(DateTime(2026, 9, 1), 15),
      ],
    );
    final card = _patterns(rising)['last-month-compare']!;
    expect(card.tone, InsightTone.warning);
    expect(card.topic, 'month-trend');
    expect(card.title, contains('أيلول'));

    // August only half tracked: no comparison.
    final partial = buildFacts(
      now: _now,
      expenses: [
        ..._month(DateTime(2026, 8, 16), 10, days: 14),
        ..._month(DateTime(2026, 9, 1), 15),
      ],
    );
    expect(_patterns(partial).containsKey('last-month-compare'), isFalse);
  });

  test('three rising months make a long trend', () {
    final facts = buildFacts(
      now: _now,
      expenses: [
        ..._month(DateTime(2026, 7, 1), 10),
        ..._month(DateTime(2026, 8, 1), 12),
        ..._month(DateTime(2026, 9, 1), 15),
      ],
    );
    final card = _patterns(facts)['long-trend']!;
    expect(card.tone, InsightTone.warning);
    expect(card.detail, contains('تموز'));
  });

  test('a purchase in three months at a steady amount is found', () {
    List<WaffrTransaction> rent(String note) => [
      for (final month in [7, 8, 9, 10])
        expenseAt(500, DateTime(2026, month, 2), note: note),
    ];
    final facts = buildFacts(
      now: _now,
      expenses: [...rent('إيجار المستودع'), ..._month(DateTime(2026, 7, 1), 5)],
    );
    final card = _patterns(facts)['recurring-found']!;
    expect(card.action, InsightAction.obligations);
    expect(card.title, contains('«إيجار المستودع»'));

    // Already a recurring bill: not suggested again.
    final known = buildFacts(
      now: _now,
      expenses: [...rent('إيجار المستودع'), ..._month(DateTime(2026, 7, 1), 5)],
      obligations: [
        ObligationFact(
          name: 'ايجار المستودع',
          amount: 500,
          monthlyEquivalent: 500,
          nextDueAt: DateTime(2026, 11, 2),
        ),
      ],
    );
    expect(_patterns(known).containsKey('recurring-found'), isFalse);
  });

  test('a small daily habit is costed over a year', () {
    final facts = buildFacts(
      now: _now,
      expenses: [
        ..._month(DateTime(2026, 9, 1), 100, days: 50),
        for (var d = 0; d < 8; d++)
          expenseAt(
            10,
            _now.subtract(Duration(days: d * 3)),
            category: 'طعام',
            note: 'قهوة',
          ),
      ],
    );
    final card = _patterns(facts)['habit-cost']!;
    expect(card.kind, InsightKind.estimate);
    expect(card.body, contains('8 مرات'));
    expect(card.body, contains('السنة'));
  });

  test('the longest finished run without spending', () {
    final facts = buildFacts(
      now: _now,
      expenses: [
        expenseAt(10, DateTime(2026, 9, 25)),
        expenseAt(10, DateTime(2026, 10, 3)),
        expenseAt(10, DateTime(2026, 10, 9)),
        // Nothing from the 10th to yesterday (the 19th): ten days.
        expenseAt(10, DateTime(2026, 10, 20, 9)),
      ],
    );
    final card = _patterns(facts)['no-spend-streak']!;
    expect(card.title, contains('10 أيام متتالية'));
  });

  test('budget pace compares the share of income with the month', () {
    final ahead = buildFacts(
      now: DateTime(2026, 10, 10, 12),
      monthlyIncome: 1000,
      expenses: [expenseAt(600, DateTime(2026, 10, 2))],
    );
    final card = _cash(ahead)['budget-pace']!;
    expect(card.tone, InsightTone.warning);
    expect(card.body, contains('\u206660%\u2069'));

    final slow = buildFacts(
      now: DateTime(2026, 10, 20, 12),
      monthlyIncome: 1000,
      expenses: [expenseAt(100, DateTime(2026, 10, 2))],
    );
    expect(_cash(slow)['budget-pace']!.tone, InsightTone.positive);

    final early = buildFacts(
      now: DateTime(2026, 10, 3, 12),
      monthlyIncome: 1000,
      expenses: [expenseAt(900, DateTime(2026, 10, 2))],
    );
    expect(_cash(early).containsKey('budget-pace'), isFalse);
  });

  test('last month income against its spending uses recorded income', () {
    final over = buildFacts(
      now: _now,
      incomes: [incomeAt(1000, DateTime(2026, 9, 1))],
      expenses: _month(DateTime(2026, 9, 1), 50),
    );
    expect(_cash(over)['last-month-income']!.tone, InsightTone.warning);

    final kept = buildFacts(
      now: _now,
      incomes: [incomeAt(3000, DateTime(2026, 9, 1))],
      expenses: _month(DateTime(2026, 9, 1), 50),
    );
    final card = _cash(kept)['last-month-income']!;
    expect(card.tone, InsightTone.positive);
    expect(card.body, contains('1,600 ل.س'));
  });

  test('regular logging without any income asks for one', () {
    final facts = buildFacts(
      now: _now,
      expenses: [
        for (var d = 0; d < 10; d++)
          expenseAt(5, _now.subtract(Duration(days: d))),
      ],
    );
    expect(_cash(facts)['no-income']!.action, InsightAction.addIncome);
    final withIncome = buildFacts(
      now: _now,
      monthlyIncome: 500,
      expenses: facts.expenses,
    );
    expect(_cash(withIncome).containsKey('no-income'), isFalse);
  });

  test('ninety days of spending against income in the overall view', () {
    final facts = buildFacts(
      now: _now,
      incomes: [
        for (final month in [8, 9, 10])
          incomeAt(1000, DateTime(2026, month, 1)),
      ],
      expenses: [
        ..._month(DateTime(2026, 7, 1), 1, days: 5),
        ..._month(DateTime(2026, 8, 1), 40, days: 80),
      ],
    );
    final card = _cash(facts, profile: true)['spend-to-income']!;
    expect(card.tone, InsightTone.warning);
    expect(card.topic, 'cashflow');
  });
}
