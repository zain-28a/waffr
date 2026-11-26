// Quality checks over many generated ledgers: every card the engine writes
// reads as finished Arabic text (no "null", NaN, Infinity, negative
// amounts, doubled spaces or empty parts), ids are unique, and rules that
// compare spans stay quiet when the data is too thin.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:waffr/core/insights/smart/insight_engine.dart';
import 'package:waffr/core/insights/smart/insight_phrasing.dart';
import 'package:waffr/core/insights/smart/report_insights.dart';
import 'package:waffr/core/insights/smart/smart_facts.dart';
import 'package:waffr/core/insights/smart/smart_insight.dart';
import 'package:waffr/data/models/transaction.dart';

import '../../../helpers/ledger_builders.dart';

const _categories = [
  'طعام',
  'مواصلات',
  'تسوق',
  'فواتير',
  'ترفيه',
  'أخرى',
  'قهوة',
];
const _notes = [null, 'قهوة', 'إيجار', 'سوق', 'اشتراك النت'];

/// A random but plausible ledger around [now].
SmartFacts _randomFacts(int seed) {
  final random = math.Random(seed);
  final now = DateTime(
    2026,
    1 + random.nextInt(12),
    1 + random.nextInt(28),
    15,
  );
  final days = random.nextInt(200);
  final expenses = <WaffrTransaction>[
    for (var i = 0; i < random.nextInt(160); i++)
      expenseAt(
        (1 + random.nextInt(400)).toDouble(),
        now.subtract(
          Duration(days: random.nextInt(days + 1), hours: random.nextInt(20)),
        ),
        category: _categories[random.nextInt(_categories.length)],
        note: _notes[random.nextInt(_notes.length)],
        paymentMethod: random.nextBool() ? 'بطاقة' : 'نقداً',
      ),
  ];
  final incomes = <WaffrTransaction>[
    for (var i = 0; i < random.nextInt(6); i++)
      incomeAt(
        (500 + random.nextInt(4000)).toDouble(),
        now.subtract(Duration(days: random.nextInt(days + 1))),
      ),
  ];
  final transfers = <WaffrTransaction>[
    for (var i = 0; i < random.nextInt(8); i++)
      transferAt(
        (10 + random.nextInt(500)).toDouble(),
        now.subtract(Duration(days: random.nextInt(days + 1))),
        out: random.nextInt(4) == 0,
        goalId: random.nextBool() ? 'g' : null,
      ),
  ];
  final recurring = random.nextBool();
  return buildFacts(
    now: now,
    expenses: expenses,
    incomes: incomes,
    transfers: transfers,
    balance: random.nextInt(3) == 0 ? 0 : random.nextInt(5000).toDouble(),
    monthlyIncome: random.nextBool()
        ? (800 + random.nextInt(3000)).toDouble()
        : null,
    hasRecurringIncome: recurring,
    incomeFrequency: random.nextBool()
        ? RecurringFrequency.monthly
        : RecurringFrequency.weekly,
    savingsBalance: random.nextInt(4000).toDouble(),
    goals: [
      if (random.nextBool())
        GoalFact(
          id: 'g',
          name: 'سيارة',
          target: 2000,
          saved: random.nextInt(2100).toDouble(),
          createdAt: now.subtract(Duration(days: random.nextInt(120))),
          plannedMonths: [0.25, 1.0, 3.0, 6.0, 12.0][random.nextInt(5)],
        ),
    ],
    obligations: [
      if (random.nextBool())
        ObligationFact(
          name: 'إنترنت',
          amount: 50,
          monthlyEquivalent: 50,
          nextDueAt: now.add(Duration(days: random.nextInt(30))),
        ),
      if (random.nextBool())
        ObligationFact(
          name: 'إيجار',
          amount: 700,
          monthlyEquivalent: 700,
          nextDueAt: now.add(Duration(days: random.nextInt(30))),
        ),
    ],
    pendingShopping: random.nextInt(5),
    streakCount: random.nextInt(20),
    usageStartedAt: now.subtract(Duration(days: days)),
  );
}

final _broken = RegExp(r'null|NaN|Infinity|  |\(\)|: ,|-\d|\$\{');

void main() {
  test('generated text is complete across 400 random ledgers', () {
    final seen = <String>{};
    for (var seed = 0; seed < 400; seed++) {
      final facts = _randomFacts(seed);
      for (final scope in InsightScope.values) {
        final report = InsightEngine(facts, seed: seed).analyze(scope);
        final ids = report.insights.map((item) => item.id).toList();
        expect(ids.toSet(), hasLength(ids.length), reason: 'seed $seed');
        for (final text in [report.headline, report.summary]) {
          expect(_broken.hasMatch(text), isFalse, reason: '$seed: $text');
        }
        for (final card in report.insights) {
          seen.add(card.id.replaceAll(RegExp(r'-g$'), ''));
          for (final text in [card.title, card.body, card.detail ?? 'x']) {
            expect(text.trim(), isNotEmpty, reason: '$seed ${card.id}');
            expect(
              _broken.hasMatch(text),
              isFalse,
              reason: '$seed ${card.id}: $text',
            );
          }
        }
      }
    }
    // The sweep reaches a wide set of rules, not a handful.
    expect(seen.length, greaterThan(45), reason: seen.toString());
  });

  test('thin data keeps comparisons quiet', () {
    final saturday = DateTime(2026, 10, 17, 12); // first day of the week
    final facts = buildFacts(
      now: saturday,
      expenses: [
        expenseAt(100, saturday),
        expenseAt(10, saturday.subtract(const Duration(days: 7))),
        for (var d = 20; d < 60; d++)
          expenseAt(10, saturday.subtract(Duration(days: d))),
      ],
    );
    final ids = ReportInsights(
      facts,
      InsightPhrasing('ل.س', math.Random(1)),
    ).all().map((item) => item.id);
    expect(ids, isNot(contains('week-trend')));

    // Day 2 of a month: no spike, no projection, no month trend.
    final second = DateTime(2026, 10, 2, 12);
    final early = buildFacts(
      now: second,
      expenses: [
        expenseAt(500, second, category: 'ترفيه'),
        for (var d = 1; d < 60; d++)
          expenseAt(10, second.subtract(Duration(days: d)), category: 'ترفيه'),
      ],
    );
    final earlyIds = ReportInsights(
      early,
      InsightPhrasing('ل.س', math.Random(1)),
    ).all().map((item) => item.id);
    expect(earlyIds, isNot(contains('category-spike')));
    expect(earlyIds, isNot(contains('projection')));
    expect(earlyIds, isNot(contains('month-trend')));
  });

  test('a new user sees the early-data card, not verdicts', () {
    final now = DateTime(2026, 10, 20, 12);
    final facts = buildFacts(
      now: now,
      monthlyIncome: 1000,
      expenses: [
        for (var d = 0; d < 5; d++)
          expenseAt(50, now.subtract(Duration(days: d))),
      ],
    );
    final ids = InsightEngine(
      facts,
      seed: 3,
    ).analyze(InsightScope.reports).insights.map((item) => item.id);
    expect(ids, contains('early-data'));
    expect(ids, isNot(contains('runway')));
    expect(ids, isNot(contains('week-trend')));
  });
}
