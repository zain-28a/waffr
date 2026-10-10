import 'package:flutter_test/flutter_test.dart';
import 'package:waffr/data/services/home_widget_sync.dart';

void main() {
  final now = DateTime(2026, 10, 20, 9);

  Map<String, Object> build({
    ({String name, double target, double saved})? goal,
    List<({String name, double amount, DateTime due})> obligations = const [],
    int streak = 5,
  }) =>
      buildHomeWidgetData(
        now: now,
        symbol: 'ل.س',
        balance: 400,
        spent: 600,
        maxBalance: 1000,
        remainingRatio: 0.4,
        goal: goal,
        obligations: obligations,
        streak: streak,
      );

  test('balance text and remaining percent', () {
    final data = build();

    expect(data['balance_amount'], '400');
    expect(data['balance_percent'], '40');
    expect(data['balance_caption'], 'مصروف 600 من 1,000 ل.س');
  });

  test('empty goal and obligation fall back to friendly text', () {
    final data = build();

    expect(data['goal_empty'], true);
    expect(data['obligation_empty'], true);
  });

  test('nearest obligation wins and its date reads naturally', () {
    final data = build(obligations: [
      (name: 'إنترنت', amount: 50, due: DateTime(2026, 10, 25)),
      (name: 'إيجار', amount: 300, due: DateTime(2026, 10, 21)),
    ]);

    expect(data['obligation_name'], 'إيجار');
    expect(data['obligation_when'], 'غداً');
    expect(
      build(obligations: [
        (name: 'x', amount: 1, due: DateTime(2026, 10, 25)),
      ])['obligation_when'],
      'بعد 5 أيام',
    );
  });

  test('goal percent and streak label agree with the number', () {
    final data = build(goal: (name: 'سفر', target: 1000, saved: 250), streak: 12);

    expect(data['goal_percent'], '25');
    expect(data['goal_empty'], false);
    expect(data['streak_label'], 'يوماً متتالياً');
    expect(build(streak: 4)['streak_label'], 'أيام متتالية');
  });
}
