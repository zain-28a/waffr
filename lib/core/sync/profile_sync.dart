import 'package:shared_preferences/shared_preferences.dart';
import 'package:waffer/core/sync/sync_clock.dart';
import 'package:waffer/core/sync/sync_dirty.dart';

/// Profile fields stored in prefs and synced through `/sync` settings.
class ProfileSync {
  ProfileSync._();

  static const Map<String, String> _accountKeys = {
    'name': 'user_name',
    'gender': 'user_gender',
    'birthdate': 'user_birthdate',
    'country': 'user_country',
    'city': 'user_city',
    'street': 'user_street',
  };

  static Future<Map<String, dynamic>> fields() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'display_name': prefs.getString('user_name'),
      'gender': prefs.getString('user_gender'),
      'birthdate': prefs.getString('user_birthdate'),
      'country': prefs.getString('user_country'),
      'city': prefs.getString('user_city'),
      'street': prefs.getString('user_street'),
      if (prefs.containsKey('dark_mode'))
        'dark_mode': prefs.getBool('dark_mode'),
    };
  }

  /// Replaces the on-device profile with [profile] from the signed-in account.
  /// Missing values are removed so a previous account cannot remain visible.
  static Future<void> adoptAccount(Map<String, dynamic> profile) async {
    final prefs = await SharedPreferences.getInstance();
    for (final entry in _accountKeys.entries) {
      if (!profile.containsKey(entry.key)) continue;
      final raw = profile[entry.key]?.toString().trim() ?? '';
      if (raw.isEmpty) {
        await prefs.remove(entry.value);
      } else {
        await prefs.setString(entry.value, raw);
      }
    }
    await SyncDirty.mark(settings: true);
  }

  /// Fills empty local fields from the signed-in account without replacing edits.
  static Future<void> fillMissing(Map<String, dynamic> profile) async {
    final prefs = await SharedPreferences.getInstance();
    for (final entry in _accountKeys.entries) {
      final raw = profile[entry.key]?.toString().trim() ?? '';
      if (raw.isEmpty) continue;
      final existing = prefs.getString(entry.value)?.trim() ?? '';
      if (existing.isEmpty) {
        await prefs.setString(entry.value, raw);
      }
    }
  }

  static Future<void> apply(Map<String, dynamic> settings) async {
    final remoteUpdated = parseSyncDate(settings['updated_at']);
    final localUpdated = await SyncDirty.settingsUpdatedAt();
    if (!newerOrEqual(remoteUpdated, localUpdated)) return;

    final prefs = await SharedPreferences.getInstance();

    final name = settings['display_name']?.toString().trim() ?? '';
    if (name.isNotEmpty) {
      await prefs.setString('user_name', name);
    }

    const synced = {
      'gender': 'user_gender',
      'birthdate': 'user_birthdate',
      'country': 'user_country',
      'city': 'user_city',
      'street': 'user_street',
    };
    for (final entry in synced.entries) {
      final value = settings[entry.key]?.toString().trim() ?? '';
      if (value.isNotEmpty) {
        await prefs.setString(entry.value, value);
      }
    }

    if (settings.containsKey('dark_mode') && settings['dark_mode'] is bool) {
      await prefs.setBool('dark_mode', settings['dark_mode'] as bool);
    }
  }
}
