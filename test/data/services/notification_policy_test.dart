// NotificationPolicy: the quiet hours, the one-non-urgent-banner-a-day
// limit, and the reminder plan (out of quiet hours, one per day by rank).

import 'package:flutter_test/flutter_test.dart';
import 'package:waffr/data/services/notification_policy.dart';

PlannedReminder _reminder(int id, DateTime at, {int rank = 0}) =>
    PlannedReminder(id: id, title: 't$id', body: 'b', at: at, rank: rank);

void main() {
  test('quiet hours run from 22:00 to 08:00', () {
    expect(NotificationPolicy.isQuiet(DateTime(2026, 10, 20, 21, 59)), isFalse);
    expect(NotificationPolicy.isQuiet(DateTime(2026, 10, 20, 22)), isTrue);
    expect(NotificationPolicy.isQuiet(DateTime(2026, 10, 21, 3)), isTrue);
    expect(NotificationPolicy.isQuiet(DateTime(2026, 10, 21, 7, 59)), isTrue);
    expect(NotificationPolicy.isQuiet(DateTime(2026, 10, 21, 8)), isFalse);
  });

  test('one non-urgent banner a day; urgent ones pass, never at night', () {
    final noon = DateTime(2026, 10, 20, 12);
    final today = NotificationPolicy.dayKey(noon);
    expect(NotificationPolicy.mayPresent(now: noon, urgent: false), isTrue);
    expect(
      NotificationPolicy.mayPresent(
        now: noon,
        urgent: false,
        lastNonUrgentDay: today,
      ),
      isFalse,
    );
    expect(
      NotificationPolicy.mayPresent(
        now: noon,
        urgent: true,
        lastNonUrgentDay: today,
      ),
      isTrue,
    );
    expect(
      NotificationPolicy.mayPresent(
        now: DateTime(2026, 10, 20, 23),
        urgent: true,
      ),
      isFalse,
    );
    expect(
      NotificationPolicy.mayPresent(
        now: noon,
        urgent: false,
        lastNonUrgentDay: NotificationPolicy.dayKey(
          noon.subtract(const Duration(days: 1)),
        ),
      ),
      isTrue,
    );
  });

  test('the plan keeps one reminder per day, the lowest rank', () {
    final now = DateTime(2026, 10, 20, 9);
    final plan = NotificationPolicy.plan([
      _reminder(1, DateTime(2026, 10, 22, 20, 30), rank: 3),
      _reminder(2, DateTime(2026, 10, 22, 18), rank: 1),
      _reminder(3, DateTime(2026, 10, 23, 18), rank: 2),
    ], now: now);
    expect(plan.map((item) => item.id), [2, 3]);
  });

  test('quiet-hour times move into the evening or morning', () {
    final now = DateTime(2026, 10, 20, 9);
    final plan = NotificationPolicy.plan([
      _reminder(1, DateTime(2026, 10, 21, 23, 15)),
      _reminder(2, DateTime(2026, 10, 22, 6)),
    ], now: now);
    expect(plan.first.at, DateTime(2026, 10, 21, 20, 30));
    expect(plan.last.at, DateTime(2026, 10, 22, 8, 30));
  });

  test('past reminders and busy days are dropped', () {
    final now = DateTime(2026, 10, 20, 19);
    final plan = NotificationPolicy.plan(
      [
        _reminder(1, DateTime(2026, 10, 20, 18)),
        _reminder(2, DateTime(2026, 10, 20, 20)),
        _reminder(3, DateTime(2026, 10, 21, 20)),
      ],
      now: now,
      busyDays: {NotificationPolicy.dayKey(now)},
    );
    expect(plan.map((item) => item.id), [3]);
  });
}
