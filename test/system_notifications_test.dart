import 'package:flutter_test/flutter_test.dart';
import 'package:waffr/data/services/system_notifications.dart';

void main() {
  DateTime next(DateTime now) => SystemNotifications.nextFridayEvening(now);

  test('weekly summary lands on the coming Friday evening', () {
    // Tuesday 2026-10-20 -> Friday 2026-10-23 18:00.
    expect(next(DateTime(2026, 10, 20, 9)), DateTime(2026, 10, 23, 18));
  });

  test('Friday morning still gets the same evening', () {
    expect(next(DateTime(2026, 10, 23, 5)), DateTime(2026, 10, 23, 18));
  });

  test('late Friday moves to the next week', () {
    expect(next(DateTime(2026, 10, 23, 17)), DateTime(2026, 10, 30, 18));
    expect(next(DateTime(2026, 10, 23, 20)), DateTime(2026, 10, 30, 18));
  });

  test('Saturday points to the following Friday', () {
    expect(next(DateTime(2026, 10, 24, 10)), DateTime(2026, 10, 30, 18));
  });
}
