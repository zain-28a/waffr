import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Marks that local user data changed since the last successful sync.
class SyncDirty {
  SyncDirty._();

  static const String key = 'waffer_sync_dirty';
  static const String settingsUpdatedAtKey = 'waffer_settings_updated_at';

  static bool suppressed = false;

  static final List<VoidCallback> _listeners = <VoidCallback>[];

  static void addListener(VoidCallback listener) {
    if (!_listeners.contains(listener)) {
      _listeners.add(listener);
    }
  }

  static void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  static Future<void> mark({bool settings = false}) async {
    if (suppressed) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, true);
    if (settings) {
      await prefs.setString(
        settingsUpdatedAtKey,
        DateTime.now().toUtc().toIso8601String(),
      );
    }

    for (final listener in List<VoidCallback>.from(_listeners)) {
      listener();
    }
  }

  static Future<bool> isDirty() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key) ?? false;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, false);
  }

  static Future<DateTime?> settingsUpdatedAt() async {
    final prefs = await SharedPreferences.getInstance();
    return DateTime.tryParse(
      prefs.getString(settingsUpdatedAtKey) ?? '',
    )?.toUtc();
  }

  static Future<void> setSettingsUpdatedAt(DateTime value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      settingsUpdatedAtKey,
      value.toUtc().toIso8601String(),
    );
  }
}
