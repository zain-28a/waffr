import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waffer/core/prefs/app_prefs.dart';
import 'package:waffer/core/usage/streak_math.dart';
import 'package:waffer/data/services/usage_streak_service.dart';
import 'package:waffer/data/stores/transaction_store.dart';
import 'package:waffer/screens/offline/profile/streak_card.dart';
import 'package:waffer/core/usage/usage_duration.dart';
import 'package:waffer/core/insights/spending_improvement.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('opening on the next day hands out one streak increase', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await AppPrefs.instance;
    await prefs.clear();
    TransactionStore.instance.resetCache();
    final service = UsageStreakService.instance..resetCache();

    await service.recordToday(now: DateTime(2026, 9, 1, 9));
    expect(service.takeIncrease(), isNull, reason: 'day one is not an increase');

    await service.recordToday(now: DateTime(2026, 9, 1, 20));
    expect(service.takeIncrease(), isNull, reason: 'same day again');

    await service.recordToday(now: DateTime(2026, 9, 2, 8));
    final increase = service.takeIncrease();
    expect(increase?.from, 1);
    expect(increase?.to, 2);
    expect(service.takeIncrease(), isNull, reason: 'handed out once');

    await service.recordToday(now: DateTime(2026, 9, 5, 8));
    expect(service.count, 1);
    expect(service.takeIncrease(), isNull, reason: 'a broken streak restarts');
  });

  test('the next streak milestone is the next round number', () {
    expect(nextStreakMilestone(1), 3);
    expect(nextStreakMilestone(3), 7);
    expect(nextStreakMilestone(29), 30);
    expect(nextStreakMilestone(365), 730);
  });

  test('first open is day one and a repeat the same day stays there', () {
    final first = StreakMath.record(
      const StreakSnapshot(),
      DateTime(2026, 9, 1, 8),
    );
    expect(first.count, 1);
    expect(first.label, 'اليوم الأول');

    final again = StreakMath.record(first, DateTime(2026, 9, 1, 22));
    expect(again.count, 1);
    expect(again.label, 'اليوم الأول');
  });

  test('the next calendar day continues and a missed day restarts', () {
    final dayOne = StreakMath.record(
      const StreakSnapshot(),
      DateTime(2026, 9, 1),
    );
    final dayTwo = StreakMath.record(dayOne, DateTime(2026, 9, 2, 1));
    expect(dayTwo.count, 2);
    expect(dayTwo.label, '2 أيام متواصلة');

    final daySeven = StreakSnapshot(
      count: 7,
      lastDay: DateTime(2026, 9, 7),
      startedAt: DateTime(2026, 9, 1),
    );
    final missed = StreakMath.record(daySeven, DateTime(2026, 9, 9));
    expect(missed.count, 1);
    expect(missed.label, 'اليوم الأول');
  });

  test('merge keeps a longer streak when this device only recorded today', () {
    final local = StreakSnapshot(
      count: 1,
      lastDay: DateTime(2026, 9, 8),
      startedAt: DateTime(2026, 9, 8),
    );
    final remote = StreakSnapshot(
      count: 7,
      lastDay: DateTime(2026, 9, 7),
      startedAt: DateTime(2026, 6, 1),
    );
    final merged = StreakMath.merge(local, remote);
    expect(merged.count, 8);
    expect(StreakSnapshot.dayKey(merged.lastDay), '2026-09-08');
    expect(merged.startedAt, DateTime(2026, 6, 1));
  });

  test('usage duration stays compact', () {
    expect(
      usageDurationText(DateTime(2026, 9, 27), DateTime(2026, 9, 27, 18)),
      'اليوم',
    );
    expect(
      usageDurationText(DateTime(2026, 9, 20), DateTime(2026, 9, 27)),
      '7 أيام',
    );
  });

  test('spending improvement matches the reports comparison', () {
    final better = SpendingImprovement.calculate(
      currentTotal: 80,
      previousTotal: 100,
    );
    expect(better.kind, SpendingChange.positive);
    expect(better.text, '+20.0%');

    final worse = SpendingImprovement.calculate(
      currentTotal: 150,
      previousTotal: 100,
    );
    expect(worse.kind, SpendingChange.negative);
    expect(worse.detail, 'المصروف ارتفع مقارنة بالفترة السابقة');
  });
}
