import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waffer/core/sync/sync_clock.dart';

/// Local profile photo stored in the app documents folder.
class ProfilePhoto {
  ProfilePhoto._();

  static const String prefsKey = 'user_photo_path';
  static const String updatedAtKey = 'user_photo_updated_at';
  static const String pendingKey = 'user_photo_pending';

  static const String pendingUpload = 'upload';
  static const String pendingDelete = 'delete';

  static Future<String> _destPath() async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/waffer_profile_photo.jpg';
  }

  static Future<String?> path() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(prefsKey)?.trim() ?? '';
    if (stored.isEmpty) return null;
    if (!File(stored).existsSync()) {
      await prefs.remove(prefsKey);
      return null;
    }
    return stored;
  }

  static Future<DateTime?> updatedAt() async {
    final prefs = await SharedPreferences.getInstance();
    return parseSyncDate(prefs.getString(updatedAtKey));
  }

  static Future<void> setUpdatedAt(DateTime? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove(updatedAtKey);
      return;
    }
    await prefs.setString(updatedAtKey, toSyncIso(value));
  }

  static Future<String?> pendingAction() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(pendingKey)?.trim() ?? '';
    if (value == pendingUpload || value == pendingDelete) return value;
    return null;
  }

  static Future<void> markPending(String action) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(pendingKey, action);
    await prefs.setString(updatedAtKey, toSyncIso(syncNow()));
  }

  static Future<void> clearPending() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(pendingKey);
  }

  static Future<String> saveBytes(List<int> bytes) async {
    final dest = File(await _destPath());
    if (await dest.exists()) {
      await dest.delete();
    }
    await dest.writeAsBytes(bytes, flush: true);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, dest.path);
    return dest.path;
  }

  static Future<String?> pick({required ImageSource source}) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 720,
        maxHeight: 720,
        imageQuality: 85,
      );
      if (picked == null) return await path();

      final dest = File(await _destPath());
      if (await dest.exists()) {
        await dest.delete();
      }
      await File(picked.path).copy(dest.path);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, dest.path);
      await markPending(pendingUpload);
      return dest.path;
    } catch (_) {
      return await path();
    }
  }

  /// Deletes the local file. [rememberDelete] queues a server delete for later sync.
  static Future<void> clear({bool rememberDelete = false}) async {
    final current = await path();
    if (current != null) {
      final file = File(current);
      if (await file.exists()) {
        await file.delete();
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(prefsKey);
    if (rememberDelete) {
      await markPending(pendingDelete);
    } else {
      await prefs.remove(pendingKey);
      await prefs.remove(updatedAtKey);
    }
  }
}
