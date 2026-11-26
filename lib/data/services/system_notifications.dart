// Device notifications for real Waffr events. In-app history stays in
// NotificationService; this mirrors new alerts, and schedules the daily
// streak nudge, the logging nudge, short comeback reminders and the weekly
// digest.
//
// NotificationPolicy decides what may show: nothing between 22:00 and
// 08:00, one non-urgent banner a day, and one scheduled reminder a day.
// Every reminder request goes through one plan, so two kinds can never
// land on the same evening.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:waffr/core/insights/smart/arabic_text.dart';
import 'package:waffr/core/insights/smart/reminder_digest.dart';
import 'package:waffr/core/prefs/app_prefs.dart';
import 'package:waffr/data/services/notification_policy.dart';

/// Shows and schedules device (OS) notifications.
class SystemNotifications {
  SystemNotifications._();

  /// The app-wide service.
  static final SystemNotifications instance = SystemNotifications._();

  /// Android channel of every Waffr notification.
  static const String channelId = 'waffr_alerts';
  static const int _streakId = 41021;
  static const int _comebackSoonId = 41022;
  static const int _comebackLaterId = 41023;
  static const int _weeklyId = 41024;
  static const int _loggingNudgeId = 41025;

  /// Every scheduled reminder id, cancelled and re-planned together.
  static const List<int> _reminderIds = [
    _streakId,
    _comebackSoonId,
    _comebackLaterId,
    _weeklyId,
    _loggingNudgeId,
  ];

  // Which reminder keeps its evening when two fall on the same day.
  static const int _rankComebackSoon = 0;
  static const int _rankLoggingNudge = 1;
  static const int _rankWeekly = 2;
  static const int _rankComebackLater = 3;
  static const int _rankStreak = 4;

  /// Prefs key: day of the last non-urgent banner (the daily limit).
  static const String _lastNonUrgentKey = 'notif_last_nonurgent_day';

  /// The reminders each sync asked for, by id; null cancels one.
  final Map<int, PlannedReminder?> _requests = {};

  /// Serializes plan rebuilds.
  Future<void> _planning = Future.value();

  /// Payload of reminders that open the smart analysis when tapped.
  static const String smartPayload = 'smart';

  final StreamController<String> _taps = StreamController<String>.broadcast();

  /// Payloads of notifications tapped while the app is running.
  Stream<String> get taps => _taps.stream;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Future<void>? _starting;
  bool _ready = false;
  bool _timeZoneReady = false;

  /// Sets up the plugin once; safe to call repeatedly.
  Future<void> initialize() {
    return _starting ??= _start();
  }

  /// Shows an alert now; [eventKey] gives it a stable id. Nothing shows in
  /// the quiet hours, and a non-[urgent] alert only when no other
  /// non-urgent banner showed today.
  Future<void> present({
    required String eventKey,
    required String title,
    required String body,
    bool urgent = false,
  }) async {
    await initialize();
    if (!_ready) return;
    final now = DateTime.now();
    final prefs = await AppPrefs.instance;
    final lastDay = prefs.getString(_lastNonUrgentKey);
    if (!NotificationPolicy.mayPresent(
      now: now,
      urgent: urgent,
      lastNonUrgentDay: lastDay,
    )) {
      return;
    }
    try {
      await _plugin.show(
        id: _id(eventKey),
        title: title,
        body: body,
        notificationDetails: _details(),
      );
    } catch (_) {
      return;
    }
    if (!urgent) {
      await prefs.setString(_lastNonUrgentKey, NotificationPolicy.dayKey(now));
      // A reminder planned for today would be a second banner.
      await _replan();
    }
  }

  /// Schedules (or cancels) the evening streak reminder for tomorrow.
  Future<void> syncStreakReminder({
    required bool enabled,
    int streakCount = 0,
  }) async {
    if (!enabled) {
      _requests[_streakId] = null;
    } else {
      final text = ReminderDigest.streakText(streakCount);
      _requests[_streakId] = PlannedReminder(
        id: _streakId,
        title: text.title,
        body: text.body,
        at: _localAt(daysFromNow: 1, hour: 19, minute: 30),
        rank: _rankStreak,
      );
    }
    await _replan();
  }

  /// Schedules the comeback reminders (two and five days ahead) and the
  /// weekly digest; every app open pushes them forward. With [enabled]
  /// false they are all cancelled.
  Future<void> syncComebackReminders({
    required bool enabled,
    (String, String)? soon,
    (String, String)? later,
    (String, String)? weekly,
  }) async {
    final now = DateTime.now();
    PlannedReminder? request(
      int id,
      (String, String)? text,
      DateTime at,
      int rank,
    ) => !enabled || text == null
        ? null
        : PlannedReminder(
            id: id,
            title: text.$1,
            body: text.$2,
            at: at,
            rank: rank,
            payload: smartPayload,
          );
    _requests[_comebackSoonId] = request(
      _comebackSoonId,
      soon,
      soonAt(now),
      _rankComebackSoon,
    );
    _requests[_comebackLaterId] = request(
      _comebackLaterId,
      later,
      laterAt(now),
      _rankComebackLater,
    );
    _requests[_weeklyId] = request(
      _weeklyId,
      weekly,
      nextFridayEvening(now),
      _rankWeekly,
    );
    await _replan();
  }

