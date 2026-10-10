// Dirty flag: tracks whether local data changed since the last successful sync.

import 'package:flutter/foundation.dart';
import 'package:waffr/core/prefs/app_prefs.dart';

// Persists a "needs push" bit and optional settings timestamp so SyncService
// knows when to send a full or incremental payload.
class SyncDirty {
  SyncDirty._();

  static const String key = 'waffer_sync_dirty';
  static const String settingsUpdatedAtKey = 'waffer_settings_updated_at';

  // When true, applying a remote pull will not re-mark local data as dirty.
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

  // Flip the dirty bit after a local edit; optionally stamp settings change time.
  static Future<void> mark({bool settings = false}) async {
    if (suppressed) return;

    final prefs = await AppPrefs.instance;
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
    final prefs = await AppPrefs.instance;
    return prefs.getBool(key) ?? false;
  }

  // Cleared only after a successful sync round-trip.
  static Future<void> clear() async {
    final prefs = await AppPrefs.instance;
    await prefs.setBool(key, false);
  }

  static Future<DateTime?> settingsUpdatedAt() async {
    final prefs = await AppPrefs.instance;
    return DateTime.tryParse(
      prefs.getString(settingsUpdatedAtKey) ?? '',
    )?.toUtc();
  }

  static Future<void> setSettingsUpdatedAt(DateTime value) async {
    final prefs = await AppPrefs.instance;
    await prefs.setString(
      settingsUpdatedAtKey,
      value.toUtc().toIso8601String(),
    );
  }
}
