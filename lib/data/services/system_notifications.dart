// Device notifications for real Waffr events. In-app history stays in
// NotificationService; this only mirrors new alerts and one daily streak nudge.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class SystemNotifications {
  SystemNotifications._();

  static final SystemNotifications instance = SystemNotifications._();

  static const String channelId = 'waffr_alerts';
  static const int _streakId = 41021;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Future<void>? _starting;
  bool _ready = false;
  bool _timeZoneReady = false;

  Future<void> initialize() {
    return _starting ??= _start();
  }

  Future<void> present({
    required String eventKey,
    required String title,
    required String body,
  }) async {
    await initialize();
    if (!_ready) return;
    try {
      await _plugin.show(
        id: _id(eventKey),
        title: title,
        body: body,
        notificationDetails: _details(),
      );
    } catch (_) {}
  }

  /// One reminder for tomorrow evening. Cancelled whenever the app is opened.
  Future<void> syncStreakReminder({
    required bool enabled,
    int streakCount = 0,
  }) async {
    await initialize();
    if (!_ready) return;
    try {
      await _plugin.cancel(id: _streakId);
      if (!enabled || !_timeZoneReady) return;

      final tomorrow = _tomorrowEvening();

      await _plugin.zonedSchedule(
        id: _streakId,
        title: streakCount >= 2
            ? 'لديك $streakCount أيام متواصلة في وفّر'
            : 'أيامك المتواصلة في وفّر',
        body: 'سجّل مصروفات اليوم حتى لا تنقطع أيامك المتواصلة.',
        scheduledDate: tomorrow,
        notificationDetails: _details(),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (_) {}
  }

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

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

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

  /// Local 19:30 tomorrow, stored as a UTC instant so no timezone database
  /// lookup is required.
  tz.TZDateTime _tomorrowEvening() {
    final now = DateTime.now();
    final local = DateTime(now.year, now.month, now.day, 19, 30)
        .add(const Duration(days: 1));
    final utc = local.toUtc();
    return tz.TZDateTime.utc(utc.year, utc.month, utc.day, utc.hour, utc.minute);
  }
}