  /// One reminder, three days after [lastExpenseAt] at 20:00, when nothing
  /// else has been logged by then. Re-synced whenever the ledger changes, so
  /// a new expense moves it; once its evening has passed it is not repeated.
  Future<void> syncLoggingNudge({
    required bool enabled,
    DateTime? lastExpenseAt,
  }) async {
    final last = lastExpenseAt?.toLocal();
    if (!enabled || last == null) {
      _requests[_loggingNudgeId] = null;
    } else {
      final at = loggingNudgeAt(last);
      _requests[_loggingNudgeId] = PlannedReminder(
        id: _loggingNudgeId,
        title: 'لم تسجّل أي مصروف منذ ${Ar.days.of(3)}',
        body:
            'سجّل ما صرفته في الأيام الماضية ولو تقريبياً، ليبقى رصيدك دقيقاً.',
        at: at,
        rank: _rankLoggingNudge,
      );
    }
    await _replan();
  }

  /// When the logging nudge for an expense at [lastExpenseAt] fires.
  @visibleForTesting
  static DateTime loggingNudgeAt(DateTime lastExpenseAt) => DateTime(
    lastExpenseAt.year,
    lastExpenseAt.month,
    lastExpenseAt.day + 3,
    20,
  );

  // Cancels every reminder and schedules the current plan.
  Future<void> _replan() {
    return _planning = _planning.then((_) async {
      await initialize();
      if (!_ready) return;
      try {
        for (final id in _reminderIds) {
          await _plugin.cancel(id: id);
        }
        if (!_timeZoneReady) return;
        final prefs = await AppPrefs.instance;
        final busy = prefs.getString(_lastNonUrgentKey);
        final plan = NotificationPolicy.plan(
          _requests.values.whereType<PlannedReminder>(),
          now: DateTime.now(),
          busyDays: {?busy},
        );
        for (final item in plan) {
          await _plugin.zonedSchedule(
            id: item.id,
            title: item.title,
            body: item.body,
            scheduledDate: _utc(item.at),
            notificationDetails: _details(),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            payload: item.payload,
          );
        }
      } catch (_) {}
    });
  }

  /// When the first comeback reminder fires (two days later, 20:30), for
  /// writing its text ahead.
  static DateTime soonAt(DateTime now) =>
      DateTime(now.year, now.month, now.day + 2, 20, 30);

  /// When the second comeback reminder fires (five days later, 20:30).
  static DateTime laterAt(DateTime now) =>
      DateTime(now.year, now.month, now.day + 5, 20, 30);

  /// Payload of the notification that launched the app, if one did.
  Future<String?> launchPayload() async {
    await initialize();
    if (!_ready) return null;
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp != true) return null;
      return details?.notificationResponse?.payload;
    } catch (_) {
      return null;
    }
  }

  /// Removes every shown and scheduled notification.
  Future<void> cancelAll() async {
    await initialize();
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }

  Future<void> _start() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.UTC);
      _timeZoneReady = true;
    } catch (_) {
      _timeZoneReady = false;
    }

    try {
      final granted = await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_waffr'),
        ),
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload != null && payload.isNotEmpty) _taps.add(payload);
        },
      );
      _ready = granted != false;
      await _android?.createNotificationChannel(
        const AndroidNotificationChannel(
          channelId,
          'تنبيهات وفّر',
          description: 'تنبيهات الرصيد والتوفير والأهداف',
          importance: Importance.defaultImportance,
        ),
      );
    } catch (error) {
      debugPrint('Notification setup failed: $error');
      _ready = false;
    }

    // Asked separately so a setup problem never skips the system prompt
    // (Android 13+; older versions allow notifications by default).
    await requestPermission();
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  /// Whether the system lets the app post notifications. Null when unknown
  /// (not Android).
  Future<bool?> deviceNotificationsEnabled() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      return await _android?.areNotificationsEnabled();
    } catch (_) {
      return null;
    }
  }

  /// Shows the system permission prompt when Android still allows it.
  /// Returns true when notifications are allowed afterwards.
  Future<bool> requestPermission() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final granted = await _android?.requestNotificationsPermission();
      return granted ?? (await deviceNotificationsEnabled() ?? false);
    } catch (error) {
      debugPrint('Notification permission request failed: $error');
      return false;
    }
  }

  NotificationDetails _details() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        'تنبيهات وفّر',
        channelDescription: 'تنبيهات الرصيد والتوفير والأهداف',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        icon: 'ic_stat_waffr',
      ),
    );
  }

  int _id(String eventKey) => eventKey.hashCode & 0x7fffffff;

  /// Friday 18:00 local after [now], at least half a day away.
  @visibleForTesting
  static DateTime nextFridayEvening(DateTime now) {
    var days = (DateTime.friday - now.weekday) % 7;
    var local = DateTime(now.year, now.month, now.day + days, 18);
    if (local.difference(now).inHours < 12) {
      days += 7;
      local = DateTime(now.year, now.month, now.day + days, 18);
    }
    return local;
  }

  /// A local wall-clock time [daysFromNow] days ahead.
  DateTime _localAt({
    required int daysFromNow,
    required int hour,
    required int minute,
  }) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day + daysFromNow, hour, minute);
  }

  /// [local] as a UTC instant, so no timezone database lookup is needed.
  tz.TZDateTime _utc(DateTime local) {
    final utc = local.toUtc();
    return tz.TZDateTime.utc(
      utc.year,
      utc.month,
      utc.day,
      utc.hour,
      utc.minute,
    );
  }
}
