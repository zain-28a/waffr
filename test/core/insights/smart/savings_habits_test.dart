// SavingsHabits: month-by-month saving habits, large withdrawals, money
// left idle late in the month, and goals heavier than the saving pace.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:waffr/core/insights/smart/insight_phrasing.dart';
import 'package:waffr/core/insights/smart/savings_habits.dart';
import 'package:waffr/core/insights/smart/smart_facts.dart';
import 'package:waffr/core/insights/smart/smart_insight.dart';

import '../../../helpers/ledger_builders.dart';

final DateTime _now = DateTime(2026, 10, 20, 12);

Map<String, SmartInsight> _run(SmartFacts facts) => {
  for (final item in SavingsHabits(
    facts,
    InsightPhrasing('ل.س', math.Random(4)),
  ).all())
    item.id: item,
};

void main() {
  test('three months with savings make a streak; a weak month is noted', () {
    final streak = buildFacts(
      now: _now,
      transfers: [
        for (final month in [7, 8, 9])
          transferAt(100, DateTime(2026, month, 2)),
      ],
    );
    expect(_run(streak)['savings-streak']!.tone, InsightTone.positive);

    final dropped = buildFacts(
      now: _now,
      transfers: [
        transferAt(200, DateTime(2026, 7, 2)),
        transferAt(200, DateTime(2026, 8, 2)),
        transferAt(20, DateTime(2026, 9, 2)),
      ],
    );
    expect(_run(dropped)['savings-dropped']!.tone, InsightTone.info);
  });

  test('the first saving is welcomed only once it is recent', () {
    final fresh = buildFacts(
      now: _now,
      transfers: [transferAt(50, DateTime(2026, 10, 12))],
    );
    expect(_run(fresh).containsKey('first-saving'), isTrue);
    final old = buildFacts(
      now: _now,
      transfers: [transferAt(50, DateTime(2026, 6, 12))],
    );
    expect(_run(old).containsKey('first-saving'), isFalse);
  });

  test('a withdrawal of a third of savings is a warning', () {
    final facts = buildFacts(
      now: _now,
      savingsBalance: 200,
      transfers: [
        transferAt(500, DateTime(2026, 8, 1)),
        transferAt(300, DateTime(2026, 10, 10), out: true),
      ],
    );
    final card = _run(facts)['large-withdrawal']!;
    expect(card.tone, InsightTone.warning);
    expect(card.body, contains('\u206660%\u2069'));
  });

  test('late in the month a large spare balance is a suggestion', () {
    final facts = buildFacts(
      now: DateTime(2026, 10, 25, 12),
      balance: 800,
      monthlyIncome: 1000,
      hasRecurringIncome: true,
      expenses: [
        for (var d = 1; d <= 24; d++) expenseAt(5, DateTime(2026, 10, d)),
      ],
    );
    final card = _run(facts)['idle-balance']!;
    expect(card.kind, InsightKind.suggestion);
    expect(card.action, InsightAction.manualSave);
    expect(
      _run(buildFacts(now: _now, balance: 800, monthlyIncome: 1000)),
      isNot(contains('idle-balance')),
    );
  });

  test('no saving at all after a month of history', () {
    final facts = buildFacts(
      now: _now,
      monthlyIncome: 1000,
      expenses: [expenseAt(10, DateTime(2026, 9, 1))],
    );
    expect(_run(facts)['never-saved']!.body, contains('50 ل.س'));
    final early = buildFacts(
      now: _now,
      monthlyIncome: 1000,
      expenses: [expenseAt(10, DateTime(2026, 10, 10))],
    );
    expect(_run(early).containsKey('never-saved'), isFalse);
  });

  test('goals needing far more than the saving pace', () {
    GoalFact goal(String id) => GoalFact(
      id: id,
      name: id,
      target: 3000,
      saved: 0,
      createdAt: DateTime(2026, 9, 1),
      plannedMonths: 3,
    );
    final facts = buildFacts(
      now: _now,
      goals: [goal('a'), goal('b')],
      transfers: [
        transferAt(100, DateTime(2026, 8, 1)),
        transferAt(100, DateTime(2026, 9, 1)),
      ],
    );
    expect(_run(facts)['goals-overloaded']!.kind, InsightKind.suggestion);
  });
}
