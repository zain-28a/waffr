// InsightSummary: the closing tip, the headline chosen from the warnings
// and positives (or the health score), and the per-scope summary line.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waffr/core/insights/smart/insight_phrasing.dart';
import 'package:waffr/core/insights/smart/insight_summary.dart';
import 'package:waffr/core/insights/smart/smart_facts.dart';
import 'package:waffr/core/insights/smart/smart_insight.dart';

import '../../../helpers/ledger_builders.dart';

final DateTime _now = DateTime(2026, 10, 20, 12);

InsightSummary _summary(SmartFacts facts, {int seed = 0}) =>
    InsightSummary(facts, InsightPhrasing('ل.س', math.Random(seed)));

SmartInsight _card(InsightTone tone) => SmartInsight(
  id: tone.name,
  tone: tone,
  icon: Icons.circle,
  title: 't',
  body: 'b',
);

void main() {
  test('the tip fits the data, or there is none', () {
    // Nothing recorded: no spending tip applies, but saving tips need no
    // spending (no goal yet).
    expect(_summary(buildFacts(now: _now)).tip(InsightScope.reports), isNull);
    final savings = _summary(buildFacts(now: _now)).tip(InsightScope.savings)!;
    expect(savings.id, 'tip');
    expect(savings.tone, InsightTone.tip);
    expect(savings.kind, InsightKind.suggestion);
    expect(savings.priority, 0);
    expect(savings.body, contains('هدف'));

    // Food as the top category brings the weekly-cap tip into the options.
    final food = buildFacts(
      now: _now,
      expenses: [
        expenseAt(300, DateTime(2026, 10, 3)),
        expenseAt(100, DateTime(2026, 10, 4), category: 'مواصلات'),
      ],
    );
    final bodies = {
      for (var seed = 0; seed < 20; seed++)
        _summary(food, seed: seed).tip(InsightScope.reports)!.body,
    };
    expect(bodies.any((body) => body.contains('الطعام')), isTrue);
  });

  test('profile headlines speak of the score', () {
    for (var seed = 0; seed < 10; seed++) {
      final line = _summary(
        buildFacts(now: _now),
        seed: seed,
      ).headline(InsightScope.profile, const [], 82);
      expect(
        line.contains('ممتازة') || line.contains('82/100'),
        isTrue,
        reason: line,
      );
    }
  });

  test('reports without expenses invite logging', () {
    final line = _summary(buildFacts(now: _now))
        .headline(InsightScope.reports, const [], null);
    expect(
      line,
      anyOf(
        startsWith('سجّل مصروفاتك'),
        startsWith('التحليل جاهز'),
        startsWith('سجّل أول مصروف'),
      ),
    );
  });

  test('warning and positive counts choose the headline family', () {
    final facts = buildFacts(
      now: _now,
      expenses: [expenseAt(5, DateTime(2026, 10, 1))],
    );
    const two = [
      'هناك نقطتان تحتاجان إلى انتباهك.',
      'بعض المؤشرات تطلب انتباهك.',
      'إليك ما يحتاج إلى متابعة أدق.',
    ];
    for (var seed = 0; seed < 8; seed++) {
      expect(
        two,
        contains(
          _summary(facts, seed: seed).headline(InsightScope.reports, [
            _card(InsightTone.warning),
            _card(InsightTone.warning),
          ], null),
        ),
      );
    }
    final three = _summary(facts, seed: 0).headline(InsightScope.reports, [
      for (var i = 0; i < 3; i++) _card(InsightTone.warning),
    ], null);
    expect(three, isNot('هناك نقطتان تحتاجان إلى انتباهك.'));

    final one = _summary(facts).headline(InsightScope.savings, [
      _card(InsightTone.warning),
      _card(InsightTone.positive),
    ], null);
    expect(
      one,
      anyOf(
        contains('نقطة واحدة'),
        contains('ملاحظة مهمة'),
        contains('أمر واحد'),
      ),
    );

    final happy = _summary(facts).headline(InsightScope.reports, [
      _card(InsightTone.positive),
      _card(InsightTone.positive),
    ], null);
    expect(happy, anyOf(contains('أخبار جيدة'), contains('المؤشرات')));
  });

  test('report summary mentions the month total and top category', () {
    final facts = buildFacts(
      now: _now,
      expenses: [
        expenseAt(300, DateTime(2026, 10, 3), category: 'مواصلات'),
        expenseAt(100, DateTime(2026, 10, 4)),
      ],
    );
    for (var seed = 0; seed < 6; seed++) {
      final text = _summary(facts, seed: seed).summary(InsightScope.reports);
      expect(text, contains('المواصلات'));
      expect(text, contains('\u206675%\u2069'), reason: 'its real share');
      expect(text, anyOf(contains('400 ل.س'), contains('20 ل.س')));
    }
    expect(_summary(buildFacts(now: _now)).summary(InsightScope.reports), '');
  });

  test('savings summary states the balance and active goals', () {
    final text = _summary(
      buildFacts(
        now: _now,
        savingsBalance: 1250,
        goals: [
          for (final id in ['a', 'b'])
            GoalFact(
              id: id,
              name: id,
              target: 10,
              saved: 0,
              createdAt: _now,
              plannedMonths: 1,
            ),
        ],
      ),
    ).summary(InsightScope.savings);
    expect(text, contains('1,250 ل.س'));
    expect(text, contains('لديك هدفان نشطان.'));
    expect(
      _summary(buildFacts(now: _now)).summary(InsightScope.profile),
      isNotEmpty,
    );
  });
}
