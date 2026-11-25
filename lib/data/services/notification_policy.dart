// When Waffr may show a device notification: never in the quiet hours,
// at most one non-urgent notification per day, and at most one scheduled
// reminder per day. Pure rules, so they are tested without the plugin;
// SystemNotifications applies them.
//
// The in-app notification list is not affected: every alert still lands
// there. Only the device banner is held back.

/// One reminder the app would like scheduled.
class PlannedReminder {
  /// The plugin id (one per reminder kind, so a new plan replaces it).
  final int id;

  /// Banner title.
  final String title;

  /// Banner text.
  final String body;

  /// Local time it should fire.
  final DateTime at;

  /// Lower wins when two reminders fall on the same day.
  final int rank;

  /// Tap payload, if any.
  final String? payload;

  /// A reminder request.
  const PlannedReminder({
    required this.id,
    required this.title,
    required this.body,
    required this.at,
    required this.rank,
    this.payload,
  });

  /// The same reminder at another time.
  PlannedReminder copyAt(DateTime when) => PlannedReminder(
    id: id,
    title: title,
    body: body,
    at: when,
    rank: rank,
    payload: payload,
  );
}

/// The quiet hours and the daily limit.
abstract final class NotificationPolicy {
  /// Quiet hours start (local hour, inclusive).
  static const int quietStartHour = 22;

  /// Quiet hours end (local hour, exclusive).
  static const int quietEndHour = 8;

  /// True between 22:00 and 08:00 local time.
  static bool isQuiet(DateTime time) =>
      time.hour >= quietStartHour || time.hour < quietEndHour;

  /// The calendar day of [time] as `yyyy-mm-dd`, the key the daily limit
  /// is counted by.
  static String dayKey(DateTime time) =>
      '${time.year.toString().padLeft(4, '0')}-'
      '${time.month.toString().padLeft(2, '0')}-'
      '${time.day.toString().padLeft(2, '0')}';

  /// Whether a banner may show now: never in quiet hours, and a non-urgent
  /// one only when no other non-urgent banner showed today
  /// ([lastNonUrgentDay] is the day key of the last one).
  static bool mayPresent({
    required DateTime now,
    required bool urgent,
    String? lastNonUrgentDay,
  }) {
    if (isQuiet(now)) return false;
    if (urgent) return true;
    return lastNonUrgentDay != dayKey(now);
  }

  /// The reminders to schedule from [requests]: each moved out of the quiet
  /// hours (late evening to 20:30, early morning to 08:30), anything not
  /// after [now] dropped, and one per day, the lowest rank winning. Days in
  /// [busyDays] (a banner already showed) get none.
  static List<PlannedReminder> plan(
    Iterable<PlannedReminder> requests, {
    required DateTime now,
    Set<String> busyDays = const {},
  }) {
    final byDay = <String, PlannedReminder>{};
    final sorted = [...requests.map(_outOfQuiet)]
      ..sort((a, b) {
        final byRank = a.rank.compareTo(b.rank);
        return byRank != 0 ? byRank : a.id.compareTo(b.id);
      });
    for (final item in sorted) {
      if (!item.at.isAfter(now)) continue;
      final day = dayKey(item.at);
      if (busyDays.contains(day) || byDay.containsKey(day)) continue;
      byDay[day] = item;
    }
    return byDay.values.toList()..sort((a, b) => a.at.compareTo(b.at));
  }

  static PlannedReminder _outOfQuiet(PlannedReminder item) {
    final at = item.at;
    if (at.hour >= quietStartHour) {
      return item.copyAt(DateTime(at.year, at.month, at.day, 20, 30));
    }
    if (at.hour < quietEndHour) {
      return item.copyAt(DateTime(at.year, at.month, at.day, 8, 30));
    }
    return item;
  }
}
